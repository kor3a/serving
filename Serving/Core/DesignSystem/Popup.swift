import SwiftUI

/// The confirming button on a `popup`. The cancel button is always added.
struct PopupAction {
    enum Role {
        case standard
        case destructive
    }

    let title: String
    var role: Role = .standard
    let action: () -> Void

    init(_ title: String, role: Role = .standard, action: @escaping () -> Void) {
        self.title = title
        self.role = role
        self.action = action
    }
}

/// A card in the middle of the screen over a dimmed background.
///
/// Used instead of `confirmationDialog`, which iOS anchors to the top of the
/// screen when it has no source view — far from a Sign out button at the
/// bottom of a list.
struct CenteredPopup: ViewModifier {
    let title: String
    let message: String?
    let confirm: PopupAction?
    let cancelTitle: String
    @Binding var isPresented: Bool

    /// Drives the full-screen cover. Kept apart from `isPresented` so the cover
    /// can appear and disappear without its slide animation; the card fades
    /// and scales in on its own instead.
    @State private var isCovering = false

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $isCovering) {
                PopupCard(
                    title: title,
                    message: message,
                    confirm: confirm,
                    cancelTitle: cancelTitle,
                    onFinish: finish
                )
                .presentationBackground(.clear)
            }
            .onChange(of: isPresented, initial: true) { _, newValue in
                guard newValue != isCovering else { return }
                withoutAnimation { isCovering = newValue }
            }
    }

    /// Called once the card has animated out. The chosen action runs after the
    /// cover is gone, so anything it presents (an error, a dismiss) isn't
    /// fighting the pop-up's own dismissal.
    private func finish(_ action: (() -> Void)?) {
        withoutAnimation { isCovering = false }
        isPresented = false
        action?()
    }

    private func withoutAnimation(_ body: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, body)
    }
}

private struct PopupCard: View {
    let title: String
    let message: String?
    let confirm: PopupAction?
    let cancelTitle: String
    let onFinish: ((() -> Void)?) -> Void

    @State private var isShowing = false
    @State private var isClosing = false

    var body: some View {
        ZStack {
            Color.black
                .opacity(isShowing ? 0.4 : 0)
                .ignoresSafeArea()
                .onTapGesture { close(then: nil) }
                .accessibilityHidden(true)

            if isShowing {
                card
                    .padding(.horizontal, Theme.Spacing.xl)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                isShowing = true
            }
        }
    }

    private var card: some View {
        VStack(spacing: Theme.Spacing.lg) {
            VStack(spacing: Theme.Spacing.sm) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                    .accessibilityAddTraits(.isHeader)
                if let message {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: Theme.Spacing.sm) {
                if let confirm {
                    Button(confirm.title) { close(then: confirm.action) }
                        .buttonStyle(PrimaryButtonStyle(
                            tint: confirm.role == .destructive ? Theme.danger : Theme.accent
                        ))
                }
                Button(cancelTitle) { close(then: nil) }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: 340)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .fill(Theme.surface)
        )
        .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private func close(then action: (() -> Void)?) {
        guard !isClosing else { return }
        isClosing = true
        withAnimation(.easeIn(duration: 0.15)) {
            isShowing = false
        } completion: {
            onFinish(action)
        }
    }
}

extension View {
    /// Asks the user to confirm something in a card centred on screen.
    /// With no `confirm` action it is a plain notice with one button.
    func popup(
        _ title: String,
        isPresented: Binding<Bool>,
        message: String? = nil,
        confirm: PopupAction? = nil,
        cancelTitle: String = "Cancel"
    ) -> some View {
        modifier(CenteredPopup(
            title: title,
            message: message,
            confirm: confirm,
            cancelTitle: cancelTitle,
            isPresented: isPresented
        ))
    }
}
