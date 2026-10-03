import CoreGraphics
import Foundation

/// Bit, Drillbit's mascot: the drill bit itself with two dot eyes. Geometry and motion live here,
/// free of SwiftUI so they stay testable; `BitView` draws them. Units are a 200 × 220 view box, y down.
enum BitMood: String, CaseIterable, Sendable {
  case idle, listening, thinking, talking, happy, drilling, content, concerned
}

/// One eye is a single closed shape: an upper and a lower curve. A negative bottom bends it into a ^.
struct BitEye: Sendable, Equatable {
  var top: Double
  var bottom: Double
}

struct BitMoodTarget: Sendable {
  var eyeWidth: Double
  var left: BitEye
  var right: BitEye
  var spin: Double
  var float: Double
  var lean = 1.0
  var blush = 0.0
  var mouth = 0.0
  var talks = false
  var dots = 0.0
  var hops = false
  var sink = 0.0
  var squash = 0.0
  var shake = 0.0
  var chips = false
  var blinks = true
  var look: CGPoint? = nil
}

extension BitMood {
  var target: BitMoodTarget {
    switch self {
    case .idle:
      BitMoodTarget(eyeWidth: 6, left: BitEye(top: 9, bottom: 9), right: BitEye(top: 9, bottom: 9), spin: 0.35, float: 3)
    case .listening:
      BitMoodTarget(eyeWidth: 6.6, left: BitEye(top: 10.2, bottom: 10.2), right: BitEye(top: 10.2, bottom: 10.2), spin: 0.2, float: 2,
        lean: 1.8, blush: 0.35)
    case .thinking:
      BitMoodTarget(eyeWidth: 5.8, left: BitEye(top: 8.6, bottom: 8.6), right: BitEye(top: 5.6, bottom: 8.6), spin: 1.2, float: 3,
        dots: 1, look: CGPoint(x: 0.62, y: -0.85))
    case .talking:
      BitMoodTarget(eyeWidth: 6, left: BitEye(top: 8.8, bottom: 8), right: BitEye(top: 8.8, bottom: 8), spin: 0.5, float: 2.4,
        blush: 0.25, talks: true)
    case .happy:
      BitMoodTarget(eyeWidth: 6.4, left: BitEye(top: 7.2, bottom: -3.6), right: BitEye(top: 7.2, bottom: -3.6), spin: 2.4, float: 2,
        blush: 1, mouth: 0.5, hops: true, blinks: false)
    case .drilling:
      BitMoodTarget(eyeWidth: 6.2, left: BitEye(top: 4, bottom: 8.8), right: BitEye(top: 4, bottom: 8.8), spin: 14, float: 0.6,
        sink: 8, squash: -0.035, shake: 1, chips: true)
    case .content:
      BitMoodTarget(eyeWidth: 6.2, left: BitEye(top: 6.4, bottom: -2.8), right: BitEye(top: 6.4, bottom: -2.8), spin: 0.2, float: 2,
        blush: 0.45, blinks: false)
    case .concerned:
      BitMoodTarget(eyeWidth: 5.6, left: BitEye(top: 7.6, bottom: 8.4), right: BitEye(top: 7.6, bottom: 8.4), spin: 0.1, float: 1.5,
        lean: 0.6, sink: 2, squash: -0.02, look: CGPoint(x: 0.1, y: 0.55))
    }
  }
}

/// The launch screen draws Bit's idle rest pose at this size, centred; the app's restoring surface matches it exactly.
enum BitLaunch {
  static let size = CGSize(width: 120, height: 132)
}

enum BitShape {
  static let viewBox = CGSize(width: 200, height: 220)
  static let centerX = 100.0, top = 38.0, maxRadius = 44.0, dome = 36.0, shank = 92.0, length = 146.0
  static let fluteStart = 66.0, fluteRamp = 12.0, pitch = 54.0, notchDepth = 6.0, grooveHeight = 14.0
  static let eyeLine = 46.0, eyeSpread = 0.37, pivot = length * 0.55, floor = 206.0

  /// Body radius at height `t` from the crown: a rounded dome, a straight shank and a soft cone.
  static func radius(at t: Double) -> Double {
    guard t > 0, t < length else { return 0 }
    if t < dome { let u = (dome - t) / dome; return maxRadius * pow(1 - pow(u, 2.2), 1 / 2.2) }
    if t <= shank { return maxRadius }
    return maxRadius * pow(1 - pow((t - shank) / (length - shank), 1.7), 0.8)
  }

