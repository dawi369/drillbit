import AppKit
import CoreGraphics
import Foundation

let side = 1024
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let space = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
  data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
else { fatalError("Could not create icon canvas") }

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
  CGColor(colorSpace: space, components: [
    CGFloat((hex >> 16) & 0xFF) / 255,
    CGFloat((hex >> 8) & 0xFF) / 255,
    CGFloat(hex & 0xFF) / 255,
    alpha,
  ])!
}

context.setFillColor(color(0x1F2430))
context.fill(CGRect(x: 0, y: 0, width: side, height: side))
let gradient = CGGradient(colorsSpace: space, colors: [color(0x232834), color(0x1F2430)] as CFArray,
                          locations: [0, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: side), end: .zero, options: [])

// The same three-point mark used by the app chrome, enlarged for icon scale.
for (x, y, radius, fill) in [
  (403.0, 507.0, 136.0, 0xFFCC65 as UInt32),
  (623.0, 615.0, 77.0, 0xFFE2A3 as UInt32),
  (651.0, 368.0, 53.0, 0xD8D6CF as UInt32),
] {
  context.setFillColor(color(fill))
  context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
}

guard let image = context.makeImage(),
      let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
else { fatalError("Could not encode icon") }
try png.write(to: destination)
