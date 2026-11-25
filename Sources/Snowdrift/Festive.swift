import AppKit
import CoreGraphics

/// Text drawn on top of everything: the countdown, the New Year banner, gift messages.
struct OverlayText {
    var text: String
    /// Global Quartz position, or nil for the middle of every screen.
    var position: CGPoint?
    var size: CGFloat
    var scale: CGFloat = 1
    var alpha: CGFloat
    var color: NSColor
}

/// The colours used for lights, ornaments, presents and fireworks.
enum Hue: Int, CaseIterable {
    case red, green, gold, blue, pink, warm, icy, white, orange, purple

    var rgb: (CGFloat, CGFloat, CGFloat) {
        switch self {
        case .red: return (0.96, 0.2, 0.22)
        case .green: return (0.2, 0.85, 0.35)
        case .gold: return (1.0, 0.78, 0.25)
        case .blue: return (0.3, 0.55, 1.0)
        case .pink: return (1.0, 0.42, 0.75)
        case .warm: return (1.0, 0.86, 0.55)
        case .icy: return (0.62, 0.88, 1.0)
        case .white: return (1.0, 1.0, 1.0)
        case .orange: return (1.0, 0.55, 0.15)
        case .purple: return (0.7, 0.45, 1.0)
        }
    }

    var cg: CGColor { let c = rgb; return CGColor(red: c.0, green: c.1, blue: c.2, alpha: 1) }
    func color(alpha: CGFloat) -> CGColor { let c = rgb; return CGColor(red: c.0, green: c.1, blue: c.2, alpha: alpha) }
}

/// Christmas and New Year decorations: string lights on windows, a tree with presents,
/// a flying sleigh, and fireworks with a countdown at midnight on New Year's Eve.
@MainActor
final class Festive {
    unowned let engine: SnowEngine
    private let settings = Settings.shared
    let sound = HolidaySound()

    private var time: CGFloat = 0
    private let glow: [CGImage]

    // Tree
    private struct Ornament { var p: CGPoint; var r: CGFloat; var hue: Hue }
    private var ornaments: [Ornament] = []
    private var treeLights: [(p: CGPoint, hue: Hue, phase: CGFloat)] = []
    private var treeShake: CGFloat = 0
    private let tiers: [(bottom: CGFloat, top: CGFloat, half: CGFloat)] =
        [(-18, -88, 72), (-62, -128, 55), (-102, -160, 40), (-136, -190, 26)]

    // Presents
    private struct Gift {
        var x: CGFloat
        var y: CGFloat?          // nil = resting on the ground
        var vy: CGFloat = 0
        var w: CGFloat
        var h: CGFloat
        var box: Hue
        var ribbon: Hue
        var slot: Int?           // position under the tree, if it belongs there
        var appear: CGFloat = 0
        var age: CGFloat = 0
    }
    private var gifts: [Gift] = []
    private var slotRespawn: [Int: CGFloat] = [:]
    private let slots: [(dx: CGFloat, w: CGFloat, h: CGFloat, box: Hue, ribbon: Hue)] = [
        (-64, 26, 20, .red, .gold), (-34, 20, 27, .blue, .white), (36, 30, 18, .gold, .red), (68, 18, 15, .green, .red),
    ]

    // Sparks: fireworks, sparkle trails and confetti
    private struct Spark {
        var p: CGPoint
        var v: CGVector
        var hue: Hue
        var life: CGFloat = 0
        var maxLife: CGFloat
        var size: CGFloat
        var gravity: CGFloat
        var drag: CGFloat
        var confetti = false
        var spin: CGFloat = 0
    }
    private var sparks: [Spark] = []
    private struct Rocket { var p: CGPoint; var v: CGVector; var hue: Hue; var fuse: CGFloat; var kind: Int }
    private var rockets: [Rocket] = []
    private var fireworksUntil: CGFloat = -1
    private var nextRocket: CGFloat = 0
    private let maxSparks = 2500

    // Sleigh
    private struct Sleigh {
        var x: CGFloat
        var baseY: CGFloat
        var dir: CGFloat
        var speed: CGFloat
        var startX: CGFloat
        var endX: CGFloat
        var dropX: CGFloat
        var dropped = false
        var y: CGFloat = 0
    }
    private var sleigh: Sleigh?
    private var nextSleigh: CGFloat = 30

    // Text
    private struct Floating { var text: String; var p: CGPoint; var age: CGFloat = 0 }
    private var floating: [Floating] = []
    private(set) var overlayTexts: [OverlayText] = []
    private var bannerText = ""
    private var bannerAge: CGFloat = -1
    private var manualCountdownEnd: Date?
    private var celebratedYear = 0

    private let giftMessages = [
        "Merry Christmas!", "Happy New Year!", "Ho ho ho!", "A warm pair of socks 🧦", "Hot cocoa time ☕",
        "Make a wish ✨", "Cozy vibes +100", "A gingerbread cookie 🍪", "Let it snow!", "Joy to you!",
        "A tiny snow globe 🔮", "Best year yet 🎉", "Peace and quiet", "A candy cane 🍬", "Sweet dreams ⭐",
    ]

    init(engine: SnowEngine) {
        self.engine = engine
        glow = Hue.allCases.compactMap { Festive.makeGlow($0) }
        buildTree()
    }

    // MARK: - Public

    var isIdle: Bool {
        let decorating = settings.holiday && (settings.tree || settings.lights != .off)
        return !decorating && sparks.isEmpty && rockets.isEmpty && sleigh == nil && floating.isEmpty
            && bannerAge < 0 && manualCountdownEnd == nil && gifts.allSatisfy({ $0.slot != nil }) && !countdownVisible
    }

