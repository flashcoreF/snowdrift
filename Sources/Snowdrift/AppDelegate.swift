import AppKit
import QuartzCore
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let engine = SnowEngine()
    private let tracker = WindowTracker()
    private let settings = Settings.shared
    private var overlays: [OverlayWindow] = []
    private var statusItem: NSStatusItem?
    private var frameTimer: Timer?
    private var windowTimer: Timer?
    private var lastTick = CACurrentMediaTime()
    private var hotKey: HotKey?
    private var previousApp: NSRunningApplication?
    private var wasIdle = false
    private var snowballMode = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        rebuildOverlays()

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(screensChanged),
                       name: NSApplication.didChangeScreenParametersNotification, object: nil)
        nc.addObserver(self, selector: #selector(toggleSnowballMode),
                       name: .snowdriftToggleSnowballMode, object: nil)
        nc.addObserver(self, selector: #selector(exitSnowballMode),
                       name: .snowdriftExitSnowballMode, object: nil)

        hotKey = HotKey()

        let frame = Timer(timeInterval: 1.0 / 60.0, target: self, selector: #selector(tick),
                          userInfo: nil, repeats: true)
        RunLoop.main.add(frame, forMode: .common)
        frameTimer = frame

        let win = Timer(timeInterval: 0.1, target: self, selector: #selector(refreshWindows),
                        userInfo: nil, repeats: true)
        RunLoop.main.add(win, forMode: .common)
        windowTimer = win
        refreshWindows()
    }

    // MARK: - Overlays

    private func rebuildOverlays() {
        for o in overlays { o.orderOut(nil) }
        let screens = NSScreen.screens
        let mainHeight = screens.first?.frame.height ?? 0
        engine.configure(screens: screens)
        overlays = screens.map { OverlayWindow.make(for: $0, engine: engine, mainHeight: mainHeight) }
        for o in overlays {
            o.ignoresMouseEvents = !snowballMode
            o.orderFrontRegardless()
        }
    }

    @objc private func screensChanged() {
        rebuildOverlays()
        refreshWindows()
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(max(now - lastTick, 0), 1.0 / 20.0)
        lastTick = now
        engine.step(dt: CGFloat(dt))
        let idle = engine.isIdle
        if idle && wasIdle { return }
        wasIdle = idle
        for o in overlays { o.snowView.needsDisplay = true }
    }

    @objc private func refreshWindows() {
        if engine.isIdle && !settings.enabled { return }
        engine.updateWindows(tracker.currentWindows())
    }

    // MARK: - Snowball mode

    @objc private func toggleSnowballMode() {
        setSnowballMode(!snowballMode)
    }

    @objc private func exitSnowballMode() {
        setSnowballMode(false)
    }

    private func setSnowballMode(_ on: Bool) {
        guard on != snowballMode else { return }
        snowballMode = on
        engine.snowballMode = on
        if !on { engine.cancelGather() }
        for o in overlays {
            o.ignoresMouseEvents = !on
            o.invalidateCursorRects(for: o.snowView)
            o.snowView.needsDisplay = true
        }
        if on {
            previousApp = NSWorkspace.shared.frontmostApplication
            NSApp.activate(ignoringOtherApps: true)
            let mouse = NSEvent.mouseLocation
            let target = overlays.first { $0.frame.contains(mouse) } ?? overlays.first
            target?.makeKeyAndOrderFront(nil)
            if let target { target.makeFirstResponder(target.snowView) }
        } else {
            if let app = previousApp, app != NSRunningApplication.current {
                app.activate(options: [])
            }
            previousApp = nil
            for o in overlays { o.orderFrontRegardless() }
        }
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "snowflake", accessibilityDescription: "Snowdrift")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Snowdrift"
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(item("Let it snow", #selector(toggleEnabled), on: settings.enabled))

        let snowfall = NSMenu()
        for level in Intensity.allCases {
            snowfall.addItem(item(level.title, #selector(setIntensity(_:)), on: settings.intensity == level, tag: level.rawValue))
        }
        menu.addItem(parent("Snowfall", snowfall))

        let wind = NSMenu()
        for level in WindStrength.allCases {
            wind.addItem(item(level.title, #selector(setWind(_:)), on: settings.wind == level, tag: level.rawValue))
        }
        menu.addItem(parent("Wind", wind))

        menu.addItem(.separator())
        menu.addItem(item("Snow settles on windows", #selector(toggleSettle), on: settings.settleOnWindows))
        menu.addItem(item("Cursor stirs the snow", #selector(toggleBreeze), on: settings.cursorBreeze))
        menu.addItem(item("Frosty screen edges", #selector(toggleFrost), on: settings.frost))

        menu.addItem(.separator())
        let balls = item(snowballMode ? "Stop throwing snowballs" : "Snowball mode", #selector(toggleSnowballMode))
        balls.keyEquivalent = "s"
        balls.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(balls)
        menu.addItem(item("Build a snowman", #selector(buildSnowman)))
        menu.addItem(item("Shake snow off windows", #selector(shakeOffWindows)))
        menu.addItem(item("Clear all snow", #selector(sweep)))

        menu.addItem(.separator())
        menu.addItem(item("Open at login", #selector(toggleLogin), on: SMAppService.mainApp.status == .enabled))
        menu.addItem(item("Quit Snowdrift", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, on: Bool? = nil, tag: Int = 0, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        i.tag = tag
        if let on { i.state = on ? .on : .off }
        return i
    }

    private func parent(_ title: String, _ submenu: NSMenu) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.submenu = submenu
        return i
    }

    @objc private func toggleEnabled() { settings.enabled.toggle() }
    @objc private func setIntensity(_ sender: NSMenuItem) {
        settings.intensity = Intensity(rawValue: sender.tag) ?? .medium
        if !settings.enabled { settings.enabled = true }
    }
    @objc private func setWind(_ sender: NSMenuItem) { settings.wind = WindStrength(rawValue: sender.tag) ?? .breeze }
    @objc private func toggleSettle() {
        settings.settleOnWindows.toggle()
        if !settings.settleOnWindows { engine.shakeOffWindows() }
    }
    @objc private func toggleBreeze() { settings.cursorBreeze.toggle() }
    @objc private func toggleFrost() { settings.frost.toggle() }
    @objc private func buildSnowman() { engine.buildSnowman() }
    @objc private func shakeOffWindows() { engine.shakeOffWindows() }
    @objc private func sweep() { engine.sweepAway() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change “Open at login”"
            alert.informativeText = "Move Snowdrift.app into your Applications folder and try again.\n\n\(error.localizedDescription)"
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
}
