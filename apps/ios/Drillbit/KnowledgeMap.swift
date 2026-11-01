import SwiftUI

/// Pro: everything you've practised as one map, an honest level estimate, and where to go next.
/// Built only from your own reps: coverage counts, grounded feedback quotes and the levels you practised at.
struct KnowledgeMapView: View {
  var model: AppModel
  @State private var selected: String?
  @State private var appeared = false
  @State private var flow: QuestionFlowEntry?
  @State private var started: Challenge?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    let nodes = KnowledgeNode.build(model: model)
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        LevelCard(estimate: LevelEstimate.from(model.memory.sessions), target: model.settings.selectedLevel)
        stats(nodes)
        VStack(alignment: .leading, spacing: 12) {
          SignalEyebrow(text: "Your map")
          ConstellationMap(nodes: nodes, selected: $selected, appeared: appeared)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("knowledgeMap")
          legend
          if let id = selected, let node = nodes.first(where: { $0.id == id }) {
            nodeDetail(node).transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 8)))
          }
        }
        nextUp(nodes)
      }
      .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 40)
      .frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity)
    }
    .background(AppPalette.background)
    .containerBackground(AppPalette.background, for: .navigation)
    .navigationTitle("Bit")
    .navigationSubtitle("What you’ve learned so far")
    .animation(reduceMotion ? nil : DrillbitMotion.reveal, value: selected)
    .task {
      await model.loadTaxonomy()
      await model.loadMemory()
      if !model.libraryCoverageLoaded { await model.preloadLibrary() }
      withAnimation(reduceMotion ? nil : .easeOut(duration: 0.9)) { appeared = true }
    }
    .refreshable { await model.loadMemory(); await model.preloadLibrary(force: true) }
    .sheet(item: $flow, onDismiss: { if let started { model.presented = started; self.started = nil } }) { entry in
      QuestionFlow(model: model, browseTopics: entry.browseTopics, area: entry.area, onStart: { started = $0 })
    }
  }

  // MARK: Stats

  private func stats(_ nodes: [KnowledgeNode]) -> some View {
    let reps = model.bootstrap?.todayPlan?.completedTotal ?? model.memory.statistics?.completed ?? 0
    let explored = nodes.filter { $0.state != .unexplored }.count
    let strong = nodes.filter { $0.state == .strong }.count
    // Three across normally; stacked at accessibility sizes so the numbers and labels read in full.
    // The tiles share one height, so a label that wraps doesn't knock its tile out of line.
    let row = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
    return row {
      statTile(value: "\(reps)", label: reps == 1 ? "rep" : "reps")
      statTile(value: "\(explored)/\(nodes.count)", label: "areas explored")
      statTile(value: "\(strong)", label: strong == 1 ? "decision held up" : "decisions held up")
    }
    .fixedSize(horizontal: false, vertical: true)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("mapStats")
  }

  private func statTile(value: String, label: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(value).font(.title2.weight(.semibold).monospacedDigit()).foregroundStyle(AppPalette.primary)
      Text(label).font(.footnote).foregroundStyle(AppPalette.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
    }
    .padding(16)
    .frame(maxWidth: .infinity, minHeight: 88, maxHeight: .infinity, alignment: .topLeading)
    .background(AppPalette.ticket, in: RoundedRectangle(cornerRadius: 12))
    .overlay { RoundedRectangle(cornerRadius: 12).stroke(AppPalette.ticketEdge, lineWidth: 1) }
  }

  private var legend: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 16) { legendItems }
      Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
        GridRow { legendItem(.strong, "Held up"); legendItem(.revisit, "Revisit") }
        GridRow { legendItem(.practised, "Practised"); legendItem(.unexplored, "Not yet") }
      }
    }
    .font(.caption)
    .foregroundStyle(AppPalette.secondary)
    .frame(maxWidth: .infinity)
    .accessibilityHidden(true)
  }

  @ViewBuilder private var legendItems: some View {
    legendItem(.strong, "Held up")
    legendItem(.revisit, "Revisit")
    legendItem(.practised, "Practised")
    legendItem(.unexplored, "Not yet")
  }
  private func legendItem(_ state: KnowledgeNode.State, _ title: String) -> some View {
    HStack(spacing: 6) { NodeDot(state: state, size: 10, glow: false); Text(title).fixedSize() }
  }

  // MARK: Detail

  private func nodeDetail(_ node: KnowledgeNode) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      DrillbitMetadata(text: node.category)
      Text(node.label).font(.title3.weight(.semibold)).foregroundStyle(AppPalette.primary)
      Text(node.statusLine).font(.subheadline.weight(.medium)).foregroundStyle(node.state == .strong || node.state == .revisit ? AppPalette.accent : AppPalette.secondary)
      if let evidence = node.evidence {
        Text("“\(evidence.quote)”").font(.subheadline).foregroundStyle(AppPalette.primary).fixedSize(horizontal: false, vertical: true)
        Text(evidence.observation).font(.subheadline).foregroundStyle(AppPalette.secondary).fixedSize(horizontal: false, vertical: true)
      } else if let description = node.description {
        Text(description).font(.subheadline).foregroundStyle(AppPalette.secondary).fixedSize(horizontal: false, vertical: true)
      }
      Button(node.state == .unexplored ? "Try it" : "Practise this") { practise(node) }
        .buttonStyle(PracticeButtonStyle())
        .accessibilityIdentifier("mapPractise")
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(AppPalette.ticket, in: RoundedRectangle(cornerRadius: 12))
    .overlay { RoundedRectangle(cornerRadius: 12).stroke(AppPalette.ticketEdge, lineWidth: 1) }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("mapDetail")
  }

  // MARK: Next up

  private func nextUp(_ nodes: [KnowledgeNode]) -> some View {
    let revisit = nodes.filter { $0.state == .revisit }
    let fresh = nodes.filter { $0.state == .unexplored && PracticeAreaCatalog.ids.contains($0.id) }
    let picks = Array((revisit + fresh).prefix(3))
    return Group {
      if !picks.isEmpty {
        VStack(alignment: .leading, spacing: 12) {
          SignalEyebrow(text: "Next up")
          ForEach(picks) { node in
            Button { practise(node) } label: {
              let row = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
              row {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                  NodeDot(state: node.state, size: 12, glow: false)
                  VStack(alignment: .leading, spacing: 2) {
                    Text(node.label).font(.body.weight(.medium)).foregroundStyle(AppPalette.primary)
                      .fixedSize(horizontal: false, vertical: true)
                    Text(node.state == .revisit ? "Worth another go" : "Not explored yet").font(.footnote).foregroundStyle(AppPalette.secondary)
                      .fixedSize(horizontal: false, vertical: true)
                  }
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                StubPill(label: "Practise").fixedSize()
              }
              .padding(16)
              .background(AppPalette.ticket, in: RoundedRectangle(cornerRadius: 12))
              .overlay { RoundedRectangle(cornerRadius: 12).stroke(AppPalette.ticketEdge, lineWidth: 1) }
              .contentShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(TicketPressStyle())
            .accessibilityLabel("Practise \(node.label)")
            .accessibilityIdentifier("nextUp-\(node.id)")
          }
        }
      }
    }
  }

  private func practise(_ node: KnowledgeNode) {
    let area = PracticeAreaGroup.all.first { $0.concepts.contains(node.id) }
    flow = QuestionFlowEntry(browseTopics: true, area: area)
  }
}

