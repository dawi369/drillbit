#!/usr/bin/env swift
// Renders docs/design/logo/drillbit-icon.svg as the opaque 1024 px App Store icon.
import AppKit

let side = 1024
guard let context = CGContext(
  data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { fatalError("Could not create icon context") }

// Work in SVG coordinates: origin top left, y down.
context.translateBy(x: 0, y: CGFloat(side))
context.scaleBy(x: 1, y: -1)

func color(_ hex: UInt32) -> CGColor {
  CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
          blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}
func gradient(_ stops: [(CGFloat, UInt32)]) -> CGGradient {
  CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: stops.map { color($0.1) } as CFArray,
             locations: stops.map(\.0))!
}

context.drawLinearGradient(gradient([(0, 0x272D3A), (1, 0x1B1F29)]),
                           start: .zero, end: CGPoint(x: 0, y: side), options: [])

func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
let drill = CGMutablePath()
drill.move(to: p(-120, -316))
drill.addQuadCurve(to: p(-96, -340), control: p(-120, -340))
drill.addLine(to: p(96, -340))
drill.addQuadCurve(to: p(120, -316), control: p(120, -340))
drill.addLine(to: p(120, -255))
drill.addCurve(to: p(0, -185), control1: p(120, -227.5), control2: p(43.5, -201.2))
drill.addCurve(to: p(-120, -115), control1: p(-43.5, -168.8), control2: p(-120, -142.5))
drill.closeSubpath()
for dy: CGFloat in [0, 140] {
  drill.move(to: p(-120, -61 + dy))
  drill.addCurve(to: p(0, -131 + dy), control1: p(-120, -88.5 + dy), control2: p(-43.5, -114.8 + dy))
  drill.addCurve(to: p(120, -201 + dy), control1: p(43.5, -147.2 + dy), control2: p(120, -173.5 + dy))
  drill.addLine(to: p(120, -115 + dy))
  drill.addCurve(to: p(0, -45 + dy), control1: p(120, -87.5 + dy), control2: p(43.5, -61.2 + dy))
  drill.addCurve(to: p(-120, 25 + dy), control1: p(-43.5, -28.8 + dy), control2: p(-120, -2.5 + dy))
  drill.closeSubpath()
}
drill.move(to: p(-120, 219))
drill.addCurve(to: p(0, 149), control1: p(-120, 191.5), control2: p(-43.5, 165.2))
drill.addCurve(to: p(120, 79), control1: p(43.5, 132.8), control2: p(120, 106.5))
drill.addLine(to: p(120, 248))
drill.addLine(to: p(12, 330.8))
drill.addQuadCurve(to: p(-12, 330.8), control: p(0, 340))
drill.addLine(to: p(-120, 248))
drill.closeSubpath()

context.translateBy(x: 512, y: 512)
context.addPath(drill)
context.clip()
context.drawLinearGradient(gradient([(0, 0xFFDA8A), (0.45, 0xFFCC65), (1, 0xE9AE45)]),
                           start: p(-120, 0), end: p(120, 0), options: [])

guard
  let image = context.makeImage(),
  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
else { fatalError("Could not render app icon") }

let output = CommandLine.arguments.dropFirst().first
  ?? "apps/ios/Drillbit/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
try png.write(to: URL(fileURLWithPath: output))
