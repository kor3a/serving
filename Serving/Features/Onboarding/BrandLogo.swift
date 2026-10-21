import SwiftUI

/// Serving mark: a racquet head with its string bed, drawn in code so it
/// scales cleanly everywhere it appears.
struct BrandLogo: View {

    var size: CGFloat = 88
    var tint: Color = .white
    var showsWordmark = false

    var body: some View {
        VStack(spacing: size * 0.18) {
            RacquetMark(tint: tint)
                .frame(width: size, height: size * 1.28)

            if showsWordmark {
                VStack(spacing: 2) {
                    Text("SERVING")
                        .font(.system(size: size * 0.28, weight: .heavy, design: .rounded))
                        .kerning(size * 0.045)
                        .foregroundStyle(tint)
                    Text("Strung by someone near you")
                        .font(.system(size: size * 0.12, weight: .medium))
                        .foregroundStyle(tint.opacity(0.75))
                }
            }
        }
    }
}

private struct RacquetMark: View {
    var tint: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let headHeight = height * 0.72
            let lineWidth = max(1.5, width * 0.055)

            ZStack(alignment: .top) {
                // String bed
                StringBed(columns: 5, rows: 6)
                    .stroke(tint.opacity(0.55), lineWidth: max(0.8, width * 0.018))
                    .frame(width: width * 0.78, height: headHeight * 0.82)
                    .clipShape(Ellipse())
                    .offset(y: headHeight * 0.09)

                // Head
                Ellipse()
                    .stroke(tint, lineWidth: lineWidth)
                    .frame(width: width, height: headHeight)

                // Throat + handle
                Capsule()
                    .fill(tint)
                    .frame(width: lineWidth * 1.15, height: height - headHeight + lineWidth)
                    .offset(y: headHeight - lineWidth / 2)

                Capsule()
                    .fill(tint)
                    .frame(width: width * 0.22, height: lineWidth)
                    .offset(y: height - lineWidth)
            }
            .frame(width: width, height: height)
        }
    }
}

/// The crossing mains and crosses inside the racquet head.
private struct StringBed: Shape {
    let columns: Int
    let rows: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()

        if columns > 1 {
            let step = rect.width / CGFloat(columns - 1)
            for index in 0..<columns {
                let x = rect.minX + CGFloat(index) * step
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
        }

        if rows > 1 {
            let step = rect.height / CGFloat(rows - 1)
            for index in 0..<rows {
                let y = rect.minY + CGFloat(index) * step
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
        }

        return path
    }
}

#Preview {
    ZStack {
        Theme.court.ignoresSafeArea()
        BrandLogo(size: 120, showsWordmark: true)
    }
}
