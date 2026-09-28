import SwiftUI

/// Signal uses one graphite and yellow identity, with a warm light companion.
/// Meaning stays in the content; yellow marks active state and primary action.
enum AppPalette {
  private static func adaptiveUIColor(_ dark: UInt32, _ light: UInt32) -> UIColor {
    UIColor { traits in
      let hex = traits.userInterfaceStyle == .dark ? dark : light
      return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                     green: CGFloat((hex >> 8) & 0xFF) / 255,
                     blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
  }
  private static func adaptive(_ dark: UInt32, _ light: UInt32) -> Color {
    Color(uiColor: adaptiveUIColor(dark, light))
  }
  static let backgroundUIColor = adaptiveUIColor(0x1F2430, 0xF6F4EE)
  static let background = Color(uiColor: backgroundUIColor)
  static let groupedBackground = background
  static let surface = adaptive(0x232834, 0xFFFFFF)
  static let elevated = adaptive(0x2A303E, 0xECE9E0)
  static let inset = adaptive(0x191E28, 0xEAE7DE)
  static let primary = adaptive(0xF3F4F6, 0x202632)
  static let secondary = adaptive(0xADB4C0, 0x566171)
  static let accent = adaptive(0xFFCC65, 0x8A5310)
  static let action = Color(red: 1, green: 204 / 255, blue: 101 / 255)
  static let actionInk = Color(red: 31 / 255, green: 36 / 255, blue: 48 / 255)
  static let accentSoft = adaptive(0x3D3730, 0xF7E7C6)
  static let hairline = adaptive(0x414C5D, 0xCBD0D5)
  static let grain = adaptive(0xD8D6CF, 0x6D717A)
  static let destructive = adaptive(0xF0817B, 0xAD3333)
  static let success = adaptive(0x97CFB0, 0x286A50)
  // Brand colours from docs/design/logo.
  static let logoDrill = adaptive(0xFFCC65, 0x1F2430)
  static let logoInk = adaptive(0xF3F4F6, 0x1F2430)
  static let logoDot = adaptive(0xFFCC65, 0xE0A030)
}

/// Shared timing. Frequent interactions stay short; only rare moments linger.
enum DrillbitMotion {
  static let press = Animation.spring(duration: 0.16, bounce: 0)
  static let fast = Animation.easeOut(duration: 0.14)
  static let selection = Animation.spring(duration: 0.24, bounce: 0)
  static let disclosure = Animation.easeInOut(duration: 0.22)
  static let reveal = Animation.smooth(duration: 0.32, extraBounce: 0)
  static let page = Animation.smooth(duration: 0.38, extraBounce: 0)
  static let entrance = Animation.smooth(duration: 0.55, extraBounce: 0)
  static let celebrate = Animation.spring(duration: 0.5, bounce: 0.3)
  // Interview document timings are tuned against keyboard and streaming layout.
  static let document = Animation.smooth(duration: 0.38, extraBounce: 0)
  static let send = Animation.smooth(duration: 0.42, extraBounce: 0)
  static let stream = Animation.easeOut(duration: 0.18)
}

/// The drill from docs/design/logo: cap, two flutes and tip, in 240 × 680 source units centred on the origin.
enum DrillbitGlyph {
  static let width: CGFloat = 240
  static let height: CGFloat = 680

  static func segment(_ index: Int) -> Path {
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
    var path = Path()
    switch index {
    case 0:
      path.move(to: p(-120, -316))
      path.addQuadCurve(to: p(-96, -340), control: p(-120, -340))
      path.addLine(to: p(96, -340))
      path.addQuadCurve(to: p(120, -316), control: p(120, -340))
      path.addLine(to: p(120, -255))
      path.addCurve(to: p(0, -185), control1: p(120, -227.5), control2: p(43.5, -201.2))
      path.addCurve(to: p(-120, -115), control1: p(-43.5, -168.8), control2: p(-120, -142.5))
    case 1, 2:
      let dy: CGFloat = index == 1 ? 0 : 140
      path.move(to: p(-120, -61 + dy))
      path.addCurve(to: p(0, -131 + dy), control1: p(-120, -88.5 + dy), control2: p(-43.5, -114.8 + dy))
      path.addCurve(to: p(120, -201 + dy), control1: p(43.5, -147.2 + dy), control2: p(120, -173.5 + dy))
      path.addLine(to: p(120, -115 + dy))
      path.addCurve(to: p(0, -45 + dy), control1: p(120, -87.5 + dy), control2: p(43.5, -61.2 + dy))
      path.addCurve(to: p(-120, 25 + dy), control1: p(-43.5, -28.8 + dy), control2: p(-120, -2.5 + dy))
    default:
      path.move(to: p(-120, 219))
      path.addCurve(to: p(0, 149), control1: p(-120, 191.5), control2: p(-43.5, 165.2))
      path.addCurve(to: p(120, 79), control1: p(43.5, 132.8), control2: p(120, 106.5))
      path.addLine(to: p(120, 248))
      path.addLine(to: p(12, 330.8))
      path.addQuadCurve(to: p(-12, 330.8), control: p(0, 340))
      path.addLine(to: p(-120, 248))
    }
    path.closeSubpath()
    return path
  }
}

struct DrillbitDrillShape: Shape {
  var segments: [Int] = [0, 1, 2, 3]
  func path(in rect: CGRect) -> Path {
    let scale = min(rect.width / DrillbitGlyph.width, rect.height / DrillbitGlyph.height)
    let place = CGAffineTransform(translationX: rect.midX, y: rect.midY).scaledBy(x: scale, y: scale)
    var path = Path()
    for index in segments { path.addPath(DrillbitGlyph.segment(index), transform: place) }
    return path
  }
}

/// The full wordmark from docs/design/logo, drawn in its 670 × 194 view box.
struct DrillbitLogoShape: Shape {
  enum Part { case drill, letters, dots }
  let part: Part

