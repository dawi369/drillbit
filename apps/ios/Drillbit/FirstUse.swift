import SwiftUI

/// The warm-up's guided tour: the interview stays visible but locked while each control is introduced in turn.
enum WarmUpStep: Int, CaseIterable {
  case question, reply, send, voice, menu
  var title: String {
    switch self {
    case .question: "Your warm-up question"
    case .reply: "Answer or ask"
    case .send: "Send it"
    case .voice: "Rather talk it through?"
    case .menu: "Stuck, or done?"
    }
  }
  var message: String {
    switch self {
    case .question: "Built from your plan, just to warm up. It won’t count. Tap it anytime to fold it and make room."
    case .reply: "Type a design choice here, or ask a clarifying question first. Same box for both."
    case .send: "The interviewer reads it and pushes back, like a real round."
    case .voice: "Tap here to answer out loud. You can switch back to typing anytime."
    case .menu: "The ••• menu up top has a nudge, an example and Finish. Finish when you want feedback."
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
    anchorPreference(key: WarmUpAnchorKey.self, value: .bounds) { [anchor: $0] }
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

/// Blocks every tap. With no step it only holds the screen still so people can take it in first.
struct WarmUpGuide: View {
  let step: WarmUpStep?
  let anchors: [WarmUpAnchor: Anchor<CGRect>]
  let advance: () -> Void
  @State private var cardHeight: CGFloat = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    GeometryReader { proxy in
      let target = step.flatMap { anchors[.step($0)] }.map { proxy[$0].insetBy(dx: -8, dy: -8) }
      let documentTop = anchors[.document].map { proxy[$0].minY } ?? 0
      ZStack(alignment: .topLeading) {
        Color.clear.contentShape(Rectangle()).onTapGesture {}
        if let step {
          Spotlight(hole: target ?? .zero)
            .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)
            .transition(.opacity)
          card(step)
            .frame(width: max(0, proxy.size.width - 32))
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
            .position(x: proxy.size.width / 2, y: cardCenter(target: target, documentTop: documentTop, height: proxy.size.height))
            .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 8)))
        }
      }
      .animation(reduceMotion ? nil : DrillbitMotion.reveal, value: step)
    }
    .ignoresSafeArea()
    .accessibilityAddTraits(.isModal)
  }

  private func cardCenter(target: CGRect?, documentTop: CGFloat, height: CGFloat) -> CGFloat {
    let half = cardHeight / 2
    guard let target else { return documentTop + 12 + half }
    // Below the target when it sits in the top half, otherwise above it.
    let y = target.midY < height / 2 ? target.maxY + 12 + half : target.minY - 12 - half
    return min(max(y, documentTop + 12 + half), height - 24 - half)
  }

  private func card(_ step: WarmUpStep) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        Text("\(step.rawValue + 1) of \(WarmUpStep.allCases.count)").font(.caption.monospaced()).foregroundStyle(AppPalette.accent)
        Spacer(minLength: 0)
        if step == .menu { Image(systemName: "arrow.up.right").foregroundStyle(AppPalette.accent).accessibilityHidden(true) }
      }
      Text(step.title).font(.headline)
      Text(step.message).font(.subheadline).foregroundStyle(AppPalette.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Button(step.next == nil ? "Let’s go" : "Next", action: advance)
        .buttonStyle(PracticeButtonStyle())
        .accessibilityIdentifier("warmUpGuideNext")
    }
    .padding(16)
    .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 12))
    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(AppPalette.accent.opacity(0.35), lineWidth: 0.5) }
    .id(step)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("warmUpGuide")
  }
}

struct FirstUseTip: View {
  let number: String
  let title: String
  let message: String
  var pointsUp = false
  var symbol: String? = nil
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Text(number).font(.caption.monospaced()).foregroundStyle(AppPalette.accent)
        Text(title).font(.headline)
        Spacer(minLength: 0)
        Image(systemName: symbol ?? (pointsUp ? "arrow.up" : "arrow.down")).foregroundStyle(AppPalette.accent).accessibilityHidden(true)
      }
      Text(message).font(.subheadline).foregroundStyle(AppPalette.secondary)
    }.padding(16).background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 12))
      .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(AppPalette.accent.opacity(0.35), lineWidth: 0.5) }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("firstUseTip")
  }
}

struct FirstUseTourTip: View {
  @Bindable var model: AppModel
  private var content: (String, String, String, AppIcon) {
    switch model.firstUse.stage {
    case .tourRecall: ("02", "Recall makes it stick.", "Short reviews grow from your real sessions. Come back here to practise what needs another look.", .recall)
    case .tourLibrary: ("03", "Your work stays in Library.", "Revisit past interviews and feedback. Next, choose how you want your first real session to feel.", .library)
    default: ("01", "Home is your starting point.", "Resume a session or explore a core area. Your next question is always within reach.", .home)
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      FirstUseTip(number: content.0, title: content.1, message: content.2, symbol: content.3.rawValue)
        .id(model.firstUse.stage)
        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity))
      Button(model.firstUse.stage == .tourLibrary ? "Choose my session" : "Next") { Task { await model.advanceFirstUseTour() } }
        .buttonStyle(PracticeButtonStyle()).accessibilityIdentifier("firstUseTourNext")
    }.padding(20).background(AppPalette.background)
      .overlay(alignment: .top) { AppPalette.hairline.frame(height: 0.5) }
      .accessibilityElement(children: .contain)
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
