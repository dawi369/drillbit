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
  private var homeCacheAccount: String?
  private var memoryRequestVersion = 0
  private var launching = true
  private(set) var restoringSession = true
  private(set) var launchError: String?
  private var cacheGeneration = 0
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
  private var syncTask: Task<Void, Never>?
  private var refreshing = false
  private var monitor = NWPathMonitor()
  private let logger = Logger(subsystem: "dawi.drillbit", category: "application")
  init(container: ModelContainer, baseURL: URL, fixture: Bool, client: APIClient? = nil, monitorNetwork: Bool = true) {
    disk = DiskStore(modelContainer: container)
    api = client ?? APIClient(baseURL: baseURL)
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
    if monitorNetwork { monitor.start(queue: DispatchQueue(label: "drillbit.connectivity")) }
  }
  // Account and filter scoped snapshots survive navigation; only committed writes refresh them.
  var librarySnapshots: [String: LibraryPage] = [:]
  var libraryDetailSnapshots: [String: LibraryDetail] = [:]
  private var libraryCompletionTasks: [String: Task<Void, Never>] = [:]
  private var libraryWarmAccount: String?
  private var libraryWarmTask: Task<Void, Never>?
  var librarySessions: [String: Challenge] = [:]
  private var locallySkipped: [String: Set<String>] = [:]
  func isLocallySkipped(account: String, id: String) -> Bool { locallySkipped[account]?.contains(id) == true }
  var libraryVersion = 0
  var libraryCoverage: [CoverageResponse.Entry] = []

  /// Warm the first 25 completed and skipped questions, including their attempt lists.
  /// Navigation consumes these snapshots; only committed mutations invalidate them.
  private func awaitLibraryResults(challengeID: String, account: String) {
    guard libraryCompletionTasks[challengeID] == nil else { return }
    libraryCompletionTasks[challengeID] = Task { @MainActor in
      defer { self.libraryCompletionTasks[challengeID] = nil }
      for _ in 0..<90 {
        guard !Task.isCancelled, self.bootstrap?.account.id == account else { return }
        if let result: Challenge = try? await self.api.send("challenges/" + challengeID), result.lifecycle == "completed", result.reflection != nil {
          await self.loadMemory()
          await self.preloadLibrary(force: true)
          return
        }
        do { try await Task.sleep(for: .seconds(2)) } catch { return }
      }
    }
  }
  func preloadLibrary(force: Bool = false, onlySkipped: Bool = false) async {
    guard let account = bootstrap?.account.id else { return }
    if let task = libraryWarmTask { await task.value; if !force, libraryWarmAccount == account { return } }
    if !force, libraryWarmAccount == account { return }
    libraryWarmAccount = account
    let task = Task { @MainActor in
      var pages = force ? self.librarySnapshots.filter { $0.key.hasSuffix(":|||0|false") || $0.key.hasSuffix(":|||0|true") } : self.librarySnapshots
      var details = self.libraryDetailSnapshots
      for skipped in (onlySkipped ? [true] : [false, true]) {
        let key = "library:" + account + ":|||0|" + String(skipped)
        if pages[key] == nil, let data = try? await self.disk.cached(key: key), let cached = try? JSONDecoder().decode(LibraryPage.self, from: data) { pages[key] = cached }
        let path = "library?q=&skipped=" + String(skipped) + "&concepts="
        if let page = try? await self.libraryResponse(path: path) { pages[key] = page }
        guard self.bootstrap?.account.id == account else { return }
        if let page = pages[key] {
          for batchStart in stride(from: 0, to: page.questions.count, by: 5) {
            let batch = Array(page.questions[batchStart..<min(batchStart + 5, page.questions.count)])
            await withTaskGroup(of: (String, LibraryDetail?).self) { group in
              for q in batch { group.addTask {
                var detail = try? await self.libraryDetail(id: q.id, path: "questions/" + q.id)
                if let first = detail?.attempts.first, !self.fixture, let full: Challenge = try? await self.api.send("challenges/" + first.id) { detail?.attempts[0] = full }
                return (q.id, detail)
              } }
              for await (id, detail) in group {
                let detailKey = "library-detail:" + account + ":" + id
                if let detail { details[detailKey] = detail; try? await self.disk.cache(key: detailKey, data: JSONEncoder().encode(detail)) }
                else if details[detailKey] == nil, let data = try? await self.disk.cached(key: detailKey) { details[detailKey] = try? JSONDecoder().decode(LibraryDetail.self, from: data) }
              }
            }
          }
          try? await self.disk.cache(key: key, data: JSONEncoder().encode(page))
        }
      }
      guard self.bootstrap?.account.id == account else { return }
      if !onlySkipped, !self.fixture, let value: CoverageResponse = try? await self.api.send("library/coverage") { self.libraryCoverage = value.concepts }
      guard self.bootstrap?.account.id == account else { return }
      for detail in details.values { for attempt in detail.attempts where attempt.session != nil { self.librarySessions[account + ":" + attempt.id] = attempt } }
      let pending = (try? await self.disk.cached(key: "eligibility:" + account)).flatMap { try? JSONDecoder().decode([EligibilityCommand].self, from: $0) } ?? []
      for command in pending {
        details["library-detail:" + account + ":" + command.questionId]?.question.eligible = command.eligible
        for key in pages.keys where key.hasSuffix("true") {
          pages[key]?.questions.removeAll { $0.id == command.questionId && command.eligible }
        }
      }
      self.libraryDetailSnapshots = details
      self.librarySnapshots = pages
      self.libraryVersion += 1
    }
    libraryWarmTask = task
    await task.value
    libraryWarmTask = nil
  }
  var taxonomy: [PracticeConcept] = []
  var fixtureLibrary: [LibraryQuestion] = []
  var fixtureLibraryAttempts: [String: [Challenge]] = [:]
  func libraryResponse(path: String) async throws -> LibraryPage {
    if !fixture { return try await api.send(path) }
    await loadTaxonomy()
    let query = URLComponents(string: "https://fixture/" + path)?.queryItems ?? []
    let skipped = query.first { $0.name == "skipped" }?.value == "true"
    let search = query.first { $0.name == "q" }?.value ?? ""
    let concepts = (query.first { $0.name == "concepts" }?.value ?? "").split(separator: ",").map(String.init)
    let rows = fixtureLibrary.filter { q in
      let last = fixtureLibraryAttempts[q.id]?.first
      return (skipped ? last?.lifecycle == "skipped" && !q.eligible : fixtureLibraryAttempts[q.id]?.contains { $0.lifecycle == "completed" } == true)
        && (search.isEmpty || q.title.localizedCaseInsensitiveContains(search))
        && (concepts.isEmpty || concepts.contains { q.conceptIds.contains($0) })
    }
    return LibraryPage(questions: rows, nextCursor: nil)
  }
  func libraryDetail(id: String, path: String) async throws -> LibraryDetail {
    if !fixture { return try await api.send(path) }
    await loadTaxonomy()
    guard let q = fixtureLibrary.first(where: { $0.id == id }) else { throw CancellationError() }
    return LibraryDetail(question: q, attempts: fixtureLibraryAttempts[id] ?? [], nextCursor: nil)
  }
  func startLibraryQuestion(_ question: LibraryQuestion, command: String) async throws -> Challenge {
    if !fixture { return try await api.send("questions/" + question.id + "/start", method: "POST", command: command) }
    let attempt = Challenge(questionId: question.id, scenario: question.scenario, primaryConceptId: question.primaryConceptId, conceptIds: question.conceptIds, engineeringLevel: question.engineeringLevel, id: command, lifecycle: "in_progress", title: question.title, prompt: question.prompt, topic: "System design", session: SessionDraft(answer: "", revision: 0))
    fixtureLibraryAttempts[question.id, default: []].insert(attempt, at: 0)
    return attempt
  }
  func loadTaxonomy() async {
    if fixture {
      if taxonomy.isEmpty {
        taxonomy = [PracticeConcept(id: "queues", label: "Queues & streams", category: "Async & coordination", aliases: []), PracticeConcept(id: "retry-safety", label: "Retry safety & idempotency", category: "Async & coordination", aliases: []), PracticeConcept(id: "caching", label: "Caching", category: "Traffic & performance", aliases: [])]
        for (id, title, state) in [("library-completed", "Design notification delivery", "completed"), ("library-skipped", "Design a distributed scheduler", "skipped")] {
          let question = LibraryQuestion(id: id, title: title, prompt: "Design a durable service that handles worker failures and retries. Explain how you prevent duplicate side effects and preserve accepted work.", scenario: "Notification service", engineeringLevel: "senior", primaryConceptId: "queues", conceptIds: ["queues", "retry-safety"], eligible: false, eligibilityRevision: 0, lastActivity: "2026-09-10T12:00:00Z", attemptCount: state == "completed" ? 1 : 0)
          fixtureLibrary.append(question)
          fixtureLibraryAttempts[id] = [Challenge(id: id + "-attempt", lifecycle: state, title: title, prompt: question.prompt, topic: "System design", createdAt: question.lastActivity, completedAt: state == "completed" ? question.lastActivity : nil, session: SessionDraft(answer: "My preserved original reasoning", revision: 1))]
        }
      }
      return
    }
    guard let account = bootstrap?.account.id else { return }
    do { let response: TaxonomyResponse = try await api.send("taxonomy"); guard bootstrap?.account.id == account else { return }; taxonomy = response.concepts; try await disk.cache(key: "taxonomy:" + account, data: JSONEncoder().encode(response)) }
    catch { if let data = try? await disk.cached(key: "taxonomy:" + account), let response = try? JSONDecoder().decode(TaxonomyResponse.self, from: data) { taxonomy = response.concepts } }
  }
  func acceptEpoch(_ result: Bootstrap) async throws {
    guard let epoch = result.practiceEpoch else { return }
    let key = "epoch:" + result.account.id
    let old = try await disk.cached(key: key).flatMap { String(data: $0, encoding: .utf8) }
    if old != epoch {
      try await disk.clearPractice(account: result.account.id)
      librarySnapshots = [:]; libraryDetailSnapshots = [:]; libraryWarmAccount = nil; librarySessions = [:]
      presented = nil; conflict = nil; hasPendingWrites = false
      if bootstrap?.account.id == result.account.id { bootstrap?.challenge = result.challenge; bootstrap?.jobs = result.jobs }
      try SharedStore.save(WidgetSnapshot(challenge: result.challenge, updatedAt: Date().ISO8601Format()))
      memory = MemoryResponse(sessions: [], patterns: [])
      homeCacheAccount = nil; memoryRequestVersion += 1; cacheGeneration += 1
      UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
      try await disk.cache(key: key, data: Data(epoch.utf8))
    }
  }
  func queueEligibility(_ question: LibraryQuestion, eligible: Bool) async throws {
    if fixture { if let index = fixtureLibrary.firstIndex(where: { $0.id == question.id }) { fixtureLibrary[index].eligible = eligible; fixtureLibrary[index].eligibilityRevision += 1
      if let account = bootstrap?.account.id { libraryDetailSnapshots["library-detail:" + account + ":" + question.id]?.question = fixtureLibrary[index] }
    }
      for key in librarySnapshots.keys where key.hasSuffix("true") { librarySnapshots[key]?.questions.removeAll { $0.id == question.id && eligible } }
      libraryVersion += 1
      return }
    guard let account = bootstrap?.account.id else { throw CancellationError() }
    try await disk.enqueueEligibility(account: account, command: EligibilityCommand(id: UUID().uuidString, questionId: question.id, revision: question.eligibilityRevision, eligible: eligible))
    guard bootstrap?.account.id == account else { return }
    let detailKey = "library-detail:" + account + ":" + question.id
    libraryDetailSnapshots[detailKey]?.question.eligible = eligible
    for key in librarySnapshots.keys where key.hasSuffix("true") {
      librarySnapshots[key]?.questions.removeAll { $0.id == question.id && eligible }
    }
    libraryVersion += 1
    hasPendingWrites = true
    Task { await sync(drainNewCommands: true) }
  }

  private func drainEligibility(account: String) async throws {
    let key = "eligibility:" + account
    let commands = try await disk.cached(key: key).flatMap { try JSONDecoder().decode([EligibilityCommand].self, from: $0) } ?? []
    for command in commands {
      guard bootstrap?.account.id == account else { throw CancellationError() }
      do { let updated: LibraryQuestion = try await api.send("questions/" + command.questionId + "/eligibility", method: "PUT", body: EligibilityInput(revision: command.revision, eligible: command.eligible), command: command.id)
        guard bootstrap?.account.id == account else { throw CancellationError() }
        let detailKey = "library-detail:" + account + ":" + command.questionId
        libraryDetailSnapshots[detailKey]?.question = updated
        for key in librarySnapshots.keys { librarySnapshots[key]?.questions.removeAll { $0.id == updated.id && updated.eligible && key.hasSuffix("true") } }
        libraryVersion += 1
      }
      catch let failure as APIError where [404,409].contains(failure.status) {
        guard bootstrap?.account.id == account else { throw CancellationError() }
        error = failure.message
        try await disk.acknowledgeEligibility(account: account, command: command.id)
        await preloadLibrary(force: true, onlySkipped: true)
        continue
      }
      try await disk.acknowledgeEligibility(account: account, command: command.id)
    }
  }
  func perform(_ action: () async throws -> Void) async {
    do { try await action() } catch is CancellationError {} catch {
      self.error = error.localizedDescription
      logger.error("Operation failed; details shown in UI")
    }
  }
  /// Hydrate authenticated account data locally before publishing Home.
  private func restoreHomeCache(account: String) async {
    guard homeCacheAccount != account else { return }
    let generation = cacheGeneration
    var restoredMemory = MemoryResponse(sessions: [], patterns: [])
    if let data = try? await disk.cached(key: "memory:" + account),
       let cached = try? JSONDecoder.api.decode(MemoryResponse.self, from: data) { restoredMemory = cached }
    var pages: [String: LibraryPage] = [:]
    var details: [String: LibraryDetail] = [:]
    for skipped in [false, true] {
      let key = "library:" + account + ":|||0|" + String(skipped)
      if let data = try? await disk.cached(key: key), let page = try? JSONDecoder().decode(LibraryPage.self, from: data) {
        pages[key] = page
        for question in page.questions {
          let detailKey = "library-detail:" + account + ":" + question.id
          if let data = try? await disk.cached(key: detailKey), let detail = try? JSONDecoder().decode(LibraryDetail.self, from: data) { details[detailKey] = detail }
        }
      }
    }
    let pending = (try? await disk.cached(key: "eligibility:" + account)).flatMap { try? JSONDecoder().decode([EligibilityCommand].self, from: $0) } ?? []
    for command in pending {
      details["library-detail:" + account + ":" + command.questionId]?.question.eligible = command.eligible
      for key in pages.keys where key.hasSuffix("true") { pages[key]?.questions.removeAll { $0.id == command.questionId && command.eligible } }
    }
    let cachedTaxonomy = (try? await disk.cached(key: "taxonomy:" + account)).flatMap { try? JSONDecoder().decode(TaxonomyResponse.self, from: $0) }
    guard cacheGeneration == generation else { return }
    memory = restoredMemory
    librarySnapshots = pages
    libraryDetailSnapshots = details
    librarySessions = [:]
    for detail in details.values { for attempt in detail.attempts where attempt.session != nil { librarySessions[account + ":" + attempt.id] = attempt } }
    taxonomy = cachedTaxonomy?.concepts ?? []
    homeCacheAccount = account
    libraryVersion += 1
  }
  func launch() async {
    restoringSession = true
    launchError = nil
    defer { restoringSession = false }
    if fixture {
      if ProcessInfo.processInfo.arguments.contains("--fixture-slow-launch") {
        try? await Task.sleep(for: .seconds(8))
      }
      if ProcessInfo.processInfo.arguments.contains("--fixture-signed-out") {
        launching = false
        return
      }
      seedFixture()
      if ProcessInfo.processInfo.arguments.contains("--fixture-cached-home"), let seeded = bootstrap {
        bootstrap = nil
        try? await disk.cache(key: "memory:" + seeded.account.id, data: JSONEncoder().encode(memory))
        memory = MemoryResponse(sessions: [], patterns: [])
        await restoreHomeCache(account: seeded.account.id)
        bootstrap = seeded
      }
      launching = false
      await preloadLibrary()
      return
    }
    for _ in 0..<25 {
      if Clerk.shared.isLoaded { break }
      try? await Task.sleep(for: .milliseconds(200))
      if Task.isCancelled { return }
    }
    guard Clerk.shared.isLoaded else {
      launchError = "Couldn’t restore your session. Check your connection and try again."
      return
    }
    if let subject = Clerk.shared.user?.id, subject == SharedStore.secret("subject"),
      let account = SharedStore.secret("account"),
      let data = try? await disk.cached(key: "bootstrap:" + account),
      let cached = try? JSONDecoder.api.decode(Bootstrap.self, from: data)
    {
      try? await acceptEpoch(cached)
      await restoreHomeCache(account: account)
      guard Clerk.shared.user?.id == subject else { launching = false; return }
      bootstrap = cached
      if let id = cached.challenge?.id, (try? await disk.pendingSkips(account: account).contains(id)) == true { bootstrap?.challenge = nil }
      settings = cached.settings
      restoringSession = false
    }
    launching = false
    if Clerk.shared.user == nil { return }
    await refresh()
    if bootstrap == nil, Clerk.shared.user != nil {
      launchError = "Couldn’t load your account. Your saved practice is safe. Try again."
      error = nil
    }
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
    guard !fixture, !refreshing, !launching else { return }
    let subject = Clerk.shared.user?.id
    refreshing = true
    defer { refreshing = false }
    do {
      let result: Bootstrap = try await api.send("bootstrap")
      guard Clerk.shared.user?.id == subject else { return }
      try await acceptEpoch(result)
      if bootstrap?.account.id != result.account.id { bootstrap = nil }
      await restoreHomeCache(account: result.account.id)
      guard Clerk.shared.user?.id == subject else { return }
      bootstrap = result
      let queuedSkips = try await disk.pendingSkips(account: result.account.id)
      if let id = result.challenge?.id, locallySkipped[result.account.id]?.contains(id) == true || queuedSkips.contains(id) { bootstrap?.challenge = nil }
      settings = result.settings
      try? await reconcileReminder()
      try SharedStore.setSecret(result.account.id, key: "account")
      try SharedStore.setSecret(Clerk.shared.user?.id, key: "subject")
      try await disk.cache(
        key: "bootstrap:" + result.account.id, data: JSONEncoder().encode(bootstrap ?? result))
      if result.account.status == "active" {
        await loadMemory()
        await preloadLibrary()
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
    memoryRequestVersion += 1
    let version = memoryRequestVersion
    let epoch = bootstrap?.practiceEpoch
    do {
      let updated: MemoryResponse = try await api.send("memory")
      guard bootstrap?.account.id == account, bootstrap?.practiceEpoch == epoch, memoryRequestVersion == version else { return }
      memory = updated
      try await disk.cache(key: "memory:" + account, data: JSONEncoder().encode(updated))
    } catch { /* Keep the already-published snapshot during failed refreshes. */ }
  }
  func refreshAfterSessionDeletion() async throws {
    guard let account = bootstrap?.account.id else { return }
    if let task = libraryWarmTask { await task.value }
    guard bootstrap?.account.id == account else { return }
    try await disk.invalidateLibrary(account: account)
    libraryDetailSnapshots = [:]; librarySessions = [:]; librarySnapshots = [:]
    libraryCoverage = []; libraryVersion += 1
    await loadMemory()
    await preloadLibrary(force: true)
  }
  func generate(_ preparation: PreparationInput? = nil) async {
    await perform { _ = try await generateForPreview(preparation) }
  }
  func generateForPreview(_ preparation: PreparationInput? = nil) async throws -> Challenge {
    guard !busy, let account = bootstrap?.account.id else {
      throw APIError(code: "busy", message: "A question is already being prepared.", status: 409)
    }
    busy = true
    defer { busy = false }
    if !fixture {
      await sync()
      guard bootstrap?.account.id == account else { throw CancellationError() }
      guard try await disk.pendingSkips(account: account).isEmpty else {
        throw APIError(code: "skip_pending", message: "Your skip is saved. Connect to prepare the next question.", status: 0)
      }
    }
    preparationFailure = nil
    failedPreparation = nil
    failedPreparationSource = nil
    if fixture {
      #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--fixture-slow-generation") {
        try await Task.sleep(for: .seconds(6))
      }
      #endif
      try await Task.sleep(for: .seconds(2))
      guard bootstrap?.account.id == account else { throw CancellationError() }
      #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--fixture-generation-failure") {
        throw APIError(code: "generation_failed", message: "Question preparation failed. Your previous question is safe.", status: 503)
      }
      #endif
      let challenge = Challenge(interviewStyle: preparation?.interviewStyle ?? .standard, engineeringLevel: preparation?.engineeringLevel ?? settings.selectedLevel,
        id: UUID().uuidString, lifecycle: "ready", title: "Design a reliable job queue",
        prompt: "Design a reliable job queue. Explain retries, ordering, and how failures are handled.",
        topic: preparation?.focus ?? settings.focus, session: SessionDraft(answer: "", revision: 0))
      bootstrap?.challenge = challenge
      return challenge
    }
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
    } else { throw APIError(code: "missing_question", message: "The question is not available yet. Check Home shortly.", status: 0) }
    guard bootstrap?.account.id == account else { throw CancellationError() }
    bootstrap?.challenge = challenge
    Task {
      guard bootstrap?.account.id == account else { return }
      await refresh()
    }
    return challenge
  }
  func waitForJob(_ id: String) async throws {
    let started = Date()
    let deadline = started.addingTimeInterval(90)
    while Date() < deadline {
      try Task.checkCancellation()
      let job: Job = try await api.send("jobs/" + id)
      if job.status == "completed" { return }
      if job.status == "failed" || job.status == "cancelled" {
        throw APIError(
          code: "job_failed", message: job.error ?? "The operation stopped. Try again.", status: 0)
      }
      try await Task.sleep(for: .milliseconds(Date().timeIntervalSince(started) < 10 ? 500 : 1500))
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
    guard !isLocallySkipped(account: account, id: challenge.id) else { return }
    try await disk.save(account: account, id: challenge.id, answer: answer, completing: completing)
    saveStatus = "Saved on this device"
    hasPendingWrites = try await !disk.pending(account: account).isEmpty
  }
  func waitForCurrentSync() async { if let syncTask { await syncTask.value } }
  func sync(challengeID: String? = nil, drainNewCommands: Bool = false) async {
    if let running = syncTask {
      await running.value
      // A caller preparing a submission must drain edits queued during the previous pass.
      if challengeID != nil || drainNewCommands { await sync(challengeID: challengeID) }
      return
    }
    let task = Task {
      defer { syncTask = nil }
      await drainSync(challengeID: challengeID)
    }
    syncTask = task
    await task.value
  }
  private func drainSync(challengeID: String?) async {
    guard let account = bootstrap?.account.id, !fixture else { return }
    do {
      let queuedSkips = try await disk.pendingSkips(account: account)
      let queuedEligibility = try await disk.cached(key: "eligibility:" + account).flatMap { try JSONDecoder().decode([EligibilityCommand].self, from: $0) } ?? []
      let queuedDrafts = try await disk.pending(account: account)
      let queuedVoice = try await disk.hasPendingVoice(account: account)
      hasPendingWrites = !queuedSkips.isEmpty || !queuedEligibility.isEmpty || !queuedDrafts.isEmpty || queuedVoice
      let remote: Bootstrap = try await api.send("bootstrap")
      try await acceptEpoch(remote)
      guard bootstrap?.account.id == account else { return }
      let skips = try await disk.pendingSkips(account: account)
      for id in skips {
        do {
          let _: EmptyResponse = try await api.send("challenges/" + id + "/skip", method: "POST")
        } catch let failure as APIError where failure.status == 404 {
          // An already removed attempt needs no further mutation.
        }
        guard bootstrap?.account.id == account else { return }
        try await disk.acknowledgeSkip(account: account, id: id)
        locallySkipped[account, default: []].insert(id)
        if conflict?.id == id { conflict = nil }
        if bootstrap?.challenge?.id == id { bootstrap?.challenge = nil }
      }
      if !skips.isEmpty { await preloadLibrary(force: true, onlySkipped: true) }
      try await drainEligibility(account: account)
      let drafts = try await disk.pending(account: account).filter { challengeID == nil || $0.challengeID == challengeID }
      if let review = drafts.first(where: { $0.conflict }), conflict == nil {
        conflict = try await api.send("challenges/" + review.challengeID)
      }
      for draft in drafts where !draft.conflict {
        let interviewKey = "interview:" + account + ":" + draft.challengeID + ":pending"
        if let data = try await disk.cached(key: interviewKey), (try? JSONDecoder().decode(PendingInterviewCommand.self, from: data)) != nil { continue }
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
            awaitLibraryResults(challengeID: draft.challengeID, account: account)
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
      let pendingDrafts = try await !disk.pending(account: account).isEmpty
      let pendingSkips = try await !disk.pendingSkips(account: account).isEmpty
      let pendingEligibility = try await disk.cached(key: "eligibility:" + account).flatMap { try JSONDecoder().decode([EligibilityCommand].self, from: $0) } ?? []
      let pendingVoice = try await disk.hasPendingVoice(account: account)
      hasPendingWrites = pendingDrafts || pendingSkips || !pendingEligibility.isEmpty || pendingVoice
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
  func skip(_ id: String, answer: String? = nil) async {
    guard let account = bootstrap?.account.id else { return }
    await perform {
      if !fixture { try await disk.queueSkip(account: account, id: id, answer: answer) }
      guard bootstrap?.account.id == account else { return }
      locallySkipped[account, default: []].insert(id)
      if bootstrap?.challenge?.id == id { bootstrap?.challenge = nil }
      presented = nil
      if let bootstrap { try? await disk.cache(key: "bootstrap:" + account, data: JSONEncoder().encode(bootstrap)) }
      if !fixture {
        hasPendingWrites = true
        Task { await sync(challengeID: id) }
      }
    }
  }
  func updateSettings() async throws {
    settings.model = "google/gemini-3.1-flash-lite"
    settings.engineeringLevel = settings.selectedLevel
    if !fixture {
      let _: PracticeSettings = try await api.send("settings", method: "PUT", body: settings)
    }
    try await reconcileReminder(requestPermission: true)
    await refresh()
  }
  func reconcileReminder(requestPermission: Bool = false) async throws {
    guard !fixture else { return }
    let center = UNUserNotificationCenter.current()
    guard settings.reminderEnabled else {
      center.removePendingNotificationRequests(withIdentifiers: ["daily-practice"])
      return
    }
    var authorization = await center.notificationSettings().authorizationStatus
    if requestPermission && authorization == .notDetermined {
      _ = try await center.requestAuthorization(options: [.alert, .sound])
      authorization = await center.notificationSettings().authorizationStatus
    }
    guard authorization == .authorized || authorization == .provisional else {
      center.removePendingNotificationRequests(withIdentifiers: ["daily-practice"])
      if requestPermission { throw APIError(code: "notifications_denied", message: "Your practice time is saved. Enable notifications for Drillbit in iPhone Settings to receive reminders.", status: 0) }
      return
    }
    let content = UNMutableNotificationContent()
    content.title = "A little space to think"
    content.body = "Your practice is here whenever you’re ready."
    content.userInfo = ["route": "home"]
    try await center.add(UNNotificationRequest(identifier: "daily-practice", content: content,
      trigger: UNCalendarNotificationTrigger(dateMatching: reminderComponents(minutes: settings.dailyMinutes, timezone: settings.timezone), repeats: true)))
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
    libraryWarmTask?.cancel(); libraryWarmTask = nil; libraryWarmAccount = nil
    librarySnapshots = [:]; libraryDetailSnapshots = [:]; librarySessions = [:]; libraryCoverage = []
    bootstrap = nil
    preparationFailure = nil
    failedPreparation = nil
    failedPreparationSource = nil
    presented = nil
    memory = MemoryResponse(sessions: [], patterns: [])
    homeCacheAccount = nil; memoryRequestVersion += 1; cacheGeneration += 1
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
      if ProcessInfo.processInfo.arguments.contains("--fixture-evidence") {
        memory.evidence = [LearningEvidence(conceptId: "queues", observation: "Defined a bounded retry policy.", quote: "Retry at most three times.", signal: "demonstrated", assistance: "unknown", sessionId: "recent", at: "2026-09-09T10:30:00Z")]
      }
    }
    #endif
    #if DEBUG
    if ProcessInfo.processInfo.arguments.contains("--fixture-interview-history") {
      challenge.lifecycle = "in_progress"
      var current = challenge.prompt
      var turns: [InterviewTurn] = []
      for index in 1...3 {
        let short = index == 1 && ProcessInfo.processInfo.arguments.contains("--fixture-short-turn")
        let next = short ? "Hello there." : "Follow-up \(index): How would your design handle failure in component \(index)?"
        turns.append(InterviewTurn(id: "history-\(index)", ordinal: index - 1, kind: "answer", prompt: current,
          text: short ? "Hello interviewer" : "Decision \(index). " + String(repeating: "Use durable records, bounded retries and explicit ownership. Explain the recovery path and its trade-offs.\n\n", count: 4),
          createdAt: "2026-09-09T18:00:00Z", jobId: "history-\(index)", status: "completed", result: InterviewResponse(outcome: "follow_up", text: next)))
        current = next
      }
      challenge.interview = InterviewState(prompt: current, turns: turns)
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
