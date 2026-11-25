import AppKit
import CoreGraphics
import QuartzCore

/// The whole snow simulation. Everything is in global Quartz coordinates:
/// origin at the top-left of the main display, y grows downward.
@MainActor
final class SnowEngine {
    let settings = Settings.shared

    // World
    private(set) var screens: [CGRect] = []
    private var mainHeight: CGFloat = 0
    private var windows: [TrackedWindow] = []
    private var piles: [CGWindowID: Pile] = [:]
    private var pileList: [Pile] = []           // front-most window first
    private var parked: [CGWindowID: (pile: Pile, since: Date)] = [:]
    private var grounds: [Pile] = []

    // Moving things
    private var flakes: [Flake] = []
    private var balls: [Snowball] = []
    private var heldBall: Snowball?
    private var heldHistory: [(p: CGPoint, t: CFTimeInterval)] = []
    private var splats: [Splat] = []
    private var snowmen: [Snowman] = []

    // Weather
    private var time: CGFloat = 0
    private var gust: CGFloat = 0
    private var gustTarget: CGFloat = 0
    private var nextGustChange: CGFloat = 0
    private var spawnAccumulator: Double = 0

    // Cursor
    private(set) var mouse = CGPoint.zero
    private var mouseVel = CGVector.zero

    var snowballMode = false
    private var pilesEmpty = true

    private let maxFlakes = 3000
    private let windowPileMax: CGFloat = 16
    private let groundPileMax: CGFloat = 28