// MARK: - Model

struct KnowledgeNode: Identifiable {
  enum State { case strong, revisit, practised, unexplored }
  let id: String
  let label: String
  let category: String
  let description: String?
  let reps: Int
  let state: State
  let evidence: LearningEvidence?

  var statusLine: String {
    let count = reps == 1 ? "1 rep" : "\(reps) reps"
    switch state {
    case .strong: return "Held up · \(count)"
    case .revisit: return "Worth another go · \(count)"
    case .practised: return "Practised · \(count)"
    case .unexplored: return "Not explored yet"
    }
  }

  /// One node per concept in the canonical vocabulary, in its category order.
  @MainActor static func build(model: AppModel) -> [KnowledgeNode] {
    let sessions = model.memory.sessions.filter { $0.lifecycle == "completed" && !$0.isWarmUp }
      .sorted { ($0.completedAt ?? "") > ($1.completedAt ?? "") }
    return model.taxonomy.map { concept in
      let coverage = model.libraryCoverage.first { $0.conceptId == concept.id }?.completedAttempts
      let reps = coverage ?? sessions.filter { ($0.conceptIds ?? []).contains(concept.id) || $0.primaryConceptId == concept.id }.count
      // The latest grounded quote for this concept: the freshest rep's feedback first, then the account summary.
      let evidence = sessions.lazy.compactMap { $0.reflection?.evidence?.first { $0.conceptId == concept.id } }.first
        ?? model.memory.evidence?.first { $0.conceptId == concept.id }
      let state: State = evidence?.signal == "demonstrated" ? .strong
        : evidence?.signal == "needs_practice" ? .revisit
        : reps > 0 ? .practised : .unexplored
      return KnowledgeNode(id: concept.id, label: concept.label, category: concept.category, description: concept.description,
                           reps: max(reps, evidence == nil ? 0 : 1), state: state, evidence: evidence)
    }
  }
}

/// Where your reps say you're working, on the same ladder as the questions. It counts a rep as holding up when its
/// feedback found at least as many sound decisions as gaps, and needs a few reps at a level before it says anything.
struct LevelEstimate {
  static let ladder = EngineeringLevel.choices
  let level: String?
  let basis: String

