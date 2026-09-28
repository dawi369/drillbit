import SwiftUI

struct MemoryView: View {
  var model: AppModel
  var body: some View { LibraryView(model: model) }
}
struct SessionRow: View {
  var session: Challenge
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(session.title)
      Text(session.topic).font(.caption).foregroundStyle(.secondary)
      if let reflection = session.reflection {
        Text(reflection.takeaway).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
      }
    }
  }
}
struct HistoryView: View {
  var model: AppModel
  @State private var search = ""
  @State private var sessions: [Challenge] = []
  @State private var cursor: String?
  @State private var loading = false
  @State private var failure: String?
  var body: some View {
    SignalList {
      ForEach(sessions) { session in
        NavigationLink {
          SessionDetailView(model: model, initial: session)
        } label: {
          SessionRow(session: session)
        }
      }
      if let failure { Text(failure).foregroundStyle(.secondary) }
      if cursor != nil { Button("Load more") { Task { await load(more: true) } }.disabled(loading) }
    }.navigationTitle("All sessions").searchable(text: $search).task(id: search) {
      try? await Task.sleep(for: .milliseconds(300))
      if !Task.isCancelled { await load(more: false) }
    }
  }
  private func load(more: Bool) async {
    loading = true
    defer { loading = false }
    if model.fixture {
      sessions = model.memory.sessions
      return
    }
    var query = URLComponents()
    query.queryItems = [URLQueryItem(name: "q", value: search)]
    if more, let cursor { query.queryItems?.append(URLQueryItem(name: "cursor", value: cursor)) }
    do {
      let page: HistoryPage = try await model.api.send(
        "sessions?" + (query.percentEncodedQuery ?? ""))
      try Task.checkCancellation()
      sessions = more ? sessions + page.sessions : page.sessions
      cursor = page.nextCursor
      failure = nil
    } catch is CancellationError {} catch {
      if !more {
        sessions = model.memory.sessions.filter {
          search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
        }
      }
      failure = "Showing cached sessions. Connect to load more."
    }
  }
}
struct SessionDetailView: View {
  var model: AppModel
  var initial: Challenge
  @State private var current: Challenge?
  @State private var deleting = false
  @State private var preparing = false
  @State private var started: Challenge?
  init(model: AppModel, initial: Challenge) {
    self.model = model; self.initial = initial
    _current = State(initialValue: model.librarySessions[(model.bootstrap?.account.id ?? "") + ":" + initial.id])
  }
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    let challenge = current ?? initial
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .leading, spacing: 8) {
          SignalEyebrow(text: challenge.lifecycle == "completed" ? "Completed session" : "Session")
          Text(challenge.title).font(.title.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
          let date = challenge.completedAt.flatMap { Date.fromAPI($0) }?.formatted(date: .abbreviated, time: .shortened)
          DrillbitMetadata(text: [challenge.levelLabel, date].compactMap { $0 }.joined(separator: " · "))
        }
        Text(QuestionMarkup.plain(challenge.prompt)).foregroundStyle(.secondary)
        if let interview = challenge.interview, !interview.turns.isEmpty {
          NavigationLink("Interview conversation") { InterviewConversation(state: interview) }
        }
        if let answer = challenge.session?.answer, !answer.isEmpty {
          Text("Your answer").font(.headline)
          Text(answer).textSelection(.enabled)
          ShareLink("Copy or share answer", item: answer)
        }
        AssistanceSummary(challenge: challenge)
        if let reflection = challenge.reflection {
          ReflectionContent(reflection: reflection)
          Button("Practise this next") { preparing = true }.buttonStyle(PracticeButtonStyle())
        } else if challenge.lifecycle == "completed" {
          Text("Feedback is pending. You can retry failed feedback from Home.").foregroundStyle(
            .secondary)
        }
        if let help = challenge.help, help.contains(where: { $0.body != nil }) {
          DisclosureGroup("Help history") {
            VStack(alignment: .leading, spacing: 16) {
              ForEach(help.filter { $0.body != nil }) { item in
                Text(item.title).font(.headline)
                Text(item.body ?? "").textSelection(.enabled)
                if let draft = item.suggestedAnswer { Text(draft).textSelection(.enabled) }
              }
            }
          }
        }
        if let turns = challenge.turns, !turns.isEmpty {
          DisclosureGroup("Assistance used") {
            ForEach(turns) { turn in
              Text(turn.text).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            }
          }
        }
        if challenge.example != nil {
          NavigationLink("Example answer viewed") {
            ExampleView(model: model, challenge: challenge)
          }
        }
      }.padding(24)
    }.background(AppPalette.background).navigationTitle("Session").navigationBarTitleDisplayMode(.inline)
      .sheet(isPresented: $preparing, onDismiss: { if let started { model.presented = started; self.started = nil } }) {
        QuestionFlow(model: model, source: challenge, onStart: { started = $0 })
      }
      .toolbar { Button("Delete", systemImage: AppIcon.delete.rawValue, role: .destructive) { deleting = true } }
      .confirmationDialog("Delete this session and its learning evidence?", isPresented: $deleting)
    {
      Button("Delete session", role: .destructive) {
        Task {
          await model.perform {
            let _: EmptyResponse = try await model.api.send(
              "challenges/" + challenge.id, method: "DELETE")
            try await model.refreshAfterSessionDeletion()
            dismiss()
          }
        }
      }
    }
      .task {
        guard !model.fixture, current?.session == nil, initial.session == nil else { return }
        await model.perform { current = try await model.api.send("challenges/" + initial.id) }
      }
  }
}
struct AssistanceSummary: View {
  var challenge: Challenge
  var body: some View {
    Text(
      !(challenge.adoptions ?? []).isEmpty
        ? "Practised with an assisted draft"
        : (challenge.help ?? []).contains(where: { $0.body != nil })
          || (challenge.interview?.turns ?? []).contains(where: { ["hint", "example"].contains($0.kind) })
          || !(challenge.turns ?? []).isEmpty || challenge.example != nil
          ? "Practised with help" : "No explicit help recorded"
    )
    .font(.footnote).foregroundStyle(.secondary)
  }
}
struct LibraryView: View {
  var model: AppModel
  var skipped = false
  var initialConcept: String? = nil
  @State private var questions: [LibraryQuestion] = []
  @State private var search = ""
  @State private var tags: Set<String> = []
  @State private var level = ""
  @State private var days = 0
  @State private var cursor: String?
  @State private var failure: String?
  @State private var loading = false
  @State private var filterOpen = false
  @State private var coverage: [CoverageResponse.Entry] = []
  @State private var loadedIdentity: String?
  @State private var requestID = UUID()
  init(model: AppModel, skipped: Bool = false, initialConcept: String? = nil) {
    self.model = model; self.skipped = skipped; self.initialConcept = initialConcept
    let selected: Set<String> = initialConcept.map { [$0] } ?? []
    _tags = State(initialValue: selected)
    let identity = Self.cacheIdentity(search: "", tags: selected, level: "", days: 0, skipped: skipped)
    let key = "library:" + (model.bootstrap?.account.id ?? "") + ":" + identity
    let cached = model.librarySnapshots[key]
    _questions = State(initialValue: cached?.questions ?? [])
    _cursor = State(initialValue: cached?.nextCursor)
    _loadedIdentity = State(initialValue: cached == nil ? nil : identity)
  }
  private static func cacheIdentity(search: String, tags: Set<String>, level: String, days: Int, skipped: Bool) -> String {
    [search, tags.sorted().joined(separator: ","), level, String(days), String(skipped)].joined(separator: "|")
  }
  private var query: String {
    var components = URLComponents()
    var items = [URLQueryItem(name: "q", value: search), URLQueryItem(name: "skipped", value: skipped ? "true" : "false"), URLQueryItem(name: "concepts", value: tags.sorted().joined(separator: ","))]
    if !level.isEmpty { items.append(URLQueryItem(name: "level", value: level)) }
    if days > 0 { items.append(URLQueryItem(name: "since", value: Date().addingTimeInterval(-Double(days) * 86400).ISO8601Format())) }
    components.queryItems = items
    return components.percentEncodedQuery ?? ""
  }
  // Keep the task identity independent of the current clock.
  private var identity: String { Self.cacheIdentity(search: search, tags: tags, level: level, days: days, skipped: skipped) }
  var body: some View {
    SignalList {
      if !skipped {
        SignalEyebrow(text: "Questions / evidence")
          .listRowBackground(AppPalette.background)
      }
      if !skipped { NavigationLink("Practice evidence") { PracticeEvidenceView(model: model) } }
      if tags.count == 1, let id = tags.first, let value = coverage.first(where: { $0.conceptId == id }) {
        Section {
          LabeledContent("Completed attempts", value: String(value.completedAttempts))
          LabeledContent("Different questions", value: String(value.distinctQuestions))
          if let date = value.lastPractised.flatMap({ Date.fromAPI($0) }) { LabeledContent("Last practised", value: date.formatted(date: .abbreviated, time: .omitted)) }
        }
      }
      if questions.isEmpty && loadedIdentity == identity && !loading && failure == nil {
        ContentUnavailableView(skipped ? "No skipped questions" : "Your question library", systemImage: AppIcon.books.rawValue, description: Text(skipped ? "Questions you skip will be kept here." : "Completed questions and repeat attempts will appear here."))
      }
      ForEach(questions) { question in
        VStack(alignment: .leading, spacing: 8) {
          NavigationLink { LibraryQuestionView(model: model, initial: question) } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text(question.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
              DrillbitMetadata(text: question.scenario + " · " + question.levelLabel)
              if let date = question.lastActivity.flatMap({ Date.fromAPI($0) }) {
                DrillbitMetadata(text: date.formatted(date: .abbreviated, time: .omitted) + ((question.attemptCount ?? 0) > 1 ? " · \(question.attemptCount!) attempts" : ""))
              }
            }
          }.accessibilityIdentifier("library-question-" + question.id)
          ForEach(Array(question.conceptIds.prefix(2)), id: \.self) { id in
            Button(model.taxonomy.first { $0.id == id }?.label ?? id) { tags = [id] }
              .font(.caption).buttonStyle(.borderless).foregroundStyle(AppPalette.accent)
          }
        }.padding(.vertical, 8).listRowBackground(AppPalette.background)
      }
      if let failure { Text(failure).font(.footnote).foregroundStyle(.secondary); Button("Retry") { Task { await load() } } }
      if cursor != nil { Button("Load more") { Task { await load(more: true) } }.disabled(loading) }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .containerBackground(AppPalette.background, for: .navigation)
    .navigationTitle(skipped ? "Skipped questions" : "Library")
    .searchable(text: $search)
    .toolbar {
      Button("Filters", systemImage: AppIcon.filter.rawValue) { filterOpen = true }
      if !skipped {
        Menu {
          NavigationLink { LibraryView(model: model, skipped: true) } label: { Label("Skipped questions", systemImage: AppIcon.skip.rawValue) }
        } label: { Image(systemName: AppIcon.more.rawValue) }.accessibilityLabel("Library menu")
      }
    }
    .sheet(isPresented: $filterOpen) {
      NavigationStack {
        SignalList {
          Section("Concepts") {
            // The practice areas, plus any concept already selected (for example from a question's tag).
            ForEach(PracticeAreaCatalog.curated(model.taxonomy) + model.taxonomy.filter { tags.contains($0.id) && !PracticeAreaCatalog.ids.contains($0.id) }) { concept in
              Toggle(concept.label, isOn: Binding(get: { tags.contains(concept.id) }, set: { if $0 { tags.insert(concept.id) } else { tags.remove(concept.id) } }))
            }
          }
          Picker("Engineering level", selection: $level) {
            Text("All levels").tag("")
            ForEach(EngineeringLevel.choices, id: \.0) { Text($0.1).tag($0.0) }
          }
          Picker("Completed", selection: $days) { Text("Any time").tag(0); Text("Last 7 days").tag(7); Text("Last 30 days").tag(30) }
          Button("Clear filters") { tags = []; level = ""; days = 0 }
        }.navigationTitle("Filters").toolbar { Button("Done") { filterOpen = false } }
      }
    }
    .task { if model.taxonomy.isEmpty { await model.loadTaxonomy() }; coverage = model.libraryCoverage }
    .task(id: identity + String(model.libraryVersion)) {
      await model.preloadLibrary()
      await load()
    }
    .onChange(of: model.libraryVersion) { _, _ in
      guard let account = model.bootstrap?.account.id, let page = model.librarySnapshots["library:" + account + ":" + identity] else { return }
      questions = page.questions; cursor = page.nextCursor; coverage = model.libraryCoverage
    }
  }
  private func load(more: Bool = false) async {
    guard let account = model.bootstrap?.account.id else { return }
    if !more, let page = model.librarySnapshots["library:" + account + ":" + identity] {
      if questions != page.questions { questions = page.questions }
      cursor = page.nextCursor; loadedIdentity = identity
      return
    }
    let captured = identity, base = query
    let request = UUID(); requestID = request
    loading = true
    defer { if requestID == request { loading = false } }
    let key = "library:" + account + ":" + identity
    if loadedIdentity != captured {
      let cached = model.librarySnapshots[key]
      questions = cached?.questions ?? []; cursor = cached?.nextCursor; failure = nil
      if cached == nil, let data = try? await model.disk.cached(key: key), let page = try? JSONDecoder().decode(LibraryPage.self, from: data), requestID == request, model.bootstrap?.account.id == account {
        questions = page.questions; cursor = page.nextCursor
      }
      guard requestID == request, captured == identity, model.bootstrap?.account.id == account else { return }
      loadedIdentity = captured
    }
    do {
      var url = "library?" + base
      if more, let cursor { var c = URLComponents(); c.queryItems = [URLQueryItem(name: "cursor", value: cursor)]; url += "&" + (c.percentEncodedQuery ?? "") }
      let page = try await model.libraryResponse(path: url)
      try Task.checkCancellation()
      guard requestID == request, captured == identity, model.bootstrap?.account.id == account else { return }
      // An unchanged first page must not discard already loaded history or move the viewport.
      if more {
        questions += page.questions.filter { next in !questions.contains { $0.id == next.id } }
        cursor = page.nextCursor
      } else if page.questions.isEmpty || Array(questions.prefix(page.questions.count)) != page.questions || questions.count <= page.questions.count {
        if questions != page.questions { questions = page.questions }
        cursor = page.nextCursor
      }
      failure = nil
      let snapshot = LibraryPage(questions: questions, nextCursor: cursor)
      model.librarySnapshots[key] = snapshot
      try await model.disk.cache(key: key, data: JSONEncoder().encode(snapshot))
    } catch is CancellationError {} catch {
      guard requestID == request, captured == identity, model.bootstrap?.account.id == account else { return }
      failure = "Couldn’t refresh. Saved results may be incomplete."
    }
  }
}

