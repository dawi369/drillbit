import SwiftUI

/// This week at a glance: a dot per day, gold where a rep landed. Resets every week, so a missed day never wipes anything out.
struct HomeWeekStrip: View {
  /// Start of each day that has a finished rep.
  let days: Set<Date>
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.calendar) private var calendar

  private var week: [Date] {
    guard let start = calendar.dateInterval(of: .weekOfYear, for: .now)?.start else { return [] }
    return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
  }

  var body: some View {
    let today = calendar.startOfDay(for: .now)
    // The seven days share the full width, so the week reads as a row across Home rather than a cluster in the corner.
    HStack(spacing: 0) {
      ForEach(week, id: \.self) { day in
        let done = days.contains(day)
        let isToday = day == today
        VStack(spacing: 8) {
          Text(day.formatted(.dateTime.weekday(.narrow)))
            .font(.caption2.weight(isToday ? .semibold : .medium))
            .foregroundStyle(isToday ? AppPalette.primary : AppPalette.secondary)
          ZStack {
            Circle().fill(done ? AppPalette.action : AppPalette.elevated)
            if isToday && !done { Circle().stroke(AppPalette.secondary, lineWidth: 1.5) }
          }
          .frame(width: 14, height: 14)
          .scaleEffect(done || reduceMotion ? 1 : 0.84)
          .animation(reduceMotion ? nil : DrillbitMotion.selection, value: done)
        }
        .frame(maxWidth: .infinity)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(spoken)
    .accessibilityIdentifier("homeWeek")
  }

  private var spoken: String {
    let done = week.filter { days.contains($0) }
    guard !done.isEmpty else { return "This week: no reps yet" }
    let names = done.map { calendar.isDateInToday($0) ? "today" : $0.formatted(.dateTime.weekday(.wide)) }
    return "This week: \(done.count) \(done.count == 1 ? "rep day" : "rep days"), " + names.formatted(.list(type: .and))
  }
}

/// A one-time gold sweep across a milestone ticket. Reduce Motion keeps the gold and drops the sweep.
struct FoilSheen: View {
  @State private var phase: CGFloat = -1
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    GeometryReader { proxy in
      LinearGradient(colors: [.clear, .white.opacity(0.28), .clear], startPoint: .leading, endPoint: .trailing)
        .frame(width: proxy.size.width * 0.5)
        .rotationEffect(.degrees(18))
        .offset(x: phase * proxy.size.width * 1.4)
        .opacity(reduceMotion ? 0 : 1)
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
    .task {
      guard !reduceMotion else { return }
      try? await Task.sleep(for: .milliseconds(450))
      withAnimation(.easeInOut(duration: 1.3)) { phase = 1 }
    }
  }
}

/// What a milestone shares: the ticket, flattened to an image.
struct MilestoneShareCard: View {
  let ticket: Int
  let line: String
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(String(format: "No. %03d", ticket))
        .font(.caption.weight(.semibold).monospaced()).tracking(1.2)
        .foregroundStyle(AppPalette.accent)
      Text(line).font(.title2.weight(.semibold)).foregroundStyle(AppPalette.primary)
        .fixedSize(horizontal: false, vertical: true)
      Text("System design reps on Drillbit").font(.subheadline).foregroundStyle(AppPalette.secondary)
    }
    .padding(24)
    .frame(width: 360, alignment: .leading)
    .background(LinearGradient(colors: [AppPalette.accentSoft, AppPalette.ticket], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 12))
    .overlay { RoundedRectangle(cornerRadius: 12).stroke(AppPalette.accent.opacity(0.5), lineWidth: 1) }
    .padding(20)
    .background(AppPalette.background)
  }

  @MainActor static func image(ticket: Int, line: String, scheme: ColorScheme) -> Image? {
    let renderer = ImageRenderer(content: MilestoneShareCard(ticket: ticket, line: line).environment(\.colorScheme, scheme))
    renderer.scale = 3
    return renderer.uiImage.map { Image(uiImage: $0) }
  }
}

