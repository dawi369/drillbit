import SwiftUI

/// Bit asks a setup question. The bubble is the screen's heading, so the screen reads fully without Bit.
struct BitAsks: View {
  let question: String
  var cheers = 0
  var mood: BitMood = .idle
  var font: Font = .title2.weight(.semibold)
  var isHeader = true
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      if !typeSize.isAccessibilitySize {
        BitView(mood: mood, cheers: cheers).frame(width: 76, height: 84)
      }
      Text(question)
        .font(font)
        .contentTransition(.opacity)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .leading) {
          ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 12).fill(AppPalette.inset)
            if !typeSize.isAccessibilitySize {
              CalloutPointer().fill(AppPalette.inset)
                .frame(width: 16, height: 8)
                .rotationEffect(.degrees(-90))
                .offset(x: -12)
            }
          }
        }
        .accessibilityAddTraits(isHeader ? .isHeader : [])
    }
  }
}

/// The small tip on a bubble's edge, drawn pointing up.
private struct CalloutPointer: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.midX - 2, y: rect.minY + 1.5))
    path.addQuadCurve(to: CGPoint(x: rect.midX + 2, y: rect.minY + 1.5), control: CGPoint(x: rect.midX, y: rect.minY - 0.5))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    path.closeSubpath()
    return path
  }
}

// MARK: Coachmarks

/// The first-run tips. They live inside the interview only, each shown once at the moment its control matters, and
/// only for what the screen can't say itself. Home and the tabs carry none.
enum CoachMark: String, CaseIterable {
  case voice, composer, path, tools
  var title: String {
    switch self {
    case .voice: "You’re in voice."
    case .composer: "Your turn."
    case .path: "Your roadmap."
    case .tools: "Stuck? Tap ⋯ up here."
    }
  }
  var message: String {
    switch self {
    case .voice: "Interviews open out loud, like the real one. Prefer to type? One tap and the same interviewer is in writing."
    case .composer: "A rough first take is fine. End a line with “?” to ask the interviewer instead."
    case .path: "The steps a strong answer usually covers. You move along as you cover them; tap it any time to see the whole path."
    case .tools: "Need a nudge? gives you a hint. Show an example shows one. Finish ends the round when you’re done."
    }
  }
  /// The dismiss button's label; the voice tip asks for the one tap it's pointing at.
  var action: String {
    switch self {
    case .voice, .path: "Show me"
    default: "Got it"
    }
  }
  var storageKey: String { "coach." + rawValue }
  /// UI tests opt in, so a tip never lands on top of an unrelated test's taps.
  static var enabled: Bool {
    let arguments = ProcessInfo.processInfo.arguments
    return !arguments.contains("--fixtures") || arguments.contains("--fixture-coach")
  }
}

struct CoachAnchorKey: PreferenceKey {
  static let defaultValue: [CoachMark: Anchor<CGRect>] = [:]
  static func reduce(value: inout [CoachMark: Anchor<CGRect>], nextValue: () -> [CoachMark: Anchor<CGRect>]) {
    value.merge(nextValue()) { $1 }
  }
}

extension View {
  /// Marks what a tip points at.
  func coachAnchor(_ mark: CoachMark) -> some View {
    // Transform, not set: a plain anchorPreference would drop anchors from inside this view.
    transformAnchorPreference(key: CoachAnchorKey.self, value: .bounds) { $0[mark] = $1 }
  }
  /// Shows `mark` beside its anchor while `active`. Toolbar targets can't be measured, so `trailingToolbar` points up at the top-trailing button instead.
  /// `shielding` keeps touches blocked while the next tip is still on its way, so nothing can be tapped in the gap.
  func coachMark(_ mark: CoachMark?, trailingToolbar: Bool = false, action: String? = nil, shielding: Bool = false,
                 dismiss: @escaping (CoachMark) -> Void) -> some View {
    overlayPreferenceValue(CoachAnchorKey.self) { anchors in
      CoachMarkLayer(mark: mark, anchors: anchors, trailingToolbar: trailingToolbar, action: action, shielding: shielding, dismiss: dismiss)
    }
  }
}

