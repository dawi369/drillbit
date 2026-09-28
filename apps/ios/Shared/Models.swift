import Foundation

struct PracticeProfile: Codable, Equatable, Sendable {
  var goals = ""
  var background = ""
  var preferences = ""
}
struct LearningPlan: Codable, Equatable, Sendable {
  var version = 1
  var objective = "learn"
  var roleTrack = "general"
  var weakAreas: [String] = []
  var dailyGoalMinutes = 10
  var targetDate: String? = nil
}

/// Device-local onboarding progress is account-scoped, never tied to a generated question.
struct FirstUseProgress: Codable, Equatable, Sendable {
  enum Stage: String, Codable, Sendable { case walkthrough, tourHome, tourRecall, tourLibrary, chooseMode, complete }
  var stage: Stage = .complete
  var tourTab: String? {
    switch stage { case .tourHome: "home"; case .tourRecall: "recall"; case .tourLibrary: "library"; default: nil }
  }
}

struct PracticeAreaGroup: Identifiable, Sendable {
  let id: String
  let title: String
  let detail: String
  let symbol: String
  let concepts: [String]
  static let all: [Self] = [
    .init(id: "data", title: "Data & storage", detail: "Models, databases, consistency", symbol: "externaldrive", concepts: ["data-modeling", "consistency"]),
    .init(id: "traffic", title: "Scale & performance", detail: "Caching and capacity", symbol: "speedometer", concepts: ["caching", "capacity-planning"]),
    .init(id: "boundaries", title: "Services & APIs", detail: "Interfaces and access", symbol: "point.3.connected.trianglepath.dotted", concepts: ["api-design", "authorization"]),
    .init(id: "async", title: "Async work", detail: "Queues and coordination", symbol: "arrow.triangle.branch", concepts: ["queues", "coordination"]),
    .init(id: "reliability", title: "Reliable systems", detail: "Failures and observability", symbol: "waveform.path.ecg", concepts: ["fault-tolerance", "observability"])
  ]
}
struct PersonalizationPreview: Codable { var text: String }
struct PracticeSettings: Codable, Equatable, Sendable {
  var practiceProfile: PracticeProfile? = nil
  var learningPlan: LearningPlan? = nil
  var onboardingComplete = false
  var focus = "System design"
  var difficulty = "medium"
  var engineeringLevel: String?
  var selectedLevel: String {
    get { engineeringLevel ?? EngineeringLevel.legacy(difficulty) }
    set { engineeringLevel = newValue }
  }
  var timezone = TimeZone.current.identifier
  var dailyMinutes = 540
  var reminderEnabled = false
  var aiMode = "managed"
  var model = "openai/gpt-6-luna"
  /// Absent means on, matching the server.
  var questionFormatting: Bool? = nil
  var formatsQuestions: Bool {
    get { questionFormatting ?? true }
    set { questionFormatting = newValue }
  }
}
struct SessionDraft: Codable, Sendable {
  var answer: String
  var revision: Int
  var updatedAt: String?
}
struct CoachTurn: Codable, Identifiable, Sendable {
  var id: String
  var role: String
  var text: String
  var state: String
}
struct LearningEvidence: Codable, Sendable, Identifiable, Equatable {
  var id: String { (sessionId ?? "") + conceptId + signal + quote }
  var conceptId: String
  var observation: String
  var quote: String
  var signal: String
  var assistance: String
  var sessionId: String? = nil
  var at: String? = nil
  var sourceTurnId: String? = nil
}
struct Reflection: Codable, Sendable {
  var evidence: [LearningEvidence]? = nil
  var nextExercise: String? = nil
  var summary: String
  var worked: [String]
  var improve: String
  var takeaway: String
  var strengths: [String]
  var gaps: [String]
}
struct ExampleAnswer: Codable, Sendable {
  struct Part: Codable, Identifiable, Sendable {
    var id = UUID().uuidString
    enum CodingKeys: String, CodingKey { case heading, body }
    var heading: String
    var body: String
  }
  var overview: String
  var sections: [Part]
  var tradeoffs: [String]
  var pitfalls: [String]
}
struct RequestStatus: Codable, Sendable {
  var id: String
  var status: String
}
struct Challenge: Codable, Identifiable, Sendable {
  var questionId: String?
  var scenario: String?
  var primaryConceptId: String?
  var conceptIds: [String]?
  var selectionReason: String?
  var constraints: [String]? = nil
  var guidanceMode: GuidanceMode? = nil
  /// Onboarding warm-up: a real generated interview that the server never counts.
  var warmUp: Bool? = nil
  var isWarmUp: Bool { warmUp == true }
  var interviewStyle: InterviewStyle?
  var interview: InterviewState?
  var engineeringLevel: String?
  var difficulty: String?
  var levelLabel: String {
    if let explicit = EngineeringLevel.choices.first(where: { $0.0 == engineeringLevel }) { return explicit.1 }
    if let difficulty, ["easy", "medium", "hard"].contains(difficulty),
      let mapped = EngineeringLevel.choices.first(where: { $0.0 == EngineeringLevel.legacy(difficulty) }) { return mapped.1 }
    return "Level not recorded"
  }
  var id: String
  var lifecycle: String
  var title: String
  var prompt: String
  var displayPrompt: String {
    guard let constraints, !constraints.isEmpty else { return prompt }
    let appendix = "\n\nConstraints\n" + constraints.map { "• " + $0 }.joined(separator: "\n")
    return prompt.hasSuffix(appendix) ? String(prompt.dropLast(appendix.count)) : prompt
  }
  var topic: String
  var createdAt: String?
  var completedAt: String?
  var session: SessionDraft?
  var turns: [CoachTurn]?
  var reflection: Reflection?
  var example: ExampleAnswer?
  var coachRequest: RequestStatus?
  var help: [HelpResult]?
  var adoptions: [AdoptionEvent]?
  var companion: CompanionContext?
  var automaticCompanion: Bool?
  var widgetSummary: Challenge {
    Challenge(id: id, lifecycle: lifecycle, title: title, prompt: prompt, topic: topic)
  }
  var isActive: Bool { lifecycle == "ready" || lifecycle == "in_progress" }
}
struct Job: Codable, Identifiable, Sendable {
  var id: String
  var kind: String
  var status: String
  var error: String?
  var challengeId: String?
}
struct VoiceCapability: Codable, Sendable {
  var available: Bool
  var reason: String?
  var checkedAt: String
  func isFresh(at now: Date = Date()) -> Bool {
    guard let date = Date.fromAPI(checkedAt) else { return false }
    return (0..<60).contains(now.timeIntervalSince(date))
  }
}
struct Bootstrap: Codable, Sendable {
  struct Capabilities: Codable, Sendable {
    var voice: VoiceCapability?
    var developerTools: Bool? = nil
  }
  var capabilities: Capabilities? = nil
  var practiceEpoch: String?
  struct Account: Codable, Sendable {
    var id: String
    var status: String
  }
  struct Credential: Codable, Sendable { var suffix: String; var model: String? }
  var account: Account
  var settings: PracticeSettings
  var challenge: Challenge?
  var jobs: [Job]
  var credential: Credential?
  var todayPlan: TodayPlan?
}
struct TodayPlan: Codable, Sendable, Equatable {
  var state: String
  var completedTotal: Int
  var completedLastSevenDays: Int
  var completedToday: Int
  var dueRecallCount: Int
  var recommendedRecallCount: Int
  var estimatedRecallMinutes: Int
  var dailyGoalMinutes: Int
}
struct DailyQuestionResponse: Codable { var day: String; var challenge: Challenge?; var job: Job? }
struct HistoryPage: Codable, Sendable {
  var sessions: [Challenge]
  var nextCursor: String?
}
struct MemoryResponse: Codable, Sendable {
  var evidence: [LearningEvidence]? = nil
  struct Statistics: Codable, Sendable {
    var completed: Int
    var lastSevenDays: Int
    var asOf: String
  }
  var statistics: Statistics? = nil
  struct Pattern: Codable, Identifiable, Sendable {
    var label: String
    var kind: String
    var sessionIds: [String]
    var id: String { kind + label }
  }
  var sessions: [Challenge]
  var patterns: [Pattern]
}
struct RecallCardDTO: Codable, Identifiable, Sendable, Equatable {
  var id: String
  var sourceChallengeId: String
  var conceptId: String
  var question: String
  var answer: String
  var dueAt: String
  var intervalDays: Int
  var repetitions: Int
  var lapses: Int
  var createdAt: String
  var updatedAt: String
  var sourceTitle: String? = nil
  var sourceCompletedAt: String? = nil
  var evidence: LearningEvidence? = nil
}
struct RecallDeckResponse: Codable, Sendable {
  var cards: [RecallCardDTO]
  var dueCount: Int
}
struct RecallReviewInput: Codable, Sendable { var rating: String; var responseMs: Int? }
struct RecallReviewResponse: Codable, Sendable { var card: RecallCardDTO }
struct WidgetSnapshot: Codable, Sendable {
  var challenge: Challenge?
  var updatedAt: String
}
struct EmptyResponse: Codable, Sendable { var ok: Bool? }
struct RevisionResponse: Codable, Sendable { var revision: Int }
struct APIError: Error, LocalizedError, Sendable {
  var code: String
  var message: String
  var status: Int
  var errorDescription: String? { message }
}
struct ErrorEnvelope: Decodable {
  struct Detail: Decodable {
    var code: String
    var message: String
  }
  var error: Detail
}
struct DraftWrite: Codable, Sendable {
  var answer: String
  var revision: Int
  var receipts: [DeliveryReceipt]?
}
struct Question: Codable, Sendable { var question: String }
struct CodeInput: Codable, Sendable { var code: String }
struct KeyInput: Codable, Sendable { var key: String; var model: String }
struct DeviceResponse: Codable, Sendable {
  var id: String
  var token: String
  var expiresAt: String
}
struct GenerationResponse: Codable, Sendable {
  var id: String?
  var challenge: Challenge?
}
struct StreamEvent: Decodable, Sendable {
  var requestId: String
  var text: String?
  var message: String?
}
extension JSONDecoder {
  static var api: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
  }
}

