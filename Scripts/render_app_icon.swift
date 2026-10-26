import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Renders the Serving app icon: an optic-yellow ball whose seam is an "S",
// on a deep court-green field.
//
//     swift Scripts/render_app_icon.swift Serving/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png

let size = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let s = CGFloat(size)

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
// Flip to top-left origin so coordinates match SwiftUI.
ctx.translateBy(x: 0, y: s)
ctx.scaleBy(x: 1, y: -1)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}

// Background
let bg = CGGradient(colorsSpace: space,
                    colors: [color(0.10, 0.33, 0.26), color(0.03, 0.15, 0.12)] as CFArray,
                    locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: 0), end: CGPoint(x: s * 0.3, y: s),
                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

// Soft glow behind the ball.
let glow = CGGradient(colorsSpace: space,
                      colors: [color(0.84, 0.93, 0.18, 0.22), color(0.84, 0.93, 0.18, 0)] as CFArray,
                      locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: s / 2, y: s / 2), startRadius: 0,
                       endCenter: CGPoint(x: s / 2, y: s / 2), endRadius: s * 0.5, options: [])

// Ball
let d = s * 0.60
let ball = CGRect(x: (s - d) / 2, y: (s - d) / 2, width: d, height: d)

// Shadow
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: s * 0.025), blur: s * 0.06, color: color(0, 0, 0, 0.45))
ctx.setFillColor(color(0.84, 0.93, 0.18))
ctx.fillEllipse(in: ball)
ctx.restoreGState()

ctx.saveGState()
ctx.addEllipse(in: ball)
ctx.clip()
let felt = CGGradient(colorsSpace: space,
                      colors: [color(0.93, 0.98, 0.42), color(0.80, 0.91, 0.16), color(0.60, 0.76, 0.10)] as CFArray,
                      locations: [0, 0.55, 1])!
ctx.drawRadialGradient(felt,
                       startCenter: CGPoint(x: ball.minX + d * 0.32, y: ball.minY + d * 0.28), startRadius: 0,
                       endCenter: CGPoint(x: ball.midX, y: ball.midY), endRadius: d * 0.62,
                       options: [.drawsAfterEndLocation])

// Seam — the "S". Unit coordinates inside the ball's bounding square;
// point-symmetric about the centre. Mirrors `SeamS` in BrandLogo.swift.
func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ball.minX + x * d, y: ball.minY + y * d) }
let seam = CGMutablePath()
seam.move(to: p(0.80, -0.04))
seam.addCurve(to: p(0.5, 0.5), control1: p(0.24, 0.00), control2: p(0.14, 0.42))
seam.addCurve(to: p(0.20, 1.04), control1: p(0.86, 0.58), control2: p(0.76, 1.00))
ctx.addPath(seam)
ctx.setStrokeColor(color(1, 1, 1))
ctx.setLineWidth(d * 0.078)
ctx.setLineCap(.round)
ctx.strokePath()
ctx.restoreGState()

let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out)")
