import ClerkKit
import Network
import OSLog
import SwiftData
import SwiftUI
import UserNotifications
import WidgetKit

@MainActor @Observable final class AppModel {
  var bootstrap: Bootstrap?
  var memory = MemoryResponse(sessions: [], patterns: [])
  var settings = PracticeSettings()
  var presented: Challenge?
  var error: String?
  var busy = false
  var preparationFailure: String?
  var failedPreparation: PreparationInput?
  var failedPreparationSource: Challenge?
  var saveStatus = ""
  var conflict: Challenge?
  var hasPendingWrites = false
  let disk: DiskStore
  let api: APIClient
  let fixture: Bool
  private var syncing = false
  private var refreshing = false
  private var monitor = NWPathMonitor()
  private let logger = Logger(subsystem: "dawi.drillbit", category: "application")
  init(container: ModelContainer, baseURL: URL, fixture: Bool) {
    disk = DiskStore(modelContainer: container)
    api = APIClient(baseURL: baseURL)
    self.fixture = fixture
    monitor.pathUpdateHandler = { [weak self] path in
      if path.status == .satisfied {
        Task { @MainActor in
          guard let self else { return }
          await self.sync()
          if self.bootstrap != nil { await self.refresh() }
        }
      }
    }
    monitor.start(queue: DispatchQueue(label: "drillbit.connectivity"))
  }
  func perform(_ action: () async throws -> Void) async {
    do { try await action() } catch is CancellationError {} catch {
      self.error = error.localizedDescription
      logger.error("Operation failed; details shown in UI")
    }
  }
  func launch() async {
    if fixture {
      seedFixture()
      return
    }
    for _ in 0..<25 {
      if Clerk.shared.isLoaded { break }
      try? await Task.sleep(for: .milliseconds(200))
      if Task.isCancelled { return }
    }
    if let subject = Clerk.shared.user?.id, subject == SharedStore.secret("subject"),
      let account = SharedStore.secret("account"),
      let data = try? await disk.cached(key: "bootstrap:" + account),
      let cached = try? JSONDecoder.api.decode(Bootstrap.self, from: data)
    {
      bootstrap = cached
      settings = cached.settings
    }
    await refresh()
  }
  func signIn() async {
    await perform {
      try await Clerk.shared.auth.signInWithApple()
      await refresh()
    }
  }
  func signIn(provider: OAuthProvider) async {
    await perform {
      try await Clerk.shared.auth.signInWithOAuth(provider: provider)
      await refresh()
    }
  }
  func redeem(_ code: String) async {
    await perform {
      let _: EmptyResponse = try await api.send(
        "invite", method: "POST", body: CodeInput(code: code))
      await refresh()
    }
  }
  func refresh() async {
    guard !fixture, !refreshing else { return }
    refreshing = true
    defer { refreshing = false }
    do {
      await sync()
      let result: Bootstrap = try await api.send("bootstrap")
      bootstrap = result
      settings = result.settings
      try SharedStore.setSecret(result.account.id, key: "account")
      try SharedStore.setSecret(Clerk.shared.user?.id, key: "subject")
      try await disk.cache(
        key: "bootstrap:" + result.account.id, data: JSONEncoder().encode(result))
      if result.account.status == "active" {
        if SharedStore.secret("widgetToken") == nil
          || (SharedStore.secret("widgetTokenExpires").flatMap { Date.fromAPI($0) } ?? .distantPast)
            < Date().addingTimeInterval(86400)
        {
          let device: DeviceResponse = try await api.send("devices", method: "POST")
          try SharedStore.setSecret(device.token, key: "widgetToken")
          try SharedStore.setSecret(device.id, key: "deviceID")
          try SharedStore.setSecret(device.expiresAt, key: "widgetTokenExpires")
          try SharedStore.setSecret(api.baseURL.absoluteString, key: "apiURL")
        }
        try SharedStore.save(
          WidgetSnapshot(
            challenge: result.challenge, updatedAt: ISO8601DateFormatter().string(from: Date())))
        WidgetCenter.shared.reloadTimelines(ofKind: SharedStore.widgetKind)
        await sync()
        await loadMemory()
      }
    } catch let e as APIError where e.status == 401 {
      if bootstrap == nil {
        error = nil
      } else {
        error = "Sign in again to sync. Your local draft is safe."
      }
    } catch { if bootstrap == nil { self.error = error.localizedDescription } }
  }
  func loadMemory() async {
    guard let account = bootstrap?.account.id, !fixture else { return }
    do {
      memory = try await api.send("memory")
      try await disk.cache(key: "memory:" + account, data: JSONEncoder().encode(memory))
    } catch {
      if let data = try? await disk.cached(key: "memory:" + account),
        let cached = try? JSONDecoder.api.decode(MemoryResponse.self, from: data)
      {
        memory = cached
      }
    }
  }
  func generate(_ preparation: PreparationInput? = nil) async {
    await perform { _ = try await generateForPreview(preparation) }
  }
  func generateForPreview(_ preparation: PreparationInput? = nil) async throws -> Challenge {
    guard !busy, let account = bootstrap?.account.id else {
      throw APIError(code: "busy", message: "A question is already being prepared.", status: 409)
    }
    busy = true
    preparationFailure = nil
    failedPreparation = nil
    failedPreparationSource = nil
    defer { busy = false }
    if fixture {
      try await Task.sleep(for: .seconds(2))
      guard bootstrap?.account.id == account else { throw CancellationError() }
      #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--fixture-generation-failure") {
        throw APIError(code: "generation_failed", message: "Question preparation failed. Your previous question is safe.", status: 503)
      }
      #endif
      let challenge = Challenge(engineeringLevel: preparation?.engineeringLevel ?? settings.selectedLevel,
        id: UUID().uuidString, lifecycle: "ready", title: "Design a reliable job queue",
        prompt: "Design a reliable job queue. Explain retries, ordering, and how failures are handled.",
        topic: preparation?.focus ?? settings.focus, session: SessionDraft(answer: "", revision: 0))
      bootstrap?.challenge = challenge
      return challenge
    }
    await sync()
    guard bootstrap?.account.id == account else { throw CancellationError() }
    if hasPendingWrites {
      throw APIError(code: "sync_pending", message: "Connect and sync your saved answer before starting another challenge.", status: 0)
    }
    let result: GenerationResponse = try await api.send("challenges", method: "POST", body: preparation, command: UUID().uuidString)
    let challenge: Challenge
    if let existing = result.challenge { challenge = existing }
    else if let id = result.id {
      try await waitForJob(id)
      guard bootstrap?.account.id == account else { throw CancellationError() }
      challenge = try await api.send("challenges/" + id)
    } else { throw APIError(code: "missing_question", message: "The question is not available yet. Check Today shortly.", status: 0) }
    guard bootstrap?.account.id == account else { throw CancellationError() }
    await refresh()
    return challenge
  }
  func waitForJob(_ id: String) async throws {
    for _ in 0..<45 {
      try Task.checkCancellation()
      let job: Job = try await api.send("jobs/" + id)
      if job.status == "completed" { return }
      if job.status == "failed" || job.status == "cancelled" {
        throw APIError(
          code: "job_failed", message: job.error ?? "The operation stopped. Try again.", status: 0)
      }
      try await Task.sleep(for: .seconds(2))
    }
    throw APIError(
      code: "job_pending", message: "Still preparing. You can leave and return later.", status: 0)
  }
  func open(_ challenge: Challenge) async {
    await perform { presented = try await openForPreview(challenge) }
  }
  func openForPreview(_ challenge: Challenge) async throws -> Challenge {
    let account = bootstrap?.account.id
    var loaded = challenge
    if !fixture {
      do { loaded = try await api.send("challenges/\(challenge.id)") } catch {
        if challenge.session == nil { throw error }
      }
    }
    guard bootstrap?.account.id == account else { throw CancellationError() }
    if let account {
      _ = try await disk.load(account: account, challenge: loaded)
    }
    guard bootstrap?.account.id == account else { throw CancellationError() }
    if loaded.lifecycle == "ready" {
      #if DEBUG
      if fixture && ProcessInfo.processInfo.arguments.contains("--fixture-start-failure") {
        throw APIError(code: "start_failed", message: "Could not start. Try again.", status: 503)
      }
      #endif
      if !fixture { loaded = try await api.send("challenges/\(challenge.id)/start", method: "POST") }
      else { loaded.lifecycle = "in_progress" }
    }
    guard loaded.isActive else { throw APIError(code: "inactive", message: "This session is no longer available to start.", status: 409) }
    guard bootstrap?.account.id == account else { throw CancellationError() }
    bootstrap?.challenge = loaded
    return loaded
  }
  func localAnswer(_ challenge: Challenge) async -> String {
    guard let account = bootstrap?.account.id else { return challenge.session?.answer ?? "" }
    do { return try await disk.load(account: account, challenge: challenge).answer } catch {
      self.error = "Your draft could not be opened. \(error.localizedDescription)"
      return challenge.session?.answer ?? ""
    }
  }
  func save(_ challenge: Challenge, answer: String, completing: Bool = false) async throws {
    guard let account = bootstrap?.account.id else { return }
    try await disk.save(account: account, id: challenge.id, answer: answer, completing: completing)
    saveStatus = "Saved on this device"
    hasPendingWrites = true
  }
  func sync() async {
    guard let account = bootstrap?.account.id, !syncing, !fixture else { return }
    syncing = true
    defer { syncing = false }
    do {
      let drafts = try await disk.pending(account: account)
      if let review = drafts.first(where: { $0.conflict }), conflict == nil {
        conflict = try await api.send("challenges/" + review.challengeID)
      }
      for draft in drafts where !draft.conflict {
        do {
          saveStatus = "Syncing"
          let receiptData = try await disk.cached(
            key: "practice:" + account + ":" + draft.challengeID + ":receipts")
          var receipts = receiptData.flatMap {
            try? JSONDecoder().decode([DeliveryReceipt].self, from: $0)
          }
          if draft.kind == "complete", let pending = receipts, pending.count > 100 {
            // Deliver older evidence first; the final batch is frozen with completion.
            for offset in stride(from: 0, to: pending.count - 100, by: 100) {
              let batch = Array(pending[offset..<min(offset + 100, pending.count - 100)])
              let _: EmptyResponse = try await api.send(
                "challenges/\(draft.challengeID)/deliveries", method: "POST",
                body: DeliveryInput(receipts: batch))
              try await disk.acknowledgeReceipts(
                key: "practice:" + account + ":" + draft.challengeID + ":receipts",
                ids: Set(batch.map(\.id)))
            }
            receipts = Array(pending.suffix(100))
          }
          let write = DraftWrite(
            answer: draft.answer, revision: draft.revision,
            receipts: draft.kind == "complete" ? receipts : nil)
          if draft.kind == "complete" {
            let result: Challenge = try await api.send(
              "challenges/\(draft.challengeID)/complete", method: "POST", body: write,
              command: draft.command)
            try await disk.acknowledge(
              account: account, sent: draft,
              revision: result.session?.revision ?? draft.revision + 1)
          } else {
            let result: RevisionResponse = try await api.send(
              "challenges/\(draft.challengeID)/draft", method: "PUT", body: write,
              command: draft.command)
            try await disk.acknowledge(account: account, sent: draft, revision: result.revision)
          }
          saveStatus = "Saved"
        } catch let failure as APIError where failure.status == 409 {
          try await disk.markConflict(account: account, id: draft.challengeID)
          conflict = try await api.send("challenges/\(draft.challengeID)")
          saveStatus = "Draft needs review"
        } catch {
          saveStatus = "Saved on this device · sync pending"
          break
        }
      }
      hasPendingWrites = try await !disk.pending(account: account).isEmpty
    } catch { self.error = error.localizedDescription }
  }
  func resolveConflict(keepLocal: Bool) async {
    guard let account = bootstrap?.account.id, let challenge = conflict else { return }
    await perform {
      try await disk.resolve(account: account, challenge: challenge, keepLocal: keepLocal)
      conflict = nil
      await sync()
    }
  }
  func finish(_ challenge: Challenge, answer: String) async throws -> Challenge {
    try await save(challenge, answer: answer, completing: true)
    await sync()
    if conflict != nil {
      throw APIError(
        code: "revision_conflict", message: "Review the conflicting draft before finishing.",
        status: 409)
    }
    var completed = challenge
    completed.lifecycle = "completed"
    completed.session = SessionDraft(answer: answer, revision: challenge.session?.revision ?? 0)
    if fixture {
      completed.reflection = Reflection(
        summary: "You separated the control plane from evaluation.",
        worked: ["Clear service boundaries"],
        improve: "Explain what happens when a rollback reaches only some clients.",
        takeaway: "Trace one stale configuration through the system.",
        strengths: ["Service boundaries"], gaps: ["Rollback consistency"])
      memory.sessions.insert(completed, at: 0)
    }
    bootstrap?.challenge = nil
    return completed
  }
  func skip(_ id: String) async {
    await perform {
      if !fixture {
        let _: EmptyResponse = try await api.send("challenges/\(id)/skip", method: "POST")
      }
      presented = nil
      await refresh()
    }
  }
  func updateSettings() async throws {
    settings.model = "google/gemini-3.1-flash-lite"
    settings.engineeringLevel = settings.selectedLevel
    if !fixture {
      let _: PracticeSettings = try await api.send("settings", method: "PUT", body: settings)
    }
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: ["daily-practice"])
    if settings.reminderEnabled {
      let granted = try await center.requestAuthorization(options: [.alert, .sound])
      if !granted {
        throw APIError(
          code: "notifications_denied",
          message: "Enable notifications for Drillbit in iPhone Settings.", status: 0)
      }
      let content = UNMutableNotificationContent()
      content.title = "Time for a practice session"
      content.body = "One question. A little space to think."
      content.userInfo = ["route": "today"]
      try await center.add(
        UNNotificationRequest(
          identifier: "daily-practice", content: content,
          trigger: UNCalendarNotificationTrigger(
            dateMatching: reminderComponents(minutes: settings.dailyMinutes, timezone: settings.timezone), repeats: true))
      )
    }
    await refresh()
  }
  func retry(_ job: Job) async {
    await perform {
      let result: Job = try await api.send(
        "jobs/\(job.id)/retry", method: "POST", command: UUID().uuidString)
      try await waitForJob(result.id)
      await refresh()
    }
  }
  func signOut(discard: Bool = false, deleting: Bool = false) async throws {
    if !deleting { await sync() }
    if hasPendingWrites && !discard {
      throw APIError(
        code: "unsynced",
        message: "Some edits have not synced. Try again online, or explicitly discard local edits.",
        status: 0)
    }
    if !fixture {
      if !deleting, let id = SharedStore.secret("deviceID") {
        let _: EmptyResponse = try await api.send("devices/" + id, method: "DELETE")
      }
      if deleting {
        try? await Clerk.shared.auth.signOut()
      } else {
        try await Clerk.shared.auth.signOut()
      }
    }
    try await disk.clear()
    for key in ["account", "subject", "widgetToken", "widgetTokenExpires", "deviceID", "apiURL"] {
      try SharedStore.setSecret(nil, key: key)
    }
    try SharedStore.save(WidgetSnapshot(challenge: nil, updatedAt: ""))
    WidgetCenter.shared.reloadAllTimelines()
    UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    bootstrap = nil
    preparationFailure = nil
    failedPreparation = nil
    failedPreparationSource = nil
    presented = nil
    memory = MemoryResponse(sessions: [], patterns: [])
  }
  private func seedFixture() {
    settings.onboardingComplete = true
    #if DEBUG
    if ProcessInfo.processInfo.arguments.contains("--fixture-onboarding") { settings.onboardingComplete = false }
    if ProcessInfo.processInfo.arguments.contains("--fixture-long-focus") { settings.focus = "Distributed backend systems, database performance, cache consistency, and safe cross-team migrations" }
    #endif
    var challenge = Challenge(
      id: "11111111-1111-4111-8111-111111111111", lifecycle: "ready",
      title: "Design a feature-flag control plane",
      prompt:
        "Design a feature-flag platform that supports staged rollouts, low-latency evaluation, audit trails and emergency rollback. How would you keep evaluation available when the control plane is unreachable?",
      topic: "System design", session: SessionDraft(answer: "", revision: 0), turns: [])
    #if DEBUG
    if ProcessInfo.processInfo.arguments.contains("--fixture-long-question") {
      challenge.prompt = String(repeating: "Describe the trade-offs, retry boundaries, and operational failure handling. State your assumptions and explain the consequences.\n\n", count: 18)
    }
    #endif
    #if DEBUG
    if ProcessInfo.processInfo.arguments.contains("--fixture-dashboard") {
      let recent = Challenge(difficulty: "easy", id: "recent", lifecycle: "completed", title: "Design a reliable job queue", prompt: "", topic: "Backend", completedAt: "2026-09-09T10:30:00Z")
      memory = MemoryResponse(statistics: .init(completed: 12, lastSevenDays: 4, asOf: ISO8601DateFormatter().string(from: Date())), sessions: [recent], patterns: [])
    }
    #endif
    bootstrap = Bootstrap(
      account: .init(id: "fixture", status: "active"), settings: settings, challenge: challenge,
      jobs: [])
    #if DEBUG
    if ProcessInfo.processInfo.arguments.contains("--fixture-dashboard") { bootstrap?.challenge = nil }
    #endif
  }
}
