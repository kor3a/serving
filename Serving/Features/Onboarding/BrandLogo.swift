import SwiftUI

/// Serving mark: an optic-yellow ball whose seam is an "S", drawn in code so
/// it scales cleanly everywhere it appears. The app icon is rendered from the
/// same geometry by `Scripts/render_app_icon.swift`.
struct BrandLogo: View {

    var size: CGFloat = 88
    var tint: Color = .white
    var showsWordmark = false

    var body: some View {
        VStack(spacing: size * 0.2) {
            BallMark()
                .frame(width: size, height: size)

            if showsWordmark {
                VStack(spacing: 2) {
                    Text("Serving")
                        .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                    Text("Strung by someone near you")
                        .font(.system(size: size * 0.12, weight: .medium))
                        .foregroundStyle(tint.opacity(0.75))
                }
            }
        }
    }
}

/// The ball on its own, sized by its frame.
struct BallMark: View {

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.93, green: 0.98, blue: 0.42),
                                Theme.optic,
                                Color(red: 0.60, green: 0.76, blue: 0.10)
                            ],
                            center: UnitPoint(x: 0.32, y: 0.28),
                            startRadius: 0,
                            endRadius: diameter * 0.75
                        )
                    )

                SeamS()
                    .stroke(.white, style: StrokeStyle(lineWidth: diameter * 0.078, lineCap: .round))
            }
            .frame(width: diameter, height: diameter)
            .clipShape(Circle())
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// The seam: an S that is point-symmetric about the centre of the ball. Its
/// ends run past the edge and are clipped by the ball.
private struct SeamS: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }

        var path = Path()
        path.move(to: point(0.80, -0.04))
        path.addCurve(to: point(0.5, 0.5), control1: point(0.24, 0.00), control2: point(0.14, 0.42))
        path.addCurve(to: point(0.20, 1.04), control1: point(0.86, 0.58), control2: point(0.76, 1.00))
        return path
    }
}

#Preview {
    ZStack {
        Theme.court.ignoresSafeArea()
        BrandLogo(size: 120, showsWordmark: true)
    }
}