  func path(in rect: CGRect) -> Path {
    let scale = min(rect.width / 670, rect.height / 194)
    let fit = CGAffineTransform(translationX: rect.midX - 335 * scale, y: rect.midY - 97 * scale)
      .scaledBy(x: scale, y: scale).translatedBy(x: 0, y: 170)
    var path = Path()
    switch part {
    case .drill:
      let drill = CGAffineTransform(translationX: 33.6, y: -73).scaledBy(x: 0.28, y: 0.28)
      for index in 0..<4 { path.addPath(DrillbitGlyph.segment(index), transform: drill) }
    case .letters:
      var strokes = Path()
      strokes.addEllipse(in: CGRect(x: 12, y: -89.5, width: 79, height: 79))
      strokes.addEllipse(in: CGRect(x: 352.5, y: -89.5, width: 79, height: 79))
      for (x, top) in [(91.0, -146.0), (139, -100), (208.5, -100), (256.5, -146), (304.5, -146), (352.5, -146), (475.5, -100), (531.5, -128)] {
        strokes.move(to: CGPoint(x: x, y: top)); strokes.addLine(to: CGPoint(x: x, y: 0))
      }
      strokes.move(to: CGPoint(x: 139, y: -50))
      strokes.addCurve(to: CGPoint(x: 178.5, y: -89.5), control1: CGPoint(x: 139, y: -71.82), control2: CGPoint(x: 156.68, y: -89.5))
      strokes.move(to: CGPoint(x: 505.5, y: -88)); strokes.addLine(to: CGPoint(x: 561.5, y: -88))
      path = strokes.strokedPath(StrokeStyle(lineWidth: 24)).applying(CGAffineTransform(translationX: 107.2, y: 0))
    case .dots:
      path.addEllipse(in: CGRect(x: 107.2 + 208.5 - 14, y: -142, width: 28, height: 28))
      path.addEllipse(in: CGRect(x: 107.2 + 475.5 - 14, y: -142, width: 28, height: 28))
    }
    return path.applying(fit)
  }
}

/// The drill alone. Rare moments let its segments arrive top to bottom.
struct DrillbitMark: View {
  /// Height in points; width follows the drill's proportions.
  var size: CGFloat = 52
  var foreground: Color = AppPalette.logoDrill
  var arrives = false
  @State private var arrived = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      ForEach(0..<4, id: \.self) { index in
        let shown = !arrives || arrived
        DrillbitDrillShape(segments: [index]).fill(foreground)
          .offset(y: shown || reduceMotion ? 0 : -size * 0.08)
          .opacity(shown ? 1 : 0)
          .animation(reduceMotion ? nil : DrillbitMotion.celebrate.delay(0.1 + Double(index) * 0.07), value: arrived)
      }
    }
    .frame(width: size * DrillbitGlyph.width / DrillbitGlyph.height, height: size)
    .onAppear { if arrives { arrived = true } }
    .accessibilityHidden(true)
  }
}

struct DrillbitLogo: View {
  var compact = false
  var body: some View {
    let height: CGFloat = compact ? 28 : 40
    ZStack {
      DrillbitLogoShape(part: .drill).fill(AppPalette.logoDrill)
      DrillbitLogoShape(part: .letters).fill(AppPalette.logoInk)
      DrillbitLogoShape(part: .dots).fill(AppPalette.logoDot)
    }
    .frame(width: height * 670 / 194, height: height)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Drillbit")
  }
}

/// Linear audio levels (0...1) written by the voice transport and read by
/// `SignalPresence` every frame. Deliberately unobserved: no view invalidation.
@MainActor final class VoiceLevels {
  var input = 0.0
  var output = 0.0
  func reset() { input = 0; output = 0 }
}