/// A conductor's punch through a finished ticket. It lands once per ticket, with a firm tap, the first time Home shows
/// that ticket done; after that it's simply there. Reduce Motion fades it in.
struct TicketPunch: View {
  let ticket: Int?
  @AppStorage("home.punchedTicket") private var punchedTicket = 0
  @State private var landed = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Circle()
      .fill(AppPalette.background)
      .overlay { Circle().stroke(AppPalette.ticketEdge, lineWidth: 1) }
      .overlay { Circle().stroke(.black.opacity(0.35), lineWidth: 2).blur(radius: 1).clipShape(Circle()) }
      .frame(width: 14, height: 14)
      .scaleEffect(landed || reduceMotion ? 1 : 0.2)
      .opacity(landed ? 1 : 0)
      .sensoryFeedback(.impact(weight: .medium), trigger: landed) { old, new in !old && new && !reduceMotion }
      .accessibilityHidden(true)
      .task(id: ticket) {
        guard let ticket else { landed = true; return }
        if punchedTicket == ticket { landed = true; return }
        // After the hand back from the rep has settled, so the punch is something you see happen.
        try? await Task.sleep(for: .milliseconds(450))
        withAnimation(reduceMotion ? DrillbitMotion.fast : .spring(duration: 0.32, bounce: 0.2)) { landed = true }
        punchedTicket = ticket
      }
  }
}

/// The newest gap your feedback found, the last few reps on that concept, and whether a later rep closed it.
struct FixNext: Equatable {
  let conceptID: String
  let area: String
  let fix: String
  let quote: String?
  let fixed: Bool
  /// The concept's last few reps, oldest first.
  var trail: [KnowledgeNode.State] = []

  @MainActor static func from(_ model: AppModel, nodes built: [KnowledgeNode]? = nil) -> FixNext? {
    let nodes = built ?? KnowledgeNode.build(model: model)
    let node = { (id: String?) in id.flatMap { id in nodes.first { $0.id == id } } }
    let reps = model.memory.sessions.filter { $0.lifecycle == "completed" && !$0.isWarmUp }
      .sorted { ($0.completedAt ?? "") > ($1.completedAt ?? "") }
    let make = { (node: KnowledgeNode, fix: String, quote: String?) in
      FixNext(conceptID: node.id, area: node.label, fix: fix, quote: quote, fixed: node.state == .strong,
              trail: trail(node, reps: reps))
    }
    for rep in reps {
      for evidence in rep.reflection?.evidence ?? [] where evidence.signal == "needs_practice" {
        guard let node = node(evidence.conceptId) else { continue }
        return make(node, evidence.observation, evidence.quote)
      }
      // Older feedback has no grounded evidence: the rep's own fix line, on its main concept.
      if let fix = rep.reflection?.fixLine, let node = node(rep.primaryConceptId) { return make(node, fix, nil) }
    }
    if let evidence = model.memory.evidence?.first(where: { $0.signal == "needs_practice" }), let node = node(evidence.conceptId) {
      return make(node, evidence.observation, evidence.quote)
    }
    return nil
  }

  /// Up to five reps on the concept, oldest first, each by what its feedback said about it.
  static func trail(_ node: KnowledgeNode, reps: [Challenge]) -> [KnowledgeNode.State] {
    let states: [KnowledgeNode.State] = reps.compactMap { rep in
      let evidence = (rep.reflection?.evidence ?? []).filter { $0.conceptId == node.id }
      guard !evidence.isEmpty || (rep.conceptIds ?? []).contains(node.id) || rep.primaryConceptId == node.id else { return nil }
      return evidence.contains { $0.signal == "demonstrated" } ? .strong
        : evidence.contains { $0.signal == "needs_practice" } ? .revisit : .practised
    }
    let recent = Array(states.prefix(5).reversed())
    return recent.isEmpty ? [node.state] : recent
  }
}

/// Reads only what the glance shows (reps, taxonomy, Recall, first use), so Home's frequent changes, like a question
/// title streaming in, don't rebuild the map.
struct HomeGlanceHost: View {
  var model: AppModel
  @Binding var flow: QuestionFlowEntry?

  var body: some View {
    let nodes = KnowledgeNode.build(model: model)
    let fix = FixNext.from(model, nodes: nodes)
    // The first rep's cards get one plain introduction instead of a tab tour.
    let introducing = model.firstUse.firstRepID != nil && !model.firstUse.recallIntroduced
    HomeGlance(fix: fix, recallDue: model.bootstrap?.todayPlan?.dueRecallCount ?? 0,
               introducingRecall: introducing, nodes: nodes,
               drill: {
                 guard let fix else { return }
                 // Free accounts out of reps meet Pro here, the same as every other rep-starting action.
                 if model.mayStartRep() { flow = QuestionFlowEntry(browseTopics: true, concept: fix.conceptID) }
                 else { PlanCoordinator.shared.register(.practiceRep) { await model.refresh() } }
               },
               openRecall: {
                 if introducing { Task { await model.markRecallIntroduced() } }
                 NotificationCenter.default.post(name: .init("OpenRecall"), object: nil)
               },
               openMap: { NotificationCenter.default.post(name: .init("OpenBit"), object: nil) })
  }
}

