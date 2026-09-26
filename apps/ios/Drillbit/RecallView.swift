import SwiftUI

enum RecallArea: String, CaseIterable, Identifiable {
  case all = "All areas"
  case systemDesign = "System design"
  case swift = "Swift"
  case typeScript = "TypeScript"
  case sql = "SQL"
  case networking = "Networking"

  var id: Self { self }
}

enum RecallDepth: String, CaseIterable, Identifiable {
  case all = "Any depth"
  case foundations = "Foundations"
  case practical = "Practical"
  case deep = "Deep dive"

  var id: Self { self }
}

struct RecallCard: Identifiable, Equatable {
  let id: String
  let area: RecallArea
  let depth: RecallDepth
  let question: String
  let answer: String
  var conceptId: String? = nil
}

struct RecallSession: Equatable {
  private(set) var queue: [RecallCard]
  private(set) var knownCount = 0
  private(set) var againCount = 0
  private(set) var isRevealed = false

  init(area: RecallArea = .all, depth: RecallDepth = .all) {
    queue = Self.filteredCards(area: area, depth: depth)
  }

  init(cards: [RecallCard]) { queue = cards }

  var current: RecallCard? { queue.first }
  var remainingCount: Int { queue.count }

  mutating func reveal() {
    guard current != nil else { return }
    isRevealed = true
  }

  mutating func markKnown() {
    guard isRevealed, !queue.isEmpty else { return }
    queue.removeFirst()
    knownCount += 1
    isRevealed = false
  }

  mutating func markAgain() {
    guard isRevealed, !queue.isEmpty else { return }
    let card = queue.removeFirst()
    queue.append(card)
    againCount += 1
    isRevealed = false
  }

  mutating func finishCurrent(again: Bool) {
    guard isRevealed, !queue.isEmpty else { return }
    queue.removeFirst()
    if again { againCount += 1 } else { knownCount += 1 }
    isRevealed = false
  }

  mutating func reset(area: RecallArea, depth: RecallDepth) {
    self = RecallSession(area: area, depth: depth)
  }

  private static func filteredCards(area: RecallArea, depth: RecallDepth) -> [RecallCard] {
    RecallCatalog.cards.filter { card in
      (area == .all || card.area == area) && (depth == .all || card.depth == depth)
    }
  }
}

enum RecallCatalog {
  static let cards: [RecallCard] = [
    .init(id: "sd-load-balancer", area: .systemDesign, depth: .foundations,
          question: "What problem does a load balancer solve?",
          answer: "It spreads requests across healthy service instances, preventing one instance from taking all traffic. It also creates one stable entry point for health checks, failover and routing policy.", conceptId: "load-balancing"),
    .init(id: "sd-cache", area: .systemDesign, depth: .practical,
          question: "When would you choose cache-aside?",
          answer: "Use it when the application can tolerate a miss and should control what enters the cache. Reads check the cache, fetch from the source on a miss and then populate it; writes must invalidate or update cached values.", conceptId: "caching"),
    .init(id: "sd-backpressure", area: .systemDesign, depth: .deep,
          question: "How does backpressure keep an overloaded system stable?",
          answer: "It makes producers slow down, shed work or wait when consumers cannot keep up. Bounded queues, admission control and explicit retry signals prevent unbounded memory growth and cascading timeouts.", conceptId: "backpressure"),
    .init(id: "swift-value-reference", area: .swift, depth: .foundations,
          question: "How do value and reference semantics differ in Swift?",
          answer: "Structs and enums are copied as independent values, while classes share identity through references. Swift collections use copy-on-write so value semantics usually avoid an immediate full copy."),
    .init(id: "swift-actor", area: .swift, depth: .practical,
          question: "What does actor isolation protect?",
          answer: "An actor serializes access to its isolated mutable state. Calls from outside its isolation domain generally cross an async boundary, preventing unsynchronized concurrent mutation."),
    .init(id: "swift-sendable", area: .swift, depth: .deep,
          question: "Why does Swift use Sendable checking?",
          answer: "Sendable marks values that can safely cross concurrency domains. Strict checking catches references or mutable state that could otherwise be shared across tasks without synchronization."),
    .init(id: "ts-unknown", area: .typeScript, depth: .foundations,
          question: "Why prefer unknown over any?",
          answer: "Unknown accepts any input but forces you to narrow its type before use. Any disables those checks and lets unsafe operations pass through the type system."),
    .init(id: "ts-discriminated-union", area: .typeScript, depth: .practical,
          question: "What makes a discriminated union useful?",
          answer: "A shared literal field lets TypeScript narrow each variant reliably. This models state transitions clearly and enables exhaustive handling with a never check."),
    .init(id: "ts-variance", area: .typeScript, depth: .deep,
          question: "What does variance describe in a generic type?",
          answer: "Variance describes how assignability changes when a generic parameter becomes more or less specific. Producers tend to be covariant, consumers contravariant and mutable containers often invariant."),
    .init(id: "sql-index", area: .sql, depth: .foundations,
          question: "What does a database index trade?",
          answer: "It trades extra storage and write maintenance for faster reads. The useful index shape follows actual filters, joins and ordering rather than simply indexing every column."),
    .init(id: "sql-composite", area: .sql, depth: .practical,
          question: "Why does column order matter in a composite index?",
          answer: "A B-tree is ordered from its leading columns onward. Queries can efficiently use a matching leftmost prefix, so equality filters usually precede range or ordering columns."),
    .init(id: "sql-isolation", area: .sql, depth: .deep,
          question: "What anomaly does serializable isolation prevent?",
          answer: "Serializable isolation prevents outcomes that could not occur if transactions ran one at a time. It covers anomalies such as write skew that snapshot isolation can still allow."),
    .init(id: "net-tcp", area: .networking, depth: .foundations,
          question: "What does TCP add above IP?",
          answer: "TCP adds an ordered, reliable byte stream with connection state, retransmission, flow control and congestion control. IP itself provides best-effort packet delivery."),
    .init(id: "net-tls", area: .networking, depth: .practical,
          question: "What does the TLS handshake establish?",
          answer: "It authenticates the server, negotiates protocol parameters and derives shared session keys. Application data can then be encrypted and integrity protected."),
    .init(id: "net-hol", area: .networking, depth: .deep,
          question: "How does HTTP/3 reduce head-of-line blocking?",
          answer: "HTTP/3 runs over QUIC, where independent streams do not all wait for one lost packet to be retransmitted. Loss still pauses the affected stream, while others can continue."),
  ]
}