/// The interviewer's presence: a slowly turning particle orb around a warm core.
/// Live levels ripple the silver shell (you) and swell the yellow core (interviewer).
/// Reduce Motion, Still mode and background render one still frame.
struct SignalPresence: View {
  enum Mode: Equatable { case still, ambient, connecting, live, muted }
  var mode: Mode = .ambient
  var density = 520
  var levels: VoiceLevels? = nil
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var visible = false
  @State private var dynamics = PresenceDynamics()

  var body: some View {
    let particles = SignalParticle.field(density)
    let still = reduceMotion || mode == .still
    // Only true background pauses; system sheets (Sign in with Apple) leave it turning.
    let paused = still || !visible || scenePhase == .background
    let interval = ProcessInfo.processInfo.isLowPowerModeEnabled ? 1.0 / 20 : 1.0 / 30
    TimelineView(.animation(minimumInterval: interval, paused: paused)) { timeline in
      let frame = still ? PresenceFrame.rest(mode) : paused ? dynamics.current : dynamics.advance(to: timeline.date, mode: mode, levels: levels)
      Canvas { context, size in
        SignalPresenceRenderer.draw(particles, frame: frame, in: &context, size: size)
      }
    }
    .onAppear { visible = true }
    .onDisappear { visible = false }
    .accessibilityHidden(true)
  }
}

struct PresenceFrame: Sendable {
  var time = 0.0
  var motion = 0.0
  var input = 0.0
  var output = 0.0
  var quiet = 0.0
  var connecting = 0.0
  var spin = 0.0
  static func rest(_ mode: SignalPresence.Mode) -> PresenceFrame {
    PresenceFrame(quiet: mode == .muted ? 1 : 0)
  }
}

/// Frame-clock state for one presence view: smoothed levels and mode blends.
@MainActor final class PresenceDynamics {
  private var last: Date?
  private var frame = PresenceFrame()
  var current: PresenceFrame { frame }

  func advance(to date: Date, mode: SignalPresence.Mode, levels: VoiceLevels?) -> PresenceFrame {
    // Accumulated time: pauses and resumes continue smoothly instead of jumping.
    let dt = min(0.1, max(0, date.timeIntervalSince(last ?? date)))
    last = date
    let live = mode == .live
    frame.time += dt
    frame.input = approach(frame.input, live ? levels?.input ?? 0 : 0, dt, attack: 0.06, release: 0.28)
    frame.output = approach(frame.output, live ? levels?.output ?? 0 : 0, dt, attack: 0.06, release: 0.28)
    frame.quiet = approach(frame.quiet, mode == .muted ? 1 : 0, dt, attack: 0.2, release: 0.2)
    frame.connecting = approach(frame.connecting, mode == .connecting ? 1 : 0, dt, attack: 0.25, release: 0.25)
    frame.motion = approach(frame.motion, 1, dt, attack: 0.6, release: 0.6)
    // Integrated so speech speeds the turn without the orb jumping.
    frame.spin += dt * (0.1 + 0.3 * max(frame.input, frame.output)) * (1 - 0.7 * frame.quiet)
    return frame
  }

  private func approach(_ value: Double, _ target: Double, _ dt: Double, attack: Double, release: Double) -> Double {
    value + (target - value) * (1 - exp(-dt / (target > value ? attack : release)))
  }
}

struct SignalParticle: Sendable {
  enum Layer: Sendable { case core, shell, dust }
  static let depthBuckets = 8
  var layer: Layer
  var theta: Double
  var height: Double
  var ring: Double
  var radius: Double
  var size: Double
  var warm: Bool
  var phase: Double
  var response: Double

  @MainActor private static var cache: [Int: [SignalParticle]] = [:]

  /// Deterministic: the same density always produces the same orb.
  @MainActor static func field(_ density: Int) -> [SignalParticle] {
    if let cached = cache[density] { return cached }
    var seed: UInt64 = 0x5349474E414C
    func unit() -> Double {
      seed = seed &* 6364136223846793005 &+ 1442695040888963407
      return Double(seed >> 11) / Double(1 << 53)
    }
    var particles: [SignalParticle] = []
    particles.reserveCapacity(density)
    for _ in 0..<density {
      let pick = unit()
      let layer: Layer = pick < 0.22 ? .core : pick < 0.93 ? .shell : .dust
      let theta = unit() * .pi * 2
      let height = unit() * 2 - 1
      let radius: Double
      let size: Double
      switch layer {
      case .core:
        let gaussian = sqrt(-2 * log(max(unit(), 1e-9))) * cos(2 * .pi * unit())
        radius = min(0.5, abs(gaussian) * 0.2)
        size = 1.2 + unit() * 1.2
      case .shell:
        // A thin shell keeps a readable sphere edge when projected.
        radius = 0.8 + (unit() + unit() + unit() - 1.5) * 0.055
        size = 0.8 + unit()
      case .dust:
        radius = 1.0 + unit() * 0.28
        size = 0.5 + unit() * 0.6
      }
      let warm = layer == .core || (layer == .shell && unit() < 0.05)
      particles.append(SignalParticle(layer: layer, theta: theta, height: height, ring: sqrt(1 - height * height),
        radius: radius, size: size, warm: warm, phase: unit() * .pi * 2, response: 0.6 + 0.8 * unit()))
    }
    cache[density] = particles
    return particles
  }
}