struct LibraryQuestionView: View {
  var model: AppModel
  var initial: LibraryQuestion
  @State private var detail: LibraryDetail?
  @State private var failure: String?
  @State private var busy = false
  @State private var preview = false
  @State private var preparing = false
  @State private var started: Challenge?
  @State private var startCommand = UUID().uuidString
  init(model: AppModel, initial: LibraryQuestion) {
    self.model = model; self.initial = initial
    _detail = State(initialValue: model.libraryDetailSnapshots["library-detail:" + (model.bootstrap?.account.id ?? "") + ":" + initial.id])
  }
  private var question: LibraryQuestion { detail?.question ?? initial }
  var body: some View {
    SignalList {
      Section {
        Text(question.title).font(.title2.weight(.semibold))
        DisclosureGroup("Original question") { QuestionBody(markup: question.prompt).textSelection(.enabled) }
      }
      Section {
        ForEach(question.conceptIds, id: \.self) { id in
          NavigationLink(model.taxonomy.first { $0.id == id }?.label ?? id) { LibraryView(model: model, initialConcept: id) }
        }
      } header: { Text("Concepts") } footer: { Text("Explore related questions in your library.") }
      Section {
        Button((detail?.attempts.contains { $0.lifecycle == "completed" } ?? false) ? "Try again" : "Practise now") { preview = true }
        Button("Practise this concept") { preparing = true }
        if question.eligible { Text("Available in your question pool").foregroundStyle(.secondary) }
        else if detail?.attempts.contains(where: { $0.lifecycle == "skipped" }) == true {
          Button("Add back to pool") { Task { busy = true; defer { busy = false }; do { try await model.queueEligibility(question, eligible: true); if let account = model.bootstrap?.account.id { detail = model.libraryDetailSnapshots["library-detail:" + account + ":" + initial.id] ?? detail } } catch { failure = error.localizedDescription } } }.disabled(busy)
        }
      }
      Section("Attempts") {
        ForEach(detail?.attempts ?? []) { attempt in
          NavigationLink { SessionDetailView(model: model, initial: attempt) } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text(attempt.lifecycle == "completed" ? "Completed" : attempt.lifecycle == "skipped" ? "Skipped" : "In progress")
              if let date = (attempt.completedAt ?? attempt.createdAt).flatMap({ Date.fromAPI($0) }) { Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
            }
          }
        }
        if detail?.nextCursor != nil { Button("Earlier attempts") { Task { await load(more: true) } } }
      }
      if let failure { Text(failure).foregroundStyle(.secondary); Button("Refresh") { Task { await load() } } }
    }.navigationTitle("Question").navigationBarTitleDisplayMode(.inline)
    .task { if detail == nil { await load() } }
    .onChange(of: model.libraryVersion) { _, _ in
      if let account = model.bootstrap?.account.id { detail = model.libraryDetailSnapshots["library-detail:" + account + ":" + initial.id] ?? detail }
    }
    .sheet(isPresented: $preview, onDismiss: { if let started { model.presented = started; self.started = nil } }) {
      NavigationStack {
        ScrollView { VStack(alignment: .leading, spacing: 16) { Text(question.title).font(.title2.weight(.semibold)); QuestionBody(markup: question.prompt).textSelection(.enabled); if let failure { Text(failure).foregroundStyle(.secondary) } }.frame(maxWidth: .infinity, alignment: .leading).padding(24) }
          .safeAreaInset(edge: .bottom) {
            Button("Start practice") {
              Task {
                busy = true; defer { busy = false }
                let account = model.bootstrap?.account.id
                do {
                  let attempt = try await model.startLibraryQuestion(question, command: startCommand)
                  guard model.bootstrap?.account.id == account, let account else { return }
                  _ = try await model.disk.load(account: account, challenge: attempt)
                  model.bootstrap?.challenge = attempt; started = attempt; preview = false
                } catch { failure = error.localizedDescription }
              }
            }.buttonStyle(PracticeButtonStyle()).disabled(busy).padding(24).background(AppPalette.background)
          }.navigationTitle("Question preview").navigationBarTitleDisplayMode(.inline).toolbar { Button("Close") { preview = false } }
      }
    }
    .sheet(isPresented: $preparing, onDismiss: { if let started { model.presented = started; self.started = nil } }) {
      QuestionFlow(model: model, recovery: PreparationInput(primaryConceptId: question.primaryConceptId, focus: "System design", kind: "design", difficulty: model.settings.difficulty, engineeringLevel: question.engineeringLevel), onStart: { started = $0 })
    }
  }
  private func load(more: Bool = false) async {
    guard let account = model.bootstrap?.account.id else { return }
    let key = "library-detail:" + account + ":" + initial.id
    if detail == nil, let data = try? await model.disk.cached(key: key), model.bootstrap?.account.id == account {
      detail = try? JSONDecoder().decode(LibraryDetail.self, from: data)
    }
    do {
      var path = "questions/" + initial.id
      if more, let cursor = detail?.nextCursor { var c = URLComponents(); c.queryItems = [URLQueryItem(name: "cursor", value: cursor)]; path += "?" + (c.percentEncodedQuery ?? "") }
      var response = try await model.libraryDetail(id: initial.id, path: path)
      guard model.bootstrap?.account.id == account else { return }
      if more { response.attempts = (detail?.attempts ?? []) + response.attempts }
      detail = response; model.libraryDetailSnapshots[key] = response; failure = nil
      try await model.disk.cache(key: key, data: JSONEncoder().encode(response))
    } catch {
      guard model.bootstrap?.account.id == account, !Task.isCancelled else { return }
      failure = "Couldn’t refresh. Showing saved details if available."
    }
  }
}