  /// How open a flute is at height `u`: 0 at its run-out point, 1 once fully cut. Linear at the start so the run-out is a V.
  static func opening(_ u: Double) -> Double {
    let v = min(1, max(0, (u - fluteStart) / fluteRamp))
    return 1 - (1 - v) * (1 - v)
  }

  /// Even spacing through the flutes so moving notches never alias between samples.
  static let samples: [Double] = {
    let crown = (0..<24).map { dome * (1 - cos(.pi / 2 * Double($0) / 24)) }
    let body = (0..<Int(((length - 8 - dome) / 1.4).rounded(.up))).map { dome + Double($0) * 1.4 }
    let tip = (0...8).map { length - 8 + 8 * sin(.pi / 2 * Double($0) / 8) }
    return crown + body + tip
  }()
}

struct BitParticle: Sendable, Equatable {
  enum Kind: Sendable { case chip, sparkle }
  var kind: Kind
  var x: Double, y: Double, vx: Double, vy: Double
  var gravity: Double, radius: Double, life: Double
  var age = 0.0
  var fade: Double { max(0, 1 - age / life) }
}

/// Everything needed to draw one frame.
struct BitPose: Sendable, Equatable {
  /// Flute rotation in radians.
  var phase = 0.9
  /// Current spin speed in radians per second; fast spins smear the flutes.
  var spin = 0.0
  var lookX = 0.0, lookY = 0.0
  var headX = 0.0, tipX = 0.0, shake = 0.0
  var squash = 1.0, lift = 0.0
  var eyeWidth = 6.0
  var left = BitEye(top: 9, bottom: 9), right = BitEye(top: 9, bottom: 9)
  var blink = 0.0, mouth = 0.0, blush = 0.0, dots = 0.0, orbit = 1.2
  var particles: [BitParticle] = []

  /// Reduce Motion and still renders: the mood's expression without movement.
  static func rest(_ mood: BitMood) -> BitPose {
    let m = mood.target
    var pose = BitPose()
    pose.lookX = m.look.map { Double($0.x) } ?? 0
    pose.lookY = m.look.map { Double($0.y) } ?? 0
    pose.squash = 1 + m.squash
    pose.lift = m.sink
    pose.eyeWidth = m.eyeWidth
    pose.left = m.left
    pose.right = m.right
    pose.mouth = m.talks ? 0.45 : m.mouth
    pose.blush = m.blush
    pose.dots = m.dots
    return pose
  }
}

/// Surface geometry for one pose. Angles are around the vertical axis; 0 faces the viewer.
struct BitGeometry {
  struct Flute {
    var upper: [CGPoint]
    var middle: [CGPoint]
    var lower: [CGPoint]
  }

  let pose: BitPose
  let grooveHeight: Double
  private let stretch: Double
  /// Each flute is a helix u(a) = origin − pitch · a / 2π that only exists below `fluteStart`.
  private let origins: [Double]

  init(pose: BitPose, grooveHeight: Double = BitShape.grooveHeight) {
    self.pose = pose
    self.grooveHeight = grooveHeight
    stretch = 1 / pose.squash.squareRoot()
    origins = [0.0, 1.0].map { BitShape.fluteStart + BitShape.pitch * (pose.phase + $0 * .pi) / (2 * .pi) }
  }

  func y(_ u: Double) -> Double { BitShape.top + pose.lift + BitShape.pivot + (u - BitShape.pivot) * pose.squash }

  /// The crown follows the lean and the tip lags behind it.
  func x(_ u: Double) -> Double {
    BitShape.centerX + pose.shake + pose.tipX + (pose.headX - pose.tipX) * pow(max(0, 1 - u / BitShape.length), 1.4)
  }

  func radius(_ u: Double) -> Double { BitShape.radius(at: u) * stretch }

  func point(_ u: Double, _ a: Double, depth: Double = 1) -> CGPoint {
    let v = min(BitShape.length, max(0, u))
    return CGPoint(x: x(v) + radius(v) * depth * sin(a), y: y(v))
  }

  /// Flute depth at (u, a), 0...1.
  func groove(_ u: Double, _ a: Double) -> Double {
    var best = 0.0
    for origin in origins {
      var d = (u - origin + BitShape.pitch * a / (2 * .pi)).truncatingRemainder(dividingBy: BitShape.pitch)
      if d < 0 { d += BitShape.pitch }
      let open = BitShape.opening(u - d), g = grooveHeight * open
      if d < g { best = max(best, open * sin(.pi * d / g)) }
    }
    return best
  }

