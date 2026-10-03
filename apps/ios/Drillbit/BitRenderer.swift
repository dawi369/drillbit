import SwiftUI

/// Bit's surfaces, ported from docs/design/mascot-studies-v3.html. The native renderer skips the study's
/// noise textures and blur filters; they belong to a later shader pass, not per-frame Canvas work.
enum BitFinish: String, CaseIterable, Sendable {
  case satin, gummy, anodized, glazed, ember, oxide, tempered, plush, blueprint
}

struct BitStop: Sendable {
  var location: Double
  var color: UInt32
  var opacity: Double
}

struct BitStyle: Sendable {
  struct Band: Sendable {
    var angle: Double
    var from: Double
    var to: Double
    var width: Double
    var color: Color
  }
  var base: Color
  var lip: Color
  var shade: [BitStop]
  var eye: Color
  var blush: Color
  var dots: Color
  var chip: Color
  var sparkle: Color
  var shadow: Color
  var vshade: [BitStop] = []
  var glow: [BitStop] = []
  var groove: Color? = nil
  var grooveHeight = BitShape.grooveHeight
  var grooveShade = Color.clear
  var grooveGlow: Color? = nil
  var grooveTop: Color? = nil
  var stitches = false
  var lipWidth = 1.1
  var lipFalloff = 0.2
  var back: Color? = nil
  var backDashed = false
  var bubbles = false
  var speckles = false
  var grid = false
  var bands: [Band] = []
  var spec = 0.0
  var specSize = CGSize(width: 7.5, height: 12)
  var dot = 0.0
  var tipGlint = 0.0
  var rimLeft = Color.clear
  var rimRight = Color.clear
  var rimWidth = 3.2
  var outline: Color? = nil
  var outlineWidth = 1.3
  var fuzzy = false
  var centerline = false
  var eyeGlow: Color? = nil
  var caustic: Color? = nil
}

private func hex(_ value: UInt32, _ opacity: Double = 1) -> Color {
  Color(.sRGB, red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
    blue: Double(value & 0xFF) / 255, opacity: opacity)
}

private func stops(_ list: [(Double, UInt32, Double)]) -> [BitStop] {
  list.map { BitStop(location: $0.0, color: $0.1, opacity: $0.2) }
}

