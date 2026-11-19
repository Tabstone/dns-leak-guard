import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count > 1 else {
    fputs("usage: GenerateIcon.swift <iconset-dir>\n", stderr)
    exit(2)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: red, green: green, blue: blue, alpha: alpha)
}

for variant in variants {
    let size = variant.pixels
    let width = CGFloat(size)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
    ) else {
        continue
    }

    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high
    context.clear(CGRect(x: 0, y: 0, width: width, height: width))

    let inset = width * 0.065
    let tile = CGRect(
        x: inset,
        y: inset,
        width: width - inset * 2,
        height: width - inset * 2
    )
    let tilePath = CGPath(
        roundedRect: tile,
        cornerWidth: width * 0.225,
        cornerHeight: width * 0.225,
        transform: nil
    )
    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            color(0.09, 0.73, 0.84),
            color(0.04, 0.38, 0.73),
            color(0.025, 0.13, 0.32)
        ] as CFArray,
        locations: [0, 0.53, 1]
    )
    if let gradient {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: width * 0.15, y: width * 0.92),
            end: CGPoint(x: width * 0.82, y: width * 0.08),
            options: []
        )
    }
    context.setFillColor(color(1, 1, 1, 0.075))
    context.fillEllipse(
        in: CGRect(
            x: width * 0.12,
            y: width * 0.54,
            width: width * 0.76,
            height: width * 0.40
        )
    )
    context.restoreGState()

    context.addPath(tilePath)
    context.setStrokeColor(color(1, 1, 1, 0.2))
    context.setLineWidth(max(1, width * 0.005))
    context.strokePath()

    let centerX = width * 0.5
    let shield = CGMutablePath()
    shield.move(to: CGPoint(x: centerX, y: width * 0.79))
    shield.addLine(to: CGPoint(x: width * 0.70, y: width * 0.69))
    shield.addCurve(
        to: CGPoint(x: centerX, y: width * 0.22),
        control1: CGPoint(x: width * 0.70, y: width * 0.49),
        control2: CGPoint(x: width * 0.62, y: width * 0.33)
    )
    shield.addCurve(
        to: CGPoint(x: width * 0.30, y: width * 0.69),
        control1: CGPoint(x: width * 0.38, y: width * 0.33),
        control2: CGPoint(x: width * 0.30, y: width * 0.49)
    )
    shield.closeSubpath()

    context.saveGState()
    context.addPath(shield)
    context.clip()
    context.setFillColor(color(1, 1, 1, 0.17))
    context.fill(CGRect(x: 0, y: 0, width: centerX, height: width))
    context.restoreGState()

    context.addPath(shield)
    context.setStrokeColor(color(1, 1, 1, 0.98))
    context.setLineWidth(width * 0.038)
    context.setLineJoin(.round)
    context.setLineCap(.round)
    context.strokePath()

    let check = CGMutablePath()
    check.move(to: CGPoint(x: width * 0.405, y: width * 0.505))
    check.addLine(to: CGPoint(x: width * 0.475, y: width * 0.435))
    check.addLine(to: CGPoint(x: width * 0.605, y: width * 0.585))
    context.addPath(check)
    context.setStrokeColor(color(1, 1, 1, 0.98))
    context.setLineWidth(width * 0.045)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()

    guard let image = context.makeImage() else { continue }
    let url = output.appendingPathComponent(variant.name)
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        continue
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { continue }
}
