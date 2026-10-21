import SwiftUI
import UIKit

/// Colors, spacing and type scale for the app.
///
/// Colors are defined in code (rather than an asset catalog) so the palette is
/// reviewable in a diff, and each one adapts to light / dark mode.
enum Theme {

    // MARK: Palette

    /// Tennis-ball yellow-green. Used for primary actions and the tracker.
    static let accent = Color(light: Color(red: 0.42, green: 0.71, blue: 0.13),
                              dark: Color(red: 0.62, green: 0.85, blue: 0.27))

    /// Deep court green, used for headers and the landing gradient.
    static let court = Color(light: Color(red: 0.07, green: 0.26, blue: 0.21),
                             dark: Color(red: 0.05, green: 0.18, blue: 0.15))

    static let clay = Color(light: Color(red: 0.79, green: 0.42, blue: 0.27),
                            dark: Color(red: 0.86, green: 0.52, blue: 0.36))

    static let background = Color(light: Color(red: 0.96, green: 0.97, blue: 0.96),
                                  dark: Color(red: 0.07, green: 0.08, blue: 0.08))

    static let surface = Color(light: .white,
                               dark: Color(red: 0.13, green: 0.14, blue: 0.14))

    static let surfaceAlt = Color(light: Color(red: 0.93, green: 0.94, blue: 0.93),
                                  dark: Color(red: 0.18, green: 0.19, blue: 0.19))

    static let primaryText = Color(light: Color(red: 0.08, green: 0.10, blue: 0.09),
                                   dark: Color(red: 0.96, green: 0.97, blue: 0.96))

    static let secondaryText = Color(light: Color(red: 0.38, green: 0.42, blue: 0.40),
                                     dark: Color(red: 0.66, green: 0.70, blue: 0.68))

    static let separator = Color(light: Color(red: 0.87, green: 0.88, blue: 0.87),
                                 dark: Color(red: 0.24, green: 0.25, blue: 0.25))

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