extension BitFinish {
  var style: BitStyle {
    let ink = hex(0x232834), darkShadow = hex(0x000000, 0.42)
    switch self {
    case .satin:
      var s = BitStyle(base: hex(0xFFCA62), lip: hex(0xFFF4D8, 0.7),
        shade: stops([(0, 0xFFFFFF, 0.2), (0.22, 0xFFFFFF, 0.05), (0.5, 0xFFFFFF, 0), (0.78, 0x6B4106, 0.12), (1, 0x4A2C04, 0.34)]),
        eye: ink, blush: hex(0xFF8A6A), dots: hex(0xA8BCD1), chip: hex(0xFFD98A), sparkle: hex(0xFFF2C8), shadow: darkShadow)
      s.vshade = stops([(0, 0xFFFFFF, 0.1), (0.3, 0xFFFFFF, 0), (0.7, 0x4A2C04, 0), (1, 0x4A2C04, 0.2)])
      s.groove = hex(0xE39B3B)
      s.grooveShade = hex(0x7A4508, 0.32)
      s.bands = [.init(angle: -0.62, from: 6, to: 146, width: 0.5, color: hex(0xFFFFFF, 0.22))]
      s.spec = 0.6
      s.tipGlint = 0.3
      s.rimLeft = hex(0xFFF8E8, 0.28)
      s.rimRight = hex(0xFFF1C9, 0.6)
      s.rimWidth = 4.2
      return s
    case .gummy:
      var s = BitStyle(base: hex(0xFFAE2E), lip: hex(0xFFFFFF, 0.9),
        shade: stops([(0, 0xFFE9B0, 0.35), (0.12, 0xFFFFFF, 0), (0.55, 0xFFFFFF, 0), (0.85, 0xD4650A, 0.22), (1, 0xA84C06, 0.45)]),
        eye: hex(0x2A1E14), blush: hex(0xFF6A3D), dots: hex(0xFFD27A), chip: hex(0xFFC24F), sparkle: hex(0xFFF6D8),
        shadow: hex(0xFFAE2E, 0.55))
      s.vshade = stops([(0, 0xFFFFFF, 0), (0.62, 0xFFFFFF, 0), (1, 0xFFF0C0, 0.55)])
      s.glow = stops([(0, 0xFFE7A6, 0.9), (0.5, 0xFFC650, 0.45), (1, 0xFFAE2E, 0)])
      s.back = hex(0xE07A12, 0.22)
      s.bubbles = true
      s.groove = hex(0xF28C14)
      s.grooveShade = hex(0xC2620A, 0.28)
      s.lipWidth = 1.2
      s.bands = [
        .init(angle: -0.74, from: 10, to: 60, width: 0.36, color: hex(0xFFFFFF, 0.7)),
        .init(angle: -0.6, from: 96, to: 132, width: 0.1, color: hex(0xFFFFFF, 0.3)),
        .init(angle: 0.78, from: 20, to: 120, width: 0.08, color: hex(0xFFF3D0, 0.25)),
      ]
      s.dot = 0.95
      s.tipGlint = 0.7
      s.rimLeft = hex(0xFFF6DC, 0.55)
      s.rimRight = hex(0xFFF4D6, 0.75)
      s.rimWidth = 4.5
      s.caustic = hex(0xFFE9A8)
      return s
    case .anodized:
      var s = BitStyle(base: hex(0xF5A623), lip: hex(0xFFF6D6),
        shade: stops([(0, 0x8A4A00, 0.35), (0.08, 0xFFE08A, 0.35), (0.22, 0xFFFFFF, 0), (0.55, 0xFFFFFF, 0), (0.75, 0x7A3E00, 0.25),
          (0.92, 0x5A2C00, 0.5), (1, 0x3A1A00, 0.65)]),
        eye: ink, blush: hex(0xFF8A6A), dots: hex(0xA8BCD1), chip: hex(0xFFE3A1), sparkle: hex(0xFFFFFF), shadow: darkShadow)
      s.vshade = stops([(0, 0xFFFFFF, 0.18), (0.18, 0xFFFFFF, 0), (0.8, 0x2A1802, 0), (1, 0x2A1802, 0.2)])
      s.groove = hex(0xB8680A)
      s.grooveShade = hex(0x3D1C00, 0.5)
      s.grooveTop = hex(0x2E1500, 0.45)
      s.lipWidth = 1.3
      s.bands = [
        .init(angle: -0.44, from: 2, to: 146, width: 0.28, color: hex(0xFFE9A8, 0.55)),
        .init(angle: -0.44, from: 4, to: 144, width: 0.09, color: hex(0xFFFBEA, 0.85)),
        .init(angle: 0.08, from: 8, to: 140, width: 0.06, color: hex(0xFFE9A8, 0.25)),
        .init(angle: 0.8, from: 8, to: 140, width: 0.12, color: hex(0xE3ECFF, 0.35)),
      ]
      s.spec = 0.6
      s.specSize = CGSize(width: 3.5, height: 6)
      s.tipGlint = 0.9
      s.rimLeft = hex(0xFFE7B0, 0.35)
      s.rimRight = hex(0xE3ECFF, 0.4)
      return s
    case .glazed:
      var s = BitStyle(base: hex(0xFFD07C), lip: hex(0xFFFBEF, 0.85),
        shade: stops([(0, 0xFFFFFF, 0.2), (0.25, 0xFFFFFF, 0), (0.6, 0xFFFFFF, 0), (0.85, 0x7A4508, 0.12), (1, 0x5A3206, 0.3)]),
        eye: hex(0x2A2420), blush: hex(0xFF8A6A), dots: hex(0xA8BCD1), chip: hex(0xFFDFA0), sparkle: hex(0xFFF6E0), shadow: darkShadow)
      s.vshade = stops([(0, 0xFFFFFF, 0.08), (0.3, 0xFFFFFF, 0), (0.7, 0xB8651A, 0), (1, 0xB8651A, 0.34)])
      s.groove = hex(0xE08A24)
      s.grooveShade = hex(0x94500A, 0.3)
      s.speckles = true
      s.bands = [
        .init(angle: -0.58, from: 8, to: 140, width: 0.36, color: hex(0xFFFFFF, 0.14)),
        .init(angle: -0.58, from: 10, to: 138, width: 0.11, color: hex(0xFFFFFF, 0.4)),
      ]
      s.spec = 0.9
      s.specSize = CGSize(width: 6, height: 10)
      s.tipGlint = 0.85
      s.rimLeft = hex(0xFFFFFF, 0.3)
      s.rimRight = hex(0xFFF6E0, 0.5)
      return s
    case .ember:
      var s = BitStyle(base: hex(0x2A313F), lip: hex(0xFFF2C8, 0.7),
        shade: stops([(0, 0xA8BCD1, 0.14), (0.25, 0xA8BCD1, 0), (0.6, 0x000000, 0), (1, 0x000000, 0.4)]),
        eye: hex(0xFFCC65), blush: hex(0xFF8A6A), dots: hex(0xFFCC65), chip: hex(0xFFCC65), sparkle: hex(0xFFE7A8),
        shadow: hex(0xFFB43A, 0.32))
      s.vshade = stops([(0, 0xA8BCD1, 0.1), (0.3, 0xA8BCD1, 0), (0.8, 0xFFB43A, 0), (1, 0xFFB43A, 0.22)])
      s.groove = hex(0xFFC24F)
      s.grooveHeight = 8
      s.grooveGlow = hex(0xFFB43A, 0.3)
      s.grooveShade = hex(0xFF8A1F, 0.5)
      s.lipWidth = 1
      s.bands = [.init(angle: -0.62, from: 6, to: 146, width: 0.3, color: hex(0xC9D6E6, 0.14))]
      s.spec = 0.35
      s.specSize = CGSize(width: 7, height: 11)
      s.tipGlint = 0.2
      s.rimLeft = hex(0x8FA6C2, 0.18)
      s.rimRight = hex(0xA8BCD1, 0.7)
      s.eyeGlow = hex(0xFFB43A)
      return s
    case .oxide:
      var s = BitStyle(base: hex(0x353842), lip: hex(0xD8E2F0, 0.75),
        shade: stops([(0, 0x9FB0D0, 0.16), (0.2, 0xFFFFFF, 0), (0.6, 0x000000, 0), (1, 0x000000, 0.45)]),
        eye: hex(0xFFCC65), blush: hex(0xFF8A6A), dots: hex(0xFFCC65), chip: hex(0xC9D6E6), sparkle: hex(0xFFE7A8), shadow: darkShadow)
      s.vshade = stops([(0, 0xC9D6E6, 0.14), (0.25, 0xC9D6E6, 0), (1, 0x000000, 0.25)])
      s.groove = hex(0x1B1D22)
      s.grooveShade = hex(0x000000, 0.35)
      s.grooveTop = hex(0x000000, 0.4)
      s.bands = [
        .init(angle: -0.48, from: 3, to: 146, width: 0.26, color: hex(0xE8EEF8, 0.3)),
        .init(angle: -0.48, from: 5, to: 144, width: 0.1, color: hex(0xE8EEF8, 0.4)),
        .init(angle: 0.7, from: 10, to: 140, width: 0.14, color: hex(0xFFC78A, 0.2)),
      ]
      s.spec = 0.35
      s.specSize = CGSize(width: 4, height: 7)
      s.tipGlint = 0.6
      s.rimLeft = hex(0x8C7CFF, 0.4)
      s.rimRight = hex(0xFFB877, 0.45)
      s.rimWidth = 4
      return s
    case .tempered:
      var s = BitStyle(base: hex(0xF2BE52), lip: hex(0xFFF7DE, 0.85),
        shade: stops([(0, 0xFFFFFF, 0.14), (0.2, 0xFFFFFF, 0), (0.55, 0xFFFFFF, 0), (0.82, 0x24123A, 0.2), (1, 0x120A24, 0.45)]),
        eye: ink, blush: hex(0xFF8A6A), dots: hex(0xA8BCD1), chip: hex(0xC9B6FF), sparkle: hex(0xFFF2C8), shadow: darkShadow)
      s.vshade = stops([(0, 0xFFFFFF, 0.1), (0.42, 0xC9822E, 0), (0.58, 0xC9822E, 0.42), (0.72, 0x8A4FC8, 0.55), (0.86, 0x4A62D8, 0.7),
        (1, 0x2E4AC0, 0.8)])
      s.groove = hex(0xB57A22)
      s.grooveShade = hex(0x2E1A03, 0.35)
      s.grooveTop = hex(0x2E1A03, 0.3)
      s.bands = [
        .init(angle: -0.48, from: 3, to: 146, width: 0.3, color: hex(0xFFF6E0, 0.3)),
        .init(angle: -0.48, from: 5, to: 144, width: 0.12, color: hex(0xFFF6E0, 0.45)),
        .init(angle: 0.66, from: 10, to: 140, width: 0.08, color: hex(0xCFE0FF, 0.3)),
      ]
      s.spec = 0.45
      s.specSize = CGSize(width: 4, height: 7)
      s.tipGlint = 0.8
      s.rimLeft = hex(0xFFE7B0, 0.25)
      s.rimRight = hex(0xBFD4FF, 0.6)
      return s
    case .plush:
      var s = BitStyle(base: hex(0xFFC65A), lip: hex(0xFFF0CC, 0.35),
        shade: stops([(0, 0xFFF1D0, 0.3), (0.14, 0xFFFFFF, 0), (0.6, 0xFFFFFF, 0), (0.86, 0x7A4508, 0.1), (1, 0x5A3206, 0.26)]),
        eye: ink, blush: hex(0xFF7A5C), dots: hex(0xA8BCD1), chip: hex(0xFFE2A0), sparkle: hex(0xFFF2C8), shadow: darkShadow)
      s.vshade = stops([(0, 0xFFFFFF, 0.06), (0.3, 0xFFFFFF, 0), (0.7, 0x5A3206, 0), (1, 0x5A3206, 0.18)])
      s.groove = hex(0xF0A944)
      s.grooveShade = hex(0x9A5A0C, 0.18)
      s.grooveTop = hex(0x7A4508, 0.6)
      s.stitches = true
      s.lipWidth = 1.6
      s.rimLeft = hex(0xFFF4DC, 0.5)
      s.rimRight = hex(0xFFF4DC, 0.45)
      s.rimWidth = 7
      s.outline = hex(0xFFC65A, 0.95)
      s.outlineWidth = 2.4
      s.fuzzy = true
      return s
    case .blueprint:
      var s = BitStyle(base: hex(0x2563B8), lip: hex(0xFFFFFF, 0.9),
        shade: stops([(0, 0xFFFFFF, 0.06), (0.3, 0xFFFFFF, 0), (0.7, 0x000000, 0), (1, 0x0A1E40, 0.3)]),
        eye: hex(0xFFFFFF), blush: hex(0x7FB2FF), dots: hex(0xFFFFFF), chip: hex(0xFFFFFF), sparkle: hex(0xFFFFFF),
        shadow: hex(0x2563B8, 0.5))
      s.grooveTop = hex(0xFFFFFF, 0.9)
      s.lipWidth = 1
      s.lipFalloff = 1
      s.back = hex(0xFFFFFF, 0.4)
      s.backDashed = true
      s.grid = true
      s.outline = hex(0xFFFFFF, 0.95)
      s.centerline = true
      return s
    }
  }
}

