import SwiftUI

/// A step in the practice sheet: an area of the map, then one of its concepts.
enum TopicStep: Hashable {
  case area(String)
  case topic(String)
}

/// The Bit map's categories as places to practise: the same names, order and concepts, so the sheet reads like the map.
struct TopicArea: Identifiable {
  let id: String
  let detail: String
  let symbol: String
  let concepts: [PracticeConcept]

  var slug: String { String(id.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }) }

  private static let about: [String: (detail: String, symbol: String)] = [
    "Data": ("How data is shaped, stored and kept right", "externaldrive"),
    "Traffic & performance": ("APIs, caches and holding up under load", "speedometer"),
    "Async & coordination": ("Queues, retries and doing things in order", "arrow.triangle.branch"),
    "Reliability & operations": ("Failures, overload and shipping safely", "waveform.path.ecg"),
    "System boundaries": ("Who gets in, whose data, which region, what it costs", "point.3.connected.trianglepath.dotted"),
  ]

  static func all(_ taxonomy: [PracticeConcept]) -> [TopicArea] {
    var order: [String] = []
    for concept in taxonomy where !order.contains(concept.category) { order.append(concept.category) }
    return order.map { category in
      TopicArea(id: category, detail: about[category]?.detail ?? "", symbol: about[category]?.symbol ?? "square.grid.2x2",
                concepts: taxonomy.filter { $0.category == category })
    }
  }
}

/// What the sheet knows about you: the map's view of each concept, and Bit's pick for your next level.
struct TopicContext {
  let nodes: [String: KnowledgeNode]
  let path: LevelPath?

  @MainActor init(model: AppModel) {
    let built = KnowledgeNode.build(model: model)
    nodes = Dictionary(built.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    path = LevelPath.from(model: model, nodes: built)
  }
  func state(_ id: String) -> KnowledgeNode.State { nodes[id]?.state ?? .unexplored }
}

// MARK: - Every area

struct TopicAreasPage: View {
  let model: AppModel
  let context: TopicContext
  @Binding var customTopic: String
  let useCustom: () -> Void
  @State private var search = ""
  @FocusState private var typingTopic: Bool

  var body: some View {
    let areas = TopicArea.all(model.taxonomy)
    ScrollViewReader { scroller in
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        if search.isEmpty {
          if let path = context.path, let pick = path.pick {
            NavigationLink(value: TopicStep.topic(pick.id)) { PickShortcut(pick: pick, level: path.level.label) }
              .buttonStyle(TicketPressStyle())
              .accessibilityIdentifier("browse-pick")
          }
          VStack(spacing: 12) {
            ForEach(areas) { area in
              NavigationLink(value: TopicStep.area(area.id)) { TopicAreaCard(area: area, context: context) }
                .buttonStyle(TicketPressStyle())
                .accessibilityIdentifier("browse-area-" + area.slug)
            }
          }
          CustomTopicCard(topic: $customTopic, focused: $typingTopic, use: useCustom)
            .id("customTopic")
        } else {
          results
        }
      }
      .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32)
      .frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity)
    }
    .background(AppPalette.background)
    .scrollDismissesKeyboard(.interactively)
    // The field sits at the bottom of the page: once the keyboard is up, bring the whole card above it.
    .onChange(of: typingTopic) { _, typing in
      guard typing else { return }
      Task {
        try? await Task.sleep(for: .milliseconds(350))
        withAnimation(DrillbitMotion.reveal) { scroller.scrollTo("customTopic", anchor: .bottom) }
      }
    }
    }
    .searchable(text: $search, prompt: "Find a topic")
    .navigationTitle("Pick a topic")
  }

  @ViewBuilder private var results: some View {
    let query = search.trimmingCharacters(in: .whitespaces)
    let matches = model.taxonomy.filter { concept in
      concept.label.localizedCaseInsensitiveContains(query)
        || concept.aliases.contains { $0.localizedCaseInsensitiveContains(query) }
        || (concept.description ?? "").localizedCaseInsensitiveContains(query)
    }
    if matches.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        Text("Nothing on the map called that.").font(.headline).foregroundStyle(AppPalette.primary)
        Text("Use it as your own topic and Bit builds the question around it.")
          .font(.subheadline).foregroundStyle(AppPalette.secondary)
        Button("Use “\(query)”") { customTopic = query; useCustom() }
          .buttonStyle(PracticeButtonStyle(secondary: true))
      }
    } else {
      TopicRows(concepts: matches, context: context, showsArea: true)
    }
  }
}