enum SignalPresenceRenderer {
  static func draw(_ particles: [SignalParticle], frame: PresenceFrame, in context: inout GraphicsContext, size: CGSize) {
    let cx = Double(size.width) / 2, cy = Double(size.height) / 2
    let scale = Double(min(size.width, size.height)) * 0.4
    let breath = frame.connecting * (0.5 + 0.5 * sin(frame.time * 2.4)) * 0.35
    let listening = max(frame.input, breath)
    let speaking = max(frame.output, breath)
    let quiet = 1 - 0.45 * frame.quiet
    let contraction = 1 - 0.06 * frame.quiet
    let tilt = 0.38 + 0.05 * sin(frame.time * 0.23) * frame.motion
    let cosTilt = cos(tilt), sinTilt = sin(tilt)

    let glow = scale * (0.62 + 0.25 * speaking)
    context.fill(Path(ellipseIn: CGRect(x: cx - glow, y: cy - glow, width: 2 * glow, height: 2 * glow)),
      with: .radialGradient(Gradient(colors: [AppPalette.action.opacity((0.2 + 0.22 * speaking) * quiet), AppPalette.action.opacity(0)]),
        center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: glow))

    let buckets = SignalParticle.depthBuckets
    var warm = Array(repeating: Path(), count: buckets)
    var grain = Array(repeating: Path(), count: buckets)
    for particle in particles {
      var radius = particle.radius * contraction * (1 + 0.02 * sin(frame.time * 0.8 + particle.phase) * frame.motion)
      switch particle.layer {
      case .core: radius *= 1 + speaking * 0.45 * particle.response
      case .shell: radius *= 1 + listening * (0.05 + 0.07 * sin(3 * particle.theta + frame.time * 5 + particle.phase)) * particle.response
      case .dust: radius *= 1 + (listening + speaking) * 0.06
      }
      // Dust turns slower than the shell, which reads as depth.
      let angle = particle.theta + frame.spin * (particle.layer == .dust ? 0.6 : 1)
      let x = radius * particle.ring * cos(angle)
      let z0 = radius * particle.ring * sin(angle)
      let y0 = radius * particle.height
      let y = y0 * cosTilt - z0 * sinTilt
      let z = y0 * sinTilt + z0 * cosTilt
      let depth = min(1, max(0, (z / 1.28 + 1) / 2))
      let dot = particle.size * (0.55 + 0.9 * depth)
      let rect = CGRect(x: cx + x * scale - dot / 2, y: cy + y * scale - dot / 2, width: dot, height: dot)
      let bucket = min(buckets - 1, Int(depth * Double(buckets)))
      if particle.warm { warm[bucket].addEllipse(in: rect) } else { grain[bucket].addEllipse(in: rect) }
    }
    for bucket in 0..<buckets {
      let depth = (Double(bucket) + 0.5) / Double(buckets)
      context.fill(grain[bucket], with: .color(AppPalette.grain.opacity(min(1, (0.08 + 0.72 * depth) * (1 + listening * 0.6)) * quiet)))
      context.fill(warm[bucket], with: .color(AppPalette.action.opacity(min(1, (0.4 + 0.6 * depth) * (1 + speaking * 0.5)) * quiet)))
    }
  }
}

struct SignalEyebrow: View {
  let text: String
  var body: some View {
    Text(text.uppercased())
      .font(.caption2.weight(.semibold).monospaced())
      .tracking(1.2)
      .foregroundStyle(AppPalette.accent)
  }
}

/// Use only for editable fields or a selected control, never to group content.
struct SignalInset: ViewModifier {
  var padding: CGFloat = 20
  func body(content: Content) -> some View {
    content
      .padding(padding)
      .background(AppPalette.inset, in: RoundedRectangle(cornerRadius: 12))
  }
}

/// Rows stay on the page floor. Only a row's control may opt into an inset.
struct SignalList<Content: View>: View {
  @ViewBuilder var content: () -> Content