enum BitRenderer {
  private struct Speckle {
    var u: Double
    var angle: Double
    var radius: Double
    var light: Bool
  }

  private static let speckles: [Speckle] = {
    var seed: UInt64 = 0x42495453
    func unit() -> Double {
      seed = seed &* 6364136223846793005 &+ 1442695040888963407
      return Double(seed >> 11) / Double(UInt64(1) << 53)
    }
    return (0..<44).map { _ in
      Speckle(u: 6 + unit() * 132, angle: unit() * 2 * .pi, radius: 0.35 + unit() * unit() * 0.9, light: unit() < 0.2)
    }
  }()

  private static let bubbles: [(u: Double, angle: Double, radius: Double)] = [(30, 0.5, 1.6), (104, -0.2, 1.3), (118, 0.9, 0.9)]

  static func draw(_ pose: BitPose, style s: BitStyle, in context: inout GraphicsContext, size: CGSize, shadow: Bool = true) {
    let box = BitShape.viewBox
    let scale = min(size.width / box.width, size.height / box.height)
    context.translateBy(x: (size.width - box.width * scale) / 2, y: (size.height - box.height * scale) / 2)
    context.scaleBy(x: scale, y: scale)

    let g = BitGeometry(pose: pose, grooveHeight: s.grooveHeight)
    let body = Path.bitSmooth(g.outline(), closed: true)
    let bounds = body.boundingRect

    if shadow { drawShadow(g, s, &context) }
    drawOrbit(pose, g, s, front: false, &context)
    context.fill(body, with: .color(s.base))

    var surface = context
    surface.clip(to: body)
    drawSurface(pose, g, s, body: body, bounds: bounds, &surface)

    if let outline = s.outline {
      context.stroke(body, with: .color(outline),
        style: StrokeStyle(lineWidth: s.outlineWidth, lineCap: .round, lineJoin: .round, dash: s.fuzzy ? [0.01, 2.3] : []))
    }
    if s.centerline {
      var axis = [CGPoint(x: g.x(0), y: g.y(0) - 14)]
      for u in stride(from: 0.0, through: BitShape.length, by: 14.6) { axis.append(CGPoint(x: g.x(u), y: g.y(u))) }
      axis.append(CGPoint(x: g.x(BitShape.length), y: g.y(BitShape.length) + 14))
      context.stroke(.bitSmooth(axis, closed: false), with: .color(.white.opacity(0.45)),
        style: StrokeStyle(lineWidth: 0.7, dash: [9, 2.5, 1.5, 2.5]))
    }

    drawFace(pose, g, s, &context)
    drawOrbit(pose, g, s, front: true, &context)
    for particle in pose.particles {
      let r = particle.radius * (0.5 + 0.5 * particle.fade)
      let color = particle.kind == .chip ? s.chip : s.sparkle
      context.fill(Path(ellipseIn: CGRect(x: particle.x - r, y: particle.y - r, width: r * 2, height: r * 2)),
        with: .color(color.opacity(particle.fade)))
    }
  }

