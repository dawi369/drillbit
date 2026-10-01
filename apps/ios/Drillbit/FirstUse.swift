import SwiftUI

/// The warm-up's guided tour: the interview stays visible but locked while each control is introduced in turn.
/// `tools` opens the ••• tools as a popover instead of a callout.
enum WarmUpStep: Int, CaseIterable {
  case tools, reply, voice
  var title: String {
    switch self {
    case .tools: "Your tools"
    case .reply: "Your turn"
    case .voice: "Rather talk?"
    }
  }
  var message: String {
    switch self {
    case .tools: ""
    case .reply: "Answer here. One line ending in “?” asks the interviewer instead."
    case .voice: "Tap to say it out loud instead."
    }
  }
  var next: WarmUpStep? { WarmUpStep(rawValue: rawValue + 1) }
}

/// Frames the tour points at; `document` places the card for toolbar targets it cannot measure.
enum WarmUpAnchor: Hashable { case step(WarmUpStep), document }
struct WarmUpAnchorKey: PreferenceKey {
  static let defaultValue: [WarmUpAnchor: Anchor<CGRect>] = [:]
  static func reduce(value: inout [WarmUpAnchor: Anchor<CGRect>], nextValue: () -> [WarmUpAnchor: Anchor<CGRect>]) {
    value.merge(nextValue()) { $1 }
  }
}
extension View {
  func warmUpAnchor(_ anchor: WarmUpAnchor) -> some View {
    // Transform, not set: a plain anchorPreference would drop anchors from inside this view.
    transformAnchorPreference(key: WarmUpAnchorKey.self, value: .bounds) { $0[anchor] = $1 }
  }
}

private struct Spotlight: Shape {
  var hole: CGRect
  var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
    get { .init(.init(hole.minX, hole.minY), .init(hole.width, hole.height)) }
    set { hole = CGRect(x: newValue.first.first, y: newValue.first.second, width: newValue.second.first, height: newValue.second.second) }
  }
  func path(in rect: CGRect) -> Path {
    var path = Path(rect)
    if hole.width > 0 { path.addRoundedRect(in: hole, cornerSize: CGSize(width: 12, height: 12)) }
    return path
  }
}

/// Blocks every tap. The callout lags the step so the spotlight settles on its target before the callout appears.
struct WarmUpGuide: View {
  let step: WarmUpStep?
  let anchors: [WarmUpAnchor: Anchor<CGRect>]
  let advance: () -> Void
  @State private var shown: WarmUpStep?
  @State private var calloutHeight: CGFloat = 120
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    GeometryReader { proxy in
      let hole = step.flatMap { anchors[.step($0)] }.map { proxy[$0].insetBy(dx: -6, dy: -6) }
      ZStack(alignment: .topLeading) {
        Color.clear.contentShape(Rectangle()).onTapGesture {}
        if step != nil {
          Spotlight(hole: hole ?? .zero)
            .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)
            .transition(.opacity)
        }
        if let shown, shown != .tools {
          callout(shown, in: proxy)
        }
      }
      .animation(reduceMotion ? nil : DrillbitMotion.page, value: step)
    }
    .ignoresSafeArea()
    .accessibilityAddTraits(.isModal)
    .task(id: step) {
      if reduceMotion { shown = step; return }
      if shown != nil { withAnimation(.easeIn(duration: 0.12)) { shown = nil } }
      guard let step else { return }
      do { try await Task.sleep(for: .milliseconds(360)) } catch { return }
      withAnimation(.spring(duration: 0.38, bounce: 0.16)) { shown = step }
    }
  }

  private func callout(_ step: WarmUpStep, in proxy: GeometryProxy) -> some View {
    let size = proxy.size
    let width = min(296, size.width - 32)
    let documentTop = anchors[.document].map { proxy[$0].minY } ?? 100
    let target = anchors[.step(step)].map { proxy[$0].insetBy(dx: -6, dy: -6) }
      ?? CGRect(x: size.width / 2, y: documentTop, width: 0, height: 0)
    let below = target.midY < size.height / 2
    let x = min(max(target.midX - width / 2, 16), size.width - 16 - width)
    let preferred = below ? target.maxY + 12 : target.minY - 12 - calloutHeight
    let y = min(max(preferred, documentTop + 8), size.height - 48 - calloutHeight)
    let pointerX = target.midX - x
    let edge: Edge = below ? .top : .bottom
    return CoachCallout(
      title: step.title, message: step.message, index: step.rawValue, count: WarmUpStep.allCases.count,
      action: step.next == nil ? "Got it" : "Next", buttonID: "warmUpGuideNext",
      pointer: edge, pointerX: pointerX, advance: advance)
      .frame(width: width)
      .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { calloutHeight = $0 }
      .offset(x: x, y: y)
      .transition(.asymmetric(
        insertion: .scale(scale: 0.9, anchor: UnitPoint(x: pointerX / width, y: below ? 0 : 1)).combined(with: .opacity),
        removal: .scale(scale: 0.97).combined(with: .opacity)))
      .accessibilityIdentifier("warmUpGuide")
  }
}

