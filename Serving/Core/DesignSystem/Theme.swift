import SwiftUI
import UIKit

/// Colors, spacing and type scale for the app.
///
/// Colors are defined in code (rather than an asset catalog) so the palette is
/// reviewable in a diff, and each one adapts to light / dark mode.
enum Theme {

    // MARK: Palette
    //
    // Every colour but the ball and the status colours comes from the court
    // style the player picked (`CourtStyle`), so switching styles re-skins
    // the whole app.

    private static var palette: CourtPalette { CourtStyle.current.palette }

    /// Primary actions, links, selection and the tracker.
    static var accent: Color { palette.accent }

    /// The court itself — deep, used for headers, the splash and secondary
    /// buttons.
    static var court: Color { palette.court }

    /// Top and bottom of the court gradient behind the landing screen and the
    /// Discover panel. Fixed: the same in light and dark mode.
    static var courtTop: Color { palette.courtTop }
    static var courtBottom: Color { palette.courtBottom }

    /// Near-black of the court's hue, for text and icons sitting on optic
    /// yellow.
    static var ink: Color { palette.ink }

    /// Optic yellow, the colour of the ball in the logo. A brand colour, so it
    /// does not change with the appearance or the court style.
    static let optic = Color(red: 0.84, green: 0.93, blue: 0.18)

    static let clay = Color(light: Color(red: 0.79, green: 0.42, blue: 0.27),
                            dark: Color(red: 0.86, green: 0.52, blue: 0.36))

    static var background: Color { palette.background }
    static var surface: Color { palette.surface }
    static var surfaceAlt: Color { palette.surfaceAlt }
    static var primaryText: Color { palette.primaryText }
    static var secondaryText: Color { palette.secondaryText }
    static var separator: Color { palette.separator }

    static let success = Color(light: Color(red: 0.14, green: 0.60, blue: 0.34),
                               dark: Color(red: 0.30, green: 0.78, blue: 0.48))

    static let warning = Color(light: Color(red: 0.85, green: 0.58, blue: 0.10),
                               dark: Color(red: 0.96, green: 0.72, blue: 0.26))

    static let danger = Color(light: Color(red: 0.78, green: 0.22, blue: 0.20),
                              dark: Color(red: 0.92, green: 0.38, blue: 0.35))

    // MARK: Metrics

    enum Radius {
        static let small: CGFloat = 10
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 14
        static let lg: CGFloat = 20
        static let xl: CGFloat = 28
    }
}

// MARK: - Court styles

/// The three surfaces the app can be dressed as. Picked on the player's
/// Profile and stored in `UserDefaults`, so it applies to every screen and
/// survives relaunches.
enum CourtStyle: String, CaseIterable, Identifiable {
    /// Cushioned acrylic: deep blue court, cool grey surrounds.
    case hard
    /// Lawn: deep green court, the original Serving look.
    case grass
    /// Crushed brick: terracotta court, warm sand surrounds.
    case clay

    static let storageKey = "courtStyle"
    static let defaultStyle = CourtStyle.grass

    var id: String { rawValue }

    static var current: CourtStyle {
        UserDefaults.standard.string(forKey: storageKey).flatMap(CourtStyle.init) ?? defaultStyle
    }

    var name: String {
        switch self {
        case .hard: return "Hard"
        case .grass: return "Grass"
        case .clay: return "Clay"
        }
    }

    var tagline: String {
        switch self {
        case .hard: return "Cool blue acrylic"
        case .grass: return "Classic lawn green"
        case .clay: return "Warm crushed brick"
        }
    }

    var palette: CourtPalette {
        switch self {
        case .hard: return .hard
        case .grass: return .grass
        case .clay: return .clay
        }
    }
}

/// The colours one court style supplies to `Theme`.
struct CourtPalette {
    let accent: Color
    let court: Color
    let courtTop: Color
    let courtBottom: Color
    let ink: Color
    let background: Color
    let surface: Color
    let surfaceAlt: Color
    let primaryText: Color
    let secondaryText: Color
    let separator: Color