  private static func drawShadow(_ g: BitGeometry, _ s: BitStyle, _ context: inout GraphicsContext) {
    let k = min(1, max(0.3, 1.3 - (BitShape.floor - g.y(BitShape.length)) / 38))
    let center = CGPoint(x: g.x(BitShape.length), y: BitShape.floor)
    soft(&context, at: center, rx: 34 * k, ry: 5.5 * k, color: s.shadow.opacity(0.8 * k))
    soft(&context, at: center, rx: 15 * k, ry: 2.6 * k, color: s.shadow.opacity(k * k))
    if let caustic = s.caustic { soft(&context, at: center, rx: 10 * k, ry: 1.8 * k, color: caustic.opacity(0.9 * k * k)) }
  }

  private static func drawSurface(_ pose: BitPose, _ g: BitGeometry, _ s: BitStyle, body: Path, bounds: CGRect,
    _ surface: inout GraphicsContext) {
    let across = (CGPoint(x: bounds.minX, y: 0), CGPoint(x: bounds.maxX, y: 0))
    if !s.glow.isEmpty {
      surface.fill(body, with: .radialGradient(gradient(s.glow),
        center: CGPoint(x: bounds.minX + bounds.width * 0.42, y: bounds.minY + bounds.height * 0.34),
        startRadius: 0, endRadius: max(bounds.width, bounds.height) * 0.62))
    }
    if let back = s.back {
      var path = Path()
      for flute in g.flutes(back: true) { path.addPath(.bitBand(flute.upper, flute.lower)) }
      if s.backDashed {
        surface.stroke(path, with: .color(back), style: StrokeStyle(lineWidth: 0.8, dash: [3, 2]))
      } else {
        surface.fill(path, with: .color(back))
      }
    }
    if s.bubbles {
      for bubble in bubbles {
        let angle = bubble.angle + pose.phase, facing = cos(angle)
        let center = g.point(bubble.u, angle, depth: 0.72), r = bubble.radius * (0.8 + 0.2 * facing)
        let circle = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        let visibility = 0.35 + 0.65 * max(0, facing)
        surface.fill(circle, with: .color(.white.opacity(0.16 * visibility)))
        surface.stroke(circle, with: .color(.white.opacity(0.6 * visibility)), lineWidth: 0.6)
      }
    }
    if s.grid { drawGrid(pose, bounds, &surface) }

    var bands = Path(), shades = Path(), tops = Path(), lips = Path()
    for flute in g.flutes() {
      bands.addPath(.bitBand(flute.upper, flute.lower))
      shades.addPath(.bitBand(flute.upper, flute.middle))
      tops.addPath(.bitSmooth(flute.upper, closed: false))
      lips.addPath(.bitSmooth(flute.lower, closed: false))
    }
    // Fast spins smear the flutes vertically instead of running a blur filter.
    let smear = min(1, max(0, (abs(pose.spin) - 4) / 9)), edges = 1 - 0.6 * smear
    if let glow = s.grooveGlow {
      surface.stroke(bands, with: .color(glow), style: StrokeStyle(lineWidth: 6, lineJoin: .round))
    }
    if let groove = s.groove {
      if smear > 0 {
        for dy in [-1.6, 1.6] {
          var offset = surface
          offset.translateBy(x: 0, y: dy)
          offset.fill(bands, with: .color(groove.opacity(0.35 * smear)))
        }
      }
      surface.fill(bands, with: .color(groove))
    }
    surface.fill(shades, with: .color(s.grooveShade))
    if let top = s.grooveTop {
      surface.stroke(tops, with: .color(top.opacity(edges)),
        style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: s.stitches ? [2.4, 2] : []))
    }
    let middle = s.lipFalloff + (1 - s.lipFalloff) * 0.75
    surface.stroke(lips, with: .linearGradient(Gradient(stops: [
      .init(color: s.lip.opacity(edges), location: 0),
      .init(color: s.lip.opacity(middle * edges), location: 0.5),
      .init(color: s.lip.opacity(s.lipFalloff * edges), location: 1),
    ]), startPoint: across.0, endPoint: across.1), style: StrokeStyle(lineWidth: s.lipWidth, lineCap: .round))