extension Date {
  static func fromAPI(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
  }
}

struct HelpResult: Codable, Identifiable, Sendable {
  var id: String
  var status: String
  var kind: String
  var revision: Int
  var body: String?
  var suggestedAnswer: String?
  var capture: CompanionCapture?
  var deliveries: [String]?
  var outcome: String?
  var suggestedFocus: String?
  var plan: [String]?
  var insertableText: String? {
    ["outline", "example", "starting_point"].contains(kind) ? body : suggestedAnswer
  }
  var running: Bool { status == "pending" || status == "running" }
  var title: String {
    switch kind {
    case "hint": "A hint"
    case "check": "Reasoning check"
    case "outline": "An outline"
    case "example": "One possible answer"
    case "draft": "Suggested draft"
    default: "Your question"
    }
  }
}
struct AdoptionEvent: Codable, Identifiable, Sendable {
  var id: String
  var sourceId: String
  var operation: String
  var revision: Int
}
struct HelpInput: Codable {
  var kind: String
  var mode: String
  var question: String
  var revision: Int
  var capture: CompanionCapture?
}
struct AdoptionInput: Codable, Sendable {
  var sourceId: String
  var operation: String
  var revision: Int
}
struct PreparationInput: Codable {
  var primaryConceptId: String? = nil
  var guidanceMode: GuidanceMode? = nil
  var interviewStyle: InterviewStyle? = nil
  var focus: String
  var kind: String
  var difficulty: String
  var engineeringLevel: String? = nil
  var replaceId: String?
  var instruction: String = ""
  var followUpId: String?
  var warmUp: Bool? = nil
}

