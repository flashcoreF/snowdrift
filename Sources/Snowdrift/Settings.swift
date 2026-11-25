import Foundation

enum Intensity: Int, CaseIterable {
    case light, medium, heavy, blizzard

    var title: String {
        switch self {
        case .light: return "Light flurries"
        case .medium: return "Steady snow"
        case .heavy: return "Heavy snow"
        case .blizzard: return "Blizzard"
        }
    }

    /// Flakes spawned per second for a ~1500pt wide screen.
    var flakesPerSecond: Double {
        switch self {
        case .light: return 25
        case .medium: return 60
        case .heavy: return 130
        case .blizzard: return 280
        }
    }
}

enum WindStrength: Int, CaseIterable {
    case calm, breeze, gusty

    var title: String {
        switch self {
        case .calm: return "Calm"
        case .breeze: return "Gentle breeze"
        case .gusty: return "Gusty"
        }
    }

    var base: Double {
        switch self {
        case .calm: return 0
        case .breeze: return 22
        case .gusty: return 55
        }
    }
}

enum LightStyle: Int, CaseIterable {
    case multicolor, warmWhite, icyBlue, off

    var title: String {
        switch self {
        case .multicolor: return "Colourful"
        case .warmWhite: return "Warm white"
        case .icyBlue: return "Icy blue"
        case .off: return "No lights"
        }
    }
}

/// User preferences, stored in UserDefaults.
final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard

    private func bool(_ key: String, _ def: Bool) -> Bool {
        d.object(forKey: key) as? Bool ?? def
    }

    var enabled: Bool {
        get { bool("enabled", true) }
        set { d.set(newValue, forKey: "enabled") }
    }

    var intensity: Intensity {
        get { Intensity(rawValue: d.object(forKey: "intensity") as? Int ?? 1) ?? .medium }
        set { d.set(newValue.rawValue, forKey: "intensity") }
    }

    var wind: WindStrength {
        get { WindStrength(rawValue: d.object(forKey: "wind") as? Int ?? 1) ?? .breeze }
        set { d.set(newValue.rawValue, forKey: "wind") }
    }

    var settleOnWindows: Bool {
        get { bool("settleOnWindows", true) }
        set { d.set(newValue, forKey: "settleOnWindows") }
    }

    var cursorBreeze: Bool {
        get { bool("cursorBreeze", true) }
        set { d.set(newValue, forKey: "cursorBreeze") }
    }

    /// Master switch for the Christmas and New Year decorations.
    var holiday: Bool {
        get { bool("holiday", true) }
        set { d.set(newValue, forKey: "holiday") }
    }

    var lights: LightStyle {
        get { LightStyle(rawValue: d.object(forKey: "lights") as? Int ?? 0) ?? .multicolor }
        set { d.set(newValue.rawValue, forKey: "lights") }
    }

    var tree: Bool {
        get { bool("tree", true) }
        set { d.set(newValue, forKey: "tree") }
    }

    var sleigh: Bool {
        get { bool("sleigh", true) }
        set { d.set(newValue, forKey: "sleigh") }
    }

    var sounds: Bool {
        get { bool("sounds", false) }
        set { d.set(newValue, forKey: "sounds") }
    }

    var newYearShow: Bool {
        get { bool("newYearShow", true) }
        set { d.set(newValue, forKey: "newYearShow") }
    }

    var frost: Bool {
        get { bool("frost", false) }
        set { d.set(newValue, forKey: "frost") }
    }
}
