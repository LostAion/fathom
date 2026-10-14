import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Renders the 1024 px Fathom app icon: night chart, depth contours, sounding line, lead and ping.
// Usage: swift Scripts/make_icon.swift Fathom/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
let size = 1024
let s = CGFloat(size)
let out = CommandLine.arguments[1]

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
// Flip so y grows downwards like the app's Canvas.
ctx.translateBy(x: 0, y: s)
ctx.scaleBy(x: 1, y: -1)

// Background
let gradient = CGGradient(colorsSpace: space, colors: [rgb(0x0F2C45), rgb(0x06121F)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: s), options: [])

// Depth contours
let center = CGPoint(x: s * 0.86, y: s * 1.08)
for ring in 0..<12 {
    let base = CGFloat(ring + 1) * s * 1.35 / 12
    let path = CGMutablePath()
    for step in 0...180 {
        let a = Double(step) / 180 * 2 * .pi
        let r = base + 14 * sin(a * 3 + Double(ring) * 0.8) + 8 * sin(a * 5 + Double(ring))
        let p = CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a))
        step == 0 ? path.move(to: p) : path.addLine(to: p)
    }
    ctx.addPath(path)
    ctx.setStrokeColor(rgb(0x2EC4B6, ring % 4 == 0 ? 0.28 : 0.14))
    ctx.setLineWidth(ring % 4 == 0 ? 5 : 3)
    ctx.strokePath()
}

let mid = s * 0.5
let leadTop = s * 0.60

// Sonar ping around the lead
for (i, alpha) in [0.55, 0.32, 0.16].enumerated() {
    let r = s * (0.17 + CGFloat(i) * 0.085)
    ctx.addArc(center: CGPoint(x: mid, y: leadTop + s * 0.1), radius: r, startAngle: .pi * 0.15, endAngle: .pi * 0.85, clockwise: false)
    ctx.setStrokeColor(rgb(0x2EC4B6, alpha))
    ctx.setLineWidth(14 - CGFloat(i) * 3)
    ctx.setLineCap(.round)
    ctx.strokePath()
}

// Sounding line with fathom marks
ctx.setStrokeColor(rgb(0xE6F1F5, 0.9))
ctx.setLineWidth(14)
ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: mid, y: s * 0.1))
ctx.addLine(to: CGPoint(x: mid, y: leadTop))
ctx.strokePath()
for mark in 1...4 {
    let y = s * 0.1 + (leadTop - s * 0.1) * CGFloat(mark) / 5
    let half: CGFloat = mark.isMultiple(of: 2) ? 70 : 42
    ctx.move(to: CGPoint(x: mid - half, y: y))
    ctx.addLine(to: CGPoint(x: mid + half, y: y))
    ctx.setLineWidth(12)
    ctx.strokePath()
}

// Lead weight (teardrop)
let lead = CGMutablePath()
let leadBottom = leadTop + s * 0.2
lead.move(to: CGPoint(x: mid, y: leadTop - 20))
lead.addCurve(to: CGPoint(x: mid, y: leadBottom), control1: CGPoint(x: mid + s * 0.07, y: leadTop + s * 0.05),
              control2: CGPoint(x: mid + s * 0.13, y: leadBottom))
lead.addCurve(to: CGPoint(x: mid, y: leadTop - 20), control1: CGPoint(x: mid - s * 0.13, y: leadBottom),
              control2: CGPoint(x: mid - s * 0.07, y: leadTop + s * 0.05))
ctx.addPath(lead)
ctx.setFillColor(rgb(0x2EC4B6))
ctx.fillPath()

let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out)")
