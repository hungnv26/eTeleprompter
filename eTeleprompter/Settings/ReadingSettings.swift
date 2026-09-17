import Foundation

/// The 5 fixed font choices (SPEC F3). Raw values are the persisted
/// identifiers; the view layer maps cases to SwiftUI fonts/designs.
enum PrompterFont: String, Codable, CaseIterable, Sendable {
    case sfPro
    case newYork
    case helveticaNeue
    case georgia
    case menlo

    var displayName: String {
        switch self {
        case .sfPro: "SF Pro"
        case .newYork: "New York"
        case .helveticaNeue: "Helvetica Neue"
        case .georgia: "Georgia"
        case .menlo: "Menlo"
        }
    }
}

/// Rotation applied to the scrolling text (mirror mode). Raw value is the
/// angle in degrees.
enum RotationAngle: Int, Codable, CaseIterable, Sendable {
    case deg0 = 0
    case deg90 = 90
    case deg180 = 180
    case deg270 = 270

    var degrees: Double { Double(rawValue) }
}

/// Global reading/mirror/speed settings (WP4). Codable struct persisted as
/// JSON under a single UserDefaults key by SettingsStore. Global, not
/// per-script (SPEC F3). Colors are stored as palette identifiers, never as
/// raw color values.
struct ReadingSettings: Codable, Equatable {

    // MARK: Text appearance

    /// Font family, from the fixed 5-font list.
    var font: PrompterFont = .sfPro
    /// Font size in points, 20...120.
    var fontSize: Double = 48
    /// Line spacing multiplier, 1.0...2.0.
    var lineSpacing: Double = 1.4
    /// Symmetric left/right margin as a fraction of width, 0...0.25.
    var marginFraction: Double = 0.10

    // MARK: Colors (palette identifiers — see PresetPalette)

    var textColorID: String = PresetPalette.white.id
    var backgroundColorID: String = PresetPalette.black.id

    // MARK: Mirror mode

    var mirrorHorizontal: Bool = false
    var flipVertical: Bool = false
    var rotation: RotationAngle = .deg0

    // MARK: Speed

    /// Persisted prompter speed in points/second (engine clamps 10...300).
    var speed: Double = PrompterEngine.defaultSpeed

    // MARK: Ranges (single source of truth for the settings UI)

    static let fontSizeRange: ClosedRange<Double> = 20...120
    static let lineSpacingRange: ClosedRange<Double> = 1.0...2.0
    static let marginFractionRange: ClosedRange<Double> = 0...0.25

    /// SPEC defaults: SF Pro 48 pt, line spacing 1.4, margins 10 %,
    /// white text on black, no mirror, 0°, 60 pts/s.
    static let `default` = ReadingSettings()

    /// First-run defaults for a phone-sized screen. Identical to `default`
    /// except 30 pt instead of 48: on a ~400 pt-wide display, 48 pt leaves
    /// only three or four words per line. Settings are per-device (no sync),
    /// so this only ever seeds a phone that has nothing stored yet.
    static let phoneDefault: ReadingSettings = {
        var s = ReadingSettings()
        s.fontSize = 30
        return s
    }()

    // MARK: Resolved colors

    /// The text swatch, falling back to the default (white) if the persisted
    /// identifier is unknown.
    var textColor: PresetColor {
        PresetPalette.color(withID: textColorID) ?? PresetPalette.white
    }

    /// The background swatch, falling back to the default (black) if the
    /// persisted identifier is unknown.
    var backgroundColor: PresetColor {
        PresetPalette.color(withID: backgroundColorID) ?? PresetPalette.black
    }
}
