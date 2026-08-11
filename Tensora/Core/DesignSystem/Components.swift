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

enum InlineSheetDetent: CaseIterable {
    case collapsed
    case medium
    case large
}

/// A draggable bottom sheet that lays out inside its parent instead of being
/// presented over the window.
///
/// `.sheet` is presented on the window, so it covers the tab bar — on a screen
/// like Discover, where the sheet is always up, that leaves the tabs
/// unreachable. Drawing the sheet as an overlay on the tab's own content keeps
/// it above the map and below the tab bar, which stays visible and tappable.
///
/// `header` is the drag area (the grabber is drawn above it); `content` is
/// free to scroll on its own.
struct InlineBottomSheet<Header: View, Content: View>: View {

    @Binding var detent: InlineSheetDetent
    /// Height of the `.collapsed` detent, measured up from the bottom edge.
    var collapsedHeight: CGFloat = 140
    /// Points left uncovered above the sheet at the `.large` detent.
    var topInset: CGFloat = 64
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content

    @State private var dragOffset: CGFloat = 0

    private static var snap: Animation { .spring(response: 0.34, dampingFraction: 0.86) }

    var body: some View {
        GeometryReader { proxy in
            let available = proxy.size.height
            // Dragging up reads as a negative translation and grows the sheet.
            let live = (height(for: detent, in: available) - dragOffset)
                .clamped(to: collapsedHeight...largeHeight(in: available))

            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    grabber
                    header
                }
                .contentShape(Rectangle())
                .gesture(dragGesture(in: available))

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(width: proxy.size.width, height: live, alignment: .top)
            .background(Theme.background)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: Theme.Radius.large,
                    topTrailingRadius: Theme.Radius.large,
                    style: .continuous
                )
            )
            .shadow(color: .black.opacity(0.18), radius: 12, y: -4)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }

    private var grabber: some View {
        Capsule()
            .fill(Theme.separator)
            .frame(width: 36, height: 5)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(Self.snap) { detent = detent == .collapsed ? .medium : .collapsed }
            }
            .accessibilityLabel("Resize sheet")
            .accessibilityAddTraits(.isButton)
    }

    private func dragGesture(in available: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                dragOffset = value.translation.height
            }
            .onEnded { value in
                // Snap to whichever detent the flick was heading towards.
                let projected = height(for: detent, in: available) - value.predictedEndTranslation.height
                withAnimation(Self.snap) {
                    detent = nearestDetent(to: projected, in: available)
                    dragOffset = 0
                }
            }
    }

    private func nearestDetent(to height: CGFloat, in available: CGFloat) -> InlineSheetDetent {
        InlineSheetDetent.allCases.min {
            abs(self.height(for: $0, in: available) - height) < abs(self.height(for: $1, in: available) - height)
        } ?? detent
    }

    private func height(for detent: InlineSheetDetent, in available: CGFloat) -> CGFloat {
        switch detent {
        case .collapsed: return collapsedHeight
        case .medium: return max(collapsedHeight, available * 0.5)
        case .large: return largeHeight(in: available)
        }
    }

    private func largeHeight(in available: CGFloat) -> CGFloat {
        max(collapsedHeight, available - topInset)
    }
}

private extension CGFloat {
    /// `Swift.` qualified because inside a `CGFloat` extension the bare names
    /// resolve to `CGFloat.min` / `CGFloat.max`.
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
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
struct TensoraField: View {
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

struct TensoraSecureField: View {
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