  /// How far the outline steps in at height `u` on `side` (±π/2). The outline is the outermost surface near
  /// the edge, so the lands either side of a flute cut a V whose sides are the flute edges themselves.
  func indent(_ u: Double, side: Double) -> Double {
    guard groove(u, side) > 0 else { return 0 }
    let r = radius(u), depth = BitShape.notchDepth * BitShape.radius(at: u) / BitShape.maxRadius
    var best = 0.0
    for i in -24...24 {
      let da = Double(i) * 0.03
      best = max(best, (r - depth * groove(u, side + da)) * cos(da))
    }
    return r - best
  }

  /// The body outline, clockwise from the crown, with extra samples inside every flute crossing.
  func outline() -> [CGPoint] {
    let right = edgeSamples(.pi / 2), left = edgeSamples(-.pi / 2)
    func edge(_ t: Double, _ dir: Double) -> CGPoint {
      CGPoint(x: x(t) + dir * (radius(t) - indent(t, side: dir * .pi / 2)), y: y(t))
    }
    return right.map { edge($0, 1) } + left.dropFirst().dropLast().reversed().map { edge($0, -1) }
  }

  private func edgeSamples(_ side: Double) -> [Double] {
    var extra: [Double] = [], skip: [(Double, Double)] = []
    for origin in origins {
      for m in -2...3 {
        let crossing = origin - BitShape.pitch * (side + 2 * .pi * Double(m)) / (2 * .pi)
        let g = grooveHeight * BitShape.opening(crossing)
        guard g >= 0.05, crossing < BitShape.length else { continue }
        for k in 0...16 {
          let t = crossing + g * Double(k) / 16
          if t < BitShape.length { extra.append(t) }
        }
        skip.append((crossing - 0.7, crossing + g + 0.7))
      }
    }
    let base = BitShape.samples.filter { t in
      t == 0 || t == BitShape.length || !skip.contains { t > $0.0 && t < $0.1 }
    }
    return (base + extra).sorted()
  }

  /// Visible flute bands on the front (or, for translucent finishes, the back). Sampled on a fixed angular
  /// grid plus the exact run-out point, so the V tip slides instead of stepping.
  func flutes(back: Bool = false) -> [Flute] {
    var result: [Flute] = []
    let step = Double.pi / 24
    for origin in origins {
      for n in -3...2 {
        let center = 2 * .pi * Double(n) + (back ? .pi : 0)
        let start = center - .pi / 2
        let end = min(center + .pi / 2, (origin - BitShape.fluteStart) * 2 * .pi / BitShape.pitch)
        guard end > start + 0.002, origin - BitShape.pitch * end / (2 * .pi) <= BitShape.length + 1 else { continue }
        var angles: [Double] = []
        var angle = start
        while angle < end - step * 0.3 { angles.append(angle); angle += step }
        angles.append(end)
        if angles.count < 2 { angles.insert(start, at: 0) }
        var flute = Flute(upper: [], middle: [], lower: [])
        for a in angles {
          let u = origin - BitShape.pitch * a / (2 * .pi), g = grooveHeight * BitShape.opening(u)
          flute.upper.append(point(u, a))
          flute.middle.append(point(u + g * 0.42, a))
          flute.lower.append(point(u + g, a))
        }
        result.append(flute)
      }
    }
    return result
  }

  /// A highlight band following the body's curvature at `angle`, tapering to points at both ends.
  func meridian(angle: Double, width: Double, from t0: Double, to t1: Double) -> (left: [CGPoint], right: [CGPoint]) {
    var left: [CGPoint] = [], right: [CGPoint] = []
    for t in BitShape.samples where t >= t0 && t <= t1 {
      let half = width / 2 * max(0, sin(.pi * (t - t0) / (t1 - t0))).squareRoot()
      left.append(point(t, angle - half))
      right.append(point(t, angle + half))
    }
    return (left, right)
  }
}