/// Home under the ticket, read in a glance: what to drill next and the Recall cards waiting as two tiles, then the
/// whole map as one bar. The words live on the pages these open.
struct HomeGlance: View {
  let fix: FixNext?
  let recallDue: Int
  let introducingRecall: Bool
  let nodes: [KnowledgeNode]
  let drill: () -> Void
  let openRecall: () -> Void
  let openMap: () -> Void
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if fix != nil || recallDue > 0 {
        let row = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        row {
          if let fix { DrillTile(fix: fix, action: drill).signalEntrance(1) }
          if recallDue > 0 { RecallTile(due: recallDue, introducing: introducingRecall, action: openRecall).signalEntrance(2) }
        }
        .fixedSize(horizontal: false, vertical: true)
      }
      if nodes.contains(where: { $0.state != .unexplored }) {
        MapStrip(nodes: nodes, action: openMap).signalEntrance(3)
      }
    }
  }
}

/// One glance tile: a small label with an arrow, then whatever the tile shows. The whole tile is the button.
private struct GlanceTile<Content: View>: View {
  let title: String
  let spoken: String
  let identifier: String
  let action: () -> Void
  @ViewBuilder var content: () -> Content

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 4) {
          Text(title).font(.footnote.weight(.semibold)).foregroundStyle(AppPalette.secondary)
            .contentTransition(.opacity)
          Spacer(minLength: 4)
          Image(systemName: "arrow.up.right").font(.caption.weight(.bold)).foregroundStyle(AppPalette.secondary)
        }
        content()
      }
      .padding(16)
      .frame(maxWidth: .infinity, minHeight: 128, maxHeight: .infinity, alignment: .topLeading)
      .glanceSurface()
    }
    .buttonStyle(TicketPressStyle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(spoken)
    .accessibilityAddTraits(.isButton)
    .accessibilityIdentifier(identifier)
  }
}

private extension View {
  func glanceSurface() -> some View {
    background(AppPalette.elevated, in: RoundedRectangle(cornerRadius: 12))
      .overlay { RoundedRectangle(cornerRadius: 12).stroke(AppPalette.ticketEdge, lineWidth: 1) }
      .contentShape(RoundedRectangle(cornerRadius: 12))
  }
}

/// A concept's last few reps as map dots, oldest first, popping in one after another the first time they show.
struct RepTrail: View {
  let states: [KnowledgeNode.State]
  var size: CGFloat = 10
  var delay = 0.45
  @State private var lit = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    HStack(spacing: size * 0.6) {
      ForEach(Array(states.enumerated()), id: \.offset) { index, state in
        NodeDot(state: state, size: size, glow: false)
          .scaleEffect(lit || reduceMotion ? 1 : 0.2)
          .opacity(lit ? 1 : 0)
          .animation(reduceMotion ? nil : DrillbitMotion.pop.delay(delay + Double(index) * 0.08), value: lit)
      }
    }
    .onAppear { lit = true }
    .accessibilityHidden(true)
  }
}

/// The concept to drill next and its last few reps as dots: gold held up, ringed worth another go.
private struct DrillTile: View {
  let fix: FixNext
  let action: () -> Void
  @State private var lit = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    GlanceTile(title: fix.fixed ? "Fixed" : "Drill next", spoken: spoken, identifier: "homeFixNext", action: action) {
      Text(fix.area).font(.title3.weight(.semibold)).foregroundStyle(AppPalette.primary)
        .multilineTextAlignment(.leading).lineLimit(3).minimumScaleFactor(0.8)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
      HStack(spacing: 6) {
        RepTrail(states: fix.trail)
        if fix.fixed {
          Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(AppPalette.success)
            .symbolEffect(.bounce, value: lit)
        }
      }
    }
    .onAppear { lit = true }
  }

  private var spoken: String {
    fix.fixed ? "Fixed: \(fix.area). Your last rep on it held up."
      : "Drill next: \(fix.area). Last time: \(fix.fix)" + (fix.quote.map { " You said \($0)" } ?? "")
  }
}

