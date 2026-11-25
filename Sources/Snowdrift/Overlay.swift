import AppKit

extension Notification.Name {
    static let snowdriftToggleSnowballMode = Notification.Name("SnowdriftToggleSnowballMode")
    static let snowdriftExitSnowballMode = Notification.Name("SnowdriftExitSnowballMode")
}

/// A transparent, click-through window covering one display.
final class OverlayWindow: NSWindow {
    var snowView: SnowView!

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    @MainActor
    static func make(for screen: NSScreen, engine: SnowEngine, mainHeight: CGFloat) -> OverlayWindow {
        let w = OverlayWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.level = .statusBar
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        w.isReleasedWhenClosed = false
        w.animationBehavior = .none

        let view = SnowView(engine: engine)
        view.quartzOrigin = CGPoint(x: screen.frame.minX, y: mainHeight - screen.frame.maxY)
        w.contentView = view
        w.snowView = view
        w.setFrame(screen.frame, display: false)
        return w
    }
}

/// Draws this display's slice of the snow world.
final class SnowView: NSView {
    let engine: SnowEngine
    /// Top-left of this display in global Quartz coordinates.
    var quartzOrigin = CGPoint.zero

    init(engine: SnowEngine) {
        self.engine = engine
        super.init(frame: .zero)
        wantsLayer = true
        layer?.isOpaque = false
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        ctx.saveGState()
        ctx.translateBy(x: -quartzOrigin.x, y: -quartzOrigin.y)
        engine.draw(in: ctx, rect: CGRect(origin: quartzOrigin, size: bounds.size))
        ctx.restoreGState()
        if let festive = engine.festive { drawTexts(festive.overlayTexts) }
        if engine.snowballMode { drawHint() }
    }

    /// Countdown numbers, the New Year banner and gift messages.
    private func drawTexts(_ texts: [OverlayText]) {
        let screenRect = CGRect(origin: quartzOrigin, size: bounds.size)
        for t in texts where t.alpha > 0.01 {
            let center: CGPoint
            if let p = t.position {
                guard screenRect.insetBy(dx: -200, dy: -100).contains(p) else { continue }
                center = CGPoint(x: p.x - quartzOrigin.x, y: p.y - quartzOrigin.y)
            } else {
                center = CGPoint(x: bounds.midX, y: bounds.midY * 0.8)
            }
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.55 * t.alpha)
            shadow.shadowBlurRadius = t.size / 6
            shadow.shadowOffset = NSSize(width: 0, height: -2)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: t.size * t.scale, weight: t.size > 40 ? .heavy : .semibold),
                .foregroundColor: t.color.withAlphaComponent(t.alpha),
                .shadow: shadow,
            ]
            let str = NSAttributedString(string: t.text, attributes: attrs)
            let sz = str.size()
            str.draw(at: NSPoint(x: center.x - sz.width / 2, y: center.y - sz.height / 2))
        }
    }

    private func drawHint() {
        let text = "Snowball mode  ·  hold to scoop snow, flick to throw  ·  click a present to open it  ·  double-click for a snowman  ·  Esc to exit"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let pill = NSRect(x: (bounds.width - size.width) / 2 - 16, y: 44,
                          width: size.width + 32, height: size.height + 14)
        NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.2, alpha: 0.72).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        str.draw(at: NSPoint(x: pill.minX + 16, y: pill.minY + 7))
    }

    // MARK: Snowball mode input

    override func mouseDown(with event: NSEvent) {
        engine.sampleMouse(dt: 0)
        // Clicking a present opens it.
        if let festive = engine.festive, festive.handleClick(at: engine.mouse) {
            engine.cancelGather()
            return
        }
        if event.clickCount >= 2 {
            engine.cancelGather()
            engine.cancelRecentBall()
            engine.buildSnowman(nearX: engine.mouse.x)
            return
        }
        engine.beginGather()
    }

    override func mouseUp(with event: NSEvent) {
        engine.releaseBall()
    }

    override func rightMouseDown(with event: NSEvent) {
        NotificationCenter.default.post(name: .snowdriftExitSnowballMode, object: nil)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            NotificationCenter.default.post(name: .snowdriftExitSnowballMode, object: nil)
        } else {
            super.keyDown(with: event)
        }
    }

    override func resetCursorRects() {
        if engine.snowballMode { addCursorRect(bounds, cursor: .crosshair) }
    }
}