/// Springs, blinks, glances and particles. Clock time accumulates per frame, so pauses resume smoothly.
@MainActor final class BitDynamics {
  private struct Spring {
    var value: Double
    var target: Double
    var velocity = 0.0
    let stiffness: Double
    let damping: Double
    init(_ value: Double, _ stiffness: Double, _ damping: Double) {
      self.value = value; target = value; self.stiffness = stiffness; self.damping = damping
    }
    mutating func step(_ dt: Double) {
      velocity += (stiffness * (target - value) - damping * velocity) * dt
      value += velocity * dt
    }
  }
  private enum Channel: Int, CaseIterable {
    case lookX, lookY, headX, tipX, squash, hop, sink, eyeWidth, leftTop, leftBottom, rightTop, rightBottom, mouth, blush, spin, dots
  }
  private var springs: [Spring] = Channel.allCases.map { channel in
    switch channel {
    case .lookX, .lookY: Spring(0, 140, 17)
    case .headX: Spring(0, 90, 12)
    case .tipX: Spring(0, 40, 6)
    case .squash: Spring(1, 260, 11)
    case .hop: Spring(0, 70, 7)
    case .sink: Spring(0, 40, 12)
    case .eyeWidth: Spring(6, 320, 26)
    case .leftTop, .leftBottom, .rightTop, .rightBottom: Spring(9, 320, 26)
    case .mouth: Spring(0, 600, 40)
    case .blush: Spring(0, 60, 14)
    case .spin: Spring(0.35, 8, 5.5)
    case .dots: Spring(0, 50, 14)
    }
  }
  private subscript(_ channel: Channel) -> Spring {
    get { springs[channel.rawValue] }
    set { springs[channel.rawValue] = newValue }
  }

  private var random: UInt64
  private let seed: Double
  private var last: Date?
  private var time = 0.0, phase = 0.9, orbit = 1.2
  private var mood: BitMood = .idle
  private var glance = CGPoint.zero, glanceIn = 1.5
  private var blinkIn = 2.0, blinkClock = -1.0
  private var hopIn = 0.0, hops = 0, chipCarry = 0.0, booped = 0.0, burstPending = false
  private var particles: [BitParticle] = []
  private(set) var current = BitPose()

  init(seed: UInt64 = .random(in: 1...UInt64.max)) {
    random = seed
    self.seed = Double(seed % 1000) / 100
    phase = Double(seed % 628) / 100
  }

  /// A tap: squish, twirl, sparkle, and be happy for a moment.
  func boop() {
    self[.squash].velocity -= 3.2
    self[.headX].velocity += (unit() - 0.5) * 90
    self[.spin].velocity += 12
    burstPending = true
    if mood != .happy { hopIn = 0.12; hops = 1; mood = .happy }
    booped = 1.5
  }

  func advance(to date: Date, mood: BitMood, level: Double? = nil) -> BitPose {
    let dt = min(0.1, max(0, date.timeIntervalSince(last ?? date)))
    last = date
    return step(dt, mood: mood, level: level)
  }

  /// `level` is measured audio (0...1); it drives the mouth while talking.
  func step(_ dt: Double, mood requested: BitMood, level: Double? = nil) -> BitPose {
    booped = max(0, booped - dt)
    let mood = booped > 0 ? .happy : requested
    if mood == .happy, self.mood != .happy { hopIn = 0.05; hops = 0 }
    self.mood = mood
    let m = mood.target
    time += dt

    glanceIn -= dt
    if glanceIn <= 0 {
      glanceIn = 1.4 + unit() * 2.6
      let next = unit() < 0.6 ? CGPoint(x: unit() * 1.5 - 0.75, y: unit() * 0.9 - 0.45) : .zero
      if hypot(next.x - glance.x, next.y - glance.y) > 0.6, blinkClock < 0, unit() < 0.6 { blinkClock = 0 }
      glance = next
    }
    let blink = blinkAmount(dt, enabled: m.blinks)
    let look = m.look ?? glance

    self[.lookX].target = look.x
    self[.lookY].target = look.y
    self[.headX].target = self[.lookX].value * 5 * m.lean + (m.chips ? 0 : sin(time * 0.8 + seed) * 1.4)
    self[.tipX].target = self[.headX].value * 0.2
    self[.eyeWidth].target = m.eyeWidth
    self[.leftTop].target = m.left.top
    self[.leftBottom].target = m.left.bottom
    self[.rightTop].target = m.right.top
    self[.rightBottom].target = m.right.bottom
    self[.mouth].target = m.talks ? (level.map { min(1, $0 * 1.6) } ?? Self.talk(time + seed)) : m.mouth
    self[.blush].target = m.blush
    self[.spin].target = m.spin
    self[.dots].target = m.dots
    self[.sink].target = m.sink
    let anticipation = m.hops && hopIn < 0.16 ? 0.08 : 0
    self[.squash].target = 1 + m.squash + sin(time * 1.6 + seed - 0.9) * 0.014 - blink * 0.025
      + self[.mouth].value * 0.025 - anticipation

    if m.hops {
      hopIn -= dt
      if hopIn <= 0 {
        self[.hop].velocity -= 210
        self[.squash].velocity += 2.2
        if hops % 3 == 0 { burstPending = true }
        hops += 1
        hopIn = 1.05
      }
    }

    // Small fixed substeps keep the stiff springs stable at any frame rate.
    let count = max(1, Int((dt / 0.01).rounded(.up))), h = dt / Double(count)
    for _ in 0..<count { for index in springs.indices { springs[index].step(h) } }

    phase = (phase + self[.spin].value * dt).truncatingRemainder(dividingBy: 2 * .pi)
    if phase < 0 { phase += 2 * .pi }
    orbit += dt * 2.4

    var pose = BitPose()
    pose.phase = phase
    pose.spin = self[.spin].value
    pose.lookX = self[.lookX].value
    pose.lookY = self[.lookY].value
    pose.headX = self[.headX].value
    pose.tipX = self[.tipX].value
    pose.shake = m.shake * sin(time * 70) * 0.7
    pose.squash = max(0.7, self[.squash].value)
    pose.lift = sin(time * 1.6 + seed) * m.float + self[.hop].value + self[.sink].value
    pose.eyeWidth = self[.eyeWidth].value
    pose.left = BitEye(top: self[.leftTop].value, bottom: self[.leftBottom].value)
    pose.right = BitEye(top: self[.rightTop].value, bottom: self[.rightBottom].value)
    pose.blink = blink
    pose.mouth = max(0, self[.mouth].value)
    pose.blush = max(0, self[.blush].value)
    pose.dots = min(1, max(0, self[.dots].value))
    pose.orbit = orbit

    let geometry = BitGeometry(pose: pose)
    if burstPending { burstPending = false; burst(geometry) }
    if m.chips {
      chipCarry += dt * 24
      while chipCarry >= 1 { chipCarry -= 1; chip(geometry) }
    } else {
      chipCarry = 0
    }
    particles = particles.compactMap { particle in
      var p = particle
      p.age += dt
      guard p.age < p.life else { return nil }
      p.vy += p.gravity * dt
      p.x += p.vx * dt
      p.y += p.vy * dt
      return p
    }
    pose.particles = particles
    current = pose
    return pose
  }

