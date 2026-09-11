import Foundation
import SwiftData
import Testing

#if canImport(DrillbitCore)
  @testable import DrillbitCore
#else
  @testable import Drillbit
#endif

struct ContractTests {
  #if !canImport(DrillbitCore)
  @MainActor @Test func libraryPreloadsOnceUntilCommittedInvalidation() async throws {
    let container = try ModelContainer(for: Schema(StoreV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let model = AppModel(container: container, baseURL: URL(string: "https://example.invalid")!, fixture: true, monitorNetwork: false)
    await model.launch()
    let account = try #require(model.bootstrap?.account.id)
    let key = "library:" + account + ":|||0|false"
    #expect(model.librarySnapshots[key]?.questions.count == 1)
    #expect(model.libraryDetailSnapshots["library-detail:" + account + ":library-completed"]?.attempts.count == 1)
    let version = model.libraryVersion
    model.fixtureLibrary = []
    await model.preloadLibrary()
    #expect(model.libraryVersion == version)
    #expect(model.librarySnapshots[key]?.questions.count == 1)
    await model.preloadLibrary(force: true)
    #expect(model.librarySnapshots[key]?.questions.isEmpty == true)
    #expect(model.libraryVersion == version + 1)
  }

  #endif
  @Test func historicalChallengeLevels() throws {
    for (difficulty, expected) in [("easy", "Junior"), ("medium", "Mid-level"), ("hard", "Senior")] {
      let json = "{\"id\":\"old\",\"lifecycle\":\"completed\",\"title\":\"Notification service\",\"prompt\":\"Design it\",\"topic\":\"Backend\",\"difficulty\":\"\(difficulty)\"}"
      var challenge = try JSONDecoder.api.decode(Challenge.self, from: Data(json.utf8))
      #expect(challenge.levelLabel == expected)
      challenge.engineeringLevel = "staff"
      #expect(challenge.levelLabel == "Staff")
      challenge.engineeringLevel = nil
      challenge.difficulty = nil
      #expect(challenge.levelLabel == "Level not recorded")
    }
  }

  @Test func settingsLevelsAndZoneRoundTrip() throws {
    for (old, level) in [("easy", "junior"), ("medium", "mid"), ("hard", "senior")] {
      var settings = PracticeSettings()
      settings.difficulty = old
      #expect(settings.selectedLevel == level)
      settings.selectedLevel = "principal"
      settings.timezone = "Asia/Kolkata"
      let restored = try JSONDecoder().decode(PracticeSettings.self, from: JSONEncoder().encode(settings))
      #expect(restored.selectedLevel == "principal")
      #expect(restored.timezone == "Asia/Kolkata")
    }
    let components = reminderComponents(minutes: 540, timezone: "America/New_York")
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    let date = calendar.nextDate(after: ISO8601DateFormatter().date(from: "2026-03-07T15:00:00Z")!, matching: components, matchingPolicy: .nextTime)!
    #expect(ISO8601DateFormatter().string(from: date) == "2026-03-08T13:00:00Z")
  }

  @Test func decodeHelpAndAdoption() throws {
    let json = Data(
      #"{"id":"p","lifecycle":"in_progress","title":"Cache","prompt":"Design a cache","topic":"Systems","help":[{"id":"h","kind":"draft","status":"completed","revision":2,"body":"A suggestion","suggestedAnswer":"A draft"}],"adoptions":[{"id":"a","source_id":"h","operation":"replace","revision":3}]}"#
        .utf8)
    let value = try JSONDecoder.api.decode(Challenge.self, from: json)
    #expect(value.help?.first?.suggestedAnswer == "A draft")
    #expect(value.adoptions?.first?.sourceId == "h")
    #expect(value.adoptions?.first?.revision == 3)
  }

  @Test func decodeBackendDraft() throws {
    let json = Data(
      #"{"id":"a","lifecycle":"in_progress","title":"Design flags","prompt":"Keep evaluation available","topic":"systems","session":{"answer":"My answer","revision":2,"updated_at":"2026-09-08T00:00:00Z"}}"#
        .utf8)
    let challenge = try JSONDecoder.api.decode(Challenge.self, from: json)
    #expect(challenge.isActive)
    #expect(challenge.session?.revision == 2)
    #expect(challenge.session?.updatedAt != nil)
  }
  @Test func localOutboxPreservesNewerEditDuringAcknowledgement() async throws {
    let container = try ModelContainer(
      for: Schema(StoreV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let disk = DiskStore(modelContainer: container)
    let challenge = Challenge(
      id: "test", lifecycle: "ready", title: "Test", prompt: "Test", topic: "Test",
      session: SessionDraft(answer: "", revision: 0))
    _ = try await disk.load(account: "account", challenge: challenge)
    try await disk.save(account: "account", id: "test", answer: "first")
    let sent = try #require(await disk.pending(account: "account").first)
    try await disk.save(account: "account", id: "test", answer: "second")
    try await disk.acknowledge(account: "account", sent: sent, revision: 1)
    let pending = try #require(await disk.pending(account: "account").first)
    #expect(pending.answer == "second")
    #expect(pending.revision == 1)
    #expect(pending.command != sent.command)
  }

  @Test func completionSurvivesRefreshAndConflictPreservesAnswer() async throws {
    let container = try ModelContainer(
      for: Schema(StoreV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let disk = DiskStore(modelContainer: container)
    var challenge = Challenge(
      id: "recovery", lifecycle: "in_progress", title: "Test", prompt: "Test", topic: "Test",
      session: SessionDraft(answer: "cloud", revision: 1))
    _ = try await disk.load(account: "a", challenge: challenge)
    try await disk.save(
      account: "a", id: challenge.id, answer: "finished offline", completing: true)
    challenge.session = SessionDraft(answer: "other device", revision: 2)
    let local = try await disk.load(account: "a", challenge: challenge)
    #expect(local.answer == "finished offline")
    #expect(local.kind == "complete")
    try await disk.markConflict(account: "a", id: challenge.id)
    #expect(try await disk.pending(account: "a").first?.conflict == true)
    #expect(try await disk.pending(account: "b").isEmpty == true)
    try await disk.resolve(account: "a", challenge: challenge, keepLocal: false)
    #expect(try await disk.pending(account: "a").isEmpty == true)
    #expect(try await disk.load(account: "a", challenge: challenge).answer == "other device")
  }
  @Test func deliveryAcknowledgementPreservesNewerIntent() async throws {
    let container = try ModelContainer(for: Schema(StoreV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let disk = DiskStore(modelContainer: container)
    let first = DeliveryReceipt(helpId: "help", disposition: "uncertain")
    let second = DeliveryReceipt(helpId: "help", disposition: "shown")
    _ = try await disk.enqueueReceipt(key: "a:receipts", receipt: first)
    _ = try await disk.enqueueReceipt(key: "a:receipts", receipt: second)
    try await disk.acknowledgeReceipts(key: "a:receipts", ids: [first.id])
    let data = try await disk.cached(key: "a:receipts")!
    let pending = try JSONDecoder().decode([DeliveryReceipt].self, from: data)
    #expect(pending.map(\.id) == [second.id])
    #expect(try await disk.cached(key: "b:receipts") == nil)
  }

  @Test func parsesDeviceExpiryWithAndWithoutFractionalSeconds() {
    #expect(Date.fromAPI("2026-09-08T00:00:00.000Z") == Date.fromAPI("2026-09-08T00:00:00Z"))
    #expect(Date.fromAPI("invalid") == nil)
  }

  @Test func widgetProjectionExcludesPrivatePractice() throws {
    let challenge = Challenge(
      id: "widget", lifecycle: "in_progress", title: "Title", prompt: "Question", topic: "Systems",
      session: SessionDraft(answer: "private answer", revision: 4),
      turns: [CoachTurn(id: "turn", role: "user", text: "private follow-up", state: "completed")])
    let json = String(decoding: try JSONEncoder().encode(challenge.widgetSummary), as: UTF8.self)
    #expect(!json.contains("private"))
    #expect(!json.contains("session"))
    #expect(!json.contains("turns"))
    #expect(json.contains("Question"))
  }
}