  var body: some View {
    List {
      Group { content() }
        .listRowBackground(AppPalette.background)
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .background(AppPalette.background)
    .containerBackground(AppPalette.background, for: .navigation)
  }
}

extension View {
  func signalInset(padding: CGFloat = 20) -> some View {
    modifier(SignalInset(padding: padding))
  }
}

struct SignalChoiceRow: View {
  let title: String
  let selected: Bool
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 16) {
        Text(title)
        Spacer(minLength: 8)
        if selected {
          Image(systemName: AppIcon.checkmark.rawValue).fontWeight(.semibold)
            .foregroundStyle(AppPalette.accent)
            .transition(.iconPop)
        }
      }
      .padding(.horizontal, 16)
      .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(SignalChoiceButtonStyle(selected: selected))
    .animation(DrillbitMotion.selection, value: selected)
    .sensoryFeedback(.selection, trigger: selected) { _, now in now }
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

private struct SignalChoiceButtonStyle: ButtonStyle {
  let selected: Bool
  @Environment(\.isEnabled) private var isEnabled
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(isEnabled ? AppPalette.primary : AppPalette.secondary)
      .background {
        // A 2-point vertical inset keeps adjacent multi-selections distinct.
        RoundedRectangle(cornerRadius: 12).fill(AppPalette.inset)
          .padding(.vertical, 2)
          .opacity(selected ? 1 : configuration.isPressed ? 0.6 : 0)
      }
      .animation(configuration.isPressed ? nil : DrillbitMotion.fast, value: configuration.isPressed)
  }
}

struct SignalChoice<ID: Hashable>: Identifiable {
  let id: ID
  let title: String
}

/// Choice rows separated by rules that step aside for the selected inset.
struct SignalChoiceList<ID: Hashable>: View {
  let options: [SignalChoice<ID>]
  let isSelected: (ID) -> Bool
  var isDisabled: (ID) -> Bool = { _ in false }
  let select: (ID) -> Void

  var body: some View {
    VStack(spacing: 0) {
      ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
        let hidesRule = index == 0 || isSelected(option.id) || isSelected(options[index - 1].id)
        SignalChoiceRow(title: option.title, selected: isSelected(option.id)) { select(option.id) }
          .disabled(isDisabled(option.id))
          .overlay(alignment: .top) {
            Divider().padding(.horizontal, 16).opacity(hidesRule ? 0 : 1)
              .animation(DrillbitMotion.selection, value: hidesRule)
          }
      }
    }
  }
}

/// Page-floor rows: an inset appears under the finger, never a card at rest.
struct DrillbitRowButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .background {
        RoundedRectangle(cornerRadius: 12).fill(AppPalette.inset)
          .padding(.horizontal, -12)
          .opacity(configuration.isPressed ? 1 : 0)
      }
      .animation(configuration.isPressed ? nil : DrillbitMotion.fast, value: configuration.isPressed)
  }
}

/// Custom-drawn controls (voice transport) share the button press language.
struct DrillbitPressStyle: ButtonStyle {
  var scale: CGFloat = 0.96
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
      .opacity(configuration.isPressed && reduceMotion ? 0.7 : 1)
      .animation(DrillbitMotion.press, value: configuration.isPressed)
  }
}

/// Step count above a track; yellow fills the completed share.
struct SignalStepProgress<Accessory: View>: View {
  let step: Int
  let total: Int
  @ViewBuilder var accessory: () -> Accessory
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        SignalEyebrow(text: String(format: "%02d / %02d", step, total))
          .contentTransition(.numericText(value: Double(step)))
          .accessibilityLabel("Step \(step) of \(total)")
        Spacer(minLength: 0)
        accessory()
      }
      Capsule().fill(AppPalette.hairline).frame(height: 2)
        .overlay(alignment: .leading) {
          GeometryReader { proxy in
            Capsule().fill(AppPalette.action)
              .frame(width: proxy.size.width * CGFloat(min(step, total)) / CGFloat(max(total, 1)))
          }
        }
        .accessibilityHidden(true)
    }
  }
}

extension SignalStepProgress where Accessory == EmptyView {
  init(step: Int, total: Int) { self.init(step: step, total: total) { EmptyView() } }
}

/// The yellow rule that links a quote to its observation; it draws once on arrival.
struct SignalRule: View {
  var draws = true
  @State private var drawn = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    Rectangle().fill(AppPalette.action).frame(height: 2)
      .scaleEffect(x: drawn || !draws || reduceMotion ? 1 : 0, anchor: .leading)
      .onAppear {
        guard draws, !drawn, !reduceMotion else { return }
        withAnimation(DrillbitMotion.entrance.delay(0.2)) { drawn = true }
      }
      .accessibilityHidden(true)
  }
}