/// Bit's pick, one tap from the top of the sheet.
private struct PickShortcut: View {
  let pick: KnowledgeNode
  let level: String
  var body: some View {
    HStack(spacing: 12) {
      NodeDot(state: pick.state, size: 12, glow: false).frame(width: 16)
      VStack(alignment: .leading, spacing: 2) {
        Text(pick.label).font(.headline).foregroundStyle(AppPalette.primary)
        Text("Bit’s pick for \(level)").font(.subheadline).foregroundStyle(AppPalette.secondary)
      }
      Spacer(minLength: 8)
      Chevron()
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .ticketCard()
    .accessibilityElement(children: .combine)
  }
}

private struct TopicAreaCard: View {
  let area: TopicArea
  let context: TopicContext
  var body: some View {
    let tried = area.concepts.filter { context.state($0.id) != .unexplored }.count
    let revisit = area.concepts.filter { context.state($0.id) == .revisit }.count
    HStack(alignment: .top, spacing: 16) {
      TopicSymbol(symbol: area.symbol)
      VStack(alignment: .leading, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text(area.id).font(.headline).foregroundStyle(AppPalette.primary)
          Text(area.detail).font(.subheadline).foregroundStyle(AppPalette.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        let dots = HStack(spacing: 4) {
          ForEach(area.concepts) { concept in NodeDot(state: context.state(concept.id), size: 8, glow: false) }
        }
        .accessibilityHidden(true)
        let line = Text(Self.progress(tried: tried, of: area.concepts.count, revisit: revisit))
          .font(.caption).foregroundStyle(AppPalette.secondary)
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 8) { dots; line.fixedSize() }
          VStack(alignment: .leading, spacing: 6) { dots; line.fixedSize(horizontal: false, vertical: true) }
        }
      }
      Spacer(minLength: 8)
      Chevron().padding(.top, 12)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .ticketCard()
    .accessibilityElement(children: .combine)
  }

  static func progress(tried: Int, of total: Int, revisit: Int) -> String {
    guard tried > 0 else { return "Nothing tried yet" }
    return "\(tried) of \(total) tried" + (revisit > 0 ? " · \(revisit) worth another go" : "")
  }
}

private struct CustomTopicCard: View {
  @Binding var topic: String
  var focused: FocusState<Bool>.Binding
  let use: () -> Void
  private var trimmed: String { topic.trimmingCharacters(in: .whitespacesAndNewlines) }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Something else in mind?").font(.headline).foregroundStyle(AppPalette.primary)
      TextField("For example, search ranking", text: $topic)
        .focused(focused)
        .submitLabel(.go)
        .onSubmit { if !trimmed.isEmpty { use() } }
        .padding(12)
        .background(AppPalette.inset, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("customTopic")
      Button("Use this topic", action: use)
        .buttonStyle(PracticeButtonStyle(secondary: true))
        .disabled(trimmed.isEmpty)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .ticketCard(quiet: true)
  }
}

// MARK: - One area

struct TopicAreaPage: View {
  let area: TopicArea
  let context: TopicContext
  var body: some View {
    let tried = area.concepts.filter { context.state($0.id) != .unexplored }.count
    let revisit = area.concepts.filter { context.state($0.id) == .revisit }.count
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        PageHeader(title: area.id)
        HStack(alignment: .center, spacing: 16) {
          TopicSymbol(symbol: area.symbol)
          VStack(alignment: .leading, spacing: 4) {
            Text(area.detail).font(.subheadline).foregroundStyle(AppPalette.primary)
              .fixedSize(horizontal: false, vertical: true)
            Text(TopicAreaCard.progress(tried: tried, of: area.concepts.count, revisit: revisit))
              .font(.footnote).foregroundStyle(AppPalette.secondary)
          }
        }
        .accessibilityElement(children: .combine)
        TopicRows(concepts: area.concepts, context: context, showsArea: false)
      }
      .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32)
      .frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity)
    }
    .background(AppPalette.background)
    .navigationBarTitleDisplayMode(.inline)
  }
}

/// Concepts as one card of rows, each with its dot and status from the map.
private struct TopicRows: View {
  let concepts: [PracticeConcept]
  let context: TopicContext
  let showsArea: Bool
  var body: some View {
    VStack(spacing: 0) {
      ForEach(concepts) { concept in
        if concept.id != concepts.first?.id { Divider().overlay(AppPalette.hairline).padding(.leading, 44) }
        NavigationLink(value: TopicStep.topic(concept.id)) { row(concept) }
          .buttonStyle(TicketPressStyle())
          .accessibilityIdentifier("browse-topic-" + concept.id)
      }
    }
    .ticketCard()
  }