    // Pre-rendered art
    private let flakeSprite: CGImage? = SnowEngine.makeFlakeSprite()
    private let ballGradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 1),
                 CGColor(red: 0.93, green: 0.96, blue: 1, alpha: 1),
                 CGColor(red: 0.74, green: 0.81, blue: 0.92, alpha: 1)] as CFArray,
        locations: [0, 0.45, 1])
    private let frostGradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [CGColor(red: 0.92, green: 0.96, blue: 1, alpha: 0.38),
                 CGColor(red: 0.92, green: 0.96, blue: 1, alpha: 0)] as CFArray,
        locations: [0, 1])

    // MARK: - Setup

    static func quartzRect(_ r: CGRect, mainHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: mainHeight - r.maxY, width: r.width, height: r.height)
    }

    func configure(screens nsScreens: [NSScreen]) {
        mainHeight = NSScreen.screens.first?.frame.height ?? 0
        screens = nsScreens.map { SnowEngine.quartzRect($0.frame, mainHeight: mainHeight) }
        grounds = screens.map { s in
            let g = Pile(frame: CGRect(x: s.minX, y: s.maxY, width: s.width, height: 1), maxHeight: groundPileMax)
            // No ground where another display sits directly below this one.
            for c in 0..<g.count {
                let probe = CGPoint(x: g.x(of: c), y: s.maxY + 4)
                g.visible[c] = !screens.contains { $0.contains(probe) }
            }
            return g
        }
    }

    // MARK: - Windows

    func updateWindows(_ list: [TrackedWindow]) {
        windows = list
        let now = Date()
        var next: [CGWindowID: Pile] = [:]
        for w in list {
            var pile = piles[w.id]
            if pile == nil, let entry = parked[w.id] {
                // A window came back (other Space, unminimised…). Restore its snow if it didn't move.
                if entry.pile.frame == w.frame { pile = entry.pile }
                parked[w.id] = nil
            }
            if let p = pile, p.frame != w.frame {
                let edgeMoved = abs(p.frame.minY - w.frame.minY) > 0.5
                    || abs(p.frame.minX - w.frame.minX) > 0.5
                    || abs(p.frame.width - w.frame.width) > 0.5
                if edgeMoved {
                    // The window was dragged or resized: the snow slides off.
                    let push = CGVector(dx: (w.frame.minX - p.frame.minX) * 6,
                                        dy: (w.frame.minY - p.frame.minY) * 6)
                    shakeOff(p, push: push)
                    pile = nil
                } else {
                    p.frame = w.frame
                }
            }
            next[w.id] = pile ?? Pile(frame: w.frame, maxHeight: windowPileMax)
        }
        for (id, p) in piles where next[id] == nil && !p.isEmpty {
            parked[id] = (p, now)
        }
        parked = parked.filter { now.timeIntervalSince($0.value.since) < 600 }
        piles = next
        pileList = list.compactMap { next[$0.id] }
        computeVisibility()
    }

    private func computeVisibility() {
        for (idx, w) in windows.enumerated() {
            guard let pile = piles[w.id] else { continue }
            let y = w.frame.minY - 2
            var vis = [Bool](repeating: false, count: pile.count)
            for s in screens where s.minY <= y && s.maxY > y {
                for c in pile.columns(from: s.minX, to: s.maxX) { vis[c] = true }
            }
            if idx > 0 {
                for j in 0..<idx {
                    let f = windows[j].frame
                    if f.minY <= y && f.maxY > y - 10 {
                        for c in pile.columns(from: f.minX, to: f.maxX) { vis[c] = false }
                    }
                }
            }
            pile.visible = vis
        }
    }

    // MARK: - Simulation

    func sampleMouse(dt: CGFloat) {
        let m = NSEvent.mouseLocation
        let q = CGPoint(x: m.x, y: mainHeight - m.y)
        if dt > 0 {
            let vx = (q.x - mouse.x) / dt
            let vy = (q.y - mouse.y) / dt
            mouseVel = CGVector(dx: mouseVel.dx * 0.5 + vx * 0.5, dy: mouseVel.dy * 0.5 + vy * 0.5)
        }
        mouse = q
    }

    func step(dt: CGFloat) {
        guard !screens.isEmpty else { return }
        time += dt
        sampleMouse(dt: dt)
        updateWind(dt: dt)
        spawn(dt: dt)
        stepFlakes(dt: dt)
        stepHeldBall(dt: dt)
        stepBalls(dt: dt)
        stepSnowmen(dt: dt)

        for i in splats.indices { splats[i].age += dt }
        splats.removeAll { $0.age > 7 }

        if !settings.enabled {
            for p in pileList { p.melt(dt * 1.2) }
            for g in grounds { g.melt(dt * 1.2) }
        }
        pilesEmpty = !pileList.contains { !$0.isEmpty } && !grounds.contains { !$0.isEmpty }
    }

    /// True when there is nothing at all to draw, so the screen doesn't need repainting.
    var isIdle: Bool {
        flakes.isEmpty && balls.isEmpty && heldBall == nil && splats.isEmpty && snowmen.isEmpty
            && !settings.frost && !snowballMode && pilesEmpty
    }

    private var windNow: CGFloat {
        let base = CGFloat(settings.wind.base)
        return base * (0.7 + 0.3 * sin(time * 0.17)) + gust
    }

    private func updateWind(dt: CGFloat) {
        if time >= nextGustChange {
            let base = CGFloat(settings.wind.base)
            let gustiness: CGFloat = settings.wind == .gusty ? 1.4 : 0.6
            gustTarget = CGFloat.random(in: -0.4...1.0) * base * gustiness
            nextGustChange = time + CGFloat.random(in: 2...6)
        }
        gust += (gustTarget - gust) * min(1, dt * 0.9)
    }

    private func spawn(dt: CGFloat) {
        guard settings.enabled else { return }
        let totalW = screens.reduce(0) { $0 + $1.width }
        let rate = settings.intensity.flakesPerSecond * Double(totalW / 1500)
        spawnAccumulator += rate * Double(dt)
        while spawnAccumulator >= 1 {
            spawnAccumulator -= 1
            guard flakes.count < maxFlakes else { continue }
            var pick = CGFloat.random(in: 0..<totalW)
            for s in screens {
                if pick < s.width {
                    let upwind = -windNow * CGFloat.random(in: 0...6)
                    flakes.append(makeFlake(at: CGPoint(x: s.minX + pick + upwind, y: s.minY - 8)))
                    break
                }
                pick -= s.width
            }
        }
    }

    private func makeFlake(at p: CGPoint) -> Flake {
        let z = CGFloat.random(in: 0.2...1)
        return Flake(p: p,
                     z: z,
                     r: (0.9 + 3.0 * z * z) * CGFloat.random(in: 0.75...1.2),
                     speed: 28 + 72 * z * CGFloat.random(in: 0.8...1.2),
                     phase: CGFloat.random(in: 0...(2 * .pi)),
                     freq: CGFloat.random(in: 0.6...1.8))
    }

    private func screenIndex(containingX x: CGFloat, y: CGFloat) -> Int? {
        screens.firstIndex { x >= $0.minX && x < $0.maxX && y >= $0.minY - 200 && y < $0.maxY + 40 }
    }

    private func stepFlakes(dt: CGFloat) {
        let wind = windNow
        let breeze = settings.cursorBreeze && !snowballMode
        let mouseSpeed = hypot(mouseVel.dx, mouseVel.dy)
        let settle = settings.settleOnWindows
        let kickDecay = exp(-2.2 * dt)

        var i = 0
        while i < flakes.count {
            var f = flakes[i]
            var remove = false
            f.life += dt

            var nx: CGFloat
            var ny: CGFloat
            if f.clump {
                f.v.dy += 900 * dt
                f.v.dx *= (1 - 0.8 * dt)
                nx = f.p.x + f.v.dx * dt
                ny = f.p.y + f.v.dy * dt
                if f.life > 6 { remove = true }
            } else {
                if breeze && mouseSpeed > 30 {
                    let dx = f.p.x - mouse.x, dy = f.p.y - mouse.y
                    let d2 = dx * dx + dy * dy
                    let radius: CGFloat = 110
                    if d2 < radius * radius {
                        let d = max(sqrt(d2), 1)
                        let k = (1 - d / radius) * 0.09
                        f.kick.dx += (mouseVel.dx * k + dx / d * 30 * k * 10)
                        f.kick.dy += (mouseVel.dy * k + dy / d * 30 * k * 10)
                        let mag = hypot(f.kick.dx, f.kick.dy)
                        if mag > 500 { f.kick.dx *= 500 / mag; f.kick.dy *= 500 / mag }
                    }
                }
                f.kick.dx *= kickDecay
                f.kick.dy *= kickDecay
                let sway = sin(time * f.freq + f.phase) * 14 * f.z
                nx = f.p.x + ((wind + sway) * f.z + f.kick.dx) * dt
                ny = f.p.y + (f.speed + f.kick.dy) * dt
            }

            if !remove && !f.clump {
                // Land on a window's top edge (only flakes close to the "glass").
                if settle && f.z > 0.55 {
                    var bestY = CGFloat.infinity
                    var bestPile: Pile?
                    var bestCol = 0
                    for pile in pileList {
                        guard let c = pile.column(at: nx), pile.visible[c] else { continue }
                        let sy = pile.surfaceY(c)
                        if f.p.y <= sy && ny >= sy && sy < bestY {
                            bestY = sy; bestPile = pile; bestCol = c
                        }
                    }
                    if let pile = bestPile {
                        pile.add(f.r * 0.32, at: bestCol)
                        remove = true
                    }
                }
                // Land on the bottom of the screen.
                if !remove {
                    for g in grounds {
                        guard let c = g.column(at: nx), g.visible[c] else { continue }
                        let sy = g.surfaceY(c)
                        if ny >= sy && f.p.y <= sy + 2 {
                            if f.z > 0.4 { g.add(f.r * 0.18, at: c) }
                            remove = true
                            break
                        }
                    }
                }
            }

            if !remove {
                f.p = CGPoint(x: nx, y: ny)
                if screenIndex(containingX: nx, y: ny) == nil {
                    // Allow flakes to drift in from the sides a little before culling.
                    let nearAny = screens.contains { $0.insetBy(dx: -80, dy: -60).contains(f.p) }
                    if !nearAny { remove = true }
                }
            }

            if remove {
                flakes.swapAt(i, flakes.count - 1)
                flakes.removeLast()
            } else {
                flakes[i] = f
                i += 1
            }
        }
    }

    /// Turns a pile into falling chunks.
    private func shakeOff(_ pile: Pile, push: CGVector) {
        var budget = 500
        var c = 0
        while c < pile.count && budget > 0 {
            defer { c += 2 }
            let h = pile.heights[c]
            guard h > 0.8, pile.visible[c] else { continue }
            let n = Int(h / 4) + 1
            for k in 0..<n {
                guard flakes.count < maxFlakes else { pile.clear(); return }
                budget -= 1
                var f = makeFlake(at: CGPoint(x: pile.x(of: c) + .random(in: -1.5...1.5),
                                              y: pile.baseY - CGFloat(k) * 3.5 - 1))
                f.clump = true
                f.z = 1
                f.r = .random(in: 1.4...3.4)
                f.v = CGVector(dx: push.dx * 0.4 + .random(in: -40...40),
                               dy: min(push.dy * 0.4, 0) + .random(in: -90...10))
                flakes.append(f)
            }
        }
        pile.clear()
    }

    private func burst(at p: CGPoint, count: Int, speed: ClosedRange<CGFloat>, size: ClosedRange<CGFloat>) {
        for _ in 0..<count {
            guard flakes.count < maxFlakes else { return }
            var f = makeFlake(at: p)
            f.clump = true
            f.z = 1
            f.r = .random(in: size)
            let a = CGFloat.random(in: 0...(2 * .pi))
            let s = CGFloat.random(in: speed)
            f.v = CGVector(dx: cos(a) * s, dy: sin(a) * s - 120)
            flakes.append(f)
        }
    }

    // MARK: - Snowballs

    func beginGather() {
        sampleMouse(dt: 0)
        heldBall = Snowball(p: mouse, prev: mouse, r: 6)
        heldHistory = [(mouse, CACurrentMediaTime())]
    }

    func cancelGather() {
        heldBall = nil
        heldHistory = []
    }

    func releaseBall() {
        guard var b = heldBall else { return }
        heldBall = nil
        let now = CACurrentMediaTime()
        heldHistory.append((mouse, now))
        var v = CGVector.zero
        if let last = heldHistory.last,
           let first = heldHistory.first(where: { now - $0.t <= 0.09 }), last.t - first.t > 0.008 {
            let t = CGFloat(last.t - first.t)
            v = CGVector(dx: (last.p.x - first.p.x) / t, dy: (last.p.y - first.p.y) / t)
        }
        let speed = hypot(v.dx, v.dy)
        let maxSpeed: CGFloat = 3800
        if speed > maxSpeed { v.dx *= maxSpeed / speed; v.dy *= maxSpeed / speed }
        b.v = v
        b.prev = b.p
        b.p = mouse
        balls.append(b)
        heldHistory = []
    }

    private func stepHeldBall(dt: CGFloat) {
        guard var b = heldBall else { return }
        b.p = mouse
        b.prev = mouse
        heldHistory.append((mouse, CACurrentMediaTime()))
        if heldHistory.count > 12 { heldHistory.removeFirst(heldHistory.count - 12) }

        var area = CGFloat.pi * b.r * b.r
        area += 240 * dt // a little magic: you can always make a snowball
        // Scoop up nearby snow.
        let reach = b.r + 22
        for pile in pileList + grounds {
            guard abs(pile.baseY - b.p.y) < reach + pile.maxHeight else { continue }
            for c in pile.columns(from: b.p.x - reach, to: b.p.x + reach) where pile.visible[c] {
                let take = min(pile.heights[c], 45 * dt)
                if take > 0 {
                    pile.heights[c] -= take
                    area += take * Pile.colW * 1.6
                }
            }
        }
        b.r = min(44, sqrt(area / .pi))
        heldBall = b
    }

    private func stepBalls(dt: CGFloat) {
        let topLimit = (screens.map(\.minY).min() ?? 0) - 3000
        let bottomLimit = (screens.map(\.maxY).max() ?? 0) + 200
        var i = 0
        while i < balls.count {
            var b = balls[i]
            b.age += dt
            b.prev = b.p
            b.v.dy += 1500 * dt
            b.v.dx *= (1 - 0.08 * dt)
            b.p = CGPoint(x: b.p.x + b.v.dx * dt, y: b.p.y + b.v.dy * dt)

            var done = collide(&b)
            if !done && (b.p.y < topLimit || b.p.y > bottomLimit || b.age > 10) { done = true }

            if done {
                balls.swapAt(i, balls.count - 1)
                balls.removeLast()
            } else {
                balls[i] = b
                i += 1
            }
        }
    }

    /// Returns true when the ball hit something and is gone.
    private func collide(_ b: inout Snowball) -> Bool {
        // Snowmen
        for idx in snowmen.indices {
            let box = snowmanBox(snowmen[idx])
            if let box, box.contains(b.p) && !box.contains(b.prev) {
                snowmen[idx].wobbleV += (b.v.dx >= 0 ? 1 : -1) * min(6, 2 + hypot(b.v.dx, b.v.dy) / 600)
                splat(at: b.p, r: b.r, burstScale: 1)
                return true
            }
        }

        // Windows (front-most first)
        for (idx, w) in windows.enumerated() {
            guard w.frame.contains(b.p) && !w.frame.contains(b.prev) else { continue }
            if idx > 0 && windows[0..<idx].contains(where: { $0.frame.contains(b.p) }) { continue }
            if b.prev.y < w.frame.minY, let pile = piles[w.id] {
                // Came down onto the top edge: becomes part of the pile.
                deposit(b, onto: pile)
                burst(at: CGPoint(x: b.p.x, y: w.frame.minY - 2), count: 10, speed: 40...160, size: 1.2...2.4)
            } else {
                splat(at: b.p, r: b.r, burstScale: 1)
            }
            return true
        }

        // Bottom of the screen
        for g in grounds {
            guard let c = g.column(at: b.p.x), g.visible[c] else { continue }
            let sy = g.surfaceY(c) - b.r * 0.3
            if b.p.y >= sy && b.prev.y < sy + 1 {
                deposit(b, onto: g)
                burst(at: CGPoint(x: b.p.x, y: sy), count: 14, speed: 60...200, size: 1.2...2.6)
                return true
            }
        }

        // Left/right edges of the desktop
        let insideHorizontally = screens.contains { b.p.x >= $0.minX && b.p.x <= $0.maxX && b.p.y <= $0.maxY + 50 }
        if !insideHorizontally && b.p.y > (screens.map(\.minY).min() ?? 0) - 50 {
            let s = screens.first { b.prev.x >= $0.minX && b.prev.x <= $0.maxX } ?? screens[0]
            let x = min(max(b.p.x, s.minX + b.r * 0.4), s.maxX - b.r * 0.4)
            splat(at: CGPoint(x: x, y: b.p.y), r: b.r, burstScale: 1)
            return true
        }
        return false
    }

    private func deposit(_ b: Snowball, onto pile: Pile) {
        let area = CGFloat.pi * b.r * b.r
        let range = pile.columns(from: b.p.x - b.r * 1.2, to: b.p.x + b.r * 1.2)
        guard !range.isEmpty else { return }
        let per = area / (CGFloat(range.count) * Pile.colW) * 0.7
        for c in range { pile.add(per, at: c) }
    }

    private func splat(at p: CGPoint, r: CGFloat, burstScale: CGFloat) {
        splats.append(Splat(p: p, r: max(10, r * 1.5), seed: UInt64.random(in: 0...UInt64.max)))
        if splats.count > 40 { splats.removeFirst() }
        burst(at: p, count: Int(18 + r * 0.8 * burstScale), speed: 80...360, size: 1.2...3.0)
    }

    // MARK: - Snowmen

    func buildSnowman(nearX x: CGFloat? = nil) {
        guard !screens.isEmpty else { return }
        let sx: CGFloat
        if let x, screens.contains(where: { x >= $0.minX && x <= $0.maxX }) {
            sx = x
        } else {
            let s = screens[0]
            sx = CGFloat.random(in: (s.minX + s.width * 0.12)...(s.maxX - s.width * 0.12))
        }
        snowmen.append(Snowman(x: sx, scale: .random(in: 0.85...1.15)))
        if snowmen.count > 6 { snowmen.removeFirst() }
    }

    private func groundY(at x: CGFloat) -> CGFloat? {
        for g in grounds {
            if let c = g.column(at: x), g.visible[c] { return g.surfaceY(c) }
        }
        return nil
    }

    private func snowmanBox(_ m: Snowman) -> CGRect? {
        guard let base = groundY(at: m.x) else { return nil }
        let s = m.scale * m.grow
        return CGRect(x: m.x - 30 * s, y: base - 128 * s, width: 60 * s, height: 128 * s)
    }

    private func stepSnowmen(dt: CGFloat) {
        for i in snowmen.indices {
            var m = snowmen[i]
            m.grow = min(1, m.grow + dt * 1.6)
            m.wobbleV += (-38 * m.wobble - 3.5 * m.wobbleV) * dt
            m.wobble += m.wobbleV * dt
            m.wobble = max(-0.6, min(0.6, m.wobble))
            snowmen[i] = m
        }
    }

    // MARK: - Clearing

    func sweepAway() {
        for p in pileList { shakeOff(p, push: .zero) }
        for g in grounds {
            var c = 0
            while c < g.count {
                if g.heights[c] > 2 && Int.random(in: 0..<6) == 0 {
                    burst(at: CGPoint(x: g.x(of: c), y: g.surfaceY(c)), count: 2, speed: 80...240, size: 1.4...2.8)
                }
                c += 1
            }
            g.clear()
        }
        parked.removeAll()
        for m in snowmen {
            if let base = groundY(at: m.x) {
                burst(at: CGPoint(x: m.x, y: base - 50 * m.scale), count: 50, speed: 80...380, size: 1.5...3.4)
            }
        }
        snowmen.removeAll()
        splats.removeAll()
    }

    func shakeOffWindows() {
        for p in pileList { shakeOff(p, push: .zero) }
        parked.removeAll()
    }

    // MARK: - Drawing

    func draw(in ctx: CGContext, rect: CGRect) {
        if settings.frost { drawFrost(ctx, rect) }
        drawPiles(ctx, rect)
        for s in splats where rect.insetBy(dx: -s.r * 2, dy: -s.r * 2).contains(s.p) { drawSplat(s, ctx) }
        for m in snowmen { drawSnowman(m, ctx, rect) }
        drawFlakes(ctx, rect)
        for b in balls where rect.insetBy(dx: -b.r, dy: -b.r).contains(b.p) { drawBall(at: b.p, r: b.r, ctx, shadow: true) }
        if let b = heldBall, rect.insetBy(dx: -b.r, dy: -b.r).contains(b.p) { drawBall(at: b.p, r: b.r, ctx, shadow: true) }
    }

    private func drawFlakes(_ ctx: CGContext, _ rect: CGRect) {
        let area = rect.insetBy(dx: -10, dy: -10)
        ctx.saveGState()
        for f in flakes where area.contains(f.p) {
            let size = f.r * 2.6
            let r = CGRect(x: f.p.x - size / 2, y: f.p.y - size / 2, width: size, height: size)
            ctx.setAlpha(f.clump ? 0.95 : 0.35 + 0.6 * f.z)
            if let sprite = flakeSprite {
                ctx.draw(sprite, in: r)
            } else {
                ctx.setFillColor(CGColor(gray: 1, alpha: 1))
                ctx.fillEllipse(in: r.insetBy(dx: size * 0.2, dy: size * 0.2))
            }
        }
        ctx.restoreGState()
    }

    private func appendPile(_ pile: Pile, to path: CGMutablePath, clip: CGRect) {
        guard pile.frame.maxX > clip.minX, pile.frame.minX < clip.maxX,
              pile.baseY > clip.minY - 2, pile.baseY - pile.maxHeight < clip.maxY + 2 else { return }
        let base = pile.baseY
        let w = Pile.colW
        var c = 0
        while c < pile.count {
            guard pile.visible[c], pile.heights[c] > 0.3 else { c += 1; continue }
            let start = c
            while c < pile.count && pile.visible[c] && pile.heights[c] > 0.3 { c += 1 }
            let end = c
            let x0 = pile.frame.minX + CGFloat(start) * w
            let x1 = pile.frame.minX + CGFloat(end) * w
            path.move(to: CGPoint(x: x0, y: base + 0.5))
            path.addLine(to: CGPoint(x: x0, y: base - pile.heights[start] * 0.5))
            var prev = CGPoint(x: x0 + w * 0.5, y: base - pile.heights[start])
            path.addLine(to: prev)
            if end - start > 1 {
                for i in (start + 1)..<end {
                    let pt = CGPoint(x: pile.x(of: i), y: base - pile.heights[i])
                    let mid = CGPoint(x: (prev.x + pt.x) / 2, y: (prev.y + pt.y) / 2)
                    path.addQuadCurve(to: mid, control: prev)
                    prev = pt
                }
            }
            path.addLine(to: prev)
            path.addLine(to: CGPoint(x: x1, y: base - pile.heights[end - 1] * 0.5))
            path.addLine(to: CGPoint(x: x1, y: base + 0.5))
            path.closeSubpath()
        }
    }

    private func drawPiles(_ ctx: CGContext, _ rect: CGRect) {
        let path = CGMutablePath()
        for p in pileList { appendPile(p, to: path, clip: rect) }
        for g in grounds { appendPile(g, to: path, clip: rect) }
        guard !path.isEmpty else { return }
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 3,
                      color: CGColor(red: 0.3, green: 0.4, blue: 0.55, alpha: 0.45))
        ctx.setFillColor(CGColor(red: 0.985, green: 0.99, blue: 1, alpha: 0.98))
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()
    }

    private func drawBall(at p: CGPoint, r: CGFloat, _ ctx: CGContext, shadow: Bool) {
        let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
        ctx.saveGState()
        if shadow {
            ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 7, color: CGColor(gray: 0, alpha: 0.3))
        }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fillEllipse(in: rect)
        ctx.restoreGState()
        if let g = ballGradient {
            ctx.saveGState()
            ctx.addEllipse(in: rect)
            ctx.clip()
            ctx.drawRadialGradient(g,
                                   startCenter: CGPoint(x: p.x - r * 0.35, y: p.y - r * 0.4), startRadius: 0,
                                   endCenter: p, endRadius: r * 1.05,
                                   options: [.drawsAfterEndLocation])
            ctx.restoreGState()
        }
    }

    private func drawSplat(_ s: Splat, _ ctx: CGContext) {
        let alpha: CGFloat = s.age < 5 ? 0.94 : 0.94 * max(0, 1 - (s.age - 5) / 2)
        guard alpha > 0 else { return }
        var rng = SeededRandom(s.seed)
        let r = s.r
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 2,
                      color: CGColor(red: 0.3, green: 0.4, blue: 0.55, alpha: 0.35 * alpha))
        ctx.setFillColor(CGColor(red: 0.975, green: 0.985, blue: 1, alpha: alpha))
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(x: s.p.x - r * 0.55, y: s.p.y - r * 0.5, width: r * 1.1, height: r * 1.0))
        for _ in 0..<9 {
            let a = rng.next() * 2 * .pi
            let d = r * (0.3 + 0.45 * rng.next())
            let br = r * (0.14 + 0.2 * rng.next())
            let c = CGPoint(x: s.p.x + cos(a) * d, y: s.p.y + sin(a) * d)
            path.addEllipse(in: CGRect(x: c.x - br, y: c.y - br, width: br * 2, height: br * 2))
        }
        for _ in 0..<12 {
            let a = rng.next() * 2 * .pi
            let d = r * (0.85 + 0.7 * rng.next())
            let br = 1 + r * 0.06 * rng.next()
            let c = CGPoint(x: s.p.x + cos(a) * d, y: s.p.y + sin(a) * d)
            path.addEllipse(in: CGRect(x: c.x - br, y: c.y - br, width: br * 2, height: br * 2))
        }
        // Slow drips sliding down.
        for _ in 0..<3 {
            let dx = (rng.next() - 0.5) * r * 0.9
            let len = min(s.age * 9, r * (0.5 + rng.next()))
            let w = 2 + r * 0.1
            let x = s.p.x + dx
            path.addRoundedRect(in: CGRect(x: x - w / 2, y: s.p.y, width: w, height: r * 0.3 + len),
                                cornerWidth: w / 2, cornerHeight: w / 2)
            path.addEllipse(in: CGRect(x: x - w * 0.7, y: s.p.y + r * 0.3 + len - w * 0.7, width: w * 1.4, height: w * 1.4))
        }
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()
    }

    private func drawSnowman(_ m: Snowman, _ ctx: CGContext, _ rect: CGRect) {
        guard let base = groundY(at: m.x) else { return }
        let s = m.scale * (0.3 + 0.7 * m.grow)
        guard rect.insetBy(dx: -80, dy: -160).contains(CGPoint(x: m.x, y: base)) else { return }
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }

        ctx.saveGState()
        ctx.translateBy(x: m.x, y: base + 5)
        ctx.rotate(by: m.wobble)
        ctx.setAlpha(min(1, m.grow * 2))

        // Arms (behind the body)
        ctx.setStrokeColor(CGColor(red: 0.36, green: 0.24, blue: 0.14, alpha: 1))
        ctx.setLineWidth(2.4 * s)
        ctx.setLineCap(.round)
        ctx.move(to: P(-16, -68)); ctx.addLine(to: P(-42, -86))
        ctx.move(to: P(-33, -80)); ctx.addLine(to: P(-38, -92))
        ctx.move(to: P(16, -68)); ctx.addLine(to: P(43, -80))
        ctx.move(to: P(34, -76)); ctx.addLine(to: P(40, -88))
        ctx.strokePath()

        // Body
        drawBall(at: P(0, -26), r: 26 * s, ctx, shadow: true)
        drawBall(at: P(0, -64), r: 19 * s, ctx, shadow: false)
        drawBall(at: P(0, -93), r: 13.5 * s, ctx, shadow: false)

        // Scarf
        ctx.setFillColor(CGColor(red: 0.78, green: 0.15, blue: 0.18, alpha: 1))
        ctx.addPath(CGPath(roundedRect: CGRect(origin: P(-14, -82.5), size: CGSize(width: 28 * s, height: 6 * s)),
                           cornerWidth: 3 * s, cornerHeight: 3 * s, transform: nil))
        ctx.fillPath()
        ctx.addPath(CGPath(roundedRect: CGRect(origin: P(5, -80), size: CGSize(width: 6 * s, height: 18 * s)),
                           cornerWidth: 2 * s, cornerHeight: 2 * s, transform: nil))
        ctx.fillPath()

        // Hat
        ctx.setFillColor(CGColor(red: 0.12, green: 0.12, blue: 0.15, alpha: 1))
        ctx.fill(CGRect(origin: P(-15, -106), size: CGSize(width: 30 * s, height: 3.5 * s)))
        ctx.fill(CGRect(origin: P(-10, -125), size: CGSize(width: 20 * s, height: 20 * s)))
        ctx.setFillColor(CGColor(red: 0.78, green: 0.15, blue: 0.18, alpha: 1))
        ctx.fill(CGRect(origin: P(-10, -110), size: CGSize(width: 20 * s, height: 3.5 * s)))

        // Face
        ctx.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1))
        for pt in [P(-4.5, -97), P(4.5, -97)] {
            ctx.fillEllipse(in: CGRect(x: pt.x - 1.8 * s, y: pt.y - 1.8 * s, width: 3.6 * s, height: 3.6 * s))
        }
        for k in 0..<5 {
            let a = CGFloat.pi * (0.25 + 0.125 * CGFloat(k))
            let pt = CGPoint(x: cos(a) * 6.5 * s, y: (-92 + sin(a) * 5) * s)
            ctx.fillEllipse(in: CGRect(x: pt.x - 0.9 * s, y: pt.y - 0.9 * s, width: 1.8 * s, height: 1.8 * s))
        }
        for y in [-71.0, -63.0, -55.0] as [CGFloat] {
            let pt = P(0, y)
            ctx.fillEllipse(in: CGRect(x: pt.x - 1.8 * s, y: pt.y - 1.8 * s, width: 3.6 * s, height: 3.6 * s))
        }
        ctx.setFillColor(CGColor(red: 0.95, green: 0.5, blue: 0.12, alpha: 1))
        ctx.move(to: P(0, -94.5)); ctx.addLine(to: P(13, -92)); ctx.addLine(to: P(0, -90.5))
        ctx.closePath()
        ctx.fillPath()

        ctx.restoreGState()
    }

    private func drawFrost(_ ctx: CGContext, _ rect: CGRect) {
        guard let g = frostGradient else { return }
        let d: CGFloat = 70
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.drawLinearGradient(g, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.minY + d), options: [])
        ctx.drawLinearGradient(g, start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.maxY - d), options: [])
        ctx.drawLinearGradient(g, start: CGPoint(x: rect.minX, y: rect.midY), end: CGPoint(x: rect.minX + d, y: rect.midY), options: [])
        ctx.drawLinearGradient(g, start: CGPoint(x: rect.maxX, y: rect.midY), end: CGPoint(x: rect.maxX - d, y: rect.midY), options: [])
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
        for c in corners {
            ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: 240, options: [])
        }
        ctx.restoreGState()
    }

    nonisolated private static func makeFlakeSprite() -> CGImage? {
        let size = 32
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let g = CGGradient(colorsSpace: space,
                                 colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 1),
                                          CGColor(red: 1, green: 1, blue: 1, alpha: 0.85),
                                          CGColor(red: 0.95, green: 0.97, blue: 1, alpha: 0)] as CFArray,
                                 locations: [0, 0.38, 1]) else { return nil }
        let c = CGPoint(x: CGFloat(size) / 2, y: CGFloat(size) / 2)
        ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(size) / 2, options: [])
        return ctx.makeImage()
    }
}