/// Staggered first appearance for rare, hierarchy-revealing moments.
private struct SignalEntrance: ViewModifier {
  let order: Int
  let active: Bool
  @State private var shown = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  func body(content: Content) -> some View {
    let visible = shown || !active
    content
      .opacity(visible ? 1 : 0)
      .offset(y: visible || reduceMotion ? 0 : 12)
      .onAppear {
        guard active, !shown else { return }
        if reduceMotion { shown = true; return }
        withAnimation(DrillbitMotion.entrance.delay(0.08 + Double(order) * 0.1)) { shown = true }
      }
  }
}

/// Contextual icons arrive from a small, blurred point rather than popping.
struct IconPopTransition: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content.modifier(IconPop(identity: phase.isIdentity))
  }
  private struct IconPop: ViewModifier {
    let identity: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
      content
        .scaleEffect(identity || reduceMotion ? 1 : 0.25)
        .blur(radius: identity || reduceMotion ? 0 : 4)
        .opacity(identity ? 1 : 0)
    }
  }
}

extension Transition where Self == IconPopTransition {
  static var iconPop: IconPopTransition { IconPopTransition() }
}

extension View {
  func signalEntrance(_ order: Int = 0, active: Bool = true) -> some View {
    modifier(SignalEntrance(order: order, active: active))
  }
}

struct DrillbitMetadata: View {
  let text: String
  @Environment(\.dynamicTypeSize) private var typeSize
  var body: some View {
    Group {
      if typeSize.isAccessibilitySize {
        Text(text).font(.caption)
      } else {
        Text(text).font(.caption.weight(.medium)).monospaced()
      }
    }
    .foregroundStyle(AppPalette.secondary)
  }
}

struct DrillbitSectionHeader: View {
  let title: String
  var eyebrow: String? = nil
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      if let eyebrow {
        Text(eyebrow.uppercased())
          .font(.caption2.weight(.semibold)).tracking(0.8)
          .foregroundStyle(AppPalette.secondary)
      }
      Text(title).font(.title3.weight(.semibold))
    }
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
  }
}

struct PracticeButtonStyle: ButtonStyle {
  var secondary = false
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    let pressed = configuration.isPressed
    configuration.label
      .font(.body.weight(.semibold))
      .multilineTextAlignment(.center)
      .padding(.horizontal, 16).padding(.vertical, 12)
      .frame(maxWidth: .infinity, minHeight: 48)
      .foregroundStyle(secondary ? AppPalette.accent : AppPalette.actionInk)
      .background(secondary ? (pressed ? AppPalette.accentSoft : .clear) : AppPalette.action, in: Capsule())
      .overlay { if !secondary { Capsule().fill(AppPalette.actionInk.opacity(pressed ? 0.08 : 0)) } }
      .contentShape(Capsule())
      .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
      .opacity(isEnabled ? 1 : 0.45)
      .animation(DrillbitMotion.press, value: pressed)
      .animation(DrillbitMotion.fast, value: isEnabled)
      .hoverEffect(.highlight)
  }
}

struct DrillbitIconButtonStyle: ButtonStyle {
  var prominent = false
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  func makeBody(configuration: Configuration) -> some View {
    let pressed = configuration.isPressed
    configuration.label
      .frame(width: 48, height: 48)
      .foregroundStyle(prominent ? AppPalette.actionInk : AppPalette.primary)
      .background(prominent ? AppPalette.action : pressed ? AppPalette.inset : AppPalette.elevated, in: Circle())
      .overlay { Circle().fill(AppPalette.actionInk.opacity(prominent && pressed ? 0.1 : 0)) }
      .overlay { Circle().stroke(prominent ? .clear : AppPalette.hairline, lineWidth: 0.5) }
      .opacity(isEnabled ? 1 : 0.42)
      .contentShape(Circle())
      .scaleEffect(pressed && !reduceMotion ? 0.96 : 1)
      .animation(DrillbitMotion.press, value: pressed)
      .animation(DrillbitMotion.fast, value: isEnabled)
  }
}

struct LoadingStatus: View {
  let message: String
  var centered: Bool
  init(_ message: String, centered: Bool = false) {
    self.message = message
    self.centered = centered
  }
  var body: some View {
    if centered {
      VStack(spacing: 12) {
        ProgressView().controlSize(.small).accessibilityHidden(true)
        Text(message).font(.subheadline).foregroundStyle(.secondary)
          .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity)
      .accessibilityElement(children: .combine)
    } else {
      HStack(spacing: 12) {
        ProgressView().controlSize(.small).accessibilityHidden(true)
        Text(message).font(.subheadline).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 12)
      .accessibilityElement(children: .combine)
    }
  }
}