struct CompanionContext: Codable, Sendable {
  var cycleConsumed: Bool?
  var guidedStarted: Bool?
  struct Decision: Codable, Sendable {
    var id: String
    var text: String
  }
  var revision: Int = 0
  var mode: String = "solo"
  var modeEpoch: Int = 0
  var paused: Bool = false
  var selectedFocus: String?
  var decisions: [Decision] = []
  var automaticCount: Int = 0
  var lastAutomaticAt: String?
  var digest: String = ""
  var cycle: String = ""
}
struct CompanionCapture: Codable, Sendable, Equatable {
  var contextRevision: Int
  var modeEpoch: Int
  var cycle: String
  var digest: String
  var trigger: String
}
struct DeliveryReceipt: Codable, Sendable, Identifiable {
  var id: String = UUID().uuidString
  var helpId: String
  var disposition: String
}
struct DeliveryInput: Codable { var receipts: [DeliveryReceipt] }
struct CompanionUpdate: Codable {
  var revision: Int
  var operation: String
  var mode: String?
  var paused: Bool?
  var text: String?
}

 enum EngineeringLevel {
  static let choices = [("intern", "Intern"), ("junior", "Junior"), ("mid", "Mid-level"), ("senior", "Senior"), ("staff", "Staff"), ("principal", "Principal")]
  static func legacy(_ difficulty: String) -> String { difficulty == "easy" ? "junior" : difficulty == "hard" ? "senior" : "mid" }
 }

