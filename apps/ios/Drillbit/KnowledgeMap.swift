import SwiftUI

/// Pro: everything you've practised as one map, what the last rep changed on it, an honest level estimate, and where
/// to go next. Built only from your own reps: coverage counts, grounded feedback quotes and the levels you practised at.
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
    let lastRep = LastRepChange.from(model, nodes: nodes)
    ScrollView {
      VStack(alignment: .leading, spacing: 32) {
        VStack(alignment: .leading, spacing: 16) {
          // The map is the page: no card around it, as wide as the screen allows.
          ConstellationMap(nodes: nodes, fresh: lastRep?.touched ?? [], selected: $selected, appeared: appeared)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("knowledgeMap")
            .padding(.horizontal, 4)
          MapLegend().padding(.horizontal, 20)
          Group {
            if let id = selected, let node = nodes.first(where: { $0.id == id }) {
              nodeDetail(node).transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 8)))
            } else if let lastRep {
              lastRepLine(lastRep).transition(.opacity)
            }
          }
          .padding(.horizontal, 20)
        }
        VStack(alignment: .leading, spacing: 32) {
          LevelCard(estimate: LevelEstimate.from(model.memory.sessions), target: model.settings.selectedLevel)
            .signalEntrance(1)
          nextUp(nodes).signalEntrance(2)
        }
        .padding(.horizontal, 20)
      }
      .padding(.top, 4).padding(.bottom, 40)
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
      QuestionFlow(model: model, browseTopics: entry.browseTopics, concept: entry.concept, level: entry.level, onStart: { started = $0 })
    }
  }

  // MARK: Since the last rep

  /// Said the way onboarding reacts to an answer: a sparkle and a line, no box.
  private func lastRepLine(_ change: LastRepChange) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "sparkle").font(.caption.weight(.semibold)).foregroundStyle(AppPalette.accent).padding(.top, 3)
        .accessibilityHidden(true)
      Text("Your last rep: \(change.line)")
        .font(.subheadline).foregroundStyle(AppPalette.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, 4).padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("lastRepChange")
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

  /// Bit's pick for your next level, why, and how far along you are by the estimate's own rule; then a quiet list of
  /// alternatives. Before you're placed, or at the top of the ladder, it's simply what's worth practising next.
  @ViewBuilder private func nextUp(_ nodes: [KnowledgeNode]) -> some View {
    let path = LevelPath.from(model: model, nodes: nodes)
    let candidates = nodes.filter { $0.state == .revisit } + nodes.filter { $0.state == .unexplored }
    if let first = path?.pick ?? candidates.first {
      let picked = path?.pick?.id == first.id ? path : nil
      let others = Array(candidates.filter { $0.id != first.id }.prefix(2))
      VStack(alignment: .leading, spacing: 12) {
        SignalEyebrow(text: "Next up")
        VStack(alignment: .leading, spacing: 16) {
          VStack(alignment: .leading, spacing: 8) {
            if picked == nil {
              HStack(spacing: 8) {
                NodeDot(state: first.state, size: 10, glow: false)
                DrillbitMetadata(text: first.state == .revisit ? "Worth another go" : "Not on your map yet")
              }
              .accessibilityElement(children: .combine)
            }
            Text(first.label).font(.title2.weight(.semibold)).foregroundStyle(AppPalette.primary)
            if let picked, let reason = picked.reason {
              // Where the reason came from: the last rep on it, or what it is when it's new.
              Text(first.state == .revisit ? "Last time: \(reason)" : reason).font(.subheadline).foregroundStyle(AppPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } else if let reason = first.state == .revisit ? first.evidence?.observation : first.description {
              Text(reason).font(.subheadline).foregroundStyle(AppPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
          if let picked {
            VStack(alignment: .leading, spacing: 8) {
              PathProgress(lit: picked.placing ? picked.rated : picked.held,
                           total: picked.placing ? LevelEstimate.needed : LevelPath.heldNeeded)
              Text(picked.progressLine).font(.footnote).foregroundStyle(AppPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("levelPath")
          }
          Button(picked.map { $0.placing ? "Practise \(first.label)" : "Practise this at \($0.level.label)" } ?? "Practise \(first.label)") {
            practise(first, level: picked?.level.id)
          }
          .buttonStyle(PracticeButtonStyle())
          .accessibilityIdentifier("nextUp-\(first.id)")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ticketCard()
        if !others.isEmpty {
          VStack(spacing: 0) {
            ForEach(others) { node in
              if node.id != others.first?.id { Divider().overlay(AppPalette.hairline).padding(.leading, 38) }
              Button { practise(node) } label: {
                HStack(spacing: 12) {
                  NodeDot(state: node.state, size: 10, glow: false).frame(width: 14)
                  VStack(alignment: .leading, spacing: 2) {
                    Text(node.label).font(.body.weight(.medium)).foregroundStyle(AppPalette.primary)
                      .fixedSize(horizontal: false, vertical: true)
                    Text(node.state == .revisit ? "Worth another go" : "Not explored yet").font(.footnote).foregroundStyle(AppPalette.secondary)
                  }
                  Spacer(minLength: 8)
                  Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(AppPalette.secondary)
                    .accessibilityHidden(true)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
              }
              .buttonStyle(TicketPressStyle())
              .accessibilityLabel("Practise \(node.label)")
              .accessibilityIdentifier("nextUp-\(node.id)")
            }
          }
          .ticketCard(quiet: true)
        }
      }
    }
  }

  /// Opens the practice sheet on this concept, at a level when Bit's pick asks for one.
  private func practise(_ node: KnowledgeNode, level: String? = nil) {
    flow = QuestionFlowEntry(browseTopics: true, concept: node.id, level: level)
  }
}

/// What the dots mean, shared by the Pro map and the free Bit tab.
struct MapLegend: View {
  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 16) { items }
      Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
        GridRow { item(.strong, "Held up"); item(.revisit, "Revisit") }
        GridRow { item(.practised, "Practised"); item(.unexplored, "Not yet") }
      }
    }
    .font(.caption)
    .foregroundStyle(AppPalette.secondary)
    .frame(maxWidth: .infinity)
    .accessibilityHidden(true)
  }

  @ViewBuilder private var items: some View {
    item(.strong, "Held up")
    item(.revisit, "Revisit")
    item(.practised, "Practised")
    item(.unexplored, "Not yet")
  }
  private func item(_ state: KnowledgeNode.State, _ title: String) -> some View {
    HStack(spacing: 6) { NodeDot(state: state, size: 10, glow: false); Text(title).fixedSize() }
  }
}

/// Segments for a short count: lit for each one done.
private struct PathProgress: View {
  let lit: Int
  let total: Int
  @State private var filled = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    HStack(spacing: 8) {
      ForEach(0..<total, id: \.self) { index in
        ZStack(alignment: .leading) {
          Capsule().fill(AppPalette.hairline)
          Capsule().fill(AppPalette.action)
            .scaleEffect(x: filled && index < lit ? 1 : 0, anchor: .leading)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.32).delay(0.2 + Double(index) * 0.12), value: filled)
        }
        .frame(height: 8)
      }
    }
    .onAppear { filled = true }
    .accessibilityHidden(true)
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
    // One pass over the reps instead of one per concept: rep counts, and each concept's freshest grounded quote.
    var counts: [String: Int] = [:]
    var latest: [String: LearningEvidence] = [:]
    for session in sessions {
      for id in Set((session.conceptIds ?? []) + [session.primaryConceptId].compactMap { $0 }) { counts[id, default: 0] += 1 }
      for evidence in session.reflection?.evidence ?? [] where latest[evidence.conceptId] == nil { latest[evidence.conceptId] = evidence }
    }
    var summary: [String: LearningEvidence] = [:]
    for evidence in model.memory.evidence ?? [] where summary[evidence.conceptId] == nil { summary[evidence.conceptId] = evidence }
    var coverage: [String: Int] = [:]
    for entry in model.libraryCoverage where coverage[entry.conceptId] == nil { coverage[entry.conceptId] = entry.completedAttempts }
    return model.taxonomy.map { concept in
      let reps = coverage[concept.id] ?? counts[concept.id] ?? 0
      // The latest grounded quote for this concept: the freshest rep's feedback first, then the account summary.
      let evidence = latest[concept.id] ?? summary[concept.id]
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
  /// Reps with grounded feedback it takes before Bit says anything.
  static let needed = 3
  let level: String?
  let basis: String
  /// Reps so far that count towards an estimate.
  var rated = 0

  static func from(_ sessions: [Challenge]) -> LevelEstimate {
    let rated = rate(sessions)
    guard rated.count >= needed else {
      let left = needed - rated.count
      return LevelEstimate(level: nil, basis: "\(left) more \(left == 1 ? "rep" : "reps") and Bit places you.", rated: rated.count)
    }
    for rank in ladder.indices.reversed() {
      let atOrAbove = rated.filter { $0.rank >= rank }
      let held = atOrAbove.filter(\.heldUp).count
      if atOrAbove.count >= 2, held >= 2, Double(held) / Double(atOrAbove.count) >= 0.6 {
        return LevelEstimate(level: ladder[rank].0, basis: "\(held) of \(atOrAbove.count) reps at \(ladder[rank].1) or above held up.", rated: rated.count)
      }
    }
    return LevelEstimate(level: ladder.first?.0, basis: "Your decisions are still settling. Keep going and this firms up fast.", rated: rated.count)
  }

  /// Finished reps with grounded feedback, each with its rung on the ladder and whether it held up.
  static func rate(_ sessions: [Challenge]) -> [(rank: Int, heldUp: Bool, rep: Challenge)] {
    sessions.compactMap { rep in
      guard rep.lifecycle == "completed", !rep.isWarmUp, let evidence = rep.reflection?.evidence, !evidence.isEmpty,
            let rank = ladder.firstIndex(where: { $0.0 == rep.engineeringLevel }) else { return nil }
      let shown = evidence.filter { $0.signal == "demonstrated" }.count
      let gaps = evidence.filter { $0.signal == "needs_practice" }.count
      return (rank, shown > 0 && shown >= gaps, rep)
    }
  }
}

/// The next rung and what it takes, by the estimate's own rule (two reps at that level or above holding up, and at
/// least three in five of them), plus the one concept Bit would practise for it.
struct LevelPath {
  /// The level the path leads to, and whether it's about getting placed at all.
  let level: (id: String, label: String)
  let placing: Bool
  /// Reps at or above the level that held up, and all reps there.
  let held: Int
  let tried: Int
  /// Reps that count towards an estimate at all: getting placed takes `LevelEstimate.needed` of them.
  let rated: Int
  let pick: KnowledgeNode?
  /// Why this concept: what the last rep on it said, or what it is when it's new.
  let reason: String?

  static let heldNeeded = 2

  var progressLine: String {
    if placing {
      let left = max(0, LevelEstimate.needed - rated)
      return left == 1 ? "1 more rep with real design calls and Bit places you." : "\(left) more reps with real design calls and Bit places you."
    }
    if held < Self.heldNeeded { return "\(held) of \(Self.heldNeeded) reps at \(level.label) held up so far." }
    return "\(held) of \(tried) reps at \(level.label) held up. Most of them need to."
  }

  @MainActor static func from(model: AppModel, nodes: [KnowledgeNode]) -> LevelPath? {
    let ladder = LevelEstimate.ladder
    let sessions = model.memory.sessions
    let estimate = LevelEstimate.from(sessions)
    let rated = LevelEstimate.rate(sessions)
    let placing = estimate.level == nil
    let next: Int
    if let current = estimate.level.flatMap({ level in ladder.firstIndex { $0.0 == level } }) {
      guard current + 1 < ladder.count else { return nil }
      next = current + 1
    } else {
      next = ladder.firstIndex { $0.0 == model.settings.selectedLevel } ?? 2
    }
    let atOrAbove = rated.filter { $0.rank >= next }
    let (pick, reason) = choose(nodes: nodes, rated: rated)
    return LevelPath(level: ladder[next], placing: placing, held: atOrAbove.filter(\.heldUp).count, tried: atOrAbove.count,
                     rated: rated.count, pick: pick, reason: reason)
  }

  /// A gap your highest, newest reps showed first; then any concept worth another go; then one you haven't tried, from
  /// the area you've touched least; then the practised concept with the fewest reps.
  static func choose(nodes: [KnowledgeNode], rated: [(rank: Int, heldUp: Bool, rep: Challenge)]) -> (KnowledgeNode?, String?) {
    let byId = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let newestHighest = rated.sorted { ($0.rank, $0.rep.completedAt ?? "") > ($1.rank, $1.rep.completedAt ?? "") }
    for entry in newestHighest {
      for evidence in entry.rep.reflection?.evidence ?? [] where evidence.signal == "needs_practice" {
        if let node = byId[evidence.conceptId], node.state == .revisit { return (node, evidence.observation) }
      }
    }
    if let node = nodes.first(where: { $0.state == .revisit }) { return (node, node.evidence?.observation) }
    let touched = Dictionary(grouping: nodes, by: \.category).mapValues { group in group.filter { $0.state != .unexplored }.count }
    if let node = nodes.filter({ $0.state == .unexplored }).min(by: { (touched[$0.category] ?? 0) < (touched[$1.category] ?? 0) }) {
      return (node, node.description)
    }
    if let node = nodes.filter({ $0.state == .practised }).min(by: { $0.reps < $1.reps }) { return (node, node.description) }
    return (nil, nil)
  }
}

/// What the latest finished rep put on the map, in the map's own words: what held up, what's worth another go,
/// and what it touched for the first time. Nil when the rep didn't tie to any concept.
struct LastRepChange {
  let touched: Set<String>
  let line: String

  @MainActor static func from(_ model: AppModel, nodes: [KnowledgeNode]) -> LastRepChange? {
    guard let rep = model.memory.sessions.filter({ $0.lifecycle == "completed" && !$0.isWarmUp })
      .max(by: { ($0.completedAt ?? "") < ($1.completedAt ?? "") }) else { return nil }
    let evidence = rep.reflection?.evidence ?? []
    let label = { (id: String) in nodes.first { $0.id == id }?.label }
    var touched = Set(rep.conceptIds ?? [])
    if let primary = rep.primaryConceptId { touched.insert(primary) }
    touched.formUnion(evidence.map(\.conceptId))
    touched = touched.filter { label($0) != nil }
    guard !touched.isEmpty else { return nil }
    let held = unique(evidence.filter { $0.signal == "demonstrated" }.compactMap { label($0.conceptId) })
    let revisit = unique(evidence.filter { $0.signal == "needs_practice" }.compactMap { label($0.conceptId) })
      .filter { !held.contains($0) }
    var parts: [String] = []
    if !held.isEmpty { parts.append("\(list(held)) held up.") }
    if !revisit.isEmpty { parts.append("\(list(revisit)) \(revisit.count == 1 ? "is" : "are") worth another go.") }
    if parts.isEmpty {
      let labels = touched.compactMap(label).sorted()
      parts.append("\(list(labels)) \(labels.count == 1 ? "is" : "are") on your map now.")
    }
    return LastRepChange(touched: touched, line: parts.joined(separator: " "))
  }

  private static func unique(_ labels: [String]) -> [String] {
    var seen: [String] = []
    for label in labels where !seen.contains(label) { seen.append(label) }
    return seen
  }
  /// "Caching", "Caching and Queues", "Caching, Queues and 2 more".
  static func list(_ labels: [String]) -> String {
    switch labels.count {
    case 0: ""
    case 1: labels[0]
    case 2: "\(labels[0]) and \(labels[1])"
    default: "\(labels[0]), \(labels[1]) and \(labels.count - 2) more"
    }
  }
}

// MARK: - Level card

private struct LevelCard: View {
  let estimate: LevelEstimate
  let target: String
  /// The ladder (or the progress towards it) fills on arrival, one step after another.
  @State private var filled = false
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    let ladder = LevelEstimate.ladder
    let current = estimate.level.flatMap { level in ladder.firstIndex { $0.0 == level } }
    let goal = ladder.firstIndex { $0.0 == target }
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 6) {
        SignalEyebrow(text: current == nil ? "Your level" : "Working at about")
        Text(current.map { ladder[$0].1 } ?? estimate.basis)
          .font(current == nil ? .title2.weight(.semibold) : .largeTitle.weight(.semibold))
          .foregroundStyle(current == nil ? AppPalette.primary : AppPalette.accent)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("levelEstimate")
      }
      if current == nil { progress } else { ladderRow(current: current, goal: goal) }
      Text(footnote(placed: current != nil, goal: goal))
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

  /// One segment per rep the estimate needs, lit for each rep that already counts.
  private var progress: some View {
    HStack(spacing: 8) {
      ForEach(0..<LevelEstimate.needed, id: \.self) { index in
        ZStack(alignment: .leading) {
          Capsule().fill(AppPalette.hairline)
          Capsule().fill(AppPalette.action)
            .scaleEffect(x: filled && index < estimate.rated ? 1 : 0, anchor: .leading)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.32).delay(0.2 + Double(index) * 0.12), value: filled)
        }
        .frame(height: 8)
      }
    }
    .accessibilityHidden(true)
  }

  private func ladderRow(current: Int?, goal: Int?) -> some View {
    let ladder = LevelEstimate.ladder
    return HStack(spacing: 0) {
      ForEach(ladder.indices, id: \.self) { index in
        VStack(spacing: 8) {
          ZStack {
            Capsule().fill(AppPalette.hairline).frame(height: 6)
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
  }

  private func footnote(placed: Bool, goal: Int?) -> String {
    let aim = goal.map { LevelEstimate.ladder[$0].1 }
    if !placed {
      return "Only reps with real design calls count." + (aim.map { " You’re aiming for \($0)." } ?? "")
    }
    return estimate.basis + (goal != nil ? " The ring is your target." : "") + " An estimate from your reps, not a hiring call."
  }
}

// MARK: - Constellation

struct NodeDot: View {
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
struct ConstellationMap: View {
  let nodes: [KnowledgeNode]
  /// What the latest rep touched: ringed so the change is the first thing you see.
  var fresh: Set<String> = []
  @Binding var selected: String?
  let appeared: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var categories: [String] { ConstellationLayout.categories(nodes) }

  var body: some View {
    GeometryReader { proxy in
      let side = min(proxy.size.width, proxy.size.height)
      let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
      let layout = positions(side: side, center: center)
      ZStack {
        OrbitEcho(side: side)
          .frame(width: side * 1.8, height: side * 1.8)
          .position(center)
          .opacity(appeared ? 1 : 0)
        // The wires grow out from Bit on first appearance: spokes to the hubs, then the hubs' edges to each concept.
        MapWires(nodes: nodes, hubs: layout.hubs, points: layout.nodes, center: center, side: side,
                 progress: appeared || reduceMotion ? 1 : 0)
          .opacity(appeared ? 1 : 0)

        BitGlow(color: AppPalette.action, opacity: 0.16)
          .frame(width: side * 0.3, height: side * 0.3)
          .position(center)
          .opacity(appeared ? 1 : 0)
          .accessibilityHidden(true)
        BitView().frame(width: 52, height: 60).position(center).accessibilityHidden(true)

        ForEach(Array(categories.enumerated()), id: \.element) { index, category in
          if let hub = layout.hubs.first(where: { $0.0 == category })?.1 {
            // The dot sits exactly on the hub, where the spoke and the category's edges meet; the name hangs below it.
            Circle().fill(AppPalette.secondary.opacity(0.6)).frame(width: 6, height: 6)
              .overlay(alignment: .top) {
                // A halo in the page colour keeps the name legible over the spokes without boxing it in.
                Text(category).font(.caption2.weight(.semibold)).foregroundStyle(AppPalette.secondary)
                  .multilineTextAlignment(.center).lineLimit(2)
                  .shadow(color: AppPalette.background, radius: 1.5)
                  .shadow(color: AppPalette.background, radius: 3)
                  .frame(width: 96)
                  .fixedSize(horizontal: false, vertical: true)
                  .offset(y: 10)
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
                .background {
                  if fresh.contains(node.id) && !isSelected { FreshRing(size: size) }
                }
                .overlay {
                  if isSelected { Circle().stroke(AppPalette.primary, lineWidth: 1.5).frame(width: size + 14, height: size + 14) }
                }
                .frame(width: 44, height: 44)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .position(point)
            .scaleEffect(appeared || reduceMotion ? 1 : 0.4)
            .opacity(appeared ? 1 : 0)
            .animation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.35).delay(Double(index) * 0.025), value: appeared)
            .accessibilityLabel("\(node.label). \(node.statusLine)" + (fresh.contains(node.id) ? ". From your last rep" : ""))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("mapNode-\(node.id)")
          }
        }

        // The selected name floats above its dot, nudged in from the map's edges so it's never cut off.
        if let id = selected, let node = nodes.first(where: { $0.id == id }), let point = layout.nodes[id] {
          EdgeClampedLabel(anchor: CGPoint(x: point.x, y: point.y - 24), margin: 12) {
            Text(node.label).font(.caption.weight(.semibold)).foregroundStyle(AppPalette.primary)
              .fixedSize()
              .padding(.horizontal, 8).padding(.vertical, 4)
              .background(AppPalette.elevated, in: Capsule())
          }
          .frame(width: proxy.size.width, height: proxy.size.height)
          .allowsHitTesting(false)
          .accessibilityHidden(true)
          .id(id)
          .transition(.opacity)
        }
      }
    }
    .aspectRatio(1, contentMode: .fit)
    // A diagram: its labels stop growing past XXL so they fit their spots; each dot speaks its full name.
    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
  }

  private func positions(side: CGFloat, center: CGPoint) -> (hubs: [(String, CGPoint)], nodes: [String: CGPoint]) {
    ConstellationLayout.positions(nodes: nodes, side: side, center: center)
  }
}

/// Places its one subview with its bottom centre on `anchor`, shifted sideways just enough to stay `margin` inside the
/// bounds.
private struct EdgeClampedLabel: Layout {
  let anchor: CGPoint
  let margin: CGFloat
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    proposal.replacingUnspecifiedDimensions()
  }
  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    for subview in subviews {
      let half = subview.sizeThatFits(.unspecified).width / 2
      let lowest = bounds.minX + margin + half, highest = bounds.maxX - margin - half
      let x = lowest > highest ? bounds.midX : min(max(bounds.minX + anchor.x, lowest), highest)
      subview.place(at: CGPoint(x: x, y: bounds.minY + anchor.y), anchor: .bottom, proposal: .unspecified)
    }
  }
}

/// The map's orbits, spokes and edges. `progress` runs 0 to 1: spokes draw out from Bit in the first half, each
/// hub's edges to its concepts in the second.
private struct MapWires: View, @preconcurrency Animatable {
  let nodes: [KnowledgeNode]
  let hubs: [(String, CGPoint)]
  let points: [String: CGPoint]
  let center: CGPoint
  let side: CGFloat
  var progress: Double
  var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  var body: some View {
    let spokes = min(1, progress * 2)
    let edges = max(0, progress * 2 - 1)
    Canvas { context, _ in
      // Two faint orbits, hubs on the inner one and concepts on the outer, so the map reads as one system.
      for radius in [side * 0.25, side * 0.42] {
        let orbit = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.stroke(orbit, with: .color(AppPalette.hairline.opacity(0.35 * progress)), style: StrokeStyle(lineWidth: 1, dash: [2, 5]))
      }
      for (category, hub) in hubs {
        var spoke = Path(); spoke.move(to: center); spoke.addLine(to: hub)
        context.stroke(spoke.trimmedPath(from: 0, to: spokes), with: .color(AppPalette.hairline), lineWidth: 1)
        guard edges > 0 else { continue }
        for node in nodes where node.category == category {
          guard let point = points[node.id] else { continue }
          var edge = Path(); edge.move(to: hub); edge.addLine(to: point)
          let lit = node.state != .unexplored
          context.stroke(edge.trimmedPath(from: 0, to: edges),
                         with: .color(lit ? AppPalette.action.opacity(node.state == .strong ? 0.55 : 0.3) : AppPalette.hairline),
                         lineWidth: lit ? 1.5 : 1)
        }
      }
    }
  }
}

/// The map's orbits carried on past its edge, fading out, so the diagram sits in a larger system. Never moves.
private struct OrbitEcho: View {
  let side: CGFloat
  var body: some View {
    Canvas { context, size in
      let center = CGPoint(x: size.width / 2, y: size.height / 2)
      for radius in [side * 0.58, side * 0.74, side * 0.9] {
        let orbit = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.stroke(orbit, with: .color(AppPalette.primary.opacity(0.06)), style: StrokeStyle(lineWidth: 1, dash: [2, 6]))
      }
    }
    .mask(RadialGradient(colors: [.black, .black.opacity(0.6), .clear], center: .center, startRadius: side * 0.4, endRadius: side * 0.9))
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

/// A ring around a concept the last rep touched. It ripples out twice on arrival to point the change out, then
/// rests as a still ring; with reduced motion it is only the still ring.
private struct FreshRing: View {
  let size: CGFloat
  @State private var ripples = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    ZStack {
      Circle().stroke(AppPalette.action.opacity(0.8), lineWidth: 1.5)
      Circle().stroke(AppPalette.action, lineWidth: 1.5)
        .keyframeAnimator(initialValue: 0.0, trigger: ripples) { ring, t in
          ring.scaleEffect(1 + t * 0.7).opacity(t == 0 ? 0 : 1 - t)
        } keyframes: { _ in
          KeyframeTrack(\.self) { LinearKeyframe(0, duration: 0); CubicKeyframe(1, duration: 1.4); LinearKeyframe(0, duration: 0) }
        }
    }
    .frame(width: size + 10, height: size + 10)
    .task {
      guard !reduceMotion else { return }
      for _ in 0..<2 {
        try? await Task.sleep(for: .seconds(1))
        ripples += 1
        try? await Task.sleep(for: .seconds(0.6))
      }
    }
    .accessibilityHidden(true)
  }
}

/// Where the map's hubs and dots sit on the Bit tab.
enum ConstellationLayout {
  static func categories(_ nodes: [KnowledgeNode]) -> [String] {
    var seen: [String] = []
    for node in nodes where !seen.contains(node.category) { seen.append(node.category) }
    return seen
  }
  /// Hubs on an inner ring, one per category; each category's concepts fan out on the outer ring within its slice.
  static func positions(nodes: [KnowledgeNode], side: CGFloat, center: CGPoint) -> (hubs: [(String, CGPoint)], nodes: [String: CGPoint]) {
    let groups = Self.categories(nodes)
    let count = max(1, groups.count)
    let slice = 2 * Double.pi / Double(count)
    let inner = side * 0.25, outer = side * 0.42
    var hubs: [(String, CGPoint)] = []
    var points: [String: CGPoint] = [:]
    for (index, category) in groups.enumerated() {
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