enum AppIcon: String, CaseIterable {
  case settings = "gearshape"
  case send = "arrow.up"
  case latest = "arrow.down"
  case undo = "arrow.uturn.backward"
  case checkmark = "checkmark"
  case skip = "forward"
  case hint = "lightbulb"
  case preferences = "slider.horizontal.3"
  case text = "text.alignleft"
  case more = "ellipsis"
  case voice = "waveform"
  case books = "books.vertical"
  case completed = "checkmark.circle"
  case filter = "line.3.horizontal.decrease"
  case delete = "trash"
  case assistance = "sparkle"
  case retry = "arrow.clockwise"
  case regenerate = "arrow.triangle.2.circlepath"
  case library = "book.closed"
  case recall = "rectangle.stack"
  case home = "house"
  case apple = "apple.logo"
  case start = "play.fill"
  case microphone = "mic.fill"
  case microphoneMuted = "mic.slash.fill"
  case history = "clock.arrow.circlepath"
  case collapsed = "chevron.right"
  case expanded = "chevron.down"
}

extension View {
  func drillbitTabClearance() -> some View {
    safeAreaInset(edge: .bottom, spacing: 0) {
      Color.clear.frame(height: 72).allowsHitTesting(false).accessibilityHidden(true)
    }
  }
}

/// Paces revealed glyphs so bursty network text reads as steady writing, and runs it backwards to stream out.
@MainActor final class RevealClock {
  private(set) var cursor = 0.0
  private var last: Date?
  private var start = Date.distantPast
  private var rewindRate: Double?
  private var reported = false
  var rewinding: Bool { rewindRate != nil }
  func reset(after delay: TimeInterval) {
    cursor = 0; last = nil; start = .now + delay; rewindRate = nil; reported = false
  }
  func rewind(over duration: TimeInterval) {
    rewindRate = max(cursor, 1) / duration; reported = false
  }
  /// `report` fires once, when the page is fully written or fully streamed out.
  func tick(_ now: Date, target: Double, instant: Bool, finished: Bool, report: () -> Void) -> Double {
    let elapsed = last.map { min(max(now.timeIntervalSince($0), 0), 1.0 / 20) } ?? 0
    last = now
    if let rewindRate {
      cursor = instant ? 0 : max(0, cursor - rewindRate * elapsed)
      if cursor == 0, !reported { reported = true; report() }
      return cursor
    }
    if instant { cursor = target }
    else if now >= start, cursor < target {
      // A steady hand that speeds up with the backlog, so a burst never trails by much more than a second.
      cursor = min(target, cursor + max(48, (target - cursor) / 0.9) * elapsed)
    }
    if finished, cursor >= target, !reported { reported = true; report() }
    return cursor
  }
}

/// Draws glyphs up to `shown`; the leading edge rises out of a slight blur. The caret trails the last visible glyph.
struct RevealRenderer: TextRenderer {
  var shown: Double
  var caret: Double
  var caretColor: Color
  var motion: Bool
  static let edge = 8.0

  func draw(layout: Text.Layout, in context: inout GraphicsContext) {
    var index = 0.0
    var tail: CGRect?
    lines: for line in layout {
      let count = Double(line.reduce(0) { $0 + $1.count })
      if index + count + Self.edge <= shown {
        context.draw(line)
        index += count
        tail = line.typographicBounds.rect
        continue
      }
      for run in line {
        for glyph in run {
          let progress = (shown - index) / Self.edge
          guard progress > 0 else { break lines }
          index += 1
          tail = glyph.typographicBounds.rect
          if progress >= 1 { context.draw(glyph); continue }
          let eased = progress * progress * (3 - 2 * progress)
          var glyphContext = context
          glyphContext.opacity = eased
          if motion {
            glyphContext.translateBy(x: 0, y: (1 - eased) * 3)
            glyphContext.addFilter(.blur(radius: (1 - eased) * 2.5))
          }
          glyphContext.draw(glyph)
        }
      }
    }
    guard caret > 0, let first = layout.first?.typographicBounds.rect else { return }
    let bounds = tail ?? CGRect(x: first.minX, y: first.minY, width: 0, height: first.height)
    var caretContext = context
    caretContext.opacity = caret
    caretContext.fill(
      Path(roundedRect: CGRect(x: bounds.maxX + 2, y: bounds.minY + bounds.height * 0.12, width: 2, height: bounds.height * 0.76), cornerRadius: 1),
      with: .color(caretColor))
  }
}

/// One piece of streamed copy. Fixed copy is known upfront, so it never proves that the text before it is complete.
struct StreamSegment {
  enum Style { case eyebrow, title, note, body, code }
  var style: Style
  var text: AttributedString
  var fixed = false
  /// Keeps a line and the caret in place while this segment is still empty.
  var placeholder = false
  var identifier: String? = nil
  var length: Double { Double(text.characters.count) }
}

/// A column of segments written out glyph by glyph, in order, with one shared cursor.
struct StreamingDocument: View {
  let clock: RevealClock
  let segments: [StreamSegment]
  let finished: Bool
  let paused: Bool
  var instant = false
  /// Shown under an empty page once the wait is noticeable.
  var waitingHint: String? = nil
  let settled: () -> Void
  @State private var slow = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private static let gap = 8.0