    if s.speckles { drawSpeckles(pose, g, &surface) }
    surface.fill(body, with: .linearGradient(gradient(s.shade), startPoint: across.0, endPoint: across.1))
    if !s.vshade.isEmpty {
      surface.fill(body, with: .linearGradient(gradient(s.vshade), startPoint: CGPoint(x: 0, y: bounds.minY),
        endPoint: CGPoint(x: 0, y: bounds.maxY)))
    }
    // Three nested fills give a band a soft edge without a blur pass.
    for band in s.bands {
      for (fraction, share) in [(1.0, 0.35), (0.62, 0.35), (0.3, 0.3)] {
        let m = g.meridian(angle: band.angle, width: band.width * fraction, from: band.from, to: band.to)
        guard m.left.count > 1 else { continue }
        surface.fill(.bitBand(m.left, m.right), with: .color(band.color.opacity(share)))
      }
    }
    if s.spec > 0 {
      soft(&surface, at: g.point(14, -0.62), rx: s.specSize.width, ry: s.specSize.height, color: .white.opacity(s.spec),
        rotation: -24 * .pi / 180)
    }
    if s.dot > 0 {
      let p = g.point(9, -0.22)
      surface.fill(Path(ellipseIn: CGRect(x: p.x - 1.7, y: p.y - 1.7, width: 3.4, height: 3.4)), with: .color(.white.opacity(s.dot)))
    }
    if s.tipGlint > 0 {
      let center = g.point(BitShape.length - 17, -0.55)
      let a = g.point(BitShape.length - 26, -0.55), b = g.point(BitShape.length - 8, -0.55)
      soft(&surface, at: center, rx: 2, ry: 6, color: .white.opacity(s.tipGlint), rotation: atan2(b.y - a.y, b.x - a.x) - .pi / 2)
    }
    surface.stroke(body, with: .linearGradient(Gradient(stops: [
      .init(color: s.rimLeft, location: 0), .init(color: s.rimLeft.opacity(0), location: 0.16),
      .init(color: s.rimRight.opacity(0), location: 0.72), .init(color: s.rimRight, location: 1),
    ]), startPoint: across.0, endPoint: across.1), lineWidth: s.rimWidth)
  }

  private static func drawGrid(_ pose: BitPose, _ bounds: CGRect, _ surface: inout GraphicsContext) {
    var minor = Path(), major = Path()
    let ox = pose.headX + pose.shake, oy = pose.lift
    for k in Int(((bounds.minX - ox) / 5).rounded(.down))...Int(((bounds.maxX - ox) / 5).rounded(.up)) {
      let x = Double(k) * 5 + ox
      if k % 4 == 0 { major.move(to: CGPoint(x: x, y: bounds.minY)); major.addLine(to: CGPoint(x: x, y: bounds.maxY)) }
      else { minor.move(to: CGPoint(x: x, y: bounds.minY)); minor.addLine(to: CGPoint(x: x, y: bounds.maxY)) }
    }
    for k in Int(((bounds.minY - oy) / 5).rounded(.down))...Int(((bounds.maxY - oy) / 5).rounded(.up)) {
      let y = Double(k) * 5 + oy
      if k % 4 == 0 { major.move(to: CGPoint(x: bounds.minX, y: y)); major.addLine(to: CGPoint(x: bounds.maxX, y: y)) }
      else { minor.move(to: CGPoint(x: bounds.minX, y: y)); minor.addLine(to: CGPoint(x: bounds.maxX, y: y)) }
    }
    surface.stroke(minor, with: .color(.white.opacity(0.14)), lineWidth: 0.35)
    surface.stroke(major, with: .color(.white.opacity(0.28)), lineWidth: 0.5)
  }

  /// Speckles sit on the surface and turn with it, so they only show on the facing side.
  private static func drawSpeckles(_ pose: BitPose, _ g: BitGeometry, _ surface: inout GraphicsContext) {
    var dark = Path(), light = Path()
    for speckle in speckles {
      let angle = speckle.angle + pose.phase, facing = cos(angle)
      guard facing > 0.15 else { continue }
      let p = g.point(speckle.u, angle), r = speckle.radius * (0.5 + 0.5 * facing)
      let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
      if speckle.light { light.addEllipse(in: rect) } else { dark.addEllipse(in: rect) }
    }
    surface.fill(dark, with: .color(hex(0x764010, 0.45)))
    surface.fill(light, with: .color(.white.opacity(0.7)))
  }

  private static func drawFace(_ pose: BitPose, _ g: BitGeometry, _ s: BitStyle, _ context: inout GraphicsContext) {
    let phi = pose.lookX * 0.55, line = BitShape.eyeLine + pose.lookY * 3.4, open = 1 - 0.92 * pose.blink
    if pose.blush > 0.01 {
      for dir in [-1.0, 1.0] {
        let a = phi + dir * 0.72, facing = cos(a)
        guard facing > 0 else { continue }
        soft(&context, at: g.point(line + 8.5, a), rx: 7 * facing, ry: 4, color: s.blush.opacity(0.6 * pose.blush))
      }
    }
    for (dir, eye) in [(-1.0, pose.left), (1.0, pose.right)] {
      let a = phi + dir * BitShape.eyeSpread, facing = cos(a)
      guard facing > 0.12 else { continue }
      let center = g.point(line, a), top = eye.top * open, bottom = eye.bottom * open, width = pose.eyeWidth
      let place = CGAffineTransform(translationX: center.x, y: center.y).scaledBy(x: facing, y: 1)
      if let glow = s.eyeGlow {
        soft(&context, at: center, rx: width * 2.2 * facing, ry: max(top, bottom, 4) * 1.6, color: glow.opacity(0.45))
      }
      let shape = eyePath(width: width, top: top, bottom: bottom).applying(place)
      context.fill(shape, with: .color(s.eye))
      context.stroke(shape, with: .color(s.eye), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
      let shine = min(1, max(0, (min(top, bottom) - 3) / 4))
      guard shine > 0 else { continue }
      var local = context
      local.concatenate(place)
      local.fill(Path(ellipseIn: CGRect(x: -width * 0.55, y: bottom * 0.55 - min(2, bottom * 0.2), width: width * 1.1,
        height: 2 * min(2, bottom * 0.2))), with: .color(.white.opacity(0.16 * shine)))
      local.fill(Path(ellipseIn: CGRect(x: -width * 0.3 - 1.7, y: -top * 0.42 - 1.7, width: 3.4, height: 3.4)),
        with: .color(.white.opacity(shine)))
      local.fill(Path(ellipseIn: CGRect(x: width * 0.3 - 0.8, y: bottom * 0.28 - 0.8, width: 1.6, height: 1.6)),
        with: .color(.white.opacity(0.85 * shine)))
    }
    if pose.mouth > 0.005 {
      let facing = cos(phi), center = g.point(line + 13, phi)
      let place = CGAffineTransform(translationX: center.x, y: center.y).scaledBy(x: max(0, facing), y: 1)
      context.fill(mouthPath(pose.mouth).applying(place), with: .color(s.eye.opacity(min(1, pose.mouth * 6))))
    }
  }

  /// Thinking dots orbit the crown like a halo; the half behind the head is drawn first and dimmer.
  private static func drawOrbit(_ pose: BitPose, _ g: BitGeometry, _ s: BitStyle, front: Bool, _ context: inout GraphicsContext) {
    guard pose.dots > 0.01 else { return }
    let center = CGPoint(x: g.x(8), y: g.y(4) - 4)
    for (index, size) in [3.2, 2.5, 1.9].enumerated() {
      let theta = pose.orbit - Double(index) * 0.45, depth = sin(theta)
      guard (depth > 0) == front else { continue }
      let r = size * (0.85 + 0.15 * depth)
      let p = CGPoint(x: center.x + (BitShape.maxRadius + 15) * cos(theta), y: center.y + 8 * depth)
      context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
        with: .color(s.dots.opacity(pose.dots * (front ? 1 : 0.55))))
    }
  }

  static func eyePath(width w: Double, top: Double, bottom: Double) -> Path {
    let a = top * 1.333, b = bottom * 1.333
    var path = Path()
    path.move(to: CGPoint(x: -w, y: 0))
    path.addCurve(to: CGPoint(x: w, y: 0), control1: CGPoint(x: -w, y: -a), control2: CGPoint(x: w, y: -a))
    path.addCurve(to: CGPoint(x: -w, y: 0), control1: CGPoint(x: w, y: b), control2: CGPoint(x: -w, y: b))
    path.closeSubpath()
    return path
  }

  static func mouthPath(_ open: Double) -> Path {
    let w = 3.6 + 3 * open, d = (1 + 7 * open) * 1.333
    var path = Path()
    path.move(to: CGPoint(x: -w, y: 0))
    path.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: 0, y: 1 + open))
    path.addCurve(to: CGPoint(x: -w, y: 0), control1: CGPoint(x: w, y: d), control2: CGPoint(x: -w, y: d))
    path.closeSubpath()
    return path
  }

  /// A radial falloff stretched into an ellipse, used for shadows, highlights, blush and glows.
  private static func soft(_ context: inout GraphicsContext, at center: CGPoint, rx: Double, ry: Double, color: Color,
    rotation: Double = 0) {
    guard rx > 0.01, ry > 0.01 else { return }
    var layer = context
    layer.translateBy(x: center.x, y: center.y)
    layer.rotate(by: .radians(rotation))
    layer.scaleBy(x: 1, y: ry / rx)
    layer.fill(Path(ellipseIn: CGRect(x: -rx, y: -rx, width: rx * 2, height: rx * 2)),
      with: .radialGradient(Gradient(colors: [color, color.opacity(0)]), center: .zero, startRadius: 0, endRadius: rx))
  }

  private static func gradient(_ list: [BitStop]) -> Gradient {
    Gradient(stops: list.map { Gradient.Stop(color: hex($0.color, $0.opacity), location: $0.location) })
  }
}

