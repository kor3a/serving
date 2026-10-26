import SwiftUI

struct LandingView: View {

    @EnvironmentObject private var session: SessionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    private let steps: [Step] = [
        Step(icon: "mappin.and.ellipse",
             title: "Find a stringer nearby",
             detail: "Shops and home stringers, on one map."),
        Step(icon: "point.3.connected.trianglepath.dotted",
             title: "Pick your string",
             detail: "Choose from their wall, or bring your own."),
        Step(icon: "calendar.badge.checkmark",
             title: "Book a drop-off",
             detail: "You're only charged once they confirm.")
    ]

    var body: some View {
        ZStack {
            background

            GeometryReader { proxy in
                content(heroHeight: min(200, max(120, proxy.size.height * 0.2)))
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { hasAppeared = true }
    }

    private func content(heroHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            hero(height: heroHeight)

            Spacer(minLength: Theme.Spacing.md)

            headline
                .padding(.bottom, Theme.Spacing.xl)

            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    StepRow(step: step)
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 12)
                        .animation(.easeOut(duration: 0.45).delay(0.35 + Double(index) * 0.08),
                                   value: hasAppeared)
                }
            }

            Spacer(minLength: Theme.Spacing.xl)

            VStack(spacing: Theme.Spacing.md) {
                Button {
                    session.beginAuthentication()
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text("Get started")
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(OpticButtonStyle())

                Text("For players and the stringers who serve them.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity)
            }
            .opacity(hasAppeared ? 1 : 0)
            .animation(.easeOut(duration: 0.5).delay(0.6), value: hasAppeared)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.md)
    }

    // MARK: - Pieces

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.29, blue: 0.23), Color(red: 0.02, green: 0.11, blue: 0.09)],
                startPoint: .topLeading,
                endPoint: .bottom
            )

            // The glow the ball sits in.
            RadialGradient(
                colors: [Theme.optic.opacity(0.18), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }

    /// Wordmark on the left; the ball rolls in from the right and rests half
    /// off the edge. It has its own band, sized to the screen, so it never
    /// runs into the headline.
    private func hero(height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            BallMark()
                .frame(width: height * 1.15, height: height * 1.15)
                .rotationEffect(.degrees(hasAppeared || reduceMotion ? -8 : 200))
                .offset(x: hasAppeared ? height * 0.4 : height * 1.3, y: -height * 0.2)
                .opacity(hasAppeared ? 1 : 0)
                .animation(.spring(response: 0.9, dampingFraction: 0.8), value: hasAppeared)
                .frame(maxWidth: .infinity, alignment: .topTrailing)

            Text("Serving")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(height: height, alignment: .top)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Restrung by\n\(Text("someone near you.").foregroundStyle(Theme.optic))")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineSpacing(-2)
                .fixedSize(horizontal: false, vertical: true)

            Text("Book a stringing in a couple of taps and pick it up ready to play.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 16)
        .animation(.easeOut(duration: 0.55).delay(0.15), value: hasAppeared)
    }
}

// MARK: - Steps

private struct Step {
    let icon: String
    let title: String
    let detail: String
}

private struct StepRow: View {
    let step: Step

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: step.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.optic)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.small + 2, style: .continuous)
                        .fill(.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.small + 2, style: .continuous)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(step.detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Button

/// Optic-yellow call to action with dark text, so it reads on the court green.
private struct OpticButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color(red: 0.04, green: 0.16, blue: 0.13))
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .fill(Theme.optic)
            )
            .shadow(color: Theme.optic.opacity(0.35), radius: 16, y: 6)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    LandingView()
        .environmentObject(SessionStore(backend: AppEnvironment.previewBackend()))
}
