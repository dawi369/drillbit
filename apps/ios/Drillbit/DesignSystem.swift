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
  static func adaptiveColor(_ dark: UInt32, _ light: UInt32, darkAlpha: CGFloat = 1, lightAlpha: CGFloat = 1) -> Color {
    Color(uiColor: UIColor { traits in
      let isDark = traits.userInterfaceStyle == .dark
      let hex = isDark ? dark : light
      return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                     blue: CGFloat(hex & 0xFF) / 255, alpha: isDark ? darkAlpha : lightAlpha)
    })
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
  /// Small controls arriving beside a primary one: a soft spring, no overshoot you'd notice.
  static let pop = Animation.spring(duration: 0.42, bounce: 0.18)
  // Interview document timings are tuned against keyboard and streaming layout.
  static let document = Animation.smooth(duration: 0.38, extraBounce: 0)
  static let send = Animation.smooth(duration: 0.42, extraBounce: 0)
  static let stream = Animation.easeOut(duration: 0.18)
}

/// The wordmark from docs/design/logo, fitted to the letters' own 574 × 148 bounds.
struct DrillbitLogoShape: Shape {
  enum Part { case letters, dots }
  let part: Part
  static let width: CGFloat = 574
  static let height: CGFloat = 148

  func path(in rect: CGRect) -> Path {
    let scale = min(rect.width / Self.width, rect.height / Self.height)
    let fit = CGAffineTransform(translationX: rect.midX - Self.width / 2 * scale, y: rect.midY - Self.height / 2 * scale)
      .scaledBy(x: scale, y: scale).translatedBy(x: 0, y: 146)
    var path = Path()
    switch part {
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
      path = strokes.strokedPath(StrokeStyle(lineWidth: 24))
    case .dots:
      path.addEllipse(in: CGRect(x: 208.5 - 14, y: -142, width: 28, height: 28))
      path.addEllipse(in: CGRect(x: 475.5 - 14, y: -142, width: 28, height: 28))
    }
    return path.applying(fit)
  }
}

struct DrillbitLogo: View {
  var compact = false
  var body: some View {
    // Keeps the letters the size they were beside the drill.
    let height: CGFloat = compact ? 22 : 30
    ZStack {
      DrillbitLogoShape(part: .letters).fill(AppPalette.logoInk)
      DrillbitLogoShape(part: .dots).fill(AppPalette.logoDot)
    }
    .frame(width: height * DrillbitLogoShape.width / DrillbitLogoShape.height, height: height)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Drillbit")
  }
}

/// Linear audio levels (0...1) written by the voice transport and read by
/// `BitView` every frame. Deliberately unobserved: no view invalidation.
@MainActor final class VoiceLevels {
  var input = 0.0
  var output = 0.0
  func reset() { input = 0; output = 0 }
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
  /// Rows cascade in on arrival, starting at this order.
  var cascadeFrom: Int? = nil
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
          .pageCascade(cascadeFrom.map { $0 + index })
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
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            Capsule().fill(AppPalette.action).frame(width: proxy.size.width * CGFloat(min(step, total)) / CGFloat(max(total, 1)))
          }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.6, bounce: 0.22), value: step)
        .accessibilityHidden(true)
    }
  }
}

extension SignalStepProgress where Accessory == EmptyView {
  init(step: Int, total: Int) { self.init(step: step, total: total) { EmptyView() } }
}

/// Onboarding pages are dealt, not pushed: the old one slips back soft, the new one lands with a little give.
struct DealTransition: Transition {
  var forward: Bool
  var arriving: Bool
  func body(content: Content, phase: TransitionPhase) -> some View {
    let distance: CGFloat = (arriving ? 64 : -28) * (forward ? 1 : -1)
    content
      .offset(x: phase.isIdentity ? 0 : distance)
      .scaleEffect(phase.isIdentity ? 1 : 0.97)
      .blur(radius: phase.isIdentity ? 0 : 8)
      .opacity(phase.isIdentity ? 1 : 0)
  }
}

extension AnyTransition {
  static func deal(forward: Bool) -> AnyTransition {
    .asymmetric(
      insertion: AnyTransition(DealTransition(forward: forward, arriving: true)).animation(.spring(duration: 0.56, bounce: 0.2).delay(0.05)),
      removal: AnyTransition(DealTransition(forward: forward, arriving: false)).animation(.easeIn(duration: 0.18)))
  }
}

/// A page's pieces settle in one after another, quickly, each with a small spring.
private struct PageCascade: ViewModifier {
  let order: Int?
  @State private var shown = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  func body(content: Content) -> some View {
    let visible = shown || order == nil || reduceMotion
    content
      .opacity(visible ? 1 : 0)
      .offset(y: visible ? 0 : 14)
      .blur(radius: visible ? 0 : 3)
      .onAppear {
        guard let order, !shown, !reduceMotion else { return }
        withAnimation(.spring(duration: 0.5, bounce: 0.24).delay(0.1 + Double(order) * 0.045)) { shown = true }
      }
  }
}