  static func from(_ sessions: [Challenge]) -> LevelEstimate {
    let rated = sessions.compactMap { rep -> (rank: Int, heldUp: Bool)? in
      guard rep.lifecycle == "completed", !rep.isWarmUp, let evidence = rep.reflection?.evidence, !evidence.isEmpty,
            let rank = ladder.firstIndex(where: { $0.0 == rep.engineeringLevel }) else { return nil }
      let shown = evidence.filter { $0.signal == "demonstrated" }.count
      let gaps = evidence.filter { $0.signal == "needs_practice" }.count
      return (rank, shown > 0 && shown >= gaps)
    }
    guard rated.count >= 3 else {
      let left = 3 - rated.count
      return LevelEstimate(level: nil, basis: "\(left) more \(left == 1 ? "rep" : "reps") with real design calls and Bit can place you.")
    }
    for rank in ladder.indices.reversed() {
      let atOrAbove = rated.filter { $0.rank >= rank }
      let held = atOrAbove.filter(\.heldUp).count
      if atOrAbove.count >= 2, held >= 2, Double(held) / Double(atOrAbove.count) >= 0.6 {
        return LevelEstimate(level: ladder[rank].0, basis: "\(held) of \(atOrAbove.count) reps at \(ladder[rank].1) or above held up.")
      }
    }
    return LevelEstimate(level: ladder.first?.0, basis: "Your decisions are still settling. Keep going and this firms up fast.")
  }
}

// MARK: - Level card

private struct LevelCard: View {
  let estimate: LevelEstimate
  let target: String
  /// The ladder fills up to the estimate on arrival, one step after another.
  @State private var filled = false
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    let ladder = LevelEstimate.ladder
    let current = estimate.level.flatMap { level in ladder.firstIndex { $0.0 == level } }
    let goal = ladder.firstIndex { $0.0 == target }
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        DrillbitMetadata(text: "Working at about")
        Text(current.map { ladder[$0].1 } ?? "Too early to say")
          .font(.title.weight(.semibold)).foregroundStyle(current == nil ? AppPalette.primary : AppPalette.accent)
          .accessibilityIdentifier("levelEstimate")
      }
      HStack(spacing: 0) {
        ForEach(ladder.indices, id: \.self) { index in
          VStack(spacing: 8) {
            ZStack {
              Capsule().fill(AppPalette.elevated).frame(height: 6)
              Capsule().fill(AppPalette.action).frame(height: 6)
                .scaleEffect(x: filled && index <= (current ?? -1) ? 1 : 0, anchor: .leading)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.28).delay(0.15 + Double(index) * 0.09), value: filled)
              if index == goal { Circle().stroke(AppPalette.primary, lineWidth: 1.5).frame(width: 14, height: 14) }
            }
            .frame(height: 14)
            // At accessibility sizes six labels can't share a row; the level is named in full above.
            if !typeSize.isAccessibilitySize {
              Text(ladder[index].1.replacingOccurrences(of: "-level", with: ""))
                .font(.caption2.weight(index == current ? .semibold : .regular))
                .foregroundStyle(index == current ? AppPalette.primary : AppPalette.secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
            }
          }
          .frame(maxWidth: .infinity)
          .padding(.horizontal, 2)
        }
      }
      .accessibilityHidden(true)
      Text(estimate.basis + (goal != nil ? " The ring is your target." : "") + " An estimate from your reps, not a hiring call.")
        .font(.footnote).foregroundStyle(AppPalette.secondary).fixedSize(horizontal: false, vertical: true)
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(AppPalette.ticket, in: RoundedRectangle(cornerRadius: 12))
    .overlay { RoundedRectangle(cornerRadius: 12).stroke(AppPalette.ticketEdge, lineWidth: 1) }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("levelCard")
    .onAppear { filled = true }
  }
}

// MARK: - Constellation

private struct NodeDot: View {
  let state: KnowledgeNode.State
  let size: CGFloat
  var glow = true
  var body: some View {
    ZStack {
      switch state {
      case .strong:
        Circle().fill(AppPalette.action)
          .shadow(color: AppPalette.action.opacity(glow ? 0.7 : 0), radius: size * 0.6)
      case .revisit:
        Circle().fill(AppPalette.elevated)
        Circle().stroke(AppPalette.action, lineWidth: max(1.5, size * 0.16))
      case .practised:
        Circle().fill(AppPalette.primary.opacity(0.85))
      case .unexplored:
        Circle().fill(AppPalette.elevated)
        Circle().stroke(AppPalette.hairline, lineWidth: 1)
      }
    }
    .frame(width: size, height: size)
  }
}

