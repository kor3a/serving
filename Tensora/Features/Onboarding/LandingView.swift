import SwiftUI

struct LandingView: View {

    @EnvironmentObject private var session: SessionStore
    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.court, Theme.court.opacity(0.85), Color.black.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Faint string-bed texture behind the mark.
            Ellipse()
                .stroke(Color.white.opacity(0.05), lineWidth: 40)
                .frame(width: 460, height: 560)
                .offset(y: -120)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                BrandLogo(size: 132, showsWordmark: true)
                    .scaleEffect(hasAppeared ? 1 : 0.9)
                    .opacity(hasAppeared ? 1 : 0)
                    .animation(.spring(response: 0.7, dampingFraction: 0.75), value: hasAppeared)

                Spacer()

                VStack(spacing: Theme.Spacing.md) {
                    Button("Get started") {
                        session.beginAuthentication()
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Text("Find a stringer, pick your string, book a drop-off.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xl)
                .opacity(hasAppeared ? 1 : 0)
                .animation(.easeOut(duration: 0.5).delay(0.2), value: hasAppeared)
            }
        }
        .onAppear { hasAppeared = true }
    }
}

#Preview {
    LandingView()
        .environmentObject(SessionStore(backend: AppEnvironment.previewBackend()))
}