  private func row(_ concept: PracticeConcept) -> some View {
    let node = context.nodes[concept.id]
    let state = node?.state ?? .unexplored
    return HStack(alignment: .top, spacing: 12) {
      NodeDot(state: state, size: 12, glow: false).frame(width: 16, height: 22)
      VStack(alignment: .leading, spacing: 4) {
        Text(concept.label).font(.body.weight(.medium)).foregroundStyle(AppPalette.primary)
          .fixedSize(horizontal: false, vertical: true)
        Text((showsArea ? concept.category + " · " : "") + (node?.statusLine ?? "Not explored yet"))
          .font(.subheadline).foregroundStyle(state == .strong || state == .revisit ? AppPalette.accent : AppPalette.secondary)
      }
      Spacer(minLength: 8)
      Chevron().padding(.top, 4)
    }
    .padding(.horizontal, 16).padding(.vertical, 12)
    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}

// MARK: - One concept

struct TopicPage: View {
  let model: AppModel
  let concept: PracticeConcept
  let context: TopicContext
  let suggestedLevel: String?
  let write: (PreparationInput) -> Void
  @State private var level = ""

  var body: some View {
    let node = context.nodes[concept.id]
    let state = node?.state ?? .unexplored
    let busy = model.busy || model.bootstrap?.challenge?.lifecycle == "in_progress"
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .leading, spacing: 12) {
          PageHeader(title: concept.label)
          HStack(spacing: 10) {
            if let node, state != .unexplored { RepTrail(states: FixNext.trail(node, reps: completedReps), delay: 0.2) }
            else { NodeDot(state: state, size: 10, glow: false) }
            DrillbitMetadata(text: concept.category)
          }
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(concept.category + ", " + (node?.statusLine ?? "Not explored yet"))
          if let description = concept.description {
            Text(description).font(.body).foregroundStyle(AppPalette.primary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        if let evidence = node?.evidence {
          VStack(alignment: .leading, spacing: 6) {
            Text(evidence.signal == "demonstrated" ? "Held up last time" : "Last time").font(.footnote.weight(.semibold))
              .foregroundStyle(AppPalette.secondary)
            Text(evidence.observation).font(.subheadline).foregroundStyle(AppPalette.primary)
              .lineLimit(3).fixedSize(horizontal: false, vertical: true)
          }
          .padding(.leading, 14)
          .overlay(alignment: .leading) { Capsule().fill(evidence.signal == "demonstrated" ? AppPalette.action : AppPalette.hairline).frame(width: 2) }
          .accessibilityElement(children: .combine)
        }
        LevelLadder(selection: $level, suggested: suggestedLevel)
      }
      .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
      .frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity)
    }
    .background(AppPalette.background)
    .navigationBarTitleDisplayMode(.inline)
    .safeAreaInset(edge: .bottom) {
      VStack(spacing: 8) {
        Button("Write my question") { write(input) }
          .buttonStyle(PracticeButtonStyle())
          .disabled(busy || level.isEmpty)
          .accessibilityIdentifier("submitPreparation")
        if let note = footnote {
          Text(note).font(.footnote).foregroundStyle(AppPalette.secondary).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(16)
      .background(AppPalette.background)
    }
    .onAppear { if level.isEmpty { level = suggestedLevel ?? model.settings.selectedLevel } }
  }

  private var completedReps: [Challenge] {
    model.memory.sessions.filter { $0.lifecycle == "completed" && !$0.isWarmUp }
      .sorted { ($0.completedAt ?? "") > ($1.completedAt ?? "") }
  }

  private var input: PreparationInput {
    // Session style follows the last real session, like the daily question; the interview's own menu still changes it.
    PreparationInput(
      primaryConceptId: concept.id, guidanceMode: model.memory.sessions.first { !$0.isWarmUp }?.guidanceMode,
      interviewStyle: .standard, focus: "System design", kind: "design", difficulty: model.settings.difficulty,
      engineeringLevel: level, replaceId: model.bootstrap?.challenge?.lifecycle == "ready" ? model.bootstrap?.challenge?.id : nil)
  }

  /// Only when the button can't be used: it says why.
  private var footnote: String? {
    model.bootstrap?.challenge?.lifecycle == "in_progress" ? "Finish or skip your current interview first." : nil
  }
}

// MARK: - Pieces

/// The question's level as the ladder itself: six rungs, the chosen one lit gold and sliding as you pick. Bit's
/// suggestion carries a small gold dot instead of a sentence.
private struct LevelLadder: View {
  @Binding var selection: String
  let suggested: String?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private static let gap: CGFloat = 4
  /// Each rung a little taller than the last: the ladder reads as a climb.
  private static func height(_ index: Int) -> CGFloat { 14 + CGFloat(index) * 5 }

