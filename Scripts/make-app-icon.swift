// Renders the Skald app icon: the Ansuz rune on a macOS squircle, drawn as vector
// strokes so no runic font is needed. Writes every size the asset catalog lists.
// Usage: swiftc -O Scripts/make-app-icon.swift -o <bin> && <bin> <appiconset dir>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Skald/Resources/Assets.xcassets/AppIcon.appiconset")

/// Rounded rectangle close to Apple's icon squircle: the shape fills 824/1024 of the
/// canvas and uses a corner radius of about 22.4% of its side.
func squircle(in rect: CGRect) -> CGPath {
    let radius = rect.width * 0.2237
    return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func render(size: Int) -> CGImage? {
    let scale = CGFloat(size) / 1024
    guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.scaleBy(x: scale, y: scale)
    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high

    // Canvas is 1024x1024 with the origin at the bottom-left (CoreGraphics).
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(in: plate)

    // Soft drop shadow, as in Apple's icon template.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: color(0x000000, alpha: 0.35))
    context.addPath(shape)
    context.setFillColor(color(0x1E1F24))
    context.fillPath()
    context.restoreGState()

    // Plate: the dark editor background, lifting toward the top like the Skald Dark theme.
    context.saveGState()
    context.addPath(shape)
    context.clip()
    let plateGradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(0x3B4160), color(0x24273A), color(0x16171E)] as CFArray, locations: [0, 0.55, 1])!
    context.drawLinearGradient(plateGradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // Glassy top highlight.
    let highlight = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(0xFFFFFF, alpha: 0.16), color(0xFFFFFF, alpha: 0.0)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(highlight, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [])
    context.restoreGState()

    // Inner rim.
    context.saveGState()
    context.addPath(squircle(in: plate.insetBy(dx: 3, dy: 3)))
    context.setStrokeColor(color(0xFFFFFF, alpha: 0.10))
    context.setLineWidth(6)
    context.strokePath()
    context.restoreGState()

    // The Ansuz rune: a stem with two parallel arms slanting down to the right.
    // Flipped y: the top of the glyph is at the high y values.
    let stroke: CGFloat = 76
    let rune = CGMutablePath()
    rune.move(to: CGPoint(x: 418, y: 788))
    rune.addLine(to: CGPoint(x: 418, y: 236))
    rune.move(to: CGPoint(x: 418, y: 772))
    rune.addLine(to: CGPoint(x: 612, y: 612))
    rune.move(to: CGPoint(x: 418, y: 622))
    rune.addLine(to: CGPoint(x: 612, y: 462))

    context.saveGState()
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setLineWidth(stroke)
    // Faint glow behind the strokes.
    context.setShadow(offset: .zero, blur: 28, color: color(0xAEB7FF, alpha: 0.45))
    context.setStrokeColor(color(0xF2EBDD))
    context.addPath(rune)
    context.strokePath()
    context.restoreGState()

    return context.makeImage()
}

func write(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "icon", code: 1)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "icon", code: 2) }
}

// (points, scale) pairs the macOS icon set expects.
let entries: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var manifest: [[String: String]] = []
for (points, scale) in entries {
    let pixels = points * scale
    let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@\(scale)x.png"
    guard let image = render(size: pixels) else { fatalError("render failed at \(pixels)") }
    try write(image, to: outputDirectory.appendingPathComponent(name))
    manifest.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
    print("wrote \(name)")
}
let contents: [String: Any] = ["images": manifest, "info": ["author": "xcode", "version": 1]]
let data = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try data.write(to: outputDirectory.appendingPathComponent("Contents.json"))
print("wrote Contents.json")