private enum RecallSection: String, CaseIterable, Identifiable {
  case review = "Review", map = "Map", paths = "Paths"
  var id: Self { self }
}

private struct LearningPath: Identifiable {
  let id: String, title: String, detail: String
  let concepts: [String]
}

struct RecallView: View {
  @Bindable var model: AppModel
  @State private var section = RecallSection.review
  @State private var area: RecallArea = .all
  @State private var depth: RecallDepth = .all
  @State private var session: RecallSession
  @State private var deckSignature: String
  @State private var revealedAt: Date?
  @State private var feedbackPulse = 0
  @State private var selectedPath: LearningPath?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(model: AppModel) {
    self.model = model
    _session = State(initialValue: RecallSession(cards: Self.dueCards(from: model.recall)))
    _deckSignature = State(initialValue: Self.signature(model.recall))
  }

  private let paths = [
    LearningPath(id:"foundations",title:"System design foundations",detail:"Model data, shape APIs, then make reads fast.",concepts:["data-modeling","api-design","caching"]),
    LearningPath(id:"scale",title:"Data at scale",detail:"Indexes, consistency, replication and partitioning.",concepts:["indexing","transactions","consistency","replication","partitioning"]),
    LearningPath(id:"async",title:"Reliable async systems",detail:"Queues, safe retries, backpressure and recovery.",concepts:["queues","retry-safety","backpressure","fault-tolerance"]),
    LearningPath(id:"production",title:"Production readiness",detail:"Capacity, observability and authorization.",concepts:["capacity-planning","observability","authorization"]),
  ]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Picker("Recall section", selection: $section) {
          ForEach(RecallSection.allCases) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.segmented)
        switch section {
        case .review: deck
        case .map: skillMap
        case .paths: learningPaths
        }
      }
      .padding(.horizontal, 20).padding(.vertical, 16)
      .frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity)
    }
    .background(AppPalette.groupedBackground)
    .navigationTitle("Recall")
    .animation(reduceMotion ? nil : DrillbitMotion.disclosure, value: session.isRevealed)
    .sensoryFeedback(.success, trigger: feedbackPulse)
    .onAppear { configureDeck() }
    .onChange(of: model.recall.cards) { _, _ in configureDeck() }
    .onDisappear {
      guard selectedPath == nil else { return }
      deckSignature = Self.signature(model.recall)
      session = RecallSession(cards: cardsForSelection())
    }
  }

  private var deck: some View {
    VStack(alignment: .leading, spacing: 20) {
      if let card = session.current {
        SignalEyebrow(text: "One live idea")
        status
        cardView(card)
      } else {
        completion
      }
    }
  }

  private var filters: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 12) { areaMenu; depthMenu }
      VStack(spacing: 12) { areaMenu; depthMenu }
    }
  }

  private var areaMenu: some View {
    Menu {
      Picker("Area", selection: $area) {
        ForEach(RecallArea.allCases) { Text($0.rawValue).tag($0) }
      }
    } label: {
      filterLabel(title: "Area", value: area.rawValue)
    }
    .accessibilityIdentifier("recallAreaPicker")
    .onChange(of: area) { _, _ in resetSession() }
  }

  private var depthMenu: some View {
    Menu {
      Picker("Depth", selection: $depth) {
        ForEach(RecallDepth.allCases) { Text($0.rawValue).tag($0) }
      }
    } label: {
      filterLabel(title: "Depth", value: depth.rawValue)
    }
    .accessibilityIdentifier("recallDepthPicker")
    .onChange(of: depth) { _, _ in resetSession() }
  }

  private func filterLabel(title: String, value: String) -> some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.caption).foregroundStyle(.secondary)
        Text(value).font(.body.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
      }
      Spacer(minLength: 8)
      Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold))
    }
    .padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 56)
    .background(AppPalette.inset, in: RoundedRectangle(cornerRadius: 12))
    .contentShape(Rectangle())
  }

  private var status: some View {
    let due = model.recall.dueCount
    let recommended = min(due, model.bootstrap?.todayPlan?.recommendedRecallCount ?? due)
    let minutes = Int(ceil(Double(max(recommended, 0)) / 2.0))
    return Text(due > recommended && recommended > 0 ? "\(due) due · start with \(recommended) · about \(minutes) minutes" : "\(due) due · about \(minutes) minutes")
      .font(.headline).accessibilityLabel("\(due) due, about \(minutes) minutes")
  }

  private func cardView(_ card: RecallCard) -> some View {
    VStack(alignment: .leading, spacing: 20) {
      SignalEyebrow(text: "From your interview")
      DrillbitMetadata(text: "\(card.area.rawValue) · \(card.depth.rawValue)")
      if let source = model.recall.cards.first(where: { $0.id == card.id }) {
        Text(source.sourceTitle ?? "From this interview").font(.subheadline.weight(.medium))
        if let date = source.sourceCompletedAt.flatMap(Date.fromAPI) { Text(date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary) }
        Text(source.evidence?.signal == "demonstrated" ? "Demonstrated evidence" : source.evidence?.signal == "needs_practice" ? "Worth revisiting" : "From this interview")
          .font(.caption).foregroundStyle(.secondary)
      }
      Text(card.question)
        .font(.largeTitle.weight(.semibold)).tracking(-0.8)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("recallQuestion")

      Rectangle().fill(AppPalette.action).frame(height: 2)

      if session.isRevealed {
        Divider()
        VStack(alignment: .leading, spacing: 8) {
          Text("Answer").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
          Text(card.answer).font(.body).fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("recallAnswer")

        HStack(spacing: 12) {
          Button("Again") { review(card, again: true) }
            .buttonStyle(PracticeButtonStyle(secondary: true))
            .accessibilityIdentifier("recallAgain")
            .accessibilityHint("Returns this card to the end of the current deck")
          Button("Got it") { review(card, again: false) }
            .buttonStyle(PracticeButtonStyle())
            .accessibilityIdentifier("recallGotIt")
            .accessibilityHint("Removes this card from the current deck")
        }
      } else {
        Button("Reveal answer") { revealedAt = Date(); session.reveal() }
          .buttonStyle(PracticeButtonStyle())
          .accessibilityIdentifier("recallReveal")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var completion: some View {
    VStack(alignment: .leading, spacing: 16) {
      SignalEyebrow(text: model.recallLoaded || model.fixture ? "Nothing due" : "Recall")
      Text(completionTitle)
        .font(.title.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
      if model.recallLoaded || model.fixture {
        Text(model.bootstrap?.todayPlan?.completedTotal == 0 ? "Finish an interview to bring its useful moments into Recall." : "New ideas will appear here when they are ready to revisit.")
          .foregroundStyle(AppPalette.secondary)
      }
    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 32)
  }

  private var completionTitle: String {
    if !model.recallLoaded && !model.fixture { return "Your review will appear here." }
    if model.bootstrap?.todayPlan?.completedTotal == 0 { return "Your first idea starts with a practice." }
    return "You’re caught up."
  }

  private func resetSession() {
    selectedPath = nil
    session = RecallSession(cards: cardsForSelection())
  }

  private func configureDeck() {
    let currentSignature = Self.signature(model.recall)
    guard currentSignature != deckSignature, selectedPath == nil,
      !session.isRevealed, session.knownCount == 0, session.againCount == 0 else { return }
    deckSignature = currentSignature
    session = RecallSession(cards: cardsForSelection())
  }

  private static func signature(_ deck: RecallDeckResponse) -> String {
    deck.cards.map { $0.id + ":" + $0.updatedAt }.joined(separator: "|")
  }

  private static func dueCards(from deck: RecallDeckResponse) -> [RecallCard] {
    deck.cards.filter { Date.fromAPI($0.dueAt).map { $0 <= Date() } ?? true }.map { item in
      RecallCard(id:item.id, area:.systemDesign, depth:item.repetitions == 0 ? .practical : .deep,
        question:item.question, answer:item.answer, conceptId:item.conceptId)
    }
  }

  private func cardsForSelection() -> [RecallCard] {
    let due = Self.dueCards(from: model.recall)
    let pathIDs = Set(selectedPath?.concepts ?? [])
    let temporary = RecallCatalog.cards.filter { card in
      (area == .all || card.area == area) && (depth == .all || card.depth == depth)
        && selectedPath != nil && card.conceptId.map { pathIDs.contains($0) } == true
    }
    return selectedPath == nil ? due : temporary
  }

  private func review(_ card: RecallCard, again: Bool) {
    let responseMs = revealedAt.map { Int(Date().timeIntervalSince($0) * 1000) }
    revealedAt = nil
    if let cloud = model.recall.cards.first(where: { $0.id == card.id }) {
      session.finishCurrent(again: again)
      Task { await model.perform { try await model.reviewRecall(cloud, rating: again ? "again" : "got_it", responseMs: responseMs) } }
    } else if again { session.markAgain() } else { session.markKnown() }
    if !again { feedbackPulse += 1 }
  }

  private var skillMap: some View {
    VStack(alignment: .leading, spacing: 16) {
      DrillbitSectionHeader(title: "Your system design map", eyebrow: "Evidence, not scores")
      ForEach(groupedConcepts, id: \.0) { category, concepts in
        VStack(alignment: .leading, spacing: 0) {
          SignalEyebrow(text: category).padding(.bottom, 8)
          ForEach(concepts) { concept in
            let coverage = model.libraryCoverage.first { $0.conceptId == concept.id }
            let evidence = model.memory.evidence?.first { $0.conceptId == concept.id }
            HStack(alignment: .top, spacing: 12) {
              Image(systemName: evidence?.signal == "demonstrated" ? "checkmark.circle" : evidence?.signal == "needs_practice" ? "arrow.clockwise.circle" : "circle")
                .foregroundStyle(evidence == nil ? .tertiary : .primary).frame(width: 20)
              VStack(alignment: .leading, spacing: 3) {
                Text(concept.label).font(.body.weight(.medium))
                Text(mapStatus(concept: concept, coverage: coverage, evidence: evidence)).font(.subheadline).foregroundStyle(.secondary)
              }
              Spacer()
            }.padding(.vertical, 10)
            if concept.id != concepts.last?.id { Divider().padding(.leading, 32) }
          }
        }
        Divider()
      }
    }
  }

  private var groupedConcepts: [(String,[PracticeConcept])] {
    let values = PracticeAreaCatalog.curated(model.taxonomy)
    return Dictionary(grouping: values, by: \.category).sorted { $0.key < $1.key }
  }

  private func mapStatus(concept: PracticeConcept, coverage: CoverageResponse.Entry?, evidence: LearningEvidence?) -> String {
    if let evidence { return evidence.signal == "demonstrated" ? "Demonstrated in your latest evidence" : "Worth revisiting" }
    guard let count = coverage?.completedAttempts, count > 0 else {
      return concept.description ?? "A core system design decision."
    }
    return "Practised in \(count) completed \(count == 1 ? "session" : "sessions")"
  }

  private var learningPaths: some View {
    VStack(alignment: .leading, spacing: 16) {
      DrillbitSectionHeader(title: "Choose a path", eyebrow: "Focused sets")
      ForEach(paths) { path in
        Button {
          selectedPath = path; section = .review; session = RecallSession(cards: cardsForSelection())
        } label: {
          HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
              Text(path.title).font(.headline).foregroundStyle(.primary)
              Text(path.detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
            }
            Spacer(); Image(systemName: "arrow.right").foregroundStyle(.secondary)
          }.padding(.vertical, 16)
        }.buttonStyle(.plain)
        Divider()
      }
      VStack(alignment: .leading, spacing: 8) {
        Text("Language deep dives").font(.headline)
        Text("Swift, TypeScript, SQL and networking are available from the Area filter in Deck.")
          .font(.subheadline).foregroundStyle(.secondary)
      }.padding(.vertical, 12)
    }
  }
}
