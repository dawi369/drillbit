// Renders the opaque 1024 px App Store icon and the launch screen's Bit with his own rig and renderer.
// Run from the repo root:
//   swiftc -parse-as-library scripts/generate-app-icon.swift apps/ios/Drillbit/BitRig.swift \
//     apps/ios/Drillbit/BitRenderer.swift -o /tmp/drillbit-icon && /tmp/drillbit-icon
import AppKit
import SwiftUI

@main
struct GenerateAppIcon {
  static let side = 1024

  @MainActor static func main() throws {
    let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first
      ?? "apps/ios/Drillbit/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
    try icon().write(to: output)
    try launchMark(output.deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("LaunchBit.imageset"))
  }

  /// Bit mid-hop: tipped over a little, leaning into it and glancing up.
  static var pose: BitPose {
    var pose = BitPose()
    pose.phase = 3.0
    pose.headX = 6
    pose.tipX = -3
    pose.squash = 1.03
    pose.lookX = 0.5
    pose.lookY = -0.35
    pose.eyeWidth = 6.4
    pose.left = BitEye(top: 9.6, bottom: 9.6)
    pose.right = pose.left
    pose.blush = 0.6
    return pose
  }

  @MainActor static func icon() -> Data {
    let art = Canvas { context, size in
      context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
        Gradient(colors: [rgb(0x272D3A), rgb(0x1B1F29)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
      context.fill(Path(ellipseIn: CGRect(x: 112, y: 120, width: 800, height: 800)), with: .radialGradient(
        Gradient(colors: [rgb(0xFFCC65, 0.16), rgb(0xFFCC65, 0)]), center: CGPoint(x: 512, y: 520), startRadius: 0, endRadius: 400))
      var shadow = context
      shadow.translateBy(x: 560, y: 930)
      shadow.scaleBy(x: 1, y: 0.16)
      shadow.fill(Path(ellipseIn: CGRect(x: -150, y: -150, width: 300, height: 300)), with: .radialGradient(
        Gradient(colors: [rgb(0x000000, 0.45), rgb(0x000000, 0)]), center: .zero, startRadius: 0, endRadius: 150))
      var bit = context
      bit.translateBy(x: 512, y: 500)
      bit.rotate(by: .degrees(-12))
      bit.scaleBy(x: 4.7, y: 4.7)
      bit.translateBy(x: -100, y: -111)
      BitRenderer.draw(pose, style: BitFinish.satin.style, in: &bit, size: BitShape.viewBox, shadow: false)
    }
    .frame(width: CGFloat(side), height: CGFloat(side))
    let renderer = ImageRenderer(content: art)
    renderer.scale = 1
    // The App Store icon must be opaque, so flatten onto a context without alpha.
    guard
      let image = renderer.cgImage,
      let flat = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { fatalError("Could not render app icon") }
    flat.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
    guard let opaque = flat.makeImage(), let png = NSBitmapImageRep(cgImage: opaque).representation(using: .png, properties: [:])
    else { fatalError("Could not encode app icon") }
    return png
  }

  /// Launch screen: Bit's idle rest pose at the size the app's restoring surface shows him.
  /// Raster, because PDF export drops his clips, blends and soft shadow.
  @MainActor static func launchMark(_ folder: URL) throws {
    let art = Canvas { context, size in
      BitRenderer.draw(BitPose.rest(.idle), style: BitFinish.satin.style, in: &context, size: size)
    }
    .frame(width: BitLaunch.size.width, height: BitLaunch.size.height)
    for scale in [2, 3] {
      let renderer = ImageRenderer(content: art)
      renderer.scale = CGFloat(scale)
      guard let image = renderer.cgImage, let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
      else { fatalError("Could not render launch mark") }
      try png.write(to: folder.appendingPathComponent("LaunchBit@\(scale)x.png"))
    }
  }

  static func rgb(_ hex: UInt32, _ opacity: Double = 1) -> Color {
    Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255, opacity: opacity)
  }
}