func reminderComponents(minutes: Int, timezone: String) -> DateComponents {
  DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(identifier: timezone), hour: minutes / 60, minute: minutes % 60)
}

enum GuidanceMode: String, CaseIterable, Codable, Identifiable, Sendable {
  case learnTogether = "learn_together", coachMe = "coach_me", mockInterview = "mock_interview"
  var id: String { rawValue }
  var title: String { switch self {
    case .learnTogether: "Guided"
    case .coachMe: "Practice"
    case .mockInterview: "Mock interview"
  } }
  var explanation: String { switch self {
    case .learnTogether: "Work through an approach together, with examples along the way."
    case .coachMe: "Take the lead. Get useful pointers when you’re stuck or missing something."
    case .mockInterview: "Put your approach to the test. Save the coaching for the debrief."
  } }
}
enum InterviewStyle: String, CaseIterable, Codable, Identifiable, Sendable {
  case quick, standard, inDepth = "in_depth"
  var id: String { rawValue }
  var title: String { switch self { case .quick: "Quick"; case .standard: "Standard"; case .inDepth: "In-depth" } }
  var explanation: String { switch self {
    case .quick: "Brief, focused follow-ups."
    case .standard: "Explore your approach and its trade-offs."
    case .inDepth: "More follow-ups that challenge your assumptions."
  } }
}
struct InterviewResponse: Codable, Sendable {
  var outcome: String
  var text: String
  var parameters: [InterviewParameter]? = nil
}
struct InterviewParameter: Codable, Hashable, Sendable {
  var label: String
  var value: String
}
enum InterviewComposerIntent {
  static func isQuestion(_ text: String) -> Bool {
    let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return message.count <= 240 && !message.contains("\n") && message.hasSuffix("?")
  }
}
struct InterviewTurn: Codable, Identifiable, Sendable {
  var id: String
  var ordinal: Int
  var kind: String
  var prompt: String
  var text: String
  var createdAt: String
  var jobId: String
  var status: String
  var error: String?
  var result: InterviewResponse?
  var partial: String? = nil
  var voice: [VoiceFragment]? = nil
  var pending: Bool { ["pending", "running"].contains(status) }
}
struct InterviewState: Codable, Sendable {
  var guidanceMode: GuidanceMode? = nil
  var style: InterviewStyle = .standard
  var prompt: String
  var wrapUp: Bool = false
  var turns: [InterviewTurn] = []
}
struct InterviewInput: Codable, Sendable {
  var promptId: String = "original"
  var kind: String
  var revision: Int
  var text: String = ""
  var style: InterviewStyle? = nil
  var guidanceMode: GuidanceMode? = nil
  var saveDraft: Bool? = nil
}

/// A finalized user answer, captured against the active account and prompt.
/// Provisional speech stays inside the future voice adapter and never enters this API.
struct FinalizedInterviewAnswer: Codable, Sendable {
  var id: UUID
  var account: String
  var challengeID: String
  var promptID: String
  var text: String
}

struct PendingInterviewCommand: Codable, Sendable {
  var command: String
  var input: InterviewInput
  var retryTurn: String?
}

/// A reading projection of durable turns. A follow-up belongs to the next exchange only.
struct InterviewExchange: Identifiable, Sendable {
  var id: String
  var prompt: String
  var turns: [InterviewTurn] = []
  var hasAnswer: Bool { turns.contains { $0.kind == "answer" } }
  static func document(original: String, state: InterviewState) -> [Self] {
    var result = [Self(id: "original", prompt: original)]
    for turn in state.turns.sorted(by: { $0.ordinal < $1.ordinal }) {
      // Explicit help is a one-time overlay, not part of the interview document.
      if ["hint", "example"].contains(turn.kind) { continue }
      result[result.count - 1].turns.append(turn)
      if ["answer", "continue"].contains(turn.kind), turn.result?.outcome != "wrap_up" {
        result.append(Self(id: turn.id, prompt: turn.result?.text ?? turn.partial ?? ""))
      }
    }
    return result
  }
}
struct InterviewReadingState: Codable, Sendable {
  var expandedAnswers: Set<String>? = nil
  var collapsed: Set<String> = []
  var offset: Double = 0
}

