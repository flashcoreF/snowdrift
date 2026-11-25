import AppKit
import CoreGraphics

/// A normal app window on screen, in global Quartz coordinates
/// (origin at the top-left of the main display, y grows downward).
struct TrackedWindow {
    let id: CGWindowID
    let frame: CGRect
}

/// Reads the positions of other apps' windows.
/// Window bounds are available without Screen Recording permission.
final class WindowTracker {
    private let ownPID = getpid()

    /// Visible windows, front-most first.
    func currentWindows() -> [TrackedWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var result: [TrackedWindow] = []
        for w in info {
            guard let layer = (w[kCGWindowLayer as String] as? NSNumber)?.intValue, layer == 0 else { continue }
            if let pid = (w[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid == ownPID { continue }
            if let alpha = (w[kCGWindowAlpha as String] as? NSNumber)?.doubleValue, alpha < 0.05 { continue }
            guard let boundsDict = w[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            guard rect.width >= 80, rect.height >= 40 else { continue }
            guard let number = (w[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { continue }
            result.append(TrackedWindow(id: CGWindowID(number), frame: rect))
        }
        return result
    }
}
