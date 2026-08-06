import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

private let canvasSize = 1024

private func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

private func makeMasterIcon() -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: nil,
        width: canvasSize,
        height: canvasSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    let plate = CGRect(x: 86, y: 86, width: 852, height: 852)
    let platePath = CGPath(
        roundedRect: plate,
        cornerWidth: 205,
        cornerHeight: 205,
        transform: nil
    )

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -22), blur: 34, color: color(0x0B0620, alpha: 0.42))
    context.addPath(platePath)
    context.setFillColor(color(0x2B1A62))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(platePath)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(0x6855E8), color(0x392A8C), color(0x21154E)] as CFArray,
        locations: [0, 0.48, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 210, y: 900),
        end: CGPoint(x: 830, y: 120),
        options: []
    )
    let glow = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(0x7B6DFF, alpha: 0.40), color(0x7B6DFF, alpha: 0)] as CFArray,
        locations: [0, 1]
    )!
    context.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: 330, y: 760), startRadius: 0,
        endCenter: CGPoint(x: 330, y: 760), endRadius: 520,
        options: []
    )
    context.restoreGState()

    let center = CGPoint(x: 512, y: 495)
    let radius: CGFloat = 270
    let start = CGFloat.pi * 0.73
    let end = CGFloat.pi * 2.27

    context.setLineCap(.round)
    context.setLineWidth(82)
    context.setStrokeColor(color(0xFFFFFF, alpha: 0.14))
    context.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
    context.strokePath()

    let segmentCount = 80
    let activeEnd = start + (end - start) * 0.78
    context.setLineWidth(76)
    for index in 0..<segmentCount {
        let t0 = CGFloat(index) / CGFloat(segmentCount)
        let t1 = CGFloat(index + 1) / CGFloat(segmentCount)
        let a0 = start + (activeEnd - start) * t0
        let a1 = start + (activeEnd - start) * t1 + 0.002
        let r = 0.18 + 0.17 * t0
        let g = 0.82 + 0.12 * t0
        let b = 0.87 - 0.25 * t0
        context.setStrokeColor(CGColor(red: r, green: g, blue: b, alpha: 1))
        context.addArc(center: center, radius: radius, startAngle: a0, endAngle: a1, clockwise: false)
        context.strokePath()
    }

    for angle in stride(from: start + 0.13, through: end - 0.13, by: (end - start - 0.26) / 6) {
        let inner = CGPoint(x: center.x + cos(angle) * 213, y: center.y + sin(angle) * 213)
        let outer = CGPoint(x: center.x + cos(angle) * 225, y: center.y + sin(angle) * 225)
        context.setStrokeColor(color(0xFFFFFF, alpha: 0.34))
        context.setLineWidth(8)
        context.move(to: inner)
        context.addLine(to: outer)
        context.strokePath()
    }

    let needleAngle = CGFloat.pi * 0.24
    let needleEnd = CGPoint(
        x: center.x + cos(needleAngle) * 188,
        y: center.y + sin(needleAngle) * 188
    )
    context.setShadow(offset: CGSize(width: 0, height: -5), blur: 12, color: color(0x0D0924, alpha: 0.46))
    context.setStrokeColor(color(0xFFFFFF, alpha: 0.96))
    context.setLineWidth(25)
    context.setLineCap(.round)
    context.move(to: center)
    context.addLine(to: needleEnd)
    context.strokePath()
    context.setShadow(offset: .zero, blur: 0)

    context.setFillColor(color(0xFFFFFF))
    context.fillEllipse(in: CGRect(x: center.x - 42, y: center.y - 42, width: 84, height: 84))
    context.setFillColor(color(0x43339E))
    context.fillEllipse(in: CGRect(x: center.x - 18, y: center.y - 18, width: 36, height: 36))

    context.setStrokeColor(color(0xFFFFFF, alpha: 0.18))
    context.setLineWidth(3)
    context.addPath(platePath)
    context.strokePath()

    return context.makeImage()!
}

private func resized(_ image: CGImage, size: Int) -> CGImage {
    let space = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    return context.makeImage()!
}

private func writePNG(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    )!
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination))
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
let master = makeMasterIcon()
let outputs: [(String, Int)] = [
    ("AppIcon-16.png", 16),
    ("AppIcon-16@2x.png", 32),
    ("AppIcon-32.png", 32),
    ("AppIcon-32@2x.png", 64),
    ("AppIcon-128.png", 128),
    ("AppIcon-128@2x.png", 256),
    ("AppIcon-256.png", 256),
    ("AppIcon-256@2x.png", 512),
    ("AppIcon-512.png", 512),
    ("AppIcon-512@2x.png", 1024)
]
for (name, size) in outputs {
    writePNG(resized(master, size: size), to: outputDirectory.appendingPathComponent(name))
}