struct InterviewStreamSnapshot: Decodable { var status: String; var text: String }
struct QuestionStreamSnapshot: Decodable { var status: String; var error: String?; var title: String; var prompt: String }
/// A question as the model writes it; provisional until the finished challenge replaces it.
struct QuestionDraft: Equatable, Sendable {
  var title = ""
  var prompt = ""
  var guidanceMode: GuidanceMode?
  var warmUp = false
}

struct PracticeConcept: Codable, Identifiable, Sendable { var id: String; var label: String; var category: String; var aliases: [String]; var description: String? = nil }
enum PracticeAreaCatalog {
  /// A small learning-facing menu over the richer canonical taxonomy used for tagging.
  static let ids = ["data-modeling", "consistency", "api-design", "caching", "queues", "coordination", "fault-tolerance", "capacity-planning", "authorization", "observability"]
  static func curated(_ concepts: [PracticeConcept]) -> [PracticeConcept] {
    ids.compactMap { id in concepts.first { $0.id == id } }
  }
}
struct TaxonomyResponse: Codable, Sendable { var version: Int; var concepts: [PracticeConcept] }
struct LibraryQuestion: Codable, Identifiable, Sendable, Equatable {
  var id: String; var title: String; var prompt: String; var scenario: String; var engineeringLevel: String
  var primaryConceptId: String; var conceptIds: [String]; var eligible: Bool; var eligibilityRevision: Int
  var lastActivity: String?; var attemptCount: Int?
  var levelLabel: String { EngineeringLevel.choices.first { $0.0 == engineeringLevel }?.1 ?? engineeringLevel }
}
struct LibraryPage: Codable, Sendable { var questions: [LibraryQuestion]; var nextCursor: String? }
struct LibraryDetail: Codable, Sendable { var question: LibraryQuestion; var attempts: [Challenge]; var nextCursor: String? }
struct CoverageResponse: Codable, Sendable {
  struct Entry: Codable, Sendable { var conceptId: String; var completedAttempts: Int; var distinctQuestions: Int; var lastPractised: String? }
  var concepts: [Entry]
}
struct EligibilityCommand: Codable, Identifiable, Sendable {
  var id: String; var questionId: String; var revision: Int; var eligible: Bool
}
struct EligibilityInput: Codable { var revision: Int; var eligible: Bool }

struct VoiceFragment: Codable, Identifiable, Equatable, Sendable {
  var id: String
  var sequence: Int
  var speaker: String
  var text: String
  var startMs: Int
  var endMs: Int
}

struct HomeRevisit: Identifiable {
  var evidence: LearningEvidence
  var source: Challenge
  var id: String { evidence.id + evidence.observation + (source.reflection?.improve ?? "") }
  static func select(memory: MemoryResponse, dismissed: Set<String>) -> HomeRevisit? {
    var checkedConcepts: Set<String> = []
    let evidence = (memory.evidence ?? []).enumerated().sorted {
      if $0.element.at != $1.element.at { return ($0.element.at ?? "") > ($1.element.at ?? "") }
      return $0.offset < $1.offset
    }.map(\.element)
    for item in evidence {
      guard checkedConcepts.insert(item.conceptId).inserted else { continue }
      guard item.signal == "needs_practice" && !item.quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !item.observation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
      guard let source = memory.sessions.first(where: { $0.id == item.sessionId && $0.lifecycle == "completed" }),
            source.reflection != nil else { continue }
      let candidate = HomeRevisit(evidence: item, source: source)
      if !dismissed.contains(candidate.id) { return candidate }
    }
    return nil
  }
}

struct PendingSettings: Codable, Equatable, Sendable {
  var id = UUID().uuidString
  var value: PracticeSettings
}

