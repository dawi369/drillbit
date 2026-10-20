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

/// The three first-run tips. Each shows once, at the moment its control matters, and never blocks the screen.
enum CoachMark: String, CaseIterable {
  case voice, keyboard, composer, path, tools, tour, recallPage, libraryPage, recall, settings
  /// Set once the first rep is over, finished or skipped: Home's tips wait for it.
  static let homeReadyKey = "coach.homeReady"
  var title: String {
    switch self {
    case .voice: "You’re in voice."
    case .keyboard: "Back out loud any time."
    case .composer: "Your turn."
    case .path: "Your roadmap."
    case .tools: "Stuck? Tap ⋯ up here."
    case .tour: "Two more tabs."
    case .recall: "Keep this one."
    case .recallPage: "Your cards."
    case .libraryPage: "Every rep, kept."
    case .settings: "Your plan, your call."
    }
  }
  var message: String {
    switch self {
    case .voice: "Interviews open out loud, like the real one. Prefer to type? One tap and the same interviewer is in writing."
    case .keyboard: "Talk returns you to voice with the same interviewer. Typing here counts just the same."
    case .composer: "A rough first take is fine. End a line with “?” to ask the interviewer instead."
    case .path: "The steps a strong answer usually covers. You move along as you cover them; tap it any time to see the whole path."
    case .tools: "Need a nudge? gives you a hint. Show an example shows one. Finish ends the round when you’re done."
    case .tour: "Recall and Library. Ten seconds, then it’s all yours."
    case .recallPage: "Each one comes from something you said in a rep. A quick check every few days makes it stick."
    case .libraryPage: "Questions, your answers and the feedback on them. Come back to any of them."
    case .recall: "Cards from your own answers. A quick check now makes them stick."
    case .settings: "Level, pace, voice or typing: everything you picked lives in here. Change it whenever."
    }
  }
  /// The dismiss button's label; the voice tip asks for the one tap it's pointing at.
  var action: String {
    switch self {
    case .voice, .tour, .path: "Show me"
    case .recallPage: "Next"
    case .libraryPage: "Back home"
    default: "Got it"
    }
  }
  var storageKey: String { "coach." + rawValue }
  /// Which tab bar item the tip points at: the tour at Recall, each page tip at its own tab.
  var tabTitle: String? {
    switch self {
    case .tour, .recallPage: "Recall"
    case .libraryPage: "Library"
    default: nil
    }
  }
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
    // Tab tips point down at their tab bar item, measured from the bar itself.
    if let tab = mark.tabTitle {
      let global = proxy.frame(in: .global)
      let item = TabBarGeometry.item(title: tab)
      let tabX = item.midX - global.minX
      let x = min(max(tabX - width / 2, 16), size.width - 16 - width)
      // The layer may cover the bar itself, so sit above the measured item rather than the layer's bottom.
      let bottom = min(size.height, item.minY - global.minY)
      return (CGPoint(x: x, y: bottom - 12 - height), .bottom, min(max(tabX - x, 24), width - 24))
    }
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

/// Where the tab bar's items are. SwiftUI's tab bar can't carry anchors, so the bar is read from UIKit;
/// if it isn't found, the items are assumed centred with the pitch iOS 26 uses on a phone.
enum TabBarGeometry {
  @MainActor static func itemCenterX(title: String) -> CGFloat { item(title: title).midX }
  /// The tab item's frame in window coordinates; a centred guess when the bar can't be read.
  @MainActor static func item(title: String) -> CGRect {
    let guess = title == "Recall" ? 1 : 2
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
      ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
    let bounds = window?.bounds ?? UIScreen.main.bounds
    guard let window, let bar = find(UITabBar.self, in: window) else { return fallback(guess, count: 3, in: bounds) }
    let items = bar.items?.count ?? 3
    let index = bar.items?.firstIndex { $0.title == title } ?? guess
    var candidates: [UIView] = []
    for view in bar.subviews { candidates.append(view); candidates.append(contentsOf: view.subviews) }
    var buttons: [CGRect] = []
    for view in candidates {
      let isButton = String(describing: type(of: view)).contains("TabBarButton") || view.accessibilityTraits.contains(.button)
      guard isButton else { continue }
      let frame = view.convert(view.bounds, to: window)
      if frame.width > 20, frame.height > 20 { buttons.append(frame) }
    }
    buttons.sort { $0.minX < $1.minX }
    guard buttons.count == items, index < buttons.count else { return fallback(index, count: items, in: bounds) }
    return buttons[index]
  }
  private static func fallback(_ index: Int, count: Int, in bounds: CGRect) -> CGRect {
    let x = bounds.width / 2 + (CGFloat(index) - CGFloat(count - 1) / 2) * 86
    return CGRect(x: x - 43, y: bounds.height - 83, width: 86, height: 49)
  }
  private static func find<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
    if let match = view as? T { return match }
    for child in view.subviews { if let match = find(type, in: child) { return match } }
    return nil
  }
}