    private var countdownVisible = false

    func startFireworks(seconds: CGFloat) {
        fireworksUntil = max(fireworksUntil, time + seconds)
        nextRocket = time
    }

    /// A 10-second practice countdown, then the New Year show.
    func startCountdown() {
        manualCountdownEnd = Date().addingTimeInterval(10)
    }

    func sendSleigh() {
        guard sleigh == nil, !engine.screens.isEmpty else { return }
        let s = engine.screens[Int.random(in: 0..<engine.screens.count)]
        let dir: CGFloat = Bool.random() ? 1 : -1
        let startX = dir > 0 ? s.minX - 260 : s.maxX + 260
        let endX = dir > 0 ? s.maxX + 260 : s.minX - 260
        sleigh = Sleigh(x: startX,
                        baseY: s.minY + s.height * CGFloat.random(in: 0.12...0.3),
                        dir: dir,
                        speed: CGFloat.random(in: 230...300),
                        startX: startX,
                        endX: endX,
                        dropX: CGFloat.random(in: (s.minX + s.width * 0.2)...(s.maxX - s.width * 0.2)))
        sound.playBells()
    }

    /// The menu's little countdown line.
    func calendarStatus() -> [String] {
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)
        var lines: [String] = []
        let comps = cal.dateComponents([.month, .day], from: now)
        if comps.month == 12 && (comps.day == 24 || comps.day == 25) {
            lines.append(comps.day == 25 ? "🎄 Merry Christmas!" : "🎄 It's Christmas Eve")
        } else if let xmas = cal.nextDate(after: now, matching: DateComponents(month: 12, day: 25), matchingPolicy: .nextTime),
                  let days = cal.dateComponents([.day], from: today, to: cal.startOfDay(for: xmas)).day {
            lines.append("🎄 Christmas in \(days) day\(days == 1 ? "" : "s")")
        }
        if comps.month == 1 && comps.day == 1 {
            lines.append("🎆 Happy New Year!")
        } else if let ny = cal.nextDate(after: now, matching: DateComponents(month: 1, day: 1, hour: 0, minute: 0, second: 0),
                                        matchingPolicy: .nextTime),
                  let days = cal.dateComponents([.day], from: today, to: cal.startOfDay(for: ny)).day {
            lines.append(days <= 1 ? "🎆 New Year is tonight!" : "🎆 New Year in \(days) days")
        }
        return lines
    }

    /// Clicks in snowball mode. Returns true when a decoration used the click.
    func handleClick(at p: CGPoint) -> Bool {
        if let i = gifts.firstIndex(where: { giftRect($0)?.insetBy(dx: -4, dy: -4).contains(p) ?? false }) {
            openGift(at: i)
            return true
        }
        if let box = treeBox, box.contains(p) {
            shakeTree()
            return true
        }
        return false
    }

    /// Snowballs flying into decorations. Returns true when the ball hit one.
    func snowballHit(at p: CGPoint, prev: CGPoint, velocity: CGVector) -> Bool {
        if let i = gifts.firstIndex(where: { r in
            guard let rect = giftRect(r) else { return false }
            return rect.contains(p) && !rect.contains(prev)
        }) {
            openGift(at: i)
            return true
        }
        if let s = sleigh, settings.holiday {
            let box = CGRect(x: s.x - 230, y: s.y - 60, width: 460, height: 80)
            if box.contains(p) && !box.contains(prev) {
                dropGift(from: CGPoint(x: s.x, y: s.y))
                sparkle(at: p, count: 40)
                return true
            }
        }
        if let box = treeBox, box.contains(p) && !box.contains(prev) {
            shakeTree()
            return true
        }
        return false
    }

    // MARK: - Simulation

    func step(dt: CGFloat) {
        time += dt
        treeShake = max(0, treeShake - dt * 0.9)
        stepGifts(dt: dt)
        stepSleigh(dt: dt)
        stepFireworks(dt: dt)
        stepSparks(dt: dt)
        stepNewYear(dt: dt)

        for i in floating.indices {
            floating[i].age += dt
            floating[i].p.y -= 28 * dt
        }
        floating.removeAll { $0.age > 3.2 }
        rebuildTexts()
    }

    private func stepGifts(dt: CGFloat) {
        let treeOn = settings.holiday && settings.tree
        if treeOn {
            for (i, _) in slots.enumerated() where !gifts.contains(where: { $0.slot == i }) {
                if let due = slotRespawn[i], time < due { continue }
                let s = slots[i]
                gifts.append(Gift(x: 0, w: s.w, h: s.h, box: s.box, ribbon: s.ribbon, slot: i))
                slotRespawn[i] = nil
            }
        } else {
            gifts.removeAll { $0.slot != nil }
        }
        var i = 0
        while i < gifts.count {
            var g = gifts[i]
            g.appear = min(1, g.appear + dt * 1.5)
            g.age += dt
            if g.slot == nil, let y = g.y {
                g.vy = min(g.vy + 500 * dt, 420)
                let ny = y + g.vy * dt
                if let ground = engine.groundY(at: g.x), ny >= ground {
                    g.y = nil
                    engine.burst(at: CGPoint(x: g.x, y: ground), count: 12, speed: 40...160, size: 1.2...2.4)
                } else if engine.groundY(at: g.x) == nil && ny > (engine.screens.map(\.maxY).max() ?? 0) {
                    gifts.remove(at: i)
                    continue
                } else {
                    g.y = ny
                }
            }
            if g.slot == nil && g.age > 240 {
                gifts.remove(at: i)
                continue
            }
            gifts[i] = g
            i += 1
        }
    }

    private func stepSleigh(dt: CGFloat) {
        if sleigh == nil && settings.holiday && settings.sleigh && settings.enabled && time >= nextSleigh {
            sendSleigh()
            let comps = Calendar.current.dateComponents([.month, .day], from: Date())
            let christmas = comps.month == 12 && (comps.day == 24 || comps.day == 25)
            nextSleigh = time + (christmas ? CGFloat.random(in: 60...120) : CGFloat.random(in: 180...420))
        }
        guard var s = sleigh else { return }
        s.x += s.dir * s.speed * dt
        s.y = s.baseY + sin(time * 1.7) * 14
        if !s.dropped && ((s.dir > 0 && s.x >= s.dropX) || (s.dir < 0 && s.x <= s.dropX)) {
            s.dropped = true
            dropGift(from: CGPoint(x: s.x - s.dir * 40, y: s.y - 20))
        }
        // Sparkle trail behind the sleigh.
        if sparks.count < maxSparks {
            for _ in 0..<2 {
                sparks.append(Spark(p: CGPoint(x: s.x - s.dir * 60 + CGFloat.random(in: -8...8), y: s.y - 6 + CGFloat.random(in: -6...6)),
                                    v: CGVector(dx: -s.dir * CGFloat.random(in: 10...50), dy: .random(in: 10...40)),
                                    hue: Bool.random() ? .gold : .warm,
                                    maxLife: .random(in: 0.8...1.6), size: .random(in: 3...6),
                                    gravity: 30, drag: 1.2))
            }
        }
        if (s.dir > 0 && s.x > s.endX) || (s.dir < 0 && s.x < s.endX) {
            sleigh = nil
        } else {
            sleigh = s
        }
    }

    private func stepFireworks(dt: CGFloat) {
        if time < fireworksUntil && time >= nextRocket, !engine.screens.isEmpty {
            launchRocket()
            let finale = fireworksUntil - time < 6
            nextRocket = time + (finale ? CGFloat.random(in: 0.08...0.2) : CGFloat.random(in: 0.3...0.9))
        }
        var i = 0
        while i < rockets.count {
            var r = rockets[i]
            r.v.dy += 260 * dt
            r.p.x += r.v.dx * dt
            r.p.y += r.v.dy * dt
            r.fuse -= dt
            if sparks.count < maxSparks {
                sparks.append(Spark(p: r.p, v: CGVector(dx: .random(in: -15...15), dy: .random(in: 20...60)),
                                    hue: .warm, maxLife: 0.45, size: 3, gravity: 60, drag: 2))
            }
            if r.fuse <= 0 || r.v.dy > -40 {
                explode(r)
                rockets.remove(at: i)
                continue
            }
            rockets[i] = r
            i += 1
        }
    }

    private func launchRocket() {
        let s = engine.screens[Int.random(in: 0..<engine.screens.count)]
        let x = CGFloat.random(in: (s.minX + s.width * 0.15)...(s.maxX - s.width * 0.15))
        let palette: [Hue] = [.red, .green, .gold, .blue, .pink, .purple, .orange, .white, .icy]
        // Aim so the burst happens in the upper part of the screen.
        let rise = s.height * CGFloat.random(in: 0.5...0.8)
        let vy = -sqrt(2 * 260 * rise)
        rockets.append(Rocket(p: CGPoint(x: x, y: s.maxY), v: CGVector(dx: .random(in: -50...50), dy: vy),
                              hue: palette.randomElement() ?? .gold, fuse: 6, kind: Int.random(in: 0..<4)))
    }

    private func explode(_ r: Rocket) {
        let second: Hue = [.white, .gold, .icy, .pink].randomElement() ?? .white
        switch r.kind {
        case 0: // sphere
            for _ in 0..<90 {
                let a = CGFloat.random(in: 0...(2 * .pi)), sp = CGFloat.random(in: 60...300)
                addSpark(r.p, a, sp, Bool.random() ? r.hue : second, life: .random(in: 1.4...2.2), size: .random(in: 4...7), g: 90, drag: 1.3)
            }
        case 1: // ring
            for k in 0..<64 {
                let a = CGFloat(k) / 64 * 2 * .pi
                addSpark(r.p, a, .random(in: 250...270), r.hue, life: .random(in: 1.3...1.8), size: 5, g: 70, drag: 1.2)
            }
            for _ in 0..<20 {
                addSpark(r.p, .random(in: 0...(2 * .pi)), .random(in: 20...90), second, life: 1.2, size: 4, g: 70, drag: 1.2)
            }
        case 2: // golden willow
            for _ in 0..<110 {
                let a = CGFloat.random(in: 0...(2 * .pi)), sp = CGFloat.random(in: 40...230)
                addSpark(r.p, a, sp, .gold, life: .random(in: 2.4...3.4), size: .random(in: 3...5), g: 45, drag: 1.7)
            }
        default: // heart-ish double burst
            for k in 0..<80 {
                let t = CGFloat(k) / 80 * 2 * .pi
                let hx = 16 * pow(sin(t), 3)
                let hy = -(13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t))
                let v = CGVector(dx: hx * 14, dy: hy * 14)
                if sparks.count < maxSparks {
                    sparks.append(Spark(p: r.p, v: v, hue: .pink, maxLife: 1.7, size: 5, gravity: 50, drag: 1.4))
                }
            }
        }
    }

    private func addSpark(_ p: CGPoint, _ a: CGFloat, _ speed: CGFloat, _ hue: Hue,
                          life: CGFloat, size: CGFloat, g: CGFloat, drag: CGFloat) {
        guard sparks.count < maxSparks else { return }
        sparks.append(Spark(p: p, v: CGVector(dx: cos(a) * speed, dy: sin(a) * speed), hue: hue,
                            maxLife: life, size: size, gravity: g, drag: drag))
    }

    private func sparkle(at p: CGPoint, count: Int) {
        for _ in 0..<count {
            addSpark(p, .random(in: 0...(2 * .pi)), .random(in: 40...220), Bool.random() ? .gold : .white,
                     life: .random(in: 0.6...1.2), size: .random(in: 3...6), g: 80, drag: 1.5)
        }
    }

    private func confetti(at p: CGPoint, count: Int) {
        let palette: [Hue] = [.red, .green, .gold, .blue, .pink, .white]
        for _ in 0..<count where sparks.count < maxSparks {
            let a = CGFloat.random(in: (-CGFloat.pi * 0.95)...(-CGFloat.pi * 0.05))
            let sp = CGFloat.random(in: 150...420)
            sparks.append(Spark(p: p, v: CGVector(dx: cos(a) * sp, dy: sin(a) * sp),
                                hue: palette.randomElement() ?? .gold, maxLife: .random(in: 1.8...2.8),
                                size: .random(in: 4...7), gravity: 380, drag: 2.2, confetti: true,
                                spin: .random(in: 0...(2 * .pi))))
        }
    }

    private func stepSparks(dt: CGFloat) {
        var i = 0
        while i < sparks.count {
            var s = sparks[i]
            s.life += dt
            if s.life >= s.maxLife {
                sparks.swapAt(i, sparks.count - 1)
                sparks.removeLast()
                continue
            }
            let k = max(0, 1 - s.drag * dt)
            s.v.dx *= k
            s.v.dy = s.v.dy * k + s.gravity * dt
            if s.confetti {
                s.v.dx += sin(time * 3 + s.spin) * 40 * dt
                s.spin += dt * 6
            }
            s.p.x += s.v.dx * dt
            s.p.y += s.v.dy * dt
            sparks[i] = s
            i += 1
        }
    }

    private func stepNewYear(dt: CGFloat) {
        if bannerAge >= 0 {
            bannerAge += dt
            if bannerAge > 14 { bannerAge = -1 }
        }
        let now = Date()
        let cal = Calendar.current
        countdownVisible = false

        if let end = manualCountdownEnd {
            let left = end.timeIntervalSince(now)
            if left <= 0 {
                manualCountdownEnd = nil
                let c = cal.dateComponents([.year, .month], from: now)
                celebrate(year: (c.year ?? 2027) + (c.month == 12 ? 1 : 0))
            } else {
                countdownVisible = true
            }
            return
        }

        guard settings.newYearShow else { return }
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
        if c.month == 12 && c.day == 31 && c.hour == 23 && c.minute == 59 && (c.second ?? 0) >= 50 {
            countdownVisible = true
        }
        if c.month == 1 && c.day == 1 && c.hour == 0 && (c.minute ?? 0) < 3, let year = c.year, celebratedYear != year {
            celebrate(year: year)
        }
    }

    private func celebrate(year: Int) {
        celebratedYear = year
        bannerText = "Happy New Year \(year)!"
        bannerAge = 0
        startFireworks(seconds: 75)
        sound.playFanfare()
        for s in engine.screens {
            for k in 0..<3 {
                confetti(at: CGPoint(x: s.minX + s.width * (0.25 + 0.25 * CGFloat(k)), y: s.minY + s.height * 0.45), count: 60)
            }
        }
    }

    private func rebuildTexts() {
        var out: [OverlayText] = []
        let gold = NSColor(calibratedRed: 1, green: 0.84, blue: 0.4, alpha: 1)

        if countdownVisible {
            let left: TimeInterval
            if let end = manualCountdownEnd {
                left = end.timeIntervalSince(Date())
            } else {
                let cal = Calendar.current
                let next = cal.nextDate(after: Date(), matching: DateComponents(hour: 0, minute: 0, second: 0),
                                        matchingPolicy: .nextTime) ?? Date()
                left = next.timeIntervalSince(Date())
            }
            let n = max(1, Int(ceil(left)))
            let frac = CGFloat(left - floor(left)) // 1 → 0 during each second
            out.append(OverlayText(text: "\(n)", position: nil, size: 190, scale: 0.8 + 0.35 * frac,
                                   alpha: 0.35 + 0.6 * frac, color: .white))
        }
        if bannerAge >= 0 {
            let a = min(1, bannerAge * 2) * (bannerAge > 12 ? max(0, 1 - (bannerAge - 12) / 2) : 1)
            out.append(OverlayText(text: bannerText, position: nil, size: 76,
                                   scale: 1 + 0.03 * sin(bannerAge * 3), alpha: a, color: gold))
        }
        for f in floating {
            let a = f.age < 0.25 ? f.age * 4 : (f.age > 2.2 ? max(0, 1 - (f.age - 2.2)) : 1)
            out.append(OverlayText(text: f.text, position: f.p, size: 20, alpha: a, color: .white))
        }
        overlayTexts = out
    }

    // MARK: - Tree & presents

    private var treeBase: CGPoint? {
        guard settings.holiday, settings.tree, let s = engine.screens.first else { return nil }
        let x = s.maxX - min(170, s.width * 0.13)
        guard let y = engine.groundY(at: x) else { return nil }
        return CGPoint(x: x, y: y + 4)
    }

    private var treeBox: CGRect? {
        guard let b = treeBase else { return nil }
        return CGRect(x: b.x - 74, y: b.y - 205, width: 148, height: 205)
    }

    private func buildTree() {
        var rng = SeededRandom(2026)
        let palette: [Hue] = [.red, .gold, .blue, .pink, .icy, .purple]
        for tier in tiers {
            for _ in 0..<5 {
                let t = 0.25 + 0.7 * rng.next()
                let y = tier.top + (tier.bottom - tier.top) * t
                let half = tier.half * t * 0.8
                let x = (rng.next() * 2 - 1) * half
                ornaments.append(Ornament(p: CGPoint(x: x, y: y), r: 3.5 + rng.next() * 2.5,
                                          hue: palette[Int(rng.next() * CGFloat(palette.count)) % palette.count]))
            }
            for _ in 0..<7 {
                let t = 0.15 + 0.8 * rng.next()
                let y = tier.top + (tier.bottom - tier.top) * t
                let x = (rng.next() * 2 - 1) * tier.half * t * 0.9
                let hues: [Hue] = [.warm, .gold, .red, .green, .blue]
                treeLights.append((CGPoint(x: x, y: y), hues[Int(rng.next() * 5) % 5], rng.next() * 6))
            }
        }
    }

    private func shakeTree() {
        treeShake = 1
        if let b = treeBase {
            engine.burst(at: CGPoint(x: b.x, y: b.y - 120), count: 30, speed: 40...200, size: 1.3...2.8)
            sparkle(at: CGPoint(x: b.x, y: b.y - 196), count: 25)
        }
        sound.playChime()
    }

    private func giftRect(_ g: Gift) -> CGRect? {
        if let slot = g.slot {
            guard let b = treeBase else { return nil }
            let s = slots[slot]
            return CGRect(x: b.x + s.dx - g.w / 2, y: b.y - g.h * g.appear, width: g.w, height: g.h * g.appear)
        }
        let bottom: CGFloat
        if let y = g.y { bottom = y } else if let ground = engine.groundY(at: g.x) { bottom = ground + 3 } else { return nil }
        return CGRect(x: g.x - g.w / 2, y: bottom - g.h, width: g.w, height: g.h)
    }

    private func dropGift(from p: CGPoint) {
        let palette: [(Hue, Hue)] = [(.red, .gold), (.green, .red), (.blue, .white), (.purple, .gold), (.gold, .red)]
        let c = palette.randomElement() ?? (.red, .gold)
        gifts.append(Gift(x: p.x, y: p.y, vy: 0, w: .random(in: 18...28), h: .random(in: 15...24),
                          box: c.0, ribbon: c.1, slot: nil, appear: 1))
        if gifts.filter({ $0.slot == nil }).count > 8, let first = gifts.firstIndex(where: { $0.slot == nil }) {
            gifts.remove(at: first)
        }
    }

    private func openGift(at i: Int) {
        let g = gifts[i]
        guard let rect = giftRect(g) else { gifts.remove(at: i); return }
        let c = CGPoint(x: rect.midX, y: rect.midY)
        confetti(at: c, count: 70)
        sparkle(at: c, count: 20)
        floating.append(Floating(text: giftMessages.randomElement() ?? "Merry Christmas!", p: CGPoint(x: c.x, y: rect.minY - 18)))
        if let slot = g.slot { slotRespawn[slot] = time + 40 }
        gifts.remove(at: i)
        sound.playChime()
    }

    // MARK: - Drawing

    /// Things that sit behind the falling snow: string lights, the tree and presents.
    func drawBack(in ctx: CGContext, rect: CGRect) {
        guard settings.holiday else { drawGifts(ctx, rect, groundOnly: true); return }
        if settings.lights != .off { drawWindowLights(ctx, rect) }
        if let b = treeBase, rect.insetBy(dx: -100, dy: -220).contains(b) { drawTree(ctx, at: b) }
        drawGifts(ctx, rect, groundOnly: false)
    }

    /// Things in front of the snow: the sleigh and all sparks.
    func drawFront(in ctx: CGContext, rect: CGRect) {
        if let s = sleigh, rect.insetBy(dx: -260, dy: -100).contains(CGPoint(x: s.x, y: s.y)) { drawSleigh(s, ctx) }
        drawSparks(ctx, rect)
    }

    private func drawGlow(_ hue: Hue, at p: CGPoint, size: CGFloat, alpha: CGFloat, _ ctx: CGContext) {
        guard hue.rawValue < glow.count else { return }
        ctx.setAlpha(alpha)
        ctx.draw(glow[hue.rawValue], in: CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size))
        ctx.setAlpha(1)
    }

    private func lightHues() -> [Hue] {
        switch settings.lights {
        case .multicolor: return [.red, .green, .gold, .blue, .pink]
        case .warmWhite: return [.warm]
        case .icyBlue: return [.icy, .white, .icy, .blue]
        case .off: return []
        }
    }

    private func brightness(index i: Int, seed: Int) -> CGFloat {
        switch Int(time / 14) % 3 {
        case 0: return 0.55 + 0.45 * sin(time * 2.3 + CGFloat(i) * 1.7 + CGFloat(seed % 13))
        case 1: return (i + Int(time * 6)) % 4 == 0 ? 1 : 0.35
        default: return (i + Int(time * 1.4)) % 2 == 0 ? 1 : 0.3
        }
    }

    private func drawWindowLights(_ ctx: CGContext, _ rect: CGRect) {
        let hues = lightHues()
        guard !hues.isEmpty else { return }
        for pile in engine.pileList {
            guard pile.frame.maxX > rect.minX, pile.frame.minX < rect.maxX,
                  pile.baseY > rect.minY, pile.baseY < rect.maxY else { continue }
            let seed = abs(Int(pile.frame.minX) &* 7 &+ Int(pile.frame.width))
            var c = 0
            while c < pile.count {
                guard pile.visible[c] else { c += 1; continue }
                let start = c
                while c < pile.count && pile.visible[c] { c += 1 }
                let x0 = pile.frame.minX + CGFloat(start) * Pile.colW + 12
                let x1 = pile.frame.minX + CGFloat(c) * Pile.colW - 12
                guard x1 - x0 > 60 else { continue }
                drawStrand(ctx, x0: x0, x1: x1, y: pile.baseY + 1, hues: hues, seed: seed)
            }
        }
    }

    private func drawStrand(_ ctx: CGContext, x0: CGFloat, x1: CGFloat, y: CGFloat, hues: [Hue], seed: Int) {
        let spans = max(1, Int((x1 - x0) / 110))
        let spanW = (x1 - x0) / CGFloat(spans)
        let sag: CGFloat = 14
        // Wire
        let wire = CGMutablePath()
        wire.move(to: CGPoint(x: x0, y: y))
        for k in 0..<spans {
            let xa = x0 + CGFloat(k) * spanW
            wire.addQuadCurve(to: CGPoint(x: xa + spanW, y: y), control: CGPoint(x: xa + spanW / 2, y: y + sag))
        }
        ctx.saveGState()
        ctx.setStrokeColor(CGColor(red: 0.08, green: 0.22, blue: 0.12, alpha: 0.9))
        ctx.setLineWidth(1.2)
        ctx.addPath(wire)
        ctx.strokePath()
        ctx.restoreGState()

        // Bulbs
        let spacing: CGFloat = 17
        let n = Int((x1 - x0) / spacing)
        guard n > 0 else { return }
        for i in 0...n {
            let x = x0 + CGFloat(i) * spacing
            let local = (x - x0).truncatingRemainder(dividingBy: spanW) / spanW
            let wy = y + 2 * local * (1 - local) * sag
            let hue = hues[(i + seed) % hues.count]
            let b = brightness(index: i, seed: seed)
            let bulb = CGPoint(x: x, y: wy + 4.5)
            drawGlow(hue, at: bulb, size: 9 + 13 * b, alpha: 0.35 + 0.55 * b, ctx)
            ctx.setFillColor(CGColor(red: 0.1, green: 0.15, blue: 0.1, alpha: 1))
            ctx.fill(CGRect(x: x - 1.2, y: wy, width: 2.4, height: 2.2))
            let c = hue.rgb
            let mix = 0.45 + 0.55 * b
            ctx.setFillColor(CGColor(red: c.0 * mix + 0.2 * b, green: c.1 * mix + 0.2 * b, blue: c.2 * mix + 0.2 * b, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: x - 1.9, y: wy + 1.8, width: 3.8, height: 5.2))
        }
    }

    private func drawTree(_ ctx: CGContext, at base: CGPoint) {
        ctx.saveGState()
        ctx.translateBy(x: base.x, y: base.y)
        ctx.rotate(by: sin(time * 22) * treeShake * 0.04)

        // Trunk
        ctx.setFillColor(CGColor(red: 0.36, green: 0.22, blue: 0.12, alpha: 1))
        ctx.fill(CGRect(x: -9, y: -24, width: 18, height: 24))

        // Branches, bottom tier first
        let space = CGColorSpace(name: CGColorSpace.sRGB)
        let green = CGGradient(colorsSpace: space,
                               colors: [CGColor(red: 0.16, green: 0.52, blue: 0.28, alpha: 1),
                                        CGColor(red: 0.05, green: 0.3, blue: 0.16, alpha: 1)] as CFArray,
                               locations: [0, 1])
        for tier in tiers {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: tier.top))
            path.addLine(to: CGPoint(x: tier.half, y: tier.bottom))
            let scallops = 5
            let w = tier.half * 2 / CGFloat(scallops)
            for k in 0..<scallops {
                let xa = tier.half - CGFloat(k) * w
                path.addQuadCurve(to: CGPoint(x: xa - w, y: tier.bottom), control: CGPoint(x: xa - w / 2, y: tier.bottom + 7))
            }
            path.closeSubpath()
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 4, color: CGColor(gray: 0, alpha: 0.35))
            ctx.addPath(path)
            ctx.setFillColor(CGColor(red: 0.07, green: 0.36, blue: 0.19, alpha: 1))
            ctx.fillPath()
            ctx.restoreGState()
            if let green {
                ctx.saveGState()
                ctx.addPath(path)
                ctx.clip()
                ctx.drawLinearGradient(green, start: CGPoint(x: -tier.half, y: tier.top), end: CGPoint(x: tier.half, y: tier.bottom), options: [])
                ctx.restoreGState()
            }
            // Snow resting on the branch tips
            ctx.setFillColor(CGColor(red: 0.97, green: 0.98, blue: 1, alpha: 0.95))
            for k in 0..<scallops {
                let xa = tier.half - CGFloat(k) * w - w / 2
                ctx.fillEllipse(in: CGRect(x: xa - w * 0.3, y: tier.bottom + 1, width: w * 0.6, height: 4))
            }
            ctx.fillEllipse(in: CGRect(x: -7, y: tier.top + 2, width: 14, height: 5))
            // Garland
            ctx.saveGState()
            ctx.setStrokeColor(Hue.gold.color(alpha: 0.95))
            ctx.setLineWidth(2.4)
            ctx.setLineCap(.round)
            ctx.setLineDash(phase: 0, lengths: [0.1, 4.5])
            let gy = tier.top + (tier.bottom - tier.top) * 0.55
            let gh = tier.half * 0.55 * 0.9
            ctx.move(to: CGPoint(x: -gh, y: gy - 4))
            ctx.addQuadCurve(to: CGPoint(x: gh, y: gy + 6), control: CGPoint(x: 0, y: gy + 12))
            ctx.strokePath()
            ctx.restoreGState()
        }

        // Ornaments
        let jiggle = treeShake * 2.5
        for (k, o) in ornaments.enumerated() {
            let p = CGPoint(x: o.p.x + sin(time * 30 + CGFloat(k)) * jiggle, y: o.p.y)
            let c = o.hue.rgb
            ctx.setFillColor(CGColor(red: c.0 * 0.85, green: c.1 * 0.85, blue: c.2 * 0.85, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: p.x - o.r, y: p.y - o.r, width: o.r * 2, height: o.r * 2))
            ctx.setFillColor(CGColor(gray: 1, alpha: 0.75))
            ctx.fillEllipse(in: CGRect(x: p.x - o.r * 0.55, y: p.y - o.r * 0.6, width: o.r * 0.6, height: o.r * 0.5))
        }

        // Twinkling lights
        for l in treeLights {
            let b = 0.5 + 0.5 * sin(time * 2.6 + l.phase)
            drawGlow(l.hue, at: l.p, size: 8 + 10 * b, alpha: 0.4 + 0.6 * b, ctx)
        }

        // Star
        let pulse = 0.5 + 0.5 * sin(time * 2)
        let starC = CGPoint(x: 0, y: -197)
        drawGlow(.gold, at: starC, size: 46 + 18 * pulse, alpha: 0.7, ctx)
        let star = CGMutablePath()
        for k in 0..<10 {
            let r: CGFloat = k % 2 == 0 ? 13 : 5.5
            let a = -CGFloat.pi / 2 + CGFloat(k) * .pi / 5
            let p = CGPoint(x: starC.x + cos(a) * r, y: starC.y + sin(a) * r)
            if k == 0 { star.move(to: p) } else { star.addLine(to: p) }
        }
        star.closeSubpath()
        ctx.addPath(star)
        ctx.setFillColor(CGColor(red: 1, green: 0.86, blue: 0.35, alpha: 1))
        ctx.fillPath()

        ctx.restoreGState()
    }

    private func drawGifts(_ ctx: CGContext, _ rect: CGRect, groundOnly: Bool) {
        for g in gifts {
            if groundOnly && g.slot != nil { continue }
            guard let r = giftRect(g), r.height > 1, rect.insetBy(dx: -40, dy: -40).intersects(r) else { continue }
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 3, color: CGColor(gray: 0, alpha: 0.35))
            ctx.setFillColor(g.box.cg)
            ctx.fill(r)
            ctx.restoreGState()
            // Darker side for a little depth
            let c = g.box.rgb
            ctx.setFillColor(CGColor(red: c.0 * 0.75, green: c.1 * 0.75, blue: c.2 * 0.75, alpha: 1))
            ctx.fill(CGRect(x: r.maxX - r.width * 0.28, y: r.minY, width: r.width * 0.28, height: r.height))
            // Ribbon
            ctx.setFillColor(g.ribbon.cg)
            ctx.fill(CGRect(x: r.midX - 2, y: r.minY, width: 4, height: r.height))
            ctx.fill(CGRect(x: r.minX, y: r.midY - 2, width: r.width, height: 4))
            // Bow
            if g.appear > 0.9 {
                ctx.fillEllipse(in: CGRect(x: r.midX - 9, y: r.minY - 6, width: 9, height: 7))
                ctx.fillEllipse(in: CGRect(x: r.midX, y: r.minY - 6, width: 9, height: 7))
                ctx.fillEllipse(in: CGRect(x: r.midX - 2.5, y: r.minY - 3.5, width: 5, height: 5))
            }
        }
    }

    private func drawSleigh(_ s: Sleigh, _ ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: s.x, y: s.y)
        ctx.scaleBy(x: s.dir, y: 1)
        ctx.rotate(by: cos(time * 1.7) * 0.04)
        let ink = CGColor(red: 0.1, green: 0.12, blue: 0.2, alpha: 0.95)
        ctx.setShadow(offset: .zero, blur: 9, color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.75))
        ctx.setFillColor(ink)
        ctx.setStrokeColor(ink)
        ctx.setLineCap(.round)

        // Sleigh body and runner
        let body = CGMutablePath()
        body.move(to: CGPoint(x: -62, y: -40))
        body.addQuadCurve(to: CGPoint(x: -52, y: -8), control: CGPoint(x: -64, y: -14))
        body.addLine(to: CGPoint(x: -10, y: -8))
        body.addQuadCurve(to: CGPoint(x: -2, y: -26), control: CGPoint(x: -2, y: -12))
        body.addLine(to: CGPoint(x: -16, y: -24))
        body.addLine(to: CGPoint(x: -48, y: -24))
        body.addLine(to: CGPoint(x: -52, y: -40))
        body.closeSubpath()
        ctx.addPath(body)
        ctx.fillPath()
        ctx.setLineWidth(2.6)
        ctx.move(to: CGPoint(x: -66, y: 1))
        ctx.addLine(to: CGPoint(x: -6, y: 1))
        ctx.addQuadCurve(to: CGPoint(x: 4, y: -10), control: CGPoint(x: 6, y: 1))
        ctx.move(to: CGPoint(x: -50, y: -8)); ctx.addLine(to: CGPoint(x: -50, y: 1))
        ctx.move(to: CGPoint(x: -18, y: -8)); ctx.addLine(to: CGPoint(x: -18, y: 1))
        ctx.strokePath()
        // Sack of presents
        ctx.fillEllipse(in: CGRect(x: -50, y: -46, width: 26, height: 24))
        ctx.fill(CGRect(x: -40, y: -50, width: 6, height: 6))

        // Reins
        ctx.setLineWidth(1.2)
        ctx.move(to: CGPoint(x: -4, y: -20))
        ctx.addQuadCurve(to: CGPoint(x: 150, y: -22), control: CGPoint(x: 70, y: -6))
        ctx.strokePath()

        // Reindeer
        for i in 0..<3 {
            let x = 40 + CGFloat(i) * 50
            let y: CGFloat = -18 + sin(time * 9 + CGFloat(i)) * 2
            ctx.fillEllipse(in: CGRect(x: x - 16, y: y - 7, width: 32, height: 13))
            ctx.setLineWidth(3)
            ctx.move(to: CGPoint(x: x + 12, y: y - 2)); ctx.addLine(to: CGPoint(x: x + 20, y: y - 14))
            ctx.strokePath()
            ctx.fillEllipse(in: CGRect(x: x + 16, y: y - 20, width: 13, height: 8))
            ctx.setLineWidth(1.4)
            ctx.move(to: CGPoint(x: x + 20, y: y - 19)); ctx.addLine(to: CGPoint(x: x + 16, y: y - 31))
            ctx.move(to: CGPoint(x: x + 17, y: y - 27)); ctx.addLine(to: CGPoint(x: x + 11, y: y - 30))
            ctx.move(to: CGPoint(x: x + 23, y: y - 19)); ctx.addLine(to: CGPoint(x: x + 25, y: y - 31))
            ctx.move(to: CGPoint(x: x + 24, y: y - 27)); ctx.addLine(to: CGPoint(x: x + 30, y: y - 29))
            ctx.strokePath()
            ctx.setLineWidth(2.2)
            let a = sin(time * 10 + CGFloat(i) * 1.3) * 0.7
            for lx in [x + 10, x - 10] as [CGFloat] {
                ctx.move(to: CGPoint(x: lx, y: y + 4))
                ctx.addLine(to: CGPoint(x: lx + sin(a) * 9, y: y + 15))
                ctx.move(to: CGPoint(x: lx - 3, y: y + 4))
                ctx.addLine(to: CGPoint(x: lx - 3 - sin(a) * 9, y: y + 15))
            }
            ctx.strokePath()
        }
        ctx.restoreGState()

        // Lantern on the front of the sleigh
        let lantern = CGPoint(x: s.x + 2 * s.dir, y: s.y - 14)
        drawGlow(.gold, at: lantern, size: 26 + 6 * sin(time * 7), alpha: 0.9, ctx)
    }

    private func drawSparks(_ ctx: CGContext, _ rect: CGRect) {
        let area = rect.insetBy(dx: -20, dy: -20)
        for s in sparks where area.contains(s.p) {
            let t = s.life / s.maxLife
            var a = 1 - t
            if !s.confetti && t > 0.6 && sin(s.life * 45 + s.p.x) < 0 { a *= 0.35 }
            if s.confetti {
                ctx.saveGState()
                ctx.translateBy(x: s.p.x, y: s.p.y)
                ctx.rotate(by: s.spin)
                ctx.setFillColor(s.hue.color(alpha: min(1, a * 1.5)))
                ctx.fill(CGRect(x: -s.size / 2, y: -s.size * 0.3 * abs(cos(s.spin * 1.3)) - 0.5,
                                width: s.size, height: s.size * 0.6 * abs(cos(s.spin * 1.3)) + 1))
                ctx.restoreGState()
            } else {
                drawGlow(s.hue, at: s.p, size: s.size * (1.6 + a), alpha: a, ctx)
            }
        }
        for r in rockets where area.contains(r.p) {
            drawGlow(.warm, at: r.p, size: 10, alpha: 1, ctx)
        }
    }

    nonisolated private static func makeGlow(_ hue: Hue) -> CGImage? {
        let size = 32
        let c = hue.rgb
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let g = CGGradient(colorsSpace: space,
                                 colors: [CGColor(red: min(1, c.0 + 0.5), green: min(1, c.1 + 0.5), blue: min(1, c.2 + 0.5), alpha: 1),
                                          CGColor(red: c.0, green: c.1, blue: c.2, alpha: 0.75),
                                          CGColor(red: c.0, green: c.1, blue: c.2, alpha: 0)] as CFArray,
                                 locations: [0, 0.22, 1]) else { return nil }
        let center = CGPoint(x: CGFloat(size) / 2, y: CGFloat(size) / 2)
        ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: CGFloat(size) / 2, options: [])
        return ctx.makeImage()
    }
}