/// The tour's first stop: what lives behind •••, one line each.
struct WarmUpTools: View {
  var showsNudge = true
  let done: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if showsNudge {
        row("Need a nudge?", "A small hint when you’re stuck.", AppIcon.hint.rawValue)
        Divider().padding(.leading, 52)
      }
      row("Show an example", "How a solid answer could go.", AppIcon.text.rawValue)
      Divider().padding(.leading, 52)
      row("Finish interview", "Done? Wrap up and get feedback.", AppIcon.checkmark.rawValue)
      Button("Got it", action: done)
        .buttonStyle(CalloutButtonStyle())
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 16)
        .accessibilityIdentifier("warmUpToolsDone")
    }
    .frame(width: 288)
    .padding(.top, 4)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("warmUpTools")
  }
  private func row(_ title: String, _ detail: String, _ symbol: String) -> some View {
    HStack(spacing: 12) {
      Image(systemName: symbol).foregroundStyle(AppPalette.accent).frame(width: 24).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).foregroundStyle(AppPalette.primary)
        Text(detail).font(.footnote).foregroundStyle(AppPalette.secondary)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .accessibilityElement(children: .combine)
  }
}

/// The small tip on a callout's edge, drawn pointing up.
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

/// A compact coachmark: short title, one line of help, progress and a small action.
struct CoachCallout: View {
  let title: String
  let message: String
  let index: Int
  let count: Int
  /// Without an action the callout waits for the person to use what it points at.
  let action: String?
  let buttonID: String
  var pointer: Edge? = nil
  /// Measured from the callout's leading edge.
  var pointerX: CGFloat? = nil
  let advance: () -> Void
  @State private var width: CGFloat = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(AppPalette.primary)
      Text(message).font(.footnote).foregroundStyle(AppPalette.secondary)
        .fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 8) {
        HStack(spacing: 4) {
          ForEach(0..<count, id: \.self) { dot in
            Capsule().fill(dot == index ? AppPalette.accent : AppPalette.hairline)
              .frame(width: dot == index ? 12 : 4, height: 4)
          }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(index + 1) of \(count)")
        Spacer(minLength: 16)
        if let action {
          Button(action, action: advance)
            .buttonStyle(CalloutButtonStyle())
            .accessibilityIdentifier(buttonID)
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.top, 12)
    .padding(.bottom, action == nil ? 12 : 4)
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

/// The tab tour's callout, pointing down at the tab it describes.
struct FirstUseTourTip: View {
  @Bindable var model: AppModel
  @State private var appeared = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private var content: (index: Int, title: String, message: String) {
    switch model.firstUse.stage {
    case .tourRecall: (1, "Recall makes it stick.", "Quick reviews from your own sessions.")
    case .tourLibrary: (2, "Everything you’ve done.", "Old interviews and their feedback.")
    default: (0, "Home base.", "Pick up where you left off, or grab a new question.")
    }
  }
  var body: some View {
    GeometryReader { proxy in
      let width = min(296, proxy.size.width - 32)
      // Three evenly spaced tabs across the floating bar.
      let tab = 24 + (proxy.size.width - 48) * (CGFloat(content.index) + 0.5) / 3
      CoachCallout(
        title: content.title, message: content.message, index: content.index, count: 3,
        action: model.firstUse.stage == .tourLibrary ? "Done" : "Next", buttonID: "firstUseTourNext",
        pointer: .bottom, pointerX: tab - (proxy.size.width - width) / 2) { Task { await model.advanceFirstUseTour() } }
        .frame(width: width)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.12), value: content.index)
    }
    .frame(height: 160)
    .opacity(appeared ? 1 : 0)
    .scaleEffect(appeared || reduceMotion ? 1 : 0.92, anchor: .bottom)
    .task {
      // Lets Home settle after the warm-up closes before pointing at anything.
      do { try await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 450)) } catch { return }
      withAnimation(.spring(duration: 0.4, bounce: 0.16)) { appeared = true }
    }
    .accessibilityIdentifier("firstUseTip")
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
