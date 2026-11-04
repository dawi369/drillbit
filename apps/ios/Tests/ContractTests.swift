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
  /// Every route that hands practice content to a model waits for the AI permission; reading and saving don't.
  @MainActor @Test func aiRoutesNeedConsentAndOthersDont() {
    for path in ["challenges", "challenges/c1/interview", "challenges/c1/interview/t1/retry", "challenges/c1/help",
                 "challenges/c1/example", "challenges/c1/complete", "challenges/c1/voice", "challenges/c1/start",
                 "challenges/c1/retry-moment/t1", "daily-question", "settings/preview", "questions/q1/start", "jobs/j1/retry"] {
      #expect(APIClient.usesAI(path), "\(path)")
    }
    for path in ["challenges/c1/draft", "challenges/c1/skip", "challenges/c1/next", "settings", "devices", "paywall/view",
                 "recall/r1/review", "entitlement", "challenges/c1/interview/t1/cancel", "challenges/c1/voice/v1/events"] {
      #expect(!APIClient.usesAI(path), "\(path)")
    }
  }

  @Test func recallSessionRevealsAndRequeuesWithoutClaimingMastery() {
    var session = RecallSession(area: .swift, depth: .foundations)
    #expect(session.remainingCount == 1)
    #expect(session.current?.id == "swift-value-reference")

    session.markKnown()
    #expect(session.remainingCount == 1)
    session.reveal()
    session.markAgain()
    #expect(session.remainingCount == 1)
    #expect(session.againCount == 1)
    #expect(session.isRevealed == false)

    session.reveal()
    session.markKnown()
    #expect(session.remainingCount == 0)
    #expect(session.knownCount == 1)
  }

  @Test func recallFiltersProduceStableTemporaryDecks() {
    let swift = RecallSession(area: .swift, depth: .all)
    #expect(swift.remainingCount == 3)
    #expect(swift.current?.area == .swift)
    let deep = RecallSession(area: .all, depth: .deep)
    #expect(deep.remainingCount == 5)
    #expect(deep.current?.depth == .deep)
  }

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
  @Test func practiceProfileIsOptionalAndRoundTrips() throws {
    let old = try JSONDecoder().decode(PracticeSettings.self, from: JSONEncoder().encode(PracticeSettings()))
    #expect(old.practiceProfile == nil)
    var current = old
    current.practiceProfile = PracticeProfile(goals: "Senior interviews", background: "Backend", preferences: "Pirate")
    let restored = try JSONDecoder().decode(PracticeSettings.self, from: JSONEncoder().encode(current))
    #expect(restored.practiceProfile == current.practiceProfile)
  }
  @Test func learningPlanAndTodayPlanRemainAdditive() throws {
    var settings = PracticeSettings()
    #expect(settings.learningPlan == nil)
    settings.learningPlan = LearningPlan(objective: "interview", roleTrack: "backend", weakAreas: ["data", "async"], dailyGoalMinutes: 10, targetDate: "2099-01-01")
    let restored = try JSONDecoder().decode(PracticeSettings.self, from: JSONEncoder().encode(settings))
    #expect(restored.learningPlan == settings.learningPlan)
    let json = #"{"state":"review_due","completedTotal":3,"completedLastSevenDays":2,"completedToday":1,"dueRecallCount":8,"recommendedRecallCount":8,"estimatedRecallMinutes":4,"dailyGoalMinutes":10}"#
    let plan = try JSONDecoder.api.decode(TodayPlan.self, from: Data(json.utf8))
    #expect(plan.state == "review_due")
    #expect(plan.estimatedRecallMinutes == 4)
  }
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
    // 9:00 in New York, across the spring-forward night: today's 9:00 has passed, so the first is tomorrow's.
    let now = ISO8601DateFormatter().date(from: "2026-03-07T15:00:00Z")!
    let schedule = reminderSchedule(minutes: 540, timezone: "America/New_York", from: now)
    let first = try #require(schedule.first)
    #expect(ISO8601DateFormatter().string(from: first.date.date!) == "2026-03-08T13:00:00Z")
    #expect(first.id == "daily-practice-2026-03-08")
  }

  @Test func proIsOfferedOnceAfterTheFirstFreeRep() {
    let fresh = PracticeAccess(plan: "free", freeReps: true, available: true, remaining: 3, limit: 3, lifetime: true)
    var afterFirst = fresh; afterFirst.remaining = 2
    var afterSecond = fresh; afterSecond.remaining = 1
    var spent = fresh; spent.remaining = 0; spent.available = false
    #expect(!fresh.offersProAfterFirstRep(alreadyOffered: false), "Nothing finished yet")
    #expect(afterFirst.offersProAfterFirstRep(alreadyOffered: false))
    #expect(!afterFirst.offersProAfterFirstRep(alreadyOffered: true), "Once per account")
    #expect(!afterSecond.offersProAfterFirstRep(alreadyOffered: false), "Only after the first")
    #expect(!spent.offersProAfterFirstRep(alreadyOffered: false), "Spent reps get the gate, not the offer")
    var two = PracticeAccess(plan: "free", freeReps: true, available: true, remaining: 1, limit: 2, lifetime: true)
    #expect(two.offersProAfterFirstRep(alreadyOffered: false), "Whatever the limit")
    two.lifetime = false
    #expect(!two.offersProAfterFirstRep(alreadyOffered: false), "Daily reps come back, so there's no first-rep offer")
    let pro = PracticeAccess(plan: "pro", freeReps: false, available: true)
    #expect(!pro.offersProAfterFirstRep(alreadyOffered: false))
  }

  @Test func reminderScheduleRotatesLinesWithoutReshuffling() throws {
    let now = ISO8601DateFormatter().date(from: "2026-11-03T08:00:00Z")!
    let schedule = reminderSchedule(minutes: 750, timezone: "Europe/Prague", from: now)
    #expect(schedule.count == 28)
    #expect(Set(schedule.map(\.id)).count == 28)
    #expect(schedule.first?.id == "daily-practice-2026-11-03", "12:30 in Prague is still ahead today")
    #expect(schedule.allSatisfy { $0.date.date! > now })
    for (today, tomorrow) in zip(schedule, schedule.dropFirst()) { #expect(today.title != tomorrow.title) }
    #expect(Set(schedule.map(\.title)).count == reminderLines.count, "Every line gets a turn")
    // Rescheduling later the same morning keeps each day's line.
    let later = reminderSchedule(minutes: 750, timezone: "Europe/Prague", from: now.addingTimeInterval(3600))
    #expect(later.map(\.title) == schedule.map(\.title))
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
  @Test func completionWriteCarriesTheFinishingStyleOnlyWhenKnown() throws {
    let plain = try JSONSerialization.jsonObject(with: JSONEncoder().encode(DraftWrite(answer: "a", revision: 1))) as? [String: Any]
    #expect(plain?["guidanceMode"] == nil)
    let finished = try JSONSerialization.jsonObject(with: JSONEncoder().encode(DraftWrite(answer: "a", revision: 1, guidanceMode: .mockInterview))) as? [String: Any]
    #expect(finished?["guidanceMode"] as? String == "mock_interview")
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
