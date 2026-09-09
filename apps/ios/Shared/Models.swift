import Foundation

struct PracticeSettings: Codable, Equatable, Sendable {
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
  var model = "google/gemini-3.1-flash-lite"
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
struct Reflection: Codable, Sendable {
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
struct Bootstrap: Codable, Sendable {
  struct Account: Codable, Sendable {
    var id: String
    var status: String
  }
  struct Credential: Codable, Sendable { var suffix: String }
  var account: Account
  var settings: PracticeSettings
  var challenge: Challenge?
  var jobs: [Job]
  var credential: Credential?
}
struct HistoryPage: Codable, Sendable {
  var sessions: [Challenge]
  var nextCursor: String?
}
struct MemoryResponse: Codable, Sendable {
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
struct KeyInput: Codable, Sendable { var key: String }
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
  var interviewStyle: InterviewStyle? = nil
  var focus: String
  var kind: String
  var difficulty: String
  var engineeringLevel: String? = nil
  var replaceId: String?
  var instruction: String = ""
  var followUpId: String?
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

enum PracticeFocus {
  static let choices = ["System design", "Backend", "Frontend", "Debugging", "Algorithms"]
}

enum InterviewStyle: String, CaseIterable, Codable, Identifiable, Sendable {
  case quick, standard, inDepth = "in_depth"
  var id: String { rawValue }
  var title: String { switch self { case .quick: "Quick"; case .standard: "Standard"; case .inDepth: "In-depth" } }
  var explanation: String { switch self {
    case .quick: "One question and a focused follow-up."
    case .standard: "Explore your approach and its trade-offs."
    case .inDepth: "More follow-ups that challenge your assumptions."
  } }
}
struct InterviewResponse: Codable, Sendable {
  var outcome: String
  var text: String
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
  var pending: Bool { ["pending", "running"].contains(status) }
}
struct InterviewState: Codable, Sendable {
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
}

struct PendingInterviewCommand: Codable, Sendable {
  var command: String
  var input: InterviewInput
  var retryTurn: String?
}
