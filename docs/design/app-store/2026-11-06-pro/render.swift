import AppKit

// Run: swift render.swift <capture-directory> <output-directory>
// Screens are resized proportionally, with every part of the app kept visible.
let root = CommandLine.arguments[1]
let output = CommandLine.arguments[2]
let fm = FileManager.default
try fm.createDirectory(atPath: output, withIntermediateDirectories: true)

let shots: [(String, String, String, String, String)] = [
  ("03-pushback", "01-interview", "SYSTEM DESIGN PRACTICE", "Get better at\nsystem design.", "An interviewer that asks the next hard question."),
  ("05-feedback", "02-feedback", "FEEDBACK YOU CAN USE", "Know what worked.\nKnow what to fix.", "Feedback grounded in what you actually said."),
  ("04-example", "03-example", "HELP WHEN YOU NEED IT", "Stuck? See one\nworked example.", "Get a concrete example, then make it your own."),
  ("06-knowledge-map", "04-knowledge-map", "YOUR KNOWLEDGE MAP · PRO", "See what you\nactually know.", "Find your strengths. Pick your next weak spot."),
  ("spare-recall", "05-recall", "RECALL PRACTICE", "Make the\nlesson stick.", "Revisit the ideas that need another round.")
]

func color(_ hex: UInt32) -> NSColor {
  NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
}
func text(_ value: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat, weight: NSFont.Weight, ink: NSColor) {
  let style = NSMutableParagraphStyle()
  style.lineSpacing = 0
  let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: ink, .paragraphStyle: style]
  (value as NSString).draw(in: NSRect(x: x, y: y, width: width, height: 350), withAttributes: attrs)
}
func canvas(width: Int, height: Int, draw: () -> Void) -> NSBitmapImageRep {
  let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
  NSGraphicsContext.current!.imageInterpolation = .high
  ctx.translateBy(x: 0, y: CGFloat(height))
  ctx.scaleBy(x: 1, y: -1)
  draw()
  NSGraphicsContext.restoreGraphicsState()
  return NSBitmapImageRep(cgImage: ctx.makeImage()!)
}
func save(_ bitmap: NSBitmapImageRep, _ path: String) throws {
  try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

for (index, shot) in shots.enumerated() {
  let image = NSImage(contentsOfFile: "\(root)/\(shot.0).png")!
  let bitmap = canvas(width: 1320, height: 2868) {
    color(0xF1EEE7).setFill()
    NSRect(x: 0, y: 0, width: 1320, height: 2868).fill()
    color(0xE9B746).setFill()
    NSRect(x: 84, y: 84, width: 52, height: 12).fill()
    text("DRILLBIT", x: 156, y: 66, width: 500, size: 34, weight: .heavy, ink: color(0x20242D))
    text(String(format: "%02d / 05", index + 1), x: 1080, y: 70, width: 170, size: 28, weight: .medium, ink: color(0x6D6B65))
    text(shot.2, x: 84, y: 160, width: 1160, size: 30, weight: .semibold, ink: color(0x68645D))
    text(shot.3, x: 76, y: 214, width: 1180, size: 112, weight: .bold, ink: color(0x20242D))
    text(shot.4, x: 84, y: 506, width: 1170, size: 37, weight: .regular, ink: color(0x5E5C57))
    let screen = NSRect(x: 160, y: 620, width: 1000, height: 1000 * 2868 / 1320)
    let frame = screen.insetBy(dx: -12, dy: -12)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.19)
    shadow.shadowBlurRadius = 32
    shadow.shadowOffset = NSSize(width: 0, height: 14)
    shadow.set()
    color(0x22242B).setFill()
    NSBezierPath(roundedRect: frame, xRadius: 96, yRadius: 96).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: screen, xRadius: 84, yRadius: 84).addClip()
    image.draw(in: screen, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
    NSGraphicsContext.restoreGraphicsState()
  }
  try save(bitmap, "\(output)/\(shot.1).png")
}

let contact = canvas(width: 1650, height: 717) {
  for (index, shot) in shots.enumerated() {
    let image = NSImage(contentsOfFile: "\(output)/\(shot.1).png")!
    image.draw(in: NSRect(x: index * 330, y: 0, width: 330, height: 717), from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
  }
}
try save(contact, "\(output)/../contact-sheet.png")
print("Rendered five opaque RGB 1320 × 2868 PNGs and contact sheet.")