enum HomeTopicRanking {
  static func ranked(_ concepts: [PracticeConcept], coverage: [CoverageResponse.Entry]) -> [PracticeConcept] {
    let counts = Dictionary(coverage.map { ($0.conceptId, $0) }, uniquingKeysWith: { _, latest in latest })
    return concepts.sorted {
      let a = counts[$0.id], b = counts[$1.id]
      if (a?.completedAttempts ?? 0) != (b?.completedAttempts ?? 0) { return (a?.completedAttempts ?? 0) < (b?.completedAttempts ?? 0) }
      if a?.lastPractised != b?.lastPractised { return (a?.lastPractised ?? "") < (b?.lastPractised ?? "") }
      return $0.id < $1.id
    }
  }
}

/// Question markup: `<b>`, `<i>` and `<code>` inline, `<pre>` blocks. Rendered natively, never as HTML;
/// anything else stays literal text. Keep the tag set in sync with apps/api/src/prompts/formatting.ts.
enum QuestionMarkup {
  enum Block: Equatable, Sendable {
    case text(AttributedString)
    case code(String)
    var length: Int {
      switch self {
      case .text(let value): value.characters.count
      case .code(let value): value.count
      }
    }
  }
  private static let inline: [String: (InlinePresentationIntent, Bool)] = [
    "<b>": (.stronglyEmphasized, true), "</b>": (.stronglyEmphasized, false),
    "<i>": (.emphasized, true), "</i>": (.emphasized, false),
    "<code>": (.code, true), "</code>": (.code, false),
  ]
  private static let tags = Array(inline.keys) + ["<pre>", "</pre>"]
  private static let entities = ["&lt;": "<", "&gt;": ">", "&amp;": "&"]

  /// Tolerates text that is still streaming: an unfinished tag or entity at the end is held back, and an open tag applies to the rest.
  static func blocks(_ source: String, formatted: Bool = true) -> [Block] {
    guard formatted else {
      let text = plain(source)
      return text.isEmpty ? [] : [.text(AttributedString(text))]
    }
    var blocks: [Block] = []
    var text = AttributedString()
    var run = ""
    var intent: InlinePresentationIntent = []
    var code: String?
    func flushRun() {
      guard !run.isEmpty else { return }
      var piece = AttributedString(run)
      if !intent.isEmpty { piece.inlinePresentationIntent = intent }
      text.append(piece)
      run = ""
    }
    func flushText() {
      flushRun()
      let value = trimmingNewlines(text)
      if !value.characters.allSatisfy(\.isWhitespace) { blocks.append(.text(value)) }
      text = AttributedString()
    }
    var index = source.startIndex
    scan: while index < source.endIndex {
      let character = source[index]
      if character == "<" || character == "&" {
        let rest = source[index...]
        let candidates = character == "<" ? tags : Array(entities.keys)
        if let match = candidates.first(where: { rest.hasPrefix($0) }) {
          index = source.index(index, offsetBy: match.count)
          if let value = entities[match] {
            if code != nil { code? += value } else { run += value }
          } else if code != nil {
            if match == "</pre>" { blocks.append(.code(code!.trimmingCharacters(in: .newlines))); code = nil }
            else { code? += match }
          } else if match == "<pre>" {
            flushText()
            code = ""
          } else if let (flag, opens) = inline[match] {
            flushRun()
            if opens { intent.insert(flag) } else { intent.remove(flag) }
          }
          continue
        }
        if candidates.contains(where: { $0.hasPrefix(rest) }) { break scan }
      }
      if code != nil { code?.append(character) } else { run.append(character) }
      index = source.index(after: index)
    }
    if let code { blocks.append(.code(code.trimmingCharacters(in: .newlines))) } else { flushText() }
    return blocks
  }

  static func plain(_ source: String) -> String {
    blocks(source).map { block in
      switch block {
      case .text(let value): String(value.characters)
      case .code(let value): value
      }
    }.joined(separator: "\n")
  }

  private static func trimmingNewlines(_ value: AttributedString) -> AttributedString {
    var value = value
    while let first = value.characters.first, first.isNewline {
      value.removeSubrange(value.startIndex..<value.characters.index(after: value.startIndex))
    }
    while let last = value.characters.last, last.isNewline {
      value.removeSubrange(value.characters.index(before: value.endIndex)..<value.endIndex)
    }
    return value
  }
}
extension Challenge {
  /// For compact previews, widgets and accessibility labels.
  var plainPrompt: String { QuestionMarkup.plain(displayPrompt) }
}