extension Path {
  /// Catmull-Rom through `points`, as cubic segments.
  static func bitSmooth(_ points: [CGPoint], closed: Bool) -> Path {
    var path = Path()
    guard let first = points.first else { return path }
    path.move(to: first)
    path.bitAppend(points, closed: closed)
    if closed { path.closeSubpath() }
    return path
  }

  /// A closed band: along `upper`, then back along `lower`.
  static func bitBand(_ upper: [CGPoint], _ lower: [CGPoint]) -> Path {
    var path = Path.bitSmooth(upper, closed: false)
    let back = Array(lower.reversed())
    guard let start = back.first else { return path }
    path.addLine(to: start)
    path.bitAppend(back, closed: false)
    path.closeSubpath()
    return path
  }

  fileprivate mutating func bitAppend(_ p: [CGPoint], closed: Bool) {
    let n = p.count
    guard n > 1 else { return }
    for i in 0..<(closed ? n : n - 1) {
      let a = closed ? p[(i - 1 + n) % n] : p[Swift.max(i - 1, 0)]
      let b = p[i], c = p[(i + 1) % n]
      let d = closed ? p[(i + 2) % n] : p[Swift.min(i + 2, n - 1)]
      addCurve(to: c, control1: CGPoint(x: b.x + (c.x - a.x) / 6, y: b.y + (c.y - a.y) / 6),
        control2: CGPoint(x: c.x - (d.x - b.x) / 6, y: c.y - (d.y - b.y) / 6))
    }
  }
}