    /// Blue hard court with a brighter blue for actions.
    static let hard = CourtPalette(
        accent: Color(light: .rgb(0.12, 0.42, 0.85), dark: .rgb(0.38, 0.62, 0.98)),
        court: Color(light: .rgb(0.09, 0.20, 0.42), dark: .rgb(0.06, 0.13, 0.28)),
        courtTop: .rgb(0.11, 0.28, 0.54),
        courtBottom: .rgb(0.05, 0.12, 0.27),
        ink: .rgb(0.04, 0.10, 0.22),
        background: Color(light: .rgb(0.95, 0.96, 0.98), dark: .rgb(0.06, 0.07, 0.10)),
        surface: Color(light: .white, dark: .rgb(0.12, 0.13, 0.17)),
        surfaceAlt: Color(light: .rgb(0.91, 0.93, 0.96), dark: .rgb(0.17, 0.19, 0.24)),
        primaryText: Color(light: .rgb(0.07, 0.09, 0.14), dark: .rgb(0.95, 0.96, 0.98)),
        secondaryText: Color(light: .rgb(0.37, 0.41, 0.49), dark: .rgb(0.64, 0.68, 0.76)),
        separator: Color(light: .rgb(0.85, 0.88, 0.92), dark: .rgb(0.23, 0.25, 0.31))
    )

    /// Lawn green with a tennis-ball green for actions — the original look.
    static let grass = CourtPalette(
        accent: Color(light: .rgb(0.42, 0.71, 0.13), dark: .rgb(0.62, 0.85, 0.27)),
        court: Color(light: .rgb(0.07, 0.26, 0.21), dark: .rgb(0.05, 0.18, 0.15)),
        courtTop: .rgb(0.08, 0.29, 0.23),
        courtBottom: .rgb(0.03, 0.14, 0.11),
        ink: .rgb(0.04, 0.16, 0.13),
        background: Color(light: .rgb(0.96, 0.97, 0.96), dark: .rgb(0.07, 0.08, 0.08)),
        surface: Color(light: .white, dark: .rgb(0.13, 0.14, 0.14)),
        surfaceAlt: Color(light: .rgb(0.93, 0.94, 0.93), dark: .rgb(0.18, 0.19, 0.19)),
        primaryText: Color(light: .rgb(0.08, 0.10, 0.09), dark: .rgb(0.96, 0.97, 0.96)),
        secondaryText: Color(light: .rgb(0.38, 0.42, 0.40), dark: .rgb(0.66, 0.70, 0.68)),
        separator: Color(light: .rgb(0.87, 0.88, 0.87), dark: .rgb(0.24, 0.25, 0.25))
    )

    /// Terracotta court with a burnt-orange for actions and sandy surrounds.
    static let clay = CourtPalette(
        accent: Color(light: .rgb(0.78, 0.35, 0.17), dark: .rgb(0.92, 0.52, 0.31)),
        court: Color(light: .rgb(0.42, 0.17, 0.09), dark: .rgb(0.30, 0.12, 0.06)),
        courtTop: .rgb(0.66, 0.29, 0.15),
        courtBottom: .rgb(0.33, 0.12, 0.06),
        ink: .rgb(0.25, 0.09, 0.04),
        background: Color(light: .rgb(0.98, 0.96, 0.94), dark: .rgb(0.09, 0.07, 0.06)),
        surface: Color(light: .white, dark: .rgb(0.16, 0.13, 0.12)),
        surfaceAlt: Color(light: .rgb(0.95, 0.92, 0.89), dark: .rgb(0.21, 0.18, 0.16)),
        primaryText: Color(light: .rgb(0.14, 0.09, 0.07), dark: .rgb(0.98, 0.95, 0.93)),
        secondaryText: Color(light: .rgb(0.47, 0.39, 0.35), dark: .rgb(0.72, 0.65, 0.61)),
        separator: Color(light: .rgb(0.90, 0.86, 0.83), dark: .rgb(0.29, 0.25, 0.23))
    )
}

private extension Color {
    static func rgb(_ red: Double, _ green: Double, _ blue: Double) -> Color {
        Color(red: red, green: green, blue: blue)
    }
}

extension Color {
    /// Builds a dynamic color without needing an asset catalog entry.
    init(light: Color, dark: Color) {
        self = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

extension StringCategory {
    var tint: Color {
        switch self {
        case .polyester: return Theme.court
        case .multifilament: return Theme.accent
        case .syntheticGut: return Theme.secondaryText
        case .naturalGut: return Theme.clay
        case .hybrid: return Theme.warning
        case .badminton: return Theme.success
        }
    }
}

extension OrderStatus {
    var tint: Color {
        switch self {
        case .awaitingBusiness: return Theme.warning
        case .awaitingPlayerApproval: return Theme.clay
        case .confirmed: return Theme.accent
        case .inProgress: return Theme.court
        case .complete: return Theme.success
        case .pickedUp: return Theme.secondaryText
        case .declined, .cancelled: return Theme.danger
        }
    }
}

extension PayoutStatus {
    var tint: Color {
        switch self {
        case .active: return Theme.success
        case .pendingVerification: return Theme.warning
        case .paused: return Theme.danger
        case .notConnected: return Theme.secondaryText
        }
    }
}