/// How many Recall cards are waiting, as a number and a small fanned deck.
private struct RecallTile: View {
  let due: Int
  let introducing: Bool
  let action: () -> Void
  @State private var fanned = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    GlanceTile(title: introducing ? "From your first rep" : "Recall", spoken: "Recall, \(due) due", identifier: "homeRecall", action: action) {
      Spacer(minLength: 0)
      HStack(alignment: .bottom) {
        VStack(alignment: .leading, spacing: 0) {
          Text("\(due)").font(.system(.largeTitle, design: .rounded, weight: .semibold)).monospacedDigit()
            .foregroundStyle(AppPalette.primary)
            .contentTransition(.numericText(value: Double(due)))
          Text(due == 1 ? "card due" : "cards due").font(.footnote).foregroundStyle(AppPalette.secondary)
        }
        Spacer(minLength: 8)
        ZStack {
          ForEach(0..<3, id: \.self) { index in
            RoundedRectangle(cornerRadius: 4)
              .fill(index == 2 ? AppPalette.ticket : AppPalette.inset)
              .overlay { RoundedRectangle(cornerRadius: 4).stroke(index == 2 ? AppPalette.action : AppPalette.hairline, lineWidth: 1) }
              .frame(width: 26, height: 34)
              .rotationEffect(.degrees(fanned && !reduceMotion ? Double(index - 1) * 12 : 0), anchor: .bottom)
              .offset(x: fanned && !reduceMotion ? CGFloat(index - 1) * 6 : 0)
          }
        }
        .frame(width: 52, height: 40)
        .animation(reduceMotion ? nil : DrillbitMotion.pop.delay(0.5), value: fanned)
      }
    }
    .onAppear { fanned = true }
  }
}

/// The whole knowledge map as one bar: a cell per concept, grouped by area, lit the way the Bit tab lights them.
/// It fills left to right the first time Home shows it.
private struct MapStrip: View {
  let nodes: [KnowledgeNode]
  let action: () -> Void
  @State private var grown = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let explored = nodes.filter { $0.state != .unexplored }.count
    Button(action: action) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          Text("Your map").font(.footnote.weight(.semibold)).foregroundStyle(AppPalette.secondary)
          Spacer(minLength: 8)
          Text("\(explored)").font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(AppPalette.primary)
            .contentTransition(.numericText(value: Double(explored)))
          Text("of \(nodes.count)").font(.subheadline).monospacedDigit().foregroundStyle(AppPalette.secondary)
          Image(systemName: "arrow.up.right").font(.caption.weight(.bold)).foregroundStyle(AppPalette.secondary)
            .padding(.leading, 4)
        }
        MapStripCells(nodes: nodes, progress: grown || reduceMotion ? 1 : 0).frame(height: 10)
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .glanceSurface()
    }
    .buttonStyle(TicketPressStyle())
    .onAppear { withAnimation(.smooth(duration: 0.9).delay(0.5)) { grown = true } }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Your map: \(explored) of \(nodes.count) areas explored, \(nodes.filter { $0.state == .strong }.count) held up")
    .accessibilityAddTraits(.isButton)
    .accessibilityIdentifier("homeMap")
  }
}

private struct MapStripCells: View, @preconcurrency Animatable {
  let nodes: [KnowledgeNode]
  var progress: Double
  var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  var body: some View {
    let groups = ConstellationLayout.categories(nodes).map { category in nodes.filter { $0.category == category } }
    Canvas { context, size in
      let cellGap: CGFloat = 3, groupGap: CGFloat = 8
      let count = CGFloat(nodes.count)
      let width = (size.width - cellGap * (count - CGFloat(groups.count)) - groupGap * CGFloat(max(groups.count - 1, 0))) / max(count, 1)
      var x: CGFloat = 0
      var index = 0.0
      for group in groups {
        for node in group {
          // Each cell fades and grows in as the fill passes it.
          let shown = min(1, max(0, progress * count - index))
          let height = size.height * (0.4 + 0.6 * shown)
          let rect = CGRect(x: x, y: (size.height - height) / 2, width: width, height: height)
          let cell = Path(roundedRect: rect, cornerRadius: 2)
          var layer = context
          layer.opacity = node.state == .unexplored ? 1 : shown
          switch node.state {
          case .strong: layer.fill(cell, with: .color(AppPalette.action))
          case .revisit: layer.stroke(cell, with: .color(AppPalette.action), lineWidth: 1.5)
          case .practised: layer.fill(cell, with: .color(AppPalette.primary.opacity(0.85)))
          case .unexplored: layer.fill(cell, with: .color(AppPalette.hairline.opacity(0.6)))
          }
          x += width + cellGap
          index += 1
        }
        x += groupGap - cellGap
      }
    }
    .accessibilityHidden(true)
  }
}
