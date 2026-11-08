// Generates the 1024×1024 app icon with CoreGraphics. Run by the CI workflow:
//   swift Tools/GenerateIcon.swift Memora/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
// To use your own icon instead, replace AppIcon.png in the asset catalog and remove the CI step.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let space = CGColorSpaceCreateDeviceRGB()

guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                          space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("Could not create context")
}

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}

let full = CGRect(x: 0, y: 0, width: size, height: size)
let center = CGPoint(x: 512, y: 512)

// Near-black base with a subtle vertical tone.
let base = CGGradient(colorsSpace: space, colors: [color(0.055, 0.060, 0.085), color(0.025, 0.027, 0.040)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(base, start: CGPoint(x: 512, y: 1024), end: CGPoint(x: 512, y: 0), options: [])

// Soft periwinkle glow.
let glow = CGGradient(colorsSpace: space, colors: [color(0.49, 0.55, 1.0, 0.45), color(0.49, 0.55, 1.0, 0.0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: 480, options: [])

// Three concentric arcs: spaced reviews strengthening a memory trace.
ctx.setLineCap(.round)
let arcs: [(radius: CGFloat, width: CGFloat, alpha: CGFloat, start: CGFloat, end: CGFloat)] = [
    (330, 30, 0.95, 0.15, 1.75),
    (250, 26, 0.75, 0.35, 1.85),
    (170, 22, 0.55, 0.55, 1.95)
]
for arc in arcs {
    ctx.setStrokeColor(color(0.62, 0.66, 1.0, arc.alpha))
    ctx.setLineWidth(arc.width)
    ctx.addArc(center: center, radius: arc.radius, startAngle: arc.start * .pi, endAngle: arc.end * .pi, clockwise: false)
    ctx.strokePath()
}

// Retrieval nodes at the arc ends.
for arc in arcs {
    let angle = arc.end * .pi
    let p = CGPoint(x: center.x + cos(angle) * arc.radius, y: center.y + sin(angle) * arc.radius)
    ctx.setFillColor(color(0.92, 0.93, 1.0))
    ctx.fillEllipse(in: CGRect(x: p.x - arc.width * 0.9, y: p.y - arc.width * 0.9, width: arc.width * 1.8, height: arc.width * 1.8))
}

// Core.
ctx.setFillColor(color(0.92, 0.93, 1.0))
ctx.fillEllipse(in: CGRect(x: center.x - 46, y: center.y - 46, width: 92, height: 92))
ctx.setFillColor(color(0.49, 0.55, 1.0))
ctx.fillEllipse(in: CGRect(x: center.x - 26, y: center.y - 26, width: 52, height: 52))

guard let image = ctx.makeImage() else { fatalError("Could not render image") }
let url = URL(fileURLWithPath: outputPath)
try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("Could not create destination")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not write PNG") }
print("Wrote \(outputPath)")
_ = full