  var body: some View {
    var offsets: [Double] = []
    var at = 0.0
    var target: Double?
    for (index, segment) in segments.enumerated() {
      offsets.append(at)
      // Streamed text is complete once anything non-fixed follows it.
      let complete = segment.fixed || finished || segments[(index + 1)...].contains { !$0.fixed && $0.length > 0 }
      if target == nil, !complete { target = at + segment.length }
      at += segment.length + Self.gap
    }
    let end = target ?? max(0, at - Self.gap) + (finished ? RevealRenderer.edge : 0)
    let empty = !segments.contains { !$0.fixed && $0.length > 0 }
    return TimelineView(.animation(paused: paused)) { timeline in
      let cursor = clock.tick(timeline.date, target: end, instant: instant || reduceMotion, finished: finished) {
        Task { @MainActor in settled() }
      }
      let pulse = 0.5 + 0.5 * cos(timeline.date.timeIntervalSinceReferenceDate * 2 * .pi / 1.1)
      let caret = clock.rewinding || instant || reduceMotion ? 0
        : finished ? max(0, min(1, (end - cursor) / RevealRenderer.edge))
        : cursor >= end - 0.01 ? 0.3 + 0.7 * pulse : 1
      let caretAt = segments.indices.last { !segments[$0].fixed && offsets[$0] <= cursor + 0.001 }
      VStack(alignment: .leading, spacing: 16) {
        ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
          view(segment, shown: cursor - offsets[index], caret: caretAt == index ? caret : 0)
        }
        if let waitingHint, slow, empty, !finished {
          Text(waitingHint).font(.footnote).foregroundStyle(.secondary).transition(.opacity)
        }
      }
    }
    .animation(DrillbitMotion.reveal, value: slow && empty && !finished)
    .task(id: empty && !finished) {
      slow = false
      guard waitingHint != nil, empty, !finished else { return }
      do { try await Task.sleep(for: .seconds(1.6)) } catch { return }
      slow = true
    }
  }

  @ViewBuilder private func view(_ segment: StreamSegment, shown: Double, caret: Double) -> some View {
    let isEmpty = segment.text.characters.isEmpty
    let renderer = RevealRenderer(shown: paused ? .infinity : isEmpty ? 0 : shown, caret: caret, caretColor: AppPalette.accent, motion: !reduceMotion)
    if !isEmpty || segment.placeholder {
      let text = Text(isEmpty ? AttributedString(" ") : segment.text)
      switch segment.style {
      case .eyebrow:
        text.font(.caption2.weight(.semibold).monospaced()).tracking(1.2).foregroundStyle(AppPalette.accent)
          .textRenderer(renderer)
      case .title:
        text.font(.largeTitle.weight(.semibold)).tracking(-0.8)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
          .textRenderer(renderer)
          .accessibilityHidden(isEmpty)
      case .note:
        text.font(.subheadline).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .textRenderer(renderer)
          .accessibilityHidden(!paused && shown <= 0)
      case .body:
        text.fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
          .textRenderer(renderer)
          .textSelection(.enabled)
          .accessibilityIdentifier(segment.identifier ?? "")
      case .code:
        CodeBlock(text: text, renderer: renderer)
          .opacity(paused ? 1 : min(1, max(0, shown / 4)))
      }
    }
  }
}

/// A short payload or snippet: monospaced, scrolls sideways instead of wrapping.
struct CodeBlock: View {
  let text: Text
  var renderer = RevealRenderer(shown: .infinity, caret: 0, caretColor: .clear, motion: false)
  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      text.font(.callout.monospaced())
        .fixedSize()
        .textRenderer(renderer)
        .textSelection(.enabled)
        .padding(12)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(AppPalette.inset, in: RoundedRectangle(cornerRadius: 12))
  }
}

/// A question's prompt with its markup rendered, or plain when formatting is off.
struct QuestionBody: View {
  let markup: String
  var lineLimit: Int? = nil
  @Environment(\.formatsQuestions) private var formatsQuestions
  var body: some View {
    let blocks = QuestionMarkup.blocks(markup, formatted: formatsQuestions)
    VStack(alignment: .leading, spacing: 12) {
      ForEach(Array((lineLimit == nil ? blocks : Array(blocks.prefix(1))).enumerated()), id: \.offset) { _, block in
        switch block {
        case .text(let value):
          Text(value).lineLimit(lineLimit).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        case .code(let value):
          CodeBlock(text: Text(value)).lineLimit(lineLimit)
        }
      }
    }
  }
}

extension EnvironmentValues {
  @Entry var formatsQuestions = true
}
