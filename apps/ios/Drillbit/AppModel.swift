import AVFAudio
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
  var recall = RecallDeckResponse(cards: [], dueCount: 0)
  private(set) var recallLoaded = false
  private(set) var recallFetchedAt: Date?
  private var recallRequestVersion = 0
  private var homeCacheAccount: String?
  private var memoryRequestVersion = 0
  private var launching = true
  private var accountResetGeneration = 0
  private(set) var restoringSession = true
  private(set) var launchError: String?
  private var cacheGeneration = 0
  var settings = PracticeSettings()
  var pendingSettings: PendingSettings?
  var settingsSyncError: String?
  private var settingsSyncTask: Task<Void, Never>?
  private var settingsSyncID: UUID?
  private var settingsSaveGeneration = 0
  var presented: Challenge?
  /// The challenge whose preview chose talking; its interview opens straight into voice.
  var talkOnOpen: String?
  /// ICE gathered while the question is still being written, so Start skips most of “Connecting”. Never a billed session.
  var voiceWarmup: (link: NativeVoiceTransport, offer: Task<String, Error>, date: Date)?
  /// How setup said they want to practise: `voice`, `text` or `mix`. Device-local; Settings can change it.
  var practiceMode: String {
    get { UserDefaults.standard.string(forKey: "practiceMode") ?? "voice" }
    set { UserDefaults.standard.set(newValue, forKey: "practiceMode") }
  }
  /// Interviews open out loud unless they asked to type. Fixture runs open in text unless `--fixture-talk`, so the text-room tests stay deterministic.
  func warmVoice() async {
    guard !fixture, voiceFirst, voiceWarmup == nil, AVAudioApplication.shared.recordPermission == .granted else { return }
    let account = bootstrap?.account.id
    if bootstrap?.capabilities?.voice?.isFresh() != true, let refreshed: Bootstrap = try? await api.send("bootstrap") {
      guard account == bootstrap?.account.id else { return }
      bootstrap?.capabilities = refreshed.capabilities
    }
    guard bootstrap?.capabilities?.voice?.available == true, voiceWarmup == nil else { return }
    let link = NativeVoiceTransport()
    voiceWarmup = (link, Task { try await link.offer() }, Date())
  }
  func takeVoiceWarmup() -> (link: NativeVoiceTransport, offer: Task<String, Error>, date: Date)? {
    defer { voiceWarmup = nil }
    guard let warm = voiceWarmup else { return nil }
    if Date().timeIntervalSince(warm.date) > 60 { warm.offer.cancel(); warm.link.close(); return nil }
    return warm
  }
  var voiceFirst: Bool {
    #if DEBUG
    if fixture { return ProcessInfo.processInfo.arguments.contains("--fixture-talk") }
    #endif
    // Out of voice for now (a spent free taste): open in text instead of a voice room that can only say no.
    return practiceMode != "text" && bootstrap?.capabilities?.voice?.available != false
  }
  var firstUse = FirstUseProgress()

  func setFirstUse(_ value: FirstUseProgress) async throws {
    guard let account = bootstrap?.account.id else { throw CancellationError() }
    try await disk.cache(key: "first-use:" + account, data: JSONEncoder().encode(value))
    guard bootstrap?.account.id == account else { throw CancellationError() }
    firstUse = value
  }
  /// The one reminder offer, under the first rep's feedback.
  func answerReminderOffer(_ accepted: Bool) async {
    var progress = firstUse
    progress.reminderOffered = true
    try? await setFirstUse(progress)
    guard accepted, await requestReminderPermission() else { return }
    settings.reminderEnabled = true
    do { try await saveSettingsLocally(); try await reconcileReminder() } catch let failure { error = failure.localizedDescription }
  }
  func markRecallIntroduced() async {
    guard !firstUse.recallIntroduced else { return }
    var progress = firstUse
    progress.recallIntroduced = true
    try? await setFirstUse(progress)
  }
  /// The completion screen after Finish is developer-only for now; everyone else goes straight back to Home.
  /// The completion screen is parked for everyone: finishing shows the rep-done moment and returns Home.
  var showsReflection: Bool { false }
  /// The first finished rep earns one reminder offer: a popup on Home, or the completion screen for developers.
  var offersReminder: Bool { firstUse.firstRepID != nil && !firstUse.reminderOffered && !settings.reminderEnabled }
  var reminderTimeText: String {
    let minutes = settings.dailyMinutes
    return Calendar.current.date(from: DateComponents(hour: minutes / 60, minute: minutes % 60))?.formatted(date: .omitted, time: .shortened) ?? "12:30"
  }
  /// Shown once when a receipt belongs to another account.
  var entitlementNotice: String?
  var isPro: Bool { bootstrap?.account.plan == "pro" || bootstrap?.practice?.freeReps == false }
  /// The server just confirmed Pro (with a purchase or restore): unlock now, before the next bootstrap lands.
  func applyConfirmedPro() {
    bootstrap?.account.plan = "pro"
    bootstrap?.practice = PracticeAccess(plan: "pro", freeReps: false, available: true)
    if var voice = bootstrap?.capabilities?.voice {
      voice.available = true; voice.plan = "pro"; voice.remaining = nil; voice.limit = nil; voice.reason = nil
      bootstrap?.capabilities?.voice = voice
    }
  }
  /// Every action that starts a rep asks here first; the `practice_rep` placement sits behind a refusal.
  func mayStartRep(swapping current: Challenge? = nil) -> Bool {
    guard let practice = bootstrap?.practice, practice.freeReps else { return true }
    if let current, current.freeRepAt != nil, current.swapped != true { return true }
    return practice.available
  }
  /// When a spent free rep comes back; nil while practice is open.
  var nextFreeRep: Date? {
    guard let practice = bootstrap?.practice, practice.freeReps, !practice.available else { return nil }
    return practice.nextFreeRepAt.flatMap(Date.fromAPI)
  }
  /// "That’s today’s free reps. More land at 2:00 AM." The reset is UTC midnight, shown in local time.
  static func freeRepLine(_ date: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
    var style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale)
    style.timeZone = calendar.timeZone
    let when = calendar.isDateInToday(date) ? "later today, at \(date.formatted(style))" : calendar.isDateInTomorrow(date) ? "tomorrow at \(date.formatted(style))" : date.formatted(.dateTime.weekday(.wide).locale(locale))
    return "That’s today’s free reps. More land \(when)."
  }
  /// "2 of 3 free reps left today", or nil on Pro.
  var repsLeftLine: String? {
    guard let practice = bootstrap?.practice, practice.freeReps, let remaining = practice.remaining, let limit = practice.limit, remaining > 0 else { return nil }
    return "\(remaining) of \(limit) free reps left today"
  }
  static var fixtureReset: String { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c.startOfDay(for: Date().addingTimeInterval(86_400)).ISO8601Format() }
  var error: String?
  var completionNoticeAccount: String?
  var busy = false
  /// The question as it's being written, for Home's ticket; nil when nothing is streaming.
  var preparingDraft: QuestionDraft?
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
  /// A refresh asked for while one was running: the running one may have read the server before the change that
  /// prompted this one (a purchase, say), so it runs once more when the first lands.
  private var refreshAgain = false
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
  var libraryCoverageLoaded = false
  var dismissedHomeRevisits: Set<String> = []
  var homeRevisit: HomeRevisit? { HomeRevisit.select(memory: memory, dismissed: dismissedHomeRevisits) }
  func dismissHomeRevisit(_ item: HomeRevisit) async {
    guard let account = bootstrap?.account.id else { return }
    dismissedHomeRevisits.insert(item.id)
    do { try await disk.cache(key: "home-revisits:" + account, data: JSONEncoder().encode(dismissedHomeRevisits)) }
    catch {
      guard bootstrap?.account.id == account else { return }
      dismissedHomeRevisits.remove(item.id)
      self.error = "Couldn’t save that dismissal. Please try again."
    }
  }

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
          await self.loadRecall()
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
      if !onlySkipped, !self.fixture, let value: CoverageResponse = try? await self.api.send("library/coverage"), self.bootstrap?.account.id == account {
        self.libraryCoverage = value.concepts; self.libraryCoverageLoaded = true
        try? await self.disk.cache(key: "home-coverage:" + account, data: JSONEncoder().encode(value))
      }
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
          var attempt = Challenge(id: id + "-attempt", lifecycle: state, title: title, prompt: question.prompt, topic: "System design", createdAt: question.lastActivity, completedAt: state == "completed" ? question.lastActivity : nil, session: SessionDraft(answer: "My preserved original reasoning", revision: 1))
          // A completed attempt has feedback, like every real one.
          if state == "completed" {
            attempt.reflection = Reflection(summary: "Workers kept their jobs through a crash.", worked: ["Accepted work survives a worker crash"], improve: "Say what a retry does when the first delivery already went out.", takeaway: "Durability first, then deduplication.", strengths: ["Durability"], gaps: ["Duplicate delivery"])
          }
          fixtureLibraryAttempts[id] = [attempt]
        }
        #if DEBUG
        // The whole vocabulary, so the knowledge map draws every area.
        if ProcessInfo.processInfo.arguments.contains("--fixture-map") {
          let all: [(String, String, String)] = [("data-modeling", "Data modeling", "Data"), ("indexing", "Indexing & access patterns", "Data"), ("transactions", "Transactions", "Data"), ("consistency", "Consistency", "Data"), ("replication", "Replication", "Data"), ("partitioning", "Partitioning", "Data"), ("api-design", "API design", "Traffic & performance"), ("caching", "Caching", "Traffic & performance"), ("load-balancing", "Load balancing", "Traffic & performance"), ("rate-limiting", "Rate limiting", "Traffic & performance"), ("capacity-planning", "Capacity planning", "Traffic & performance"), ("queues", "Queues & streams", "Async & coordination"), ("retry-safety", "Retry safety & idempotency", "Async & coordination"), ("coordination", "Ordering & coordination", "Async & coordination"), ("scheduling", "Scheduling", "Async & coordination"), ("fault-tolerance", "Fault tolerance & recovery", "Reliability & operations"), ("backpressure", "Overload & backpressure", "Reliability & operations"), ("observability", "Observability", "Reliability & operations"), ("migration", "Deployment & migration", "Reliability & operations"), ("authorization", "Authentication & authorization", "System boundaries"), ("tenant-isolation", "Tenant isolation", "System boundaries"), ("data-lifecycle", "Data lifecycle & privacy", "System boundaries"), ("multi-region", "Multi-region design", "System boundaries"), ("cost-efficiency", "Cost efficiency", "System boundaries")]
          taxonomy = all.map { PracticeConcept(id: $0.0, label: $0.1, category: $0.2, aliases: [], description: "A core system design decision.") }
        }
        #endif
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
      let savedPreferences = try await disk.cached(key: "settings-pending:" + result.account.id)
      try await disk.clearPractice(account: result.account.id)
      if let savedPreferences { try await disk.cache(key: "settings-pending:" + result.account.id, data: savedPreferences) }
      librarySnapshots = [:]; libraryDetailSnapshots = [:]; libraryWarmAccount = nil; librarySessions = [:]
      presented = nil; conflict = nil; hasPendingWrites = false
      if bootstrap?.account.id == result.account.id { bootstrap?.challenge = result.challenge; bootstrap?.jobs = result.jobs }
      try SharedStore.save(WidgetSnapshot(challenge: result.challenge, updatedAt: Date().ISO8601Format()))
      libraryCoverage = []; libraryCoverageLoaded = false; dismissedHomeRevisits = []
      try await disk.cache(key: "home-coverage:" + result.account.id, data: Data())
      try await disk.cache(key: "home-revisits:" + result.account.id, data: Data())
      memory = MemoryResponse(sessions: [], patterns: [])
      recall = RecallDeckResponse(cards: [], dueCount: 0); recallLoaded = false; recallFetchedAt = nil; recallRequestVersion += 1
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
    do { try await action() } catch is CancellationError {} catch let error as URLError where error.code == .cancelled {} catch {
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
    let coverage = (try? await disk.cached(key: "home-coverage:" + account)).flatMap { try? JSONDecoder().decode(CoverageResponse.self, from: $0) }
    let dismissals = (try? await disk.cached(key: "home-revisits:" + account)).flatMap { try? JSONDecoder().decode(Set<String>.self, from: $0) } ?? []
    let cachedRecall = (try? await disk.cached(key: "recall:" + account)).flatMap { try? JSONDecoder.api.decode(RecallDeckResponse.self, from: $0) }
    let restoredFirstUse = (try? await disk.cached(key: "first-use:" + account)).flatMap { try? JSONDecoder().decode(FirstUseProgress.self, from: $0) }
    guard cacheGeneration == generation else { return }
    firstUse = restoredFirstUse ?? FirstUseProgress()
    pendingSettings = (try? await disk.cached(key: "settings-pending:" + account)).flatMap { try? JSONDecoder().decode(PendingSettings.self, from: $0) }
    dismissedHomeRevisits = dismissals
    libraryCoverage = coverage?.concepts ?? []; libraryCoverageLoaded = coverage != nil
    memory = restoredMemory
    recall = cachedRecall ?? RecallDeckResponse(cards: [], dueCount: 0)
    recallLoaded = cachedRecall != nil
    recallFetchedAt = nil
    recallRequestVersion += 1
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
        // A signed-out launch is a first run for the tests: forget any earlier draft or stage.
        UserDefaults.standard.removeObject(forKey: SetupView.draftKey)
        UserDefaults.standard.removeObject(forKey: "firstRun.stage")
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
      let skipped = (try? await disk.pendingSkips(account: account)) ?? []
      guard Clerk.shared.user?.id == subject else { launching = false; return }
      // Settings land in the same step as the account, never after: anything keyed on being signed in must not
      // see default settings (onboarding unfinished) in between and send a finished user back through setup.
      var restored = cached
      if let id = cached.challenge?.id, skipped.contains(id) { restored.challenge = nil }
      settings = pendingSettings?.value ?? cached.settings
      restored.settings = settings
      bootstrap = restored
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
    guard !fixture, !launching else { return }
    if refreshing { refreshAgain = true; return }
    defer {
      if refreshAgain { refreshAgain = false; Task { await refresh() } }
    }
    let resetGeneration = accountResetGeneration
    let subject = Clerk.shared.user?.id
    let settingsAtStart = settings
    let hadLocalEdits = bootstrap.map { settings != $0.settings } ?? false
    let saveGeneration = settingsSaveGeneration
    let pendingAtStart = pendingSettings
    refreshing = true
    defer { refreshing = false }
    do {
      let result: Bootstrap = try await api.send("bootstrap")
      guard Clerk.shared.user?.id == subject, accountResetGeneration == resetGeneration else { return }
      try await acceptEpoch(result)
      if bootstrap?.account.id != result.account.id { bootstrap = nil }
      await restoreHomeCache(account: result.account.id)
      let queuedSkips = try await disk.pendingSkips(account: result.account.id)
      guard Clerk.shared.user?.id == subject else { return }
      // Settings first, then the account, with no suspension between (see launch()).
      if let pendingSettings { settings = pendingSettings.value }
      else if !hadLocalEdits && pendingAtStart == nil && saveGeneration == settingsSaveGeneration && settings == settingsAtStart { settings = result.settings }
      var updated = result
      if let id = result.challenge?.id, locallySkipped[result.account.id]?.contains(id) == true || queuedSkips.contains(id) { updated.challenge = nil }
      if pendingSettings != nil || pendingAtStart != nil || saveGeneration != settingsSaveGeneration { updated.settings = pendingSettings?.value ?? settings }
      bootstrap = updated
      PlanCoordinator.shared.identify(account: result.account.id)
      syncSettingsInBackground()
      try? await reconcileReminder()
      try SharedStore.setSecret(result.account.id, key: "account")
      try SharedStore.setSecret(Clerk.shared.user?.id, key: "subject")
      try await disk.cache(
        key: "bootstrap:" + result.account.id, data: JSONEncoder().encode(bootstrap ?? result))
      if result.account.status == "active" {
        await withTaskGroup(of: Void.self) { group in
          group.addTask { await self.loadMemory() }
          group.addTask { await self.preloadRecallIfNeeded() }
          group.addTask { await self.preloadLibrary() }
        }
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
      } else if Clerk.shared.session == nil {
        // The session is gone (signed out elsewhere, revoked): go back to sign-in without clearing the
        // local store, so drafts are still there under the same account once they sign in again.
        presented = nil
        conflict = nil
        bootstrap = nil
        error = "Your session ended. Sign in again to keep going. Your draft is saved on this device."
      } else {
        error = "Sign in again to continue. Your local draft is safe."
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
  func loadRecall() async {
    guard let account = bootstrap?.account.id else { return }
    recallRequestVersion += 1
    let version = recallRequestVersion
    let epoch = bootstrap?.practiceEpoch
    if fixture {
      #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--fixture-recall-due") {
        let now = Date.now.ISO8601Format()
        func card(_ id: String, _ concept: String, _ question: String, _ answer: String) -> RecallCardDTO {
          RecallCardDTO(id: id, sourceChallengeId: "fixture", conceptId: concept, question: question, answer: answer, dueAt: now,
                        intervalDays: 0, repetitions: 0, lapses: 0, createdAt: now, updatedAt: now,
                        sourceTitle: "Design a reliable job queue", sourceCompletedAt: now, sourceTicket: 12)
        }
        let cards = [
          card("due-1", "idempotency", "Why does a retried job need an idempotency key?",
               "So a second delivery of the same job sees the key and skips the side effect instead of charging or sending twice."),
          card("due-2", "backpressure", "What should a queue do when consumers fall behind?",
               "Push back on producers, shed or delay low-priority work, and alert, instead of letting the backlog grow without a bound."),
        ]
        // One card already spaced out, so caught up can say when it's back.
        var later = card("later-1", "caching", "A popular profile expires and 500 requests miss at once. What reaches the database?",
                         "All 500, unless concurrent misses share one in-flight read and refill the cache from it.")
        later.dueAt = Date.now.addingTimeInterval(86_400).ISO8601Format()
        recall = RecallDeckResponse(cards: cards + [later], dueCount: cards.count); recallLoaded = true; recallFetchedAt = Date(); return
      }
      #endif
      recall = RecallDeckResponse(cards: [], dueCount: 0); recallLoaded = true; recallFetchedAt = Date(); return
    }
    do {
      let updated: RecallDeckResponse = try await api.send("recall")
      guard bootstrap?.account.id == account, bootstrap?.practiceEpoch == epoch, recallRequestVersion == version else { return }
      recall = updated; recallLoaded = true; recallFetchedAt = Date()
      try await disk.cache(key: "recall:" + account, data: JSONEncoder().encode(updated))
    } catch {
      if bootstrap?.account.id == account, recallRequestVersion == version { recallLoaded = true }
    }
  }
  func preloadRecallIfNeeded(maxAge: TimeInterval = 45) async {
    guard bootstrap?.account.status == "active" else { return }
    if let recallFetchedAt, Date().timeIntervalSince(recallFetchedAt) < maxAge { return }
    await loadRecall()
  }
  func reviewRecall(_ card: RecallCardDTO, rating: String, responseMs: Int?) async throws {
    recallRequestVersion += 1
    let account = bootstrap?.account.id
    let epoch = bootstrap?.practiceEpoch
    let resetGeneration = accountResetGeneration
    let previous = recall
    let previousPlan = bootstrap?.todayPlan
    recall.cards.removeAll { $0.id == card.id }
    recall.dueCount = max(0, recall.dueCount - (Date.fromAPI(card.dueAt).map { $0 <= Date() } == true ? 1 : 0))
    if var plan = bootstrap?.todayPlan {
      plan.dueRecallCount = recall.dueCount
      plan.recommendedRecallCount = min(plan.dueRecallCount, plan.dailyGoalMinutes * 2)
      plan.estimatedRecallMinutes = Int(ceil(Double(plan.recommendedRecallCount) / 2.0))
      if plan.dueRecallCount == 0 { plan.state = plan.completedToday > 0 ? "complete_today" : (bootstrap?.challenge == nil ? "prepare" : "question_ready") }
      bootstrap?.todayPlan = plan
    }
    // Fixtures have no account to tell; the local deck is the whole story.
    if fixture { return }
    do {
      let result: RecallReviewResponse = try await api.send("recall/\(card.id)/review", method: "POST",
        body: RecallReviewInput(rating: rating, responseMs: responseMs), command: UUID().uuidString)
      guard bootstrap?.account.id == account, bootstrap?.practiceEpoch == epoch,
        accountResetGeneration == resetGeneration else { throw CancellationError() }
      recall.cards.append(result.card)
      recall.cards.sort { $0.dueAt == $1.dueAt ? $0.id < $1.id : $0.dueAt < $1.dueAt }
      try? await disk.cache(key: "recall:" + (account ?? ""), data: JSONEncoder().encode(recall))
    } catch {
      guard bootstrap?.account.id == account, bootstrap?.practiceEpoch == epoch,
        accountResetGeneration == resetGeneration else { throw error }
      recall = previous
      bootstrap?.todayPlan = previousPlan
      throw error
    }
  }
  func retryMoment(challenge: Challenge, turn: InterviewTurn) async throws -> Challenge {
    if fixture {
      let branch = Challenge(questionId: challenge.questionId, scenario: challenge.scenario,
        primaryConceptId: challenge.primaryConceptId, conceptIds: challenge.conceptIds,
        engineeringLevel: challenge.engineeringLevel, id: UUID().uuidString, lifecycle: "in_progress",
        title: challenge.title + " · Retry", prompt: turn.prompt, topic: challenge.topic,
        session: SessionDraft(answer: "", revision: 0))
      bootstrap?.challenge = branch
      return branch
    }
    let branch: Challenge = try await api.send("challenges/\(challenge.id)/retry-moment/\(turn.id)", method: "POST", command: UUID().uuidString)
    bootstrap?.challenge = branch
    if let current = bootstrap { try? await disk.cache(key: "bootstrap:" + current.account.id, data: JSONEncoder().encode(current)) }
    return branch
  }
  func refreshAfterSessionDeletion() async throws {
    guard let account = bootstrap?.account.id else { return }
    if let task = libraryWarmTask { await task.value }
    guard bootstrap?.account.id == account else { return }
    try await disk.invalidateLibrary(account: account)
    try await disk.cache(key: "home-coverage:" + account, data: Data())
    libraryDetailSnapshots = [:]; librarySessions = [:]; librarySnapshots = [:]
    libraryCoverage = []; libraryCoverageLoaded = false; libraryVersion += 1
    await loadMemory()
    await loadRecall()
    await preloadLibrary(force: true)
  }
  func resetDeveloperPractice() async throws {
    guard let account = bootstrap?.account.id,
      bootstrap?.capabilities?.developerTools == true || fixture
    else { throw APIError(code: "not_found", message: "This tool is unavailable.", status: 404) }
    accountResetGeneration += 1
    settingsSyncTask?.cancel()
    await settingsSyncTask?.value
    settingsSyncTask = nil; settingsSyncID = nil
    if !fixture {
      let _: EmptyResponse = try await api.send("developer/practice", method: "DELETE")
    }
    try await disk.clearPractice(account: account)
    pendingSettings = nil; settingsSyncError = nil; settingsSaveGeneration += 1
    libraryWarmTask?.cancel(); libraryWarmTask = nil; libraryWarmAccount = nil
    librarySnapshots = [:]; libraryDetailSnapshots = [:]; librarySessions = [:]
    libraryCoverage = []; libraryCoverageLoaded = false; dismissedHomeRevisits = []
    locallySkipped[account] = []
    memory = MemoryResponse(sessions: [], patterns: [])
    recall = RecallDeckResponse(cards: [], dueCount: 0); recallLoaded = false; recallFetchedAt = nil; recallRequestVersion += 1
    memoryRequestVersion += 1; cacheGeneration += 1; libraryVersion += 1
    settings = PracticeSettings()
    firstUse = FirstUseProgress()
    UserDefaults.standard.removeObject(forKey: SetupView.draftKey)
    bootstrap?.settings = settings
    bootstrap?.challenge = nil; bootstrap?.todayPlan = nil
    bootstrap?.jobs = []
    presented = nil; conflict = nil; hasPendingWrites = false
    completionNoticeAccount = nil; preparationFailure = nil
    failedPreparation = nil; failedPreparationSource = nil
    homeCacheAccount = nil
    for key in ["widgetToken", "widgetTokenExpires", "deviceID"] { try SharedStore.setSecret(nil, key: key) }
    try SharedStore.save(WidgetSnapshot(challenge: nil, updatedAt: ""))
    WidgetCenter.shared.reloadAllTimelines()
    UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    if !fixture {
      Task { @MainActor in
        while self.refreshing { try? await Task.sleep(for: .milliseconds(50)) }
        await self.refresh()
      }
    }
  }
  /// The nuclear option: server practice wiped, local store cleared, walkthrough and coach tips forgotten, signed out.
  func resetDeveloperEverything(reinvite: Bool) async throws {
    try await resetDeveloperPractice()
    if reinvite, !fixture { let _: EmptyResponse = try await api.send("developer/reinvite", method: "POST") }
    Self.forgetDeviceOnboarding()
    try await signOut(discard: true)
  }
  /// Device-side first-run memory: walkthrough, coach tips, practice mode, dismissed notices.
  static func forgetDeviceOnboarding() {
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: "walkthroughVersion")
    defaults.removeObject(forKey: "practiceMode")
    defaults.removeObject(forKey: "firstRun.stage")
    defaults.removeObject(forKey: SetupView.draftKey)
    for mark in CoachMark.allCases { defaults.removeObject(forKey: mark.storageKey) }
  }
  /// Developer preview of the free plan without touching the server; a refresh puts the real plan back.
  func previewPlan(_ preview: PlanPreview) {
    switch preview {
    case .live: Task { await refresh() }
    case .freeReps:
      bootstrap?.account.plan = "free"
      bootstrap?.practice = PracticeAccess(plan: "free", freeReps: true, available: true, remaining: 2, limit: 3, resetsAt: Self.fixtureReset)
      bootstrap?.capabilities?.voice = VoiceCapability(available: true, plan: "free", checkedAt: Date().ISO8601Format(), sessionSeconds: 180, remaining: 3, limit: 3, kind: "intro")
    case .freeSpent:
      bootstrap?.account.plan = "free"
      bootstrap?.practice = PracticeAccess(plan: "free", freeReps: true, available: false, nextFreeRepAt: Self.fixtureReset, remaining: 0, limit: 3, resetsAt: Self.fixtureReset)
      bootstrap?.capabilities?.voice = VoiceCapability(available: false, plan: "free", reason: "Your next free voice session comes back Thursday. Pro has it any time.", checkedAt: Date().ISO8601Format(), sessionSeconds: 180, remaining: 0, limit: 1, resetsAt: Date().addingTimeInterval(4 * 86_400).ISO8601Format(), kind: "taste")
    }
  }
  enum PlanPreview: String, CaseIterable, Identifiable { case live, freeReps, freeSpent; var id: String { rawValue } }
  /// Developer accounts act as Free or Pro on the server, so gates, voice limits and the paywall behave for real.
  /// nil goes back to the billed plan. Fixture runs have no server and preview it locally instead.
  func setDeveloperPlan(_ plan: String?) async {
    if fixture {
      switch plan {
      case "free": previewPlan(.freeSpent)
      case "pro":
        bootstrap?.account.plan = "pro"
        bootstrap?.practice = PracticeAccess(plan: "pro", freeReps: false, available: true)
      default: previewPlan(.live)
      }
      bootstrap?.account.planOverride = plan
      return
    }
    await perform {
      struct Result: Decodable { var plan: String }
      // Encodes `"plan": null` explicitly: the endpoint clears the override only on an explicit null.
      let _: Result = try await api.send("developer/plan", method: "POST", body: DeveloperPlanInput(plan: plan))
      await refresh()
    }
  }
  private var checkingDailyQuestion = false
  private var automaticPreparationAccounts: Set<String> = []
  func ensureHomeQuestion() async {
    guard let account = bootstrap?.account, account.status == "active", settings.onboardingComplete,
      firstUse.stage == .complete, AIConsent.shared.granted,
      !busy, !checkingDailyQuestion else { return }
    if fixture {
      #if DEBUG
      guard ProcessInfo.processInfo.arguments.contains("--fixture-auto-question"), bootstrap?.challenge == nil,
        !automaticPreparationAccounts.contains(account.id) else { return }
      automaticPreparationAccounts.insert(account.id)
      do { _ = try await generateForPreview() } catch { preparationFailure = error.localizedDescription }
      #endif
      return
    }
    checkingDailyQuestion = true
    defer { checkingDailyQuestion = false }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: settings.timezone) ?? .gmt
    let components = calendar.dateComponents([.year, .month, .day], from: Date())
    let day = String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
    let key = "daily-visit:" + account.id
    if let saved = try? await disk.cached(key: key), String(data: saved, encoding: .utf8) == day { return }
    // Persist the local attempt before networking; failed opens don't repeatedly request generation.
    try? await disk.cache(key: key, data: Data(day.utf8))
    do {
      await sync()
      guard bootstrap?.account.id == account.id else { return }
      guard try await disk.pendingSkips(account: account.id).isEmpty else { return }
      let style = memory.sessions.first { !$0.isWarmUp }?.guidanceMode
      let result: DailyQuestionResponse = try await api.send("daily-question", method: "POST", body: DailyQuestionInput(guidanceMode: style))
      guard bootstrap?.account.id == account.id else { return }
      if let challenge = result.challenge { bootstrap?.challenge = challenge }
      if let job = result.job {
        busy = true
        // Stays "preparing" until the refresh below has placed the question; otherwise the ticket blanks for one round trip.
        defer { busy = false; preparingDraft = nil }
        var streamed = false, delivered: Challenge?
        try? await api.questionStream(job: job.id) { snapshot in
          guard self.bootstrap?.account.id == account.id else { return }
          self.preparingDraft = QuestionDraft(title: snapshot.title, prompt: snapshot.prompt, textDone: snapshot.textDone == true)
          streamed = snapshot.status == "completed"
          delivered = snapshot.challenge
        }
        // The stream's last frame already said the job is done; polling again only adds the pause the ticket shows as a freeze.
        if !streamed { try await waitForJob(job.id) }
        guard bootstrap?.account.id == account.id else { return }
        // The stream's last frame brought the question; a fetch is only the fallback.
        let fresh: Challenge
        if let delivered { fresh = delivered } else { fresh = try await api.send("challenges/" + (job.challengeId ?? job.id)) }
        guard bootstrap?.account.id == account.id else { return }
        bootstrap?.challenge = fresh
        bootstrap?.jobs.removeAll { $0.id == job.id }
        if let bootstrap { try? await disk.cache(key: "bootstrap:" + account.id, data: JSONEncoder().encode(bootstrap)) }
        Task {
          guard bootstrap?.account.id == account.id else { return }
          await refresh()
          guard bootstrap?.account.id == account.id, let bootstrap else { return }
          try? await disk.cache(key: "bootstrap:" + account.id, data: JSONEncoder().encode(bootstrap))
        }
        return
      }
      await refresh()
      guard bootstrap?.account.id == account.id else { return }
      if let bootstrap { try await disk.cache(key: "bootstrap:" + account.id, data: JSONEncoder().encode(bootstrap)) }
    } catch is CancellationError {
      // The watch was superseded (background, sign-out, a newer refresh); the job itself is still running.
    } catch let error as URLError where error.code == .cancelled {
    } catch {
      if bootstrap?.account.id == account.id { preparationFailure = error.localizedDescription }
    }
  }
  func generate(_ preparation: PreparationInput? = nil) async {
    await perform { _ = try await generateForPreview(preparation) }
  }
  /// Saves a finished session to shape tomorrow's automatic question, or takes it back.
  func setQueuedNext(_ source: Challenge, queued: Bool) async throws {
    guard let account = bootstrap?.account.id else { throw CancellationError() }
    if fixture {
      let label = taxonomy.first { $0.id == source.primaryConceptId }?.label
      bootstrap?.queuedNext = queued ? QueuedNext(sourceId: source.id, title: source.title, conceptId: source.primaryConceptId, label: label, createdAt: Date().ISO8601Format()) : nil
      return
    }
    let result: QueuedNextResult = try await api.send("challenges/\(source.id)/next", method: queued ? "PUT" : "DELETE")
    guard bootstrap?.account.id == account else { throw CancellationError() }
    bootstrap?.queuedNext = result.queuedNext
  }
  func generateForPreview(_ preparation: PreparationInput? = nil, onDraft: (@MainActor (QuestionDraft) -> Void)? = nil) async throws -> Challenge {
    guard !busy, let account = bootstrap?.account.id else {
      throw APIError(code: "busy", message: "A question is already being prepared.", status: 409)
    }
    // The first rep is a counted Guided question from the saved plan; its one swap replaces the ready question.
    let firstRep = firstUse.stage == .firstRep
    var preparation = preparation
    if firstRep && preparation == nil {
      let current = bootstrap?.challenge
      preparation = PreparationInput(guidanceMode: .learnTogether, focus: settings.focus, kind: "design",
        difficulty: settings.difficulty, engineeringLevel: settings.selectedLevel,
        replaceId: current?.lifecycle == "ready" ? current?.id : nil)
    }
    busy = true
    defer { busy = false; preparingDraft = nil }
    let publish: @MainActor (QuestionDraft) -> Void = { draft in
      self.preparingDraft = draft
      onDraft?(draft)
    }
    if firstRep {
      syncSettingsInBackground()
      await settingsSyncTask?.value
      guard bootstrap?.account.id == account else { throw CancellationError() }
      guard pendingSettings == nil else { throw APIError(code: "settings_pending", message: "Your plan is saved on this device. Connect to prepare your first question.", status: 0) }
    }
    if !fixture {
      await sync()
      guard bootstrap?.account.id == account else { throw CancellationError() }
      guard try await disk.pendingSkips(account: account).isEmpty else {
        throw APIError(code: "skip_pending", message: "Your skip is saved. The next question will be prepared shortly.", status: 0)
      }
    }
    preparationFailure = nil
    failedPreparation = nil
    failedPreparationSource = nil
    let draft = QuestionDraft(guidanceMode: preparation?.guidanceMode ?? .coachMe)
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
      let replaced = bootstrap?.challenge.flatMap { $0.id == preparation?.replaceId ? $0 : nil }
      let challenge = Challenge(guidanceMode: preparation?.guidanceMode ?? .coachMe, minutes: 20, path: ["Pin down what the queue promises", "Sketch the job lifecycle", "Handle worker failures", "Make retries safe"],
        opener: "You’ve designed a few systems, so let’s skip the basics. A worker can crash at any point. What should a client be able to rely on?",
        freeRepAt: bootstrap?.practice?.freeReps == true ? replaced?.freeRepAt ?? Date().ISO8601Format() : nil,
        swapped: replaced?.freeRepAt != nil ? true : nil,
        interviewStyle: preparation?.interviewStyle ?? .standard, engineeringLevel: preparation?.engineeringLevel ?? settings.selectedLevel,
        id: UUID().uuidString, lifecycle: "ready", title: "Design a reliable job queue",
        prompt: "Design a reliable job queue. Explain retries, ordering, and how failures are handled.",
        topic: preparation?.focus ?? settings.focus, session: SessionDraft(answer: "", revision: 0))
      do {
        var written = draft
        #if DEBUG
        let bursty = ProcessInfo.processInfo.arguments.contains("--fixture-bursty-stream")
        #else
        let bursty = false
        #endif
        if bursty {
          // The live shape: the provider hands over big chunks with quiet gaps, the text ends before the job does.
          let full = challenge.title + "\u{1}" + challenge.prompt
          var sent = 0
          for (index, chunk) in [37, 92, 140, 61, 210, 180].enumerated() where sent < full.count {
            try await Task.sleep(for: .milliseconds([600, 350, 1200, 300, 900, 450][index]))
            sent = min(full.count, sent + chunk)
            let parts = String(full.prefix(sent)).split(separator: "\u{1}", maxSplits: 1, omittingEmptySubsequences: false)
            written.title = String(parts[0]); written.prompt = parts.count > 1 ? String(parts[1]) : ""
            publish(written)
          }
          written.textDone = true; publish(written)
          try await Task.sleep(for: .milliseconds(500))
        } else {
          // Arrives word by word at roughly a model's pace so the preview streams like it does live.
          for (field, text) in [(\QuestionDraft.title, challenge.title), (\QuestionDraft.prompt, challenge.prompt)] {
            for word in text.split(separator: " ", omittingEmptySubsequences: false) {
              written[keyPath: field] += (written[keyPath: field].isEmpty ? "" : " ") + word
              publish(written)
              try await Task.sleep(for: .milliseconds(45))
            }
          }
        }
        guard bootstrap?.account.id == account else { throw CancellationError() }
      }
      bootstrap?.challenge = challenge
      if bootstrap?.practice?.freeReps == true, replaced?.freeRepAt == nil { bootstrap?.practice?.available = false }
      return challenge
    }
    guard bootstrap?.account.id == account else { throw CancellationError() }
    if try await !disk.pending(account: account).isEmpty {
      throw APIError(code: "practice_pending", message: "Couldn’t prepare a new question right now. Try again shortly.", status: 0)
    }
    let result: GenerationResponse
    do { result = try await api.send("challenges", method: "POST", body: preparation, command: UUID().uuidString) }
    catch let failure as APIError where failure.code == "practice_gate" {
      // Home learns when the free rep comes back.
      Task { await refresh() }
      throw failure
    }
    let challenge: Challenge
    var streamed = false, delivered: Challenge?
    if let existing = result.challenge { challenge = existing }
    else if let id = result.id {
      do {
        // Streaming is a nicety; the job itself is the source of truth, so any stream failure falls back to polling.
        try? await api.questionStream(job: id) { snapshot in
          guard self.bootstrap?.account.id == account else { return }
          var written = draft
          written.title = snapshot.title
          written.prompt = snapshot.prompt
          written.textDone = snapshot.textDone == true
          publish(written)
          streamed = snapshot.status == "completed"
          delivered = snapshot.challenge
        }
      }
      if !streamed { try await waitForJob(id) }
      guard bootstrap?.account.id == account else { throw CancellationError() }
      if let delivered { challenge = delivered } else { challenge = try await api.send("challenges/" + id) }
    } else { throw APIError(code: "missing_question", message: "The question is not available yet. Check Home shortly.", status: 0) }
    guard bootstrap?.account.id == account else { throw CancellationError() }
    bootstrap?.challenge = challenge
    if let bootstrap { try await disk.cache(key: "bootstrap:" + account, data: JSONEncoder().encode(bootstrap)) }
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
      else { loaded.lifecycle = "in_progress"; loaded.startedAt = Date().ISO8601Format() }
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
            receipts: draft.kind == "complete" ? receipts : nil,
            guidanceMode: draft.kind == "complete" ? try await finishingMode(account: account, challengeID: draft.challengeID) : nil)
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
        } catch let failure as APIError where failure.status == 404 {
          try await disk.retireMissingAttempt(account: account, id: draft.challengeID)
          saveStatus = "Saved on this device"
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
    } catch is CancellationError {} catch let error as URLError where error.code == .cancelled {} catch {
      hasPendingWrites = true
      saveStatus = "Saved"
    }
  }
  /// The style the workspace had when Finish was pressed; the interview room caches it per attempt.
  private func finishingMode(account: String, challengeID: String) async throws -> GuidanceMode? {
    guard let data = try await disk.cached(key: "interview:" + account + ":" + challengeID + ":guidanceMode") else { return nil }
    return try? JSONDecoder().decode(GuidanceMode.self, from: data)
  }
  func resolveConflict(keepLocal: Bool) async {
    guard let account = bootstrap?.account.id, let challenge = conflict else { return }
    await perform {
      try await disk.resolve(account: account, challenge: challenge, keepLocal: keepLocal)
      conflict = nil
      await sync()
    }
  }
  /// `completesOnboarding: false` lets the caller end onboarding itself, once its own ending has played: ending it
  /// here swaps the root from setup to the tabs, which takes the interview (and anything on it) down at once.
  func finish(_ challenge: Challenge, answer: String, completesOnboarding: Bool = true) async throws -> Challenge {
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
        summary: "You gave workers durable ownership of queued jobs.",
        worked: ["Used leases and durable records"],
        improve: "Explain what happens when work finishes but its acknowledgement is lost.",
        takeaway: "Make retries safe before making them automatic.",
        strengths: ["Queue durability"], gaps: ["Retry safety"])
      switch challenge.guidanceMode {
      case .learnTogether:
        completed.reflection?.guidanceMode = .learnTogether
        completed.reflection?.lesson = Lesson(learned: ["A lease lets another worker take over a stalled job", "Retries need a stable operation ID to stay safe"], tryAlone: "Design retries for a payment webhook without any hints.")
      case .mockInterview:
        completed.reflection?.guidanceMode = .mockInterview
        completed.reflection?.debrief = Debrief(
          verdict: .borderline, reason: "Durable ownership is solid, but a lost acknowledgement would still run the job twice.",
          signals: [
            .init(area: "requirements", rating: "strong", note: "Pinned down retries and ordering early."),
            .init(area: "design", rating: "mixed", note: "Leases are right; completion isn't idempotent yet."),
            .init(area: "trade_offs", rating: "weak", note: "Didn't weigh at-least-once against exactly-once."),
            .init(area: "communication", rating: "strong", note: "Clear, in a sensible order."),
          ],
          toPass: "Show how a retry recognises work that already finished before running it again.")
      default: break
      }
      completed.completedAt = Date().ISO8601Format()
      if !challenge.isWarmUp {
        completed.ticket = bootstrap?.todayPlan?.nextTicket
        bootstrap?.todayPlan?.nextTicket? += 1
        memory.sessions.insert(completed, at: 0)
      }
    }
    bootstrap?.challenge = nil
    // Uncounted legacy warm-ups never become Home's completion notice.
    if !challenge.isWarmUp { completionNoticeAccount = bootstrap?.account.id }
    if firstUse.stage == .firstRep {
      var done = FirstUseProgress()
      if !challenge.isWarmUp { done.firstRepID = challenge.id }
      try? await setFirstUse(done)
    }
    if completesOnboarding { await completeOnboarding() }
    return completed
  }
  /// Setup stays on screen behind the first rep; Home replaces it only once the rep is over.
  func completeOnboarding() async {
    guard let account = bootstrap?.account.id, !settings.onboardingComplete else { return }
    settings.onboardingComplete = true
    // Setup's answers are applied; a kept draft could only replay setup over a finished account.
    UserDefaults.standard.removeObject(forKey: SetupView.draftKey)
    do { try await saveSettingsLocally() } catch let failure { error = failure.localizedDescription }
    try? await disk.cache(key: "onboarding-v2:" + account, data: Data())
  }
  func skip(_ id: String, answer: String? = nil) async {
    guard let account = bootstrap?.account.id else { return }
    await perform {
      if !fixture { try await disk.queueSkip(account: account, id: id, answer: answer) }
      guard bootstrap?.account.id == account else { return }
      // Skipping the first rep still ends onboarding; Home takes over.
      if firstUse.stage == .firstRep {
        try? await setFirstUse(FirstUseProgress())
      }
      await completeOnboarding()
      locallySkipped[account, default: []].insert(id)
      if bootstrap?.challenge?.id == id { bootstrap?.challenge = nil }
      if var plan = bootstrap?.todayPlan { plan.state = plan.dueRecallCount > 0 ? "review_due" : "prepare"; bootstrap?.todayPlan = plan }
      presented = nil
      if let bootstrap { try? await disk.cache(key: "bootstrap:" + account, data: JSONEncoder().encode(bootstrap)) }
      if !fixture {
        hasPendingWrites = true
        Task { await sync(challengeID: id) }
      }
    }
  }
  /// Done waits for durable local storage, never for the network.
  func saveSettingsLocally() async throws {
    guard let account = bootstrap?.account.id else { return }
    settings.model = "openai/gpt-6-luna"
    settings.engineeringLevel = settings.selectedLevel
    let command = PendingSettings(value: settings)
    settingsSaveGeneration += 1
    try await disk.cache(key: "settings-pending:" + account, data: JSONEncoder().encode(command))
    guard bootstrap?.account.id == account else { return }
    pendingSettings = command
    bootstrap?.settings = command.value
    settingsSyncError = nil
    syncSettingsInBackground()
    Task { try? await reconcileReminder(requestPermission: true) }
  }
  func syncSettingsInBackground() {
    guard settingsSyncTask == nil, let account = bootstrap?.account.id, pendingSettings != nil else { return }
    let syncID = UUID()
    settingsSyncID = syncID
    settingsSyncTask = Task { @MainActor in
      defer { if self.settingsSyncID == syncID { self.settingsSyncTask = nil; self.settingsSyncID = nil } }
      while let command = self.pendingSettings, self.bootstrap?.account.id == account, !Task.isCancelled {
        do {
          #if DEBUG
          if self.fixture && ProcessInfo.processInfo.arguments.contains("--fixture-settings-offline") {
            throw APIError(code: "offline", message: "Offline", status: 0)
          }
          #endif
          if !self.fixture {
            let _: PracticeSettings = try await self.api.send("settings", method: "PUT", body: command.value)
          }
          guard self.bootstrap?.account.id == account, !Task.isCancelled else { return }
          // A newer edit supersedes this acknowledgement; send it next.
          guard self.pendingSettings?.id == command.id else { continue }
          if var cached = self.bootstrap {
            cached.settings = command.value
            try await self.disk.cache(key: "bootstrap:" + account, data: JSONEncoder().encode(cached))
          }
          guard self.pendingSettings?.id == command.id else { continue }
          let acknowledged = try await self.disk.acknowledgeSettings(account: account, id: command.id)
          guard acknowledged, self.pendingSettings?.id == command.id else { continue }
          self.pendingSettings = nil
          self.settingsSyncError = nil
        } catch {
          guard self.bootstrap?.account.id == account else { return }
          self.settingsSyncError = nil
          return
        }
      }
    }
  }
  /// Network-dependent operations require confirmed settings; the local walkthrough does not.
  func updateSettings() async throws {
    try await saveSettingsLocally()
    await settingsSyncTask?.value
    if pendingSettings != nil {
      throw APIError(code: "settings_pending", message: "Your settings are kept on this device. Connect and retry to continue setup.", status: 0)
    }
    try? await reconcileReminder(requestPermission: true)
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
    content.title = "Your next boss fight"
    content.body = "A few minutes of interview drilling? Those technical rounds don't pass themselves you know ;)."
    content.userInfo = ["route": "home"]
    try await center.add(UNNotificationRequest(identifier: "daily-practice", content: content,
      trigger: UNCalendarNotificationTrigger(dateMatching: reminderComponents(minutes: settings.dailyMinutes, timezone: settings.timezone), repeats: true)))
  }
  func requestReminderPermission() async -> Bool {
    guard !fixture else { return true }
    let center = UNUserNotificationCenter.current()
    var status = await center.notificationSettings().authorizationStatus
    if status == .notDetermined {
      _ = try? await center.requestAuthorization(options: [.alert, .sound])
      status = await center.notificationSettings().authorizationStatus
    }
    return status == .authorized || status == .provisional
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
    if !deleting { await sync(); syncSettingsInBackground(); await settingsSyncTask?.value }
    if (hasPendingWrites || pendingSettings != nil) && !discard {
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
        // The server may already have revoked the session; resync so no stale session survives relaunch.
        do { try await Clerk.shared.auth.signOut() } catch { _ = try? await Clerk.shared.refreshClient() }
      } else {
        try await Clerk.shared.auth.signOut()
      }
    }
    settingsSyncTask?.cancel(); settingsSyncTask = nil; settingsSyncID = nil; pendingSettings = nil; settingsSyncError = nil
    try await disk.clear()
    for key in ["account", "subject", "widgetToken", "widgetTokenExpires", "deviceID", "apiURL"] {
      try SharedStore.setSecret(nil, key: key)
    }
    try SharedStore.save(WidgetSnapshot(challenge: nil, updatedAt: ""))
    PlanCoordinator.shared.identify(account: nil)
    WidgetCenter.shared.reloadAllTimelines()
    UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    libraryWarmTask?.cancel(); libraryWarmTask = nil; libraryWarmAccount = nil
    librarySnapshots = [:]; libraryDetailSnapshots = [:]; librarySessions = [:]; libraryCoverage = []; libraryCoverageLoaded = false; dismissedHomeRevisits = []
    recall = RecallDeckResponse(cards: [], dueCount: 0); recallLoaded = false; recallFetchedAt = nil; recallRequestVersion += 1
    bootstrap = nil
    firstUse = FirstUseProgress()
    completionNoticeAccount = nil
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
    // Device-level choices from an earlier test run must not leak into this one.
    for mark in CoachMark.allCases { UserDefaults.standard.removeObject(forKey: mark.storageKey) }
    if ProcessInfo.processInfo.arguments.contains("--fixture-onboarding") {
      settings.onboardingComplete = false
      // A fresh first run: forget any draft or stage left behind by an earlier launch.
      UserDefaults.standard.removeObject(forKey: SetupView.draftKey)
      UserDefaults.standard.removeObject(forKey: "firstRun.stage")
    }
    if ProcessInfo.processInfo.arguments.contains("--fixture-long-focus") { settings.focus = "Distributed backend systems, database performance, cache consistency, and safe cross-team migrations" }
    #endif
    var challenge = Challenge(
      primaryConceptId: "queues", conceptIds: ["queues", "retry-safety"], engineeringLevel: "mid",
      id: "11111111-1111-4111-8111-111111111111", lifecycle: "ready",
      title: "Design a reliable job queue",
      prompt:
        "Design a durable job queue that survives worker failures. Explain how workers claim jobs, how retries avoid duplicate side effects and how accepted work is recovered after a crash.",
      topic: "System design", session: SessionDraft(answer: "", revision: 0), turns: [])
    #if DEBUG
    if ProcessInfo.processInfo.arguments.contains("--fixture-long-question") {
      challenge.prompt = String(repeating: "Describe the trade-offs, retry boundaries, and operational failure handling. State your assumptions and explain the consequences.\n\n", count: 18)
    }
    #endif
    #if DEBUG
    if ProcessInfo.processInfo.arguments.contains("--fixture-dashboard") {
      var recent = Challenge(difficulty: "easy", id: "recent", lifecycle: "completed", title: "Design a reliable job queue", prompt: "", topic: "Backend", completedAt: "2026-09-09T10:30:00Z")
      recent.ticket = 1
      // A finished rep of a Library question, with feedback that left something to fix: Library's "Worth another go".
      var notification = Challenge(questionId: "library-completed", scenario: "Notification service", primaryConceptId: "queues", conceptIds: ["queues", "retry-safety"], engineeringLevel: "senior",
        id: "library-completed-attempt", lifecycle: "completed", title: "Design notification delivery", prompt: "Design a durable service that handles worker failures and retries.",
        topic: "System design", completedAt: Date.now.addingTimeInterval(-86_400).ISO8601Format(), session: SessionDraft(answer: "My preserved original reasoning", revision: 1))
      notification.ticket = 2
      notification.reflection = Reflection(summary: "Workers kept their jobs through a crash.", worked: ["Accepted work survives a worker crash"], improve: "Say what a retry does when the first delivery already went out.", takeaway: "Durability first, then deduplication.", strengths: ["Durability"], gaps: ["Duplicate delivery"])
      memory = MemoryResponse(statistics: .init(completed: 12, lastSevenDays: 4, asOf: ISO8601DateFormatter().string(from: Date())), sessions: [notification, recent], patterns: [])
      if ProcessInfo.processInfo.arguments.contains("--fixture-evidence") {
        memory.evidence = [LearningEvidence(conceptId: "queues", observation: "Defined a bounded retry policy.", quote: "Retry at most three times.", signal: "demonstrated", assistance: "unknown", sessionId: "recent", at: "2026-09-09T10:30:00Z")]
      }
    }
    #endif
    #if DEBUG
    if ProcessInfo.processInfo.arguments.contains("--fixture-home-rich") {
      let evidence = LearningEvidence(conceptId: "queues", observation: "Consider what happens when a worker finishes a job but its acknowledgement is lost.", quote: "The worker deletes the job when it finishes.", signal: "needs_practice", assistance: "unknown", sessionId: "recent")
      var source = Challenge(id: "recent", lifecycle: "completed", title: "Design a reliable job queue", prompt: "Design a job queue that recovers from worker failures.", topic: "System design", session: SessionDraft(answer: evidence.quote, revision: 1))
      source.reflection = Reflection(summary: "A useful start on worker ownership.", worked: ["Defined worker ownership"], improve: evidence.observation, takeaway: "Acknowledgements can be lost.", strengths: [], gaps: [])
      memory = MemoryResponse(evidence: [evidence], statistics: .init(completed: 12, lastSevenDays: 4, asOf: Date().ISO8601Format()), sessions: [source], patterns: [])
      libraryCoverage = [.init(conceptId: "queues", completedAttempts: 3, distinctQuestions: 2)]; libraryCoverageLoaded = true
    }
    // An active learner for the knowledge map: reps at three levels, grounded feedback, coverage across areas.
    if ProcessInfo.processInfo.arguments.contains("--fixture-map") {
      func rep(_ id: String, _ title: String, _ level: String, _ concepts: [String], _ evidence: [(String, String, String)], daysAgo: Double) -> Challenge {
        var c = Challenge(primaryConceptId: concepts.first, conceptIds: concepts, engineeringLevel: level, id: id, lifecycle: "completed", title: title, prompt: "", topic: "System design",
                          completedAt: Date.now.addingTimeInterval(-daysAgo * 86_400).ISO8601Format())
        c.reflection = Reflection(evidence: evidence.map { LearningEvidence(conceptId: $0.0, observation: $0.2, quote: $0.1, signal: $0.2.hasPrefix("Missed") ? "needs_practice" : "demonstrated", assistance: "unknown") },
                                  summary: "", worked: [], improve: "", takeaway: "", strengths: [], gaps: [])
        return c
      }
      let sessions = [
        rep("m1", "Rate limiter for a public API", "senior", ["rate-limiting", "caching"], [("rate-limiting", "Token bucket per key in Redis, checked atomically.", "Shared, atomic state keeps the limit honest across servers.")], daysAgo: 1),
        rep("m2", "Charge a card exactly once", "mid", ["retry-safety", "transactions"], [("retry-safety", "Reuse the same idempotency key on retry.", "A stable key lets a retry find the original charge."), ("transactions", "Mark paid and save the charge id together.", "Missed that both writes must commit in one transaction.")], daysAgo: 2),
        rep("m3", "Design a reliable job queue", "mid", ["queues", "fault-tolerance"], [("queues", "Ack only after the work is written.", "Late acks keep accepted work through a crash.")], daysAgo: 4),
        rep("m4", "Chat presence at scale", "senior", ["fault-tolerance", "replication"], [("fault-tolerance", "Presence expires on a 70 second TTL.", "Missed that the TTL overshoots the freshness target.")], daysAgo: 6),
        rep("m5", "Feed for a social app", "senior", ["data-modeling", "caching"], [("data-modeling", "Fan out on write, except for huge accounts.", "Picks the write path by follower count.")], daysAgo: 9),
        rep("m6", "Profile cache that survives expiry", "junior", ["caching", "backpressure"], [("caching", "Concurrent misses share one read.", "Collapses a stampede into one database read.")], daysAgo: 12),
      ]
      memory = MemoryResponse(statistics: .init(completed: sessions.count, lastSevenDays: 4, asOf: Date().ISO8601Format()), sessions: sessions, patterns: [])
      libraryCoverage = [("caching", 3), ("rate-limiting", 1), ("retry-safety", 1), ("transactions", 1), ("queues", 1), ("fault-tolerance", 2), ("replication", 1), ("data-modeling", 1), ("backpressure", 1), ("api-design", 1)]
        .map { .init(conceptId: $0.0, completedAttempts: $0.1, distinctQuestions: $0.1) }
      libraryCoverageLoaded = true
      bootstrap?.todayPlan?.completedTotal = sessions.count
    }
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
    if ProcessInfo.processInfo.arguments.contains("--fixture-voice-example") {
      challenge.lifecycle = "in_progress"
      challenge.interview = InterviewState(prompt: challenge.prompt, turns: [InterviewTurn(
        id: "earlier-example", ordinal: 0, kind: "example", prompt: challenge.prompt,
        text: "", createdAt: "2026-09-09T18:00:00Z", jobId: "earlier-example", status: "completed",
        result: InterviewResponse(outcome: "reply", text: "For example, give each logical operation a stable key and store its result in the same transaction as the state change."))])
    }
    #endif
    let tomorrow = Calendar(identifier: .gregorian).startOfDay(for: .now.addingTimeInterval(86_400))
    bootstrap = Bootstrap(
      capabilities: .init(voice: VoiceCapability(available: true, plan: "free", checkedAt: Date.now.ISO8601Format(), sessionSeconds: 180, remaining: 2, limit: 3, resetsAt: tomorrow.ISO8601Format(), kind: "intro"),
                          // A customer account for store screenshots: no developer-only tab.
                          developerTools: !ProcessInfo.processInfo.arguments.contains("--fixture-customer")),
      account: .init(id: "fixture", status: "active"), settings: settings, challenge: challenge,
      jobs: [], todayPlan: TodayPlan(state: ProcessInfo.processInfo.arguments.contains("--fixture-dashboard") ? "complete_today" : "first_session",
        completedTotal: ProcessInfo.processInfo.arguments.contains("--fixture-dashboard") ? 12 : 0,
        completedLastSevenDays: ProcessInfo.processInfo.arguments.contains("--fixture-dashboard") ? 4 : 0,
        completedToday: ProcessInfo.processInfo.arguments.contains("--fixture-dashboard") ? 1 : 0,
        dueRecallCount: 0, recommendedRecallCount: 0, estimatedRecallMinutes: 0, dailyGoalMinutes: 10,
        nextTicket: ProcessInfo.processInfo.arguments.contains("--fixture-dashboard") ? 13 : 1))
    #if DEBUG
    if ProcessInfo.processInfo.arguments.contains("--fixture-dashboard") { bootstrap?.challenge = nil }
    // Today's rep is ticket No. 010: the first milestone, and a second filled day on the week strip.
    if ProcessInfo.processInfo.arguments.contains("--fixture-milestone") {
      var tenth = Challenge(id: "milestone-10", lifecycle: "completed", title: "Rate limiter for a public API", prompt: "Design per-key limits for a public API.",
                            topic: "System design", completedAt: Date.now.addingTimeInterval(-600).ISO8601Format())
      tenth.ticket = 10
      tenth.reflection = Reflection(summary: "", worked: ["Atomic check and decrement"], improve: "Say what happens when Redis is unreachable.", takeaway: "Shared state keeps the limit honest.", strengths: [], gaps: [])
      memory.sessions.insert(tenth, at: 0)
      bootstrap?.challenge = nil
      bootstrap?.todayPlan?.nextTicket = 11
    }
    if ProcessInfo.processInfo.arguments.contains("--fixture-pro") { applyConfirmedPro() }
    if ProcessInfo.processInfo.arguments.contains("--fixture-free-reps") {
      bootstrap?.account.plan = "free"
      bootstrap?.practice = PracticeAccess(plan: "free", freeReps: true, available: true, remaining: 2, limit: 3, resetsAt: Self.fixtureReset)
      bootstrap?.capabilities?.voice = VoiceCapability(available: true, plan: "free", checkedAt: Date().ISO8601Format(), sessionSeconds: 180, remaining: 3, limit: 3, kind: "intro")
    }
    if ProcessInfo.processInfo.arguments.contains("--fixture-gate") {
      bootstrap?.account.plan = "free"
      bootstrap?.practice = PracticeAccess(plan: "free", freeReps: true, available: false, nextFreeRepAt: Self.fixtureReset, remaining: 0, limit: 3, resetsAt: Self.fixtureReset)
      bootstrap?.capabilities?.voice = VoiceCapability(available: false, plan: "free", reason: "Your next free voice session comes back Thursday. Pro has it any time.", checkedAt: Date().ISO8601Format(), sessionSeconds: 180, remaining: 0, limit: 1, resetsAt: Date().addingTimeInterval(4 * 86_400).ISO8601Format(), kind: "taste")
    }
    #endif
  }
}

/// `plan: null` must reach the server as null, not be dropped, so it clears the override.
private struct DeveloperPlanInput: Encodable {
  var plan: String?
  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(plan, forKey: .plan)
  }
  enum CodingKeys: String, CodingKey { case plan }
}