extension View {
  func pageCascade(_ order: Int?) -> some View { modifier(PageCascade(order: order)) }
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
  case transcript = "text.bubble"
  case end = "xmark"
  case write = "square.and.pencil"
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
    // Real time between frames, capped only against a long suspension: a dropped frame or a busy main thread must
    // not slow the writing down and then force it to sprint.
    let elapsed = last.map { min(max(now.timeIntervalSince($0), 0), 0.5) } ?? 0
    last = now
    if let rewindRate {
      cursor = instant ? 0 : max(0, cursor - rewindRate * elapsed)
      if cursor == 0, !reported { reported = true; report() }
      return cursor
    }
    if instant { cursor = target }
    else if now >= start, cursor < target {
      // A steady hand while the stream is open: the pace rises with the backlog but stays within what reads as typing.
      // Once the text is finished, whatever is left is written out within half a second rather than left to crawl.
      let backlog = target - cursor
      let rate = finished ? max(110, backlog / 0.5) : min(max(40, backlog / 1.8), 110)
      cursor = min(target, cursor + rate * elapsed)
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
  /// The full text's length, when the layout may be truncated (a line limit): once every glyph the layout has is
  /// written, the caret stops rather than blinking at the cut while invisible text goes on streaming.
  var total: Double? = nil
  /// Glyph indices where a new sentence starts. Each sentence then owns `edge` extra cursor units, so `shown`
  /// can rest with the sentence fully inked and the next one fades in from nothing instead of mid-edge.
  var breaks: [Int] = []
  static let edge = 8.0

  private func offset(_ index: Double) -> Double {
    Double(breaks.count { Double($0) <= index }) * Self.edge
  }

  func draw(layout: Text.Layout, in context: inout GraphicsContext) {
    var index = 0.0
    var tail: CGRect?
    lines: for line in layout {
      let count = Double(line.reduce(0) { $0 + $1.count })
      if count > 0, shown >= index + count - 1 + offset(index + count - 1) + Self.edge {
        context.draw(line)
        index += count
        tail = line.typographicBounds.rect
        continue
      }
      for run in line {
        for glyph in run {
          let progress = (shown - index - offset(index)) / Self.edge
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
    if let total, index + Self.edge < total, shown >= index + Self.edge { return }
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
  enum Style { case eyebrow, title, note, body, bullet, ask, code }
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
  let settled: () -> Void
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
        ForEach(Self.groups(segments), id: \.self) { group in
          if segments[group[0]].style == .bullet {
            KeyFacts {
              VStack(alignment: .leading, spacing: 8) {
                ForEach(group, id: \.self) { index in
                  view(segments[index], shown: cursor - offsets[index], caret: caretAt == index ? caret : 0)
                }
              }
            }
            .opacity(paused || cursor > offsets[group[0]] ? 1 : 0)
          } else {
            view(segments[group[0]], shown: cursor - offsets[group[0]], caret: caretAt == group[0] ? caret : 0)
          }
        }
      }
    }
  }

  /// Consecutive key facts share one inset; every other segment stands alone.
  private static func groups(_ segments: [StreamSegment]) -> [[Int]] {
    var result: [[Int]] = []
    for index in segments.indices {
      if segments[index].style == .bullet, let last = result.last, segments[last[0]].style == .bullet, last.last == index - 1 {
        result[result.count - 1].append(index)
      } else {
        result.append([index])
      }
    }
    return result
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
      case .bullet:
        QuestionBullet(text: text.textRenderer(renderer)).opacity(paused || shown > 0 ? 1 : 0)
      case .ask:
        QuestionAsk(text: text.textRenderer(renderer), reveal: paused ? 1 : min(1, max(0, shown / max(segment.length, 1))))
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
      ForEach(Array((lineLimit == nil ? blocks : Array(blocks.prefix(1))).enumerated()), id: \.offset) { index, block in
        switch block {
        case .text(let value) where lineLimit == nil && QuestionMarkup.isAsk(index, of: blocks):
          QuestionAsk(text: Text(value))
        case .text(let value):
          Text(value).lineLimit(lineLimit).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        case .bullets(let items):
          KeyFacts {
            VStack(alignment: .leading, spacing: 8) {
              ForEach(Array(items.enumerated()), id: \.offset) { _, item in QuestionBullet(text: Text(item)) }
            }
          }
        case .code(let value):
          CodeBlock(text: Text(value)).lineLimit(lineLimit)
        }
      }
    }
  }
}

/// A key fact: accent dot with a hanging indent.
struct QuestionBullet<Content: View>: View {
  let text: Content
  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Circle().fill(AppPalette.accent).frame(width: 5, height: 5).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
        .accessibilityHidden(true)
      text.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

/// The question's closing ask: the one thing to answer, set apart from the setup.
struct QuestionAsk<Content: View>: View {
  let text: Content
  /// How much of the ask is written; the rule grows alongside it and isn't there before it.
  var reveal: Double = 1
  var body: some View {
    text.fontWeight(.semibold).foregroundStyle(AppPalette.primary)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.leading, 12)
      .overlay(alignment: .topLeading) {
        GeometryReader { proxy in
          Capsule().fill(AppPalette.accent)
            .frame(width: 3, height: max(3, proxy.size.height * reveal))
        }
        .opacity(reveal > 0 ? 1 : 0)
        .accessibilityHidden(true)
      }
  }
}

extension EnvironmentValues {
  @Entry var formatsQuestions = true
}
