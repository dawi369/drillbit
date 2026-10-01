import SwiftUI

/// Surfaces for the ticket: today's question as one object with a perforated stub.
extension AppPalette {
  static let ticket = adaptiveColor(0x2B3241, 0xFFFFFF)
  static let ticketLower = adaptiveColor(0x262C39, 0xFCFBF8)
  static let ticketStub = adaptiveColor(0x262C39, 0xFCFBF8)
  static let ticketEdge = adaptiveColor(0xFFFFFF, 0x202632, darkAlpha: 0.07, lightAlpha: 0.07)
  static let perforation = adaptiveColor(0x465264, 0xC4CAD1)
  static let ticketShadow = adaptiveColor(0x000000, 0x202632, darkAlpha: 0.32, lightAlpha: 0.1)
  static let ticketContact = adaptiveColor(0x000000, 0x202632, darkAlpha: 0.3, lightAlpha: 0.08)
  static let underline = adaptiveColor(0xFFCC65, 0xE0A030)
}

/// One half of a ticket: rounded outer corners, and half-circle notches where the perforation meets the edges.
struct TicketHalf: Shape {
  enum Perforation { case top, bottom }
  var perforation: Perforation
  var radius: CGFloat = 12
  var notch: CGFloat = 9

  func path(in rect: CGRect) -> Path {
    var path = Path()
    let r = min(radius, rect.height / 2), n = min(notch, rect.height / 2)
    let (minX, minY, maxX, maxY) = (rect.minX, rect.minY, rect.maxX, rect.maxY)
    switch perforation {
    case .bottom:
      path.move(to: CGPoint(x: minX, y: minY + r))
      path.addArc(center: CGPoint(x: minX + r, y: minY + r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
      path.addLine(to: CGPoint(x: maxX - r, y: minY))
      path.addArc(center: CGPoint(x: maxX - r, y: minY + r), radius: r, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
      path.addLine(to: CGPoint(x: maxX, y: maxY - n))
      path.addArc(center: CGPoint(x: maxX, y: maxY), radius: n, startAngle: .degrees(270), endAngle: .degrees(180), clockwise: true)
      path.addLine(to: CGPoint(x: minX + n, y: maxY))
      path.addArc(center: CGPoint(x: minX, y: maxY), radius: n, startAngle: .degrees(0), endAngle: .degrees(270), clockwise: true)
    case .top:
      path.move(to: CGPoint(x: minX, y: minY + n))
      path.addArc(center: CGPoint(x: minX, y: minY), radius: n, startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
      path.addLine(to: CGPoint(x: maxX - n, y: minY))
      path.addArc(center: CGPoint(x: maxX, y: minY), radius: n, startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
      path.addLine(to: CGPoint(x: maxX, y: maxY - r))
      path.addArc(center: CGPoint(x: maxX - r, y: maxY - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
      path.addLine(to: CGPoint(x: minX + r, y: maxY))
      path.addArc(center: CGPoint(x: minX + r, y: maxY - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
    }
    path.closeSubpath()
    return path
  }
}

/// The dashed tear line between the notches.
struct Perforation: View {
  var body: some View {
    Canvas { context, size in
      var line = Path()
      line.move(to: CGPoint(x: 18, y: 0.5))
      line.addLine(to: CGPoint(x: size.width - 18, y: 0.5))
      context.stroke(line, with: .color(AppPalette.perforation), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
    }
    .frame(height: 1)
    .accessibilityHidden(true)
  }
}

/// Today's question as an object: a body for the question and a stub below the perforation for what you do with it.
struct Ticket<Content: View, Stub: View>: View {
  @ViewBuilder var content: () -> Content
  @ViewBuilder var stub: () -> Stub

  var body: some View {
    VStack(spacing: 0) {
      content()
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
          TicketHalf(perforation: .bottom)
            .fill(LinearGradient(colors: [AppPalette.ticket, AppPalette.ticketLower], startPoint: .top, endPoint: .bottom))
            .overlay { TicketHalf(perforation: .bottom).stroke(AppPalette.ticketEdge, lineWidth: 1) }
        }
      stub()
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
          TicketHalf(perforation: .top).fill(AppPalette.ticketStub)
            .overlay { TicketHalf(perforation: .top).stroke(AppPalette.ticketEdge, lineWidth: 1) }
        }
        .overlay(alignment: .top) { Perforation() }
    }
    .compositingGroup()
    .shadow(color: AppPalette.ticketContact, radius: 1, y: 1)
    .shadow(color: AppPalette.ticketShadow, radius: 14, y: 12)
  }
}

/// A ticket that is only a stub: the torn-off part that carries your words.
struct TicketStub<Content: View>: View {
  var padding: CGFloat = 22
  @ViewBuilder var content: () -> Content
  var body: some View {
    content()
      .padding(padding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background {
        TicketHalf(perforation: .top).fill(AppPalette.ticketStub)
          .overlay { TicketHalf(perforation: .top).stroke(AppPalette.ticketEdge, lineWidth: 1) }
      }
      .overlay(alignment: .top) { Perforation() }
      .compositingGroup()
      .shadow(color: AppPalette.ticketContact, radius: 1, y: 1)
      .shadow(color: AppPalette.ticketShadow, radius: 12, y: 10)
  }
}

/// The ticket's printed data line: number on the left in the accent, facts on the right.
struct TicketHeader: View {
  let number: String
  let detail: String
  @Environment(\.dynamicTypeSize) private var typeSize
  var body: some View {
    let font: Font = typeSize.isAccessibilitySize ? .caption.weight(.semibold) : .caption.weight(.medium).monospaced()
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text(number).foregroundStyle(AppPalette.accent)
        Spacer(minLength: 8)
        Text(detail).foregroundStyle(AppPalette.secondary).lineLimit(1)
      }
      VStack(alignment: .leading, spacing: 4) {
        Text(number).foregroundStyle(AppPalette.accent)
        Text(detail).foregroundStyle(AppPalette.secondary)
      }
    }
    .font(font)
    .textCase(.uppercase)
    .tracking(typeSize.isAccessibilitySize ? 0 : 0.8)
    .accessibilityElement(children: .combine)
  }
}

extension Challenge {
  /// The printed number: assigned on completion; unfinished tickets show the one they'll get.
  func ticketLabel(next: Int?) -> String {
    if isWarmUp { return "Warm-up" }
    if let ticket { return String(format: "No. %03d", ticket) }
    if let next { return String(format: "No. %03d", next) }
    return "Today"
  }
}

/// Loading cue: the drill mark makes one good turn, rests a beat, and turns again while work runs.
struct DrillbitSpinner: View {
  var size: CGFloat = 22
  var color: Color = AppPalette.logoDrill
  @State private var start = Date.now
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    TimelineView(.animation) { timeline in
      let time = max(0, timeline.date.timeIntervalSince(start))
      let progress = min(1, time.truncatingRemainder(dividingBy: 1.4) / 0.9)
      let eased = progress < 0.5 ? 4 * pow(progress, 3) : 1 - pow(2 - 2 * progress, 3) / 2
      DrillbitMark(size: size, foreground: color)
        .rotationEffect(.degrees(reduceMotion ? 0 : 360 * eased))
        .opacity(reduceMotion ? 0.6 + 0.4 * cos(time * .pi / 0.7) : 1)
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}

/// The drill mark as an activity cue: its flutes travel only while real work runs, so it reads as the bit turning.
struct DrillbitBit: View {
  var working: Bool
  var height: CGFloat = 22
  var color: Color = AppPalette.logoDrill
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let moving = working && !reduceMotion
    TimelineView(.animation(paused: !moving)) { timeline in
      let phase = moving ? timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.8) / 0.8 : 0
      Canvas { context, size in
        let scale = min(size.width / DrillbitGlyph.width, size.height / DrillbitGlyph.height)
        context.translateBy(x: size.width / 2, y: size.height / 2)
        context.scaleBy(x: scale, y: scale)
        context.fill(Self.silhouette, with: .color(color))
        // A drawLayer would composite its cut-outs onto nothing; erase from the silhouette itself.
        var cut = context
        cut.clip(to: Self.fluteZone)
        cut.blendMode = .destinationOut
        for start in [-255.0, -115, 25, 165] { cut.fill(Self.gap(start + 140 * phase), with: .color(.black)) }
      }
    }
    .frame(width: height * DrillbitGlyph.width / DrillbitGlyph.height, height: height)
    .accessibilityHidden(true)
  }

  private static let silhouette: Path = {
    var path = Path()
    path.move(to: CGPoint(x: -120, y: -316))
    path.addQuadCurve(to: CGPoint(x: -96, y: -340), control: CGPoint(x: -120, y: -340))
    path.addLine(to: CGPoint(x: 96, y: -340))
    path.addQuadCurve(to: CGPoint(x: 120, y: -316), control: CGPoint(x: 120, y: -340))
    path.addLine(to: CGPoint(x: 120, y: 248))
    path.addLine(to: CGPoint(x: 12, y: 330.8))
    path.addQuadCurve(to: CGPoint(x: -12, y: 330.8), control: CGPoint(x: 0, y: 340))
    path.addLine(to: CGPoint(x: -120, y: 248))
    path.closeSubpath()
    return path
  }()

  /// The fluted section between the cap and the tip; flutes are clipped to it as they travel.
  private static let fluteZone: Path = {
    var path = Path()
    path.move(to: CGPoint(x: -120, y: -115))
    path.addCurve(to: CGPoint(x: 0, y: -185), control1: CGPoint(x: -120, y: -142.5), control2: CGPoint(x: -43.5, y: -168.8))
    path.addCurve(to: CGPoint(x: 120, y: -255), control1: CGPoint(x: 43.5, y: -201.2), control2: CGPoint(x: 120, y: -227.5))
    path.addLine(to: CGPoint(x: 120, y: 79))
    path.addCurve(to: CGPoint(x: 0, y: 149), control1: CGPoint(x: 120, y: 106.5), control2: CGPoint(x: 43.5, y: 132.8))
    path.addCurve(to: CGPoint(x: -120, y: 219), control1: CGPoint(x: -43.5, y: 165.2), control2: CGPoint(x: -120, y: 191.5))
    path.closeSubpath()
    return path
  }()

  /// One flute gap whose upper edge meets the left side at `g`; at rest the gaps sit exactly where the logo's cuts are.
  private static func gap(_ g: Double) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: -120, y: g))
    path.addCurve(to: CGPoint(x: 0, y: g - 70), control1: CGPoint(x: -120, y: g - 27.5), control2: CGPoint(x: -43.5, y: g - 53.8))
    path.addCurve(to: CGPoint(x: 120, y: g - 140), control1: CGPoint(x: 43.5, y: g - 86.2), control2: CGPoint(x: 120, y: g - 112.5))
    path.addLine(to: CGPoint(x: 120, y: g - 86))
    path.addCurve(to: CGPoint(x: 0, y: g - 16), control1: CGPoint(x: 120, y: g - 58.5), control2: CGPoint(x: 43.5, y: g - 32.2))
    path.addCurve(to: CGPoint(x: -120, y: g + 54), control1: CGPoint(x: -43.5, y: g + 0.2), control2: CGPoint(x: -120, y: g + 26.5))
    path.closeSubpath()
    return path
  }
}

/// Draws an underline under the text, left to right across its lines, up to `progress`.
struct UnderlineRenderer: TextRenderer, Animatable {
  var progress: Double
  var color: Color
  var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }
  func draw(layout: Text.Layout, in context: inout GraphicsContext) {
    let total = layout.reduce(0.0) { $0 + $1.typographicBounds.width }
    var remaining = total * progress
    for line in layout {
      context.draw(line)
      let bounds = line.typographicBounds
      let width = min(bounds.width, max(0, remaining))
      remaining -= bounds.width
      guard width > 0 else { continue }
      let y = bounds.rect.minY + bounds.ascent + max(2, bounds.descent * 0.45)
      context.fill(Path(roundedRect: CGRect(x: bounds.rect.minX, y: y, width: width, height: 2), cornerRadius: 1), with: .color(color))
    }
  }
}

/// A line from the person's own answer. When `draws`, the underline runs once on arrival with a success haptic.
struct YourLine: View {
  let quote: String
  var font: Font = .title2.weight(.medium)
  var draws = false
  @State private var progress = 0.0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    Text("“\(quote)”")
      .font(font)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
      .textRenderer(UnderlineRenderer(progress: draws ? progress : 1, color: AppPalette.underline))
      .textSelection(.enabled)
      .sensoryFeedback(.success, trigger: progress == 1 && draws)
      .onAppear {
        guard draws, progress == 0 else { return }
        if reduceMotion { progress = 1; return }
        withAnimation(.smooth(duration: 0.55).delay(0.35)) { progress = 1 }
      }
      .accessibilityLabel("From your answer: \(quote)")
  }
}

/// The question's key facts, set apart in an inset like a spec on the ticket.
struct KeyFacts<Content: View>: View {
  @ViewBuilder var content: () -> Content
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Key facts").font(.subheadline.weight(.medium)).foregroundStyle(AppPalette.secondary)
        .accessibilityAddTraits(.isHeader)
      content()
    }
    .padding(.horizontal, 16).padding(.vertical, 14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(AppPalette.inset, in: RoundedRectangle(cornerRadius: 12))
  }
}