/// Positions one callout beside its target. It waits a beat so the screen settles first, then grows out of its pointer.
private struct CoachMarkLayer: View {
  let mark: CoachMark?
  let anchors: [CoachMark: Anchor<CGRect>]
  let trailingToolbar: Bool
  /// Replaces the mark's own button label, for a tip shown in a context where its action doesn't apply.
  var action: String? = nil
  var shielding = false
  let dismiss: (CoachMark) -> Void
  @State private var shown: CoachMark?
  @State private var height: CGFloat = 96
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    GeometryReader { proxy in
      let width = min(296, proxy.size.width - 32)
      // While a tip is queued or showing, the screen under it takes no touches: the tip's own button is the way on.
      if mark != nil || shielding {
        Color.clear.contentShape(Rectangle())
          .onTapGesture {}
          .accessibilityHidden(true)
          .accessibilityIdentifier("coachShield")
      }
      // No anchor yet (the screen is still laying out): wait rather than flash the callout at the top.
      if let shown, let placement = place(shown, width: width, in: proxy) {
        CoachCallout(title: shown.title, message: shown.message, action: action ?? shown.action, pointer: placement.edge, pointerX: placement.pointerX) { dismiss(shown) }
          .frame(width: width)
          .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
          .offset(x: placement.origin.x, y: placement.origin.y)
          .transition(reduceMotion ? .opacity : .asymmetric(
            insertion: .scale(scale: 0.96, anchor: UnitPoint(x: placement.pointerX / width, y: placement.edge == .top ? 0 : 1)).combined(with: .opacity),
            removal: .opacity))
          .accessibilityIdentifier("coach-" + shown.rawValue)
      }
    }
    .task(id: mark) {
      if shown != nil, shown != mark { withAnimation(.easeOut(duration: 0.12)) { shown = nil } }
      guard let mark, shown != mark else { return }
      do { try await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 320)) } catch { return }
      withAnimation(reduceMotion ? nil : .spring(duration: 0.2, bounce: 0)) { shown = mark }
      AccessibilityNotification.Announcement("Tip. \(mark.title) \(mark.message)").post()
    }
  }

  private func place(_ mark: CoachMark, width: CGFloat, in proxy: GeometryProxy) -> (origin: CGPoint, edge: Edge, pointerX: CGFloat)? {
    let size = proxy.size
    if trailingToolbar && mark == .tools {
      // The trailing toolbar button's centre sits about 38 points in from the edge.
      let x = size.width - 12 - width
      return (CGPoint(x: x, y: 8), .top, width - 26)
    }
    guard let anchor = anchors[mark] else { return nil }
    let target = proxy[anchor].insetBy(dx: -4, dy: -4)
    // Prefer above: below a composer is where the keyboard comes up.
    let above = target.minY - 12 - height > 8
    let x = min(max(target.midX - width / 2, 16), size.width - 16 - width)
    let y = above ? target.minY - 12 - height : target.maxY + 12
    return (CGPoint(x: x, y: y), above ? .bottom : .top, min(max(target.midX - x, 24), width - 24))
  }
}

/// A compact coachmark: short title, one line of help and a small Got it, with a pointer toward what it explains.
struct CoachCallout: View {
  let title: String
  let message: String
  var action = "Got it"
  var pointer: Edge? = nil
  /// Measured from the callout's leading edge.
  var pointerX: CGFloat? = nil
  let done: () -> Void
  @State private var width: CGFloat = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(AppPalette.primary)
      Text(message).font(.footnote).foregroundStyle(AppPalette.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Button(action, action: done)
        .buttonStyle(CalloutButtonStyle())
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityIdentifier("coachDone")
    }
    .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 4)
    .frame(maxWidth: .infinity, alignment: .leading)
    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    .background {
      ZStack(alignment: pointer == .bottom ? .bottomLeading : .topLeading) {
        RoundedRectangle(cornerRadius: 12).fill(AppPalette.elevated)
        if let pointer {
          CalloutPointer().fill(AppPalette.elevated)
            .frame(width: 16, height: 8)
            .rotationEffect(.degrees(pointer == .bottom ? 180 : 0))
            .offset(x: min(max(pointerX ?? width / 2, 20), max(20, width - 20)) - 8, y: pointer == .bottom ? 8 : -8)
        }
      }
      .compositingGroup()
      .shadow(color: .black.opacity(0.24), radius: 16, y: 6)
    }
    .accessibilityElement(children: .contain)
  }
}

private struct CalloutButtonStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.footnote.weight(.semibold))
      .foregroundStyle(AppPalette.actionInk)
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(AppPalette.action, in: Capsule())
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
      .animation(DrillbitMotion.press, value: configuration.isPressed)
      // Keeps a 44-point hit area around the small capsule.
      .padding(.vertical, 8)
      .contentShape(Rectangle())
  }
}

struct PracticeAreaGroupRow: View {
  let area: PracticeAreaGroup
  var body: some View {
    HStack(spacing: 16) {
      Image(systemName: area.symbol).font(.system(size: 20)).foregroundStyle(AppPalette.accent).frame(width: 24)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(area.title).foregroundStyle(AppPalette.primary)
        Text(area.detail).font(.caption).foregroundStyle(AppPalette.secondary)
      }
      Spacer(minLength: 8)
      Image(systemName: "chevron.right").font(.caption).foregroundStyle(AppPalette.secondary).accessibilityHidden(true)
    }.frame(minHeight: 64).contentShape(Rectangle())
  }
}
