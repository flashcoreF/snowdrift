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
        if engine.snowballMode { drawHint() }
    }

    private func drawHint() {
        let text = "Snowball mode  ·  hold to scoop snow, flick to throw  ·  double-click to build a snowman  ·  Esc to exit"
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
        if event.clickCount >= 2 {
            engine.cancelGather()
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