  static func talk(_ t: Double) -> Double {
    if sin(t * 1.25) + sin(t * 0.53) * 0.6 < -0.4 { return 0.06 }
    return 0.18 + 0.82 * max(0, sin(t * 12.5 + sin(t * 2.9) * 2.2)) * (0.6 + 0.4 * sin(t * 4.7))
  }

  private func blinkAmount(_ dt: Double, enabled: Bool) -> Double {
    guard enabled else { blinkClock = -1; return 0 }
    blinkIn -= dt
    if blinkIn <= 0, blinkClock < 0 {
      blinkClock = 0
      blinkIn = unit() < 0.18 ? 0.32 : 2.2 + unit() * 3.4
    }
    guard blinkClock >= 0 else { return 0 }
    blinkClock += dt
    let p = blinkClock / 0.17
    if p >= 1 { blinkClock = -1; return 0 }
    return p < 0.45 ? sin(p / 0.45 * .pi / 2) : 0.5 + 0.5 * cos((p - 0.45) / 0.55 * .pi)
  }

  private func emit(_ particle: BitParticle) {
    if particles.count < 16 { particles.append(particle) }
  }

  private func burst(_ g: BitGeometry) {
    for i in 0..<7 {
      let a = -.pi + .pi * (Double(i) + 0.5) / 7 + (unit() - 0.5) * 0.3, speed = 70 + unit() * 50
      emit(BitParticle(kind: .sparkle, x: g.x(10) + cos(a) * 30, y: g.y(10) + sin(a) * 14, vx: cos(a) * speed,
        vy: sin(a) * speed - 20, gravity: 60, radius: 1.5 + unit(), life: 0.6 + unit() * 0.3))
    }
  }

  private func chip(_ g: BitGeometry) {
    let u = BitShape.fluteStart + 10 + unit() * (BitShape.length - BitShape.fluteStart - 26)
    let side: Double = unit() < 0.5 ? -1 : 1
    emit(BitParticle(kind: .chip, x: g.x(u) + side * g.radius(u), y: g.y(u), vx: side * (40 + unit() * 70),
      vy: -(40 + unit() * 80), gravity: 300, radius: 1.3 + unit() * 1.5, life: 0.5 + unit() * 0.4))
  }

  private func unit() -> Double {
    random = random &* 6364136223846793005 &+ 1442695040888963407
    return Double(random >> 11) / Double(UInt64(1) << 53)
  }
}