  var body: some View {
    let levels = EngineeringLevel.choices
    let chosen = levels.firstIndex { $0.0 == selection } ?? 0
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Text("Question level").font(.footnote.weight(.semibold)).foregroundStyle(AppPalette.secondary)
        Spacer(minLength: 8)
        Text(levels[chosen].1).font(.headline).foregroundStyle(AppPalette.primary)
          .contentTransition(.opacity)
      }
      VStack(spacing: 6) {
        HStack(spacing: Self.gap) {
          ForEach(levels, id: \.0) { level in
            Circle().fill(AppPalette.action).frame(width: 5, height: 5)
              .opacity(level.0 == suggested ? 1 : 0)
              .frame(maxWidth: .infinity)
          }
        }
        // The rungs never change shape; one gold piece slides and resizes over them, so nothing fades in or out.
        HStack(alignment: .bottom, spacing: Self.gap) {
          ForEach(Array(levels.indices), id: \.self) { index in
            RoundedRectangle(cornerRadius: 4).fill(index < chosen ? AppPalette.elevated : AppPalette.inset)
              .frame(maxWidth: .infinity)
              .frame(height: Self.height(index))
          }
        }
        .overlay(alignment: .bottomLeading) {
          GeometryReader { proxy in
            let width = (proxy.size.width - Self.gap * CGFloat(levels.count - 1)) / CGFloat(levels.count)
            RoundedRectangle(cornerRadius: 4).fill(AppPalette.action)
              .frame(width: width, height: Self.height(chosen))
              .offset(x: CGFloat(chosen) * (width + Self.gap), y: proxy.size.height - Self.height(chosen))
          }
        }
        HStack(spacing: Self.gap) {
          ForEach(Array(levels.enumerated()), id: \.element.0) { index, level in
            // One weight for every label, so the chosen one changes colour without reflowing.
            Text(level.1).font(.caption2.weight(.medium))
              .foregroundStyle(index == chosen ? AppPalette.primary : AppPalette.secondary)
              .lineLimit(1).minimumScaleFactor(0.7)
              .frame(maxWidth: .infinity)
          }
        }
      }
      .animation(reduceMotion ? nil : .smooth(duration: 0.32), value: chosen)
      // Whole columns are the tap targets, laid over the drawing.
      .overlay {
        HStack(spacing: Self.gap) {
          ForEach(Array(levels.enumerated()), id: \.element.0) { index, level in
            Button { selection = level.0 } label: {
              Color.clear.frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(level.1 + (level.0 == suggested ? ", Bit’s pick" : ""))
            .accessibilityAddTraits(index == chosen ? .isSelected : [])
            .accessibilityIdentifier("level-" + level.0)
          }
        }
      }
    }
    .padding(16)
    .ticketCard()
    .sensoryFeedback(.selection, trigger: selection)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("prepareLevel")
  }
}

/// A page title that wraps: concept and area names run long, and a large navigation title cuts them off.
private struct PageHeader: View {
  let title: String
  var body: some View {
    Text(title).font(.largeTitle.weight(.bold)).foregroundStyle(AppPalette.primary)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityAddTraits(.isHeader)
  }
}

private struct TopicSymbol: View {
  let symbol: String
  var body: some View {
    Image(systemName: symbol).font(.title3).foregroundStyle(AppPalette.accent)
      .frame(width: 44, height: 44)
      .background(AppPalette.elevated, in: RoundedRectangle(cornerRadius: 12))
      .accessibilityHidden(true)
  }
}

private struct Chevron: View {
  var body: some View {
    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(AppPalette.secondary)
      .accessibilityHidden(true)
  }
}

extension View {
  /// The ticket surface the Bit tab's cards use; quiet for secondary cards.
  func ticketCard(quiet: Bool = false) -> some View {
    background(AppPalette.ticket.opacity(quiet ? 0.5 : 1), in: RoundedRectangle(cornerRadius: 12))
      .overlay { RoundedRectangle(cornerRadius: 12).stroke(AppPalette.ticketEdge, lineWidth: 1) }
  }
}
