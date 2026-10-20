// Renders Bit's silhouette as a tab bar glyph: a template image the bar tints, with the eyes cut out.
// Run from the repo root:
//   swiftc -parse-as-library scripts/generate-bit-tab.swift apps/ios/Drillbit/BitRig.swift \
//     apps/ios/Drillbit/BitRenderer.swift -o /tmp/drillbit-bit-tab && /tmp/drillbit-bit-tab
import AppKit
import SwiftUI

@main
struct GenerateBitTab {
  /// Oversized on purpose: the silhouette has no stroke, so it needs more height than an SF Symbol to read.
  static let height = 30.0
  /// Icon pose, mirrored to face into the tab bar and leaned further than the icon so the tilt reads at glyph size.
  static var pose: BitPose {
    var pose = BitPose()
    pose.phase = 3.0
    pose.headX = 6
    pose.tipX = -3
    pose.squash = 1.03
    pose.lookX = 0.7
    pose.lookY = -1.0
    pose.eyeWidth = 6.4
    pose.left = BitEye(top: 9.6, bottom: 9.6)
    pose.right = pose.left
    return pose
  }
  static let tilt = Angle.degrees(32)

  @MainActor static func main() throws {
    let folder = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first
      ?? "apps/ios/Drillbit/Assets.xcassets/BitTab.imageset")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let pose = pose
    let g = BitGeometry(pose: pose)
    var body = Path.bitSmooth(g.outline(), closed: true)
    // Eyes read as holes, placed and foreshortened the way BitRenderer.drawFace does so the gaze carries over;
    // drawn larger than life so they survive the downscale.
    let phi = pose.lookX * 0.55, line = BitShape.eyeLine + pose.lookY * 3.4, scale = 1.5
    for dir in [-1.0, 1.0] {
      let a = phi + dir * BitShape.eyeSpread, facing = cos(a)
      let center = g.point(line, a)
      let w = pose.eyeWidth * scale * facing, h = (pose.left.top + pose.left.bottom) / 2 * scale
      body.addEllipse(in: CGRect(x: center.x - w, y: center.y - h, width: w * 2, height: h * 2))
    }
    body = body.applying(CGAffineTransform(scaleX: -1, y: 1).concatenating(CGAffineTransform(rotationAngle: tilt.radians)))
    // Fit the tilted silhouette itself, not the rig's view box, so Bit fills the glyph.
    let bounds = body.boundingRect
    let width = (height * bounds.width / bounds.height).rounded()
    let art = Canvas { context, size in
      let fit = min(size.width / bounds.width, size.height / bounds.height)
      var local = context
      local.translateBy(x: (size.width - bounds.width * fit) / 2, y: (size.height - bounds.height * fit) / 2)
      local.scaleBy(x: fit, y: fit)
      local.translateBy(x: -bounds.minX, y: -bounds.minY)
      local.fill(body, with: .color(.black), style: FillStyle(eoFill: true))
    }
    .frame(width: width, height: height)
    for scale in [2, 3] {
      let renderer = ImageRenderer(content: art)
      renderer.scale = CGFloat(scale)
      guard let image = renderer.cgImage, let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
      else { fatalError("Could not render the tab glyph") }
      try png.write(to: folder.appendingPathComponent("BitTab@\(scale)x.png"))
    }
    let contents = """
    {
      "images" : [
        { "idiom" : "universal", "scale" : "1x" },
        { "filename" : "BitTab@2x.png", "idiom" : "universal", "scale" : "2x" },
        { "filename" : "BitTab@3x.png", "idiom" : "universal", "scale" : "3x" }
      ],
      "info" : { "author" : "xcode", "version" : 1 },
      "properties" : { "template-rendering-intent" : "template" }
    }
    """
    try contents.write(to: folder.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    print("BitTab \(Int(width))x\(Int(height)) pt")
  }
}
