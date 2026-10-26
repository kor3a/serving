import SwiftUI
import UIKit

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent
    var isLoading: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        // Rendered by a real View so it can read `isEnabled` from the
        // environment — a ButtonStyle itself never gets environment updates.
        PrimaryButtonBody(configuration: configuration, tint: tint, isLoading: isLoading)
    }
}

private struct PrimaryButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let tint: Color
    let isLoading: Bool

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        ZStack {
            configuration.label
                .opacity(isLoading ? 0 : 1)
            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            }
        }
        .font(.headline)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .fill(tint.opacity(isEnabled ? 1 : 0.35))
        )
        .scaleEffect(configuration.isPressed ? 0.98 : 1)
        .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.court

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .stroke(tint.opacity(0.35), lineWidth: 1.5)
            )
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .fill(Theme.surface)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Containers

struct Card<Content: View>: View {
    var padding: CGFloat = Theme.Spacing.md
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .stroke(Theme.separator, lineWidth: 1)
            )
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
    }
}

// MARK: - Small pieces

/// A racquet for the sport, drawn in code — the racquet itself rather than
/// SF Symbols' figure playing the sport.
///
/// A badminton racquet is the narrower head on the longer shaft.
struct RacquetGlyph: View {
    let sport: RacquetSport
    var height: CGFloat = 14

    var body: some View {
        let headHeight = height * (sport == .tennis ? 0.58 : 0.46)
        let width = height * (sport == .tennis ? 0.52 : 0.36)
        let lineWidth = max(1, height * 0.09)

        ZStack(alignment: .top) {
            // Head
            Ellipse()
                .stroke(lineWidth: lineWidth)
                .frame(width: width, height: headHeight)

            // Shaft
            Capsule()
                .frame(width: lineWidth, height: height - headHeight + lineWidth)
                .offset(y: headHeight - lineWidth / 2)

            // Butt of the grip
            Capsule()
                .frame(width: max(width * 0.5, lineWidth * 2), height: lineWidth)
                .offset(y: height - lineWidth)
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}

struct Badge: View {
    let text: String
    var tint: Color = Theme.accent
    var filled: Bool = false

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(filled ? .white : tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(filled ? tint : tint.opacity(0.14))
            )
    }
}

struct LabeledRow: View {
    let label: String
    let value: String
    var valueColor: Color = Theme.primaryText
    var isMonospaced: Bool = false

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            Spacer(minLength: Theme.Spacing.md)
            Text(value)
                .font(isMonospaced ? .subheadline.monospacedDigit() : .subheadline.weight(.medium))
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// Drop-off / pick-up rows on the order confirmation screen.
struct ScheduleRow: View {
    let title: String
    let date: Date?
    let iconName: String
    var placeholder: String = "To be confirmed"
    var detail: String?

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: iconName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                Text(date?.dropOffLabel ?? placeholder)
                    .font(.headline)
                    .foregroundStyle(date == nil ? Theme.secondaryText : Theme.primaryText)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var caption: String?
    var tint: Color = Theme.court
    var iconName: String?

    var body: some View {
        Card(padding: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if let iconName {
                        Image(systemName: iconName)
                            .font(.caption)
                            .foregroundStyle(tint)
                    }
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                Text(value)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.primaryText)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                if let caption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(2)
                }
            }
        }
    }
}

struct EmptyStateView: View {
    let iconName: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: iconName)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.secondaryText)
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(SecondaryButtonStyle())
                    .frame(maxWidth: 240)
                    .padding(.top, Theme.Spacing.sm)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
    }
}

/// Text field styled to match the onboarding forms.
struct ServingField: View {
    let title: String
    var placeholder: String = ""
    @Binding var text: String
    var isDisabled: Bool = false
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType?
    var autocapitalization: TextInputAutocapitalization = .sentences
    var footnote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.secondaryText)

            TextField(placeholder.isEmpty ? title : placeholder, text: $text)
                .textFieldStyle(.plain)
                .keyboardType(keyboard)
                .textContentType(contentType)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled()
                .disabled(isDisabled)
                .foregroundStyle(isDisabled ? Theme.secondaryText : Theme.primaryText)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                        .fill(isDisabled ? Theme.surfaceAlt : Theme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                        .stroke(Theme.separator, lineWidth: 1)
                )

            if let footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

struct ServingSecureField: View {
    let title: String
    @Binding var text: String
    var footnote: String?
    @State private var isRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.secondaryText)

            HStack {
                Group {
                    if isRevealed {
                        TextField(title, text: $text)
                    } else {
                        SecureField(title, text: $text)
                    }
                }
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .stroke(Theme.separator, lineWidth: 1)
            )

            if let footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

// MARK: - Modifiers

extension View {
    /// Standard screen background used across both account types.
    func screenBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
    }

    @ViewBuilder
    func hidden(_ isHidden: Bool) -> some View {
        if isHidden { self.hidden() } else { self }
    }
}

/// Presents `BackendError` (and anything else) as an alert.
struct ErrorAlert: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.alert(
            "Something went wrong",
            isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) { message = nil }
            },
            message: {
                Text(message ?? "")
            }
        )
    }
}

extension View {
    func errorAlert(message: Binding<String?>) -> some View {
        modifier(ErrorAlert(message: message))
    }
}