/// Bit in the middle, a hub per category around him, and each concept fanned out past its hub. Tap a concept to see it.
private struct ConstellationMap: View {
  let nodes: [KnowledgeNode]
  @Binding var selected: String?
  let appeared: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var categories: [String] {
    var seen: [String] = []
    for node in nodes where !seen.contains(node.category) { seen.append(node.category) }
    return seen
  }

  var body: some View {
    GeometryReader { proxy in
      let side = min(proxy.size.width, proxy.size.height)
      let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
      let layout = positions(side: side, center: center)
      ZStack {
        Canvas { context, _ in
          for (category, hub) in layout.hubs {
            var spoke = Path(); spoke.move(to: center); spoke.addLine(to: hub)
            context.stroke(spoke, with: .color(AppPalette.hairline), lineWidth: 1)
            for node in nodes where node.category == category {
              guard let point = layout.nodes[node.id] else { continue }
              var edge = Path(); edge.move(to: hub); edge.addLine(to: point)
              let lit = node.state != .unexplored
              context.stroke(edge, with: .color(lit ? AppPalette.action.opacity(node.state == .strong ? 0.55 : 0.3) : AppPalette.hairline),
                             lineWidth: lit ? 1.5 : 1)
            }
          }
        }
        .opacity(appeared ? 1 : 0)

        BitView().frame(width: 40, height: 46).position(center).accessibilityHidden(true)

        ForEach(Array(categories.enumerated()), id: \.element) { index, category in
          if let hub = layout.hubs.first(where: { $0.0 == category })?.1 {
            VStack(spacing: 4) {
              Circle().fill(AppPalette.secondary.opacity(0.6)).frame(width: 6, height: 6)
              Text(category).font(.caption2.weight(.semibold)).foregroundStyle(AppPalette.secondary)
                .multilineTextAlignment(.center).lineLimit(2)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(AppPalette.background.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
                .frame(width: 96)
            }
            .position(hub)
            .opacity(appeared ? 1 : 0)
            .accessibilityHidden(true)
          }
        }

        ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
          if let point = layout.nodes[node.id] {
            let isSelected = selected == node.id
            let size: CGFloat = node.state == .unexplored ? 10 : min(22, 12 + CGFloat(node.reps) * 2)
            Button { selected = isSelected ? nil : node.id } label: {
              NodeDot(state: node.state, size: isSelected ? size + 6 : size)
                .overlay {
                  if isSelected { Circle().stroke(AppPalette.primary, lineWidth: 1.5).frame(width: size + 14, height: size + 14) }
                }
                .frame(width: 44, height: 44)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .top) {
              if isSelected {
                Text(node.label).font(.caption.weight(.semibold)).foregroundStyle(AppPalette.primary)
                  .fixedSize()
                  .padding(.horizontal, 8).padding(.vertical, 4)
                  .background(AppPalette.elevated, in: Capsule())
                  .offset(y: -26)
                  .transition(.opacity)
              }
            }
            .position(point)
            .scaleEffect(appeared || reduceMotion ? 1 : 0.4)
            .opacity(appeared ? 1 : 0)
            .animation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.35).delay(Double(index) * 0.025), value: appeared)
            .accessibilityLabel("\(node.label). \(node.statusLine)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("mapNode-\(node.id)")
          }
        }
      }
    }
    .aspectRatio(1, contentMode: .fit)
    // A diagram: its labels stop growing past XXL so they fit their spots; each dot speaks its full name.
    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    .background(AppPalette.ticket.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    .overlay { RoundedRectangle(cornerRadius: 12).stroke(AppPalette.ticketEdge, lineWidth: 1) }
  }

  /// Hubs on an inner ring, one per category; each category's concepts fan out on the outer ring within its slice.
  private func positions(side: CGFloat, center: CGPoint) -> (hubs: [(String, CGPoint)], nodes: [String: CGPoint]) {
    let count = max(1, categories.count)
    let slice = 2 * Double.pi / Double(count)
    let inner = side * 0.25, outer = side * 0.42
    var hubs: [(String, CGPoint)] = []
    var points: [String: CGPoint] = [:]
    for (index, category) in categories.enumerated() {
      let angle = -Double.pi / 2 + Double(index) * slice
      hubs.append((category, CGPoint(x: center.x + inner * cos(angle), y: center.y + inner * sin(angle))))
      let members = nodes.filter { $0.category == category }
      let spread = slice * 0.78
      for (offset, node) in members.enumerated() {
        let t = members.count == 1 ? 0.5 : Double(offset) / Double(members.count - 1)
        let a = angle - spread / 2 + spread * t
        // Alternate radii a little so neighbours in a big category don't touch.
        let r = outer - (offset % 2 == 0 ? 0 : side * 0.05)
        points[node.id] = CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a))
      }
    }
    return (hubs, points)
  }
}
