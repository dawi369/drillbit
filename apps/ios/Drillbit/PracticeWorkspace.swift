import SwiftUI

enum AssistanceMode: String, CaseIterable, Identifiable {
  case solo = "Solo"
  case coach = "Coach"
  case guided = "Guided"
  var id: String { rawValue }
  var explanation: String {
    switch self {
    case .solo: "Your reasoning, at your pace. Help is here if you need it."
    case .coach: "A nudge or a reasoning check. You keep the pen."
    case .guided: "Outlines, examples and drafts. You choose what to use."
    }
  }
}
enum WorkspaceSheet: String, Identifiable {
  case help, question, options
  var id: String { rawValue }
}

@MainActor @Observable final class PracticeController {
  let companion = CompanionCoordinator()
  var contextBusy = false
  var composing = false
  var helpSubmission = false
  var localCaptures: [String: Int] = [:]
  let accountID: String
  let model: AppModel
  var challenge: Challenge
  var answer = ""
  var mode: AssistanceMode = .solo
  var help: [HelpResult] = []
  var loaded = false
  var working = false
  var locked = false
  var failure: String?
  var undoEvent: AdoptionEvent?
  var finished: Challenge?
  private var saveTask: Task<Void, Never>?
  private var previousFixtureAnswer = ""
  private struct PendingAdoption: Codable {
    var command: String
    var input: AdoptionInput
  }
  var key: String { "practice:" + accountID + ":" + challenge.id }
  init(model: AppModel, challenge: Challenge) {
    self.accountID = model.bootstrap?.account.id ?? ""
    self.model = model
    self.challenge = challenge
  }
  var running: HelpResult? { help.last(where: \.running) }
  var nonempty: Bool { !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  var assistanceLabel: String {
    if !(challenge.adoptions ?? []).isEmpty { return "Practised with an assisted draft" }
    if help.contains(where: { $0.body != nil }) { return "Practised with help" }
    return "No help used"
  }
  func load() async {
    guard !loaded else { return }
    answer = await model.localAnswer(challenge)
    help = challenge.help ?? []
    undoEvent = challenge.adoptions?.last(where: {
      $0.operation != "undo" && $0.revision == challenge.session?.revision
    })
    if let data = try? await model.disk.cached(key: key + ":companion"),
      let saved = try? JSONDecoder().decode(CompanionCoordinator.Recovery.self, from: data)
    {
      companion.recovery = saved
    }
    if let context = challenge.companion { companion.context = context }
    mode = AssistanceMode(rawValue: companion.context.mode.capitalized) ?? .solo
    for item in help
    where (item.deliveries ?? []).contains("shown") && companion.matches(item, answer: answer) {
      localCaptures[item.id] = companion.generation
    }
    let pending = try? await model.disk.cached(key: key + ":adoption")
    locked = !model.fixture && !(pending?.isEmpty ?? true)
    loaded = true
    if !model.fixture, let drafts = try? await model.disk.pending(account: accountID),
      drafts.contains(where: { $0.challengeID == challenge.id && $0.kind == "complete" })
    {
      companion.completing = true
      failure = "Finish is saved on this device. Reconnect to complete this practice."
    }
    if locked { await reconcileAdoption() }
    if let data = try? await model.disk.cached(key: key + ":context-command"),
      let pending = try? JSONDecoder().decode(PendingContext.self, from: data)
    {
      await changeContext(pending.input)
    }
    if let data = try? await model.disk.cached(key: key + ":help-command"),
      let pending = try? JSONDecoder().decode(PendingHelp.self, from: data), !model.fixture
    {
      // Reopening only reads the durable job. Results from a previous edit generation stay in Earlier help.
      if let job: Job = try? await model.api.send("jobs/" + pending.command),
        !help.contains(where: { $0.id == job.id })
      {
        help.append(
          HelpResult(
            id: job.id, status: job.status, kind: pending.input.kind,
            revision: pending.input.revision))
      }
    }
  }
  func select(_ value: AssistanceMode) {
    guard mode != value, !contextBusy else { return }
    companion.suggestion = nil
    companion.event(.modeChanged)
    // Solo immediately blocks presentation even before its durable mode command is acknowledged.
    mode = value
    Task {
      await changeContext(
        CompanionUpdate(
          revision: companion.context.revision, operation: "mode", mode: value.rawValue.lowercased()
        ))
      companion.pendingGuided =
        value == .guided && companion.context.guidedStarted != true
        && !companion.recovery.guidedCycles.contains(companion.context.cycle)
    }
  }
  func edit(_ value: String) {
    guard loaded, !locked, finished == nil else { return }
    if value != answer { companion.event(.answerCommitted(value)) }
    answer = value
    undoEvent = nil
    saveTask?.cancel()
    saveTask = Task {
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled else { return }
      await model.perform { try await model.save(challenge, answer: self.answer) }
      try? await Task.sleep(for: .seconds(2))
      guard !Task.isCancelled else { return }
      await model.sync()
    }
  }
  func flush() async throws {
    saveTask?.cancel()
    guard !locked else {
      throw APIError(
        code: "reconcile", message: "Reconnect to check the last insertion first.", status: 0)
    }
    try await model.save(challenge, answer: answer)
    await model.sync()
  }
  func refreshHelp() async {
    guard model.bootstrap?.account.id == accountID, !model.fixture, loaded, finished == nil else {
      return
    }
    do {
      let current: Challenge = try await model.api.send("challenges/" + challenge.id)
      help = current.help ?? []
      challenge = current
      if !contextBusy, companion.unavailable == nil, let context = current.companion {
        companion.context = context
        mode = AssistanceMode(rawValue: context.mode.capitalized) ?? .solo
      }
      // Never replace the editor's local draft during background polling.
      if current.lifecycle == "completed", companion.completing, !model.hasPendingWrites {
        finished = current
      }
      if !current.isActive {
        failure = "This session was finished elsewhere. Close it to review your drafts."
      }
    } catch {
      if running != nil {
        failure = "Connection lost. Your request is saved; reconnect to check it."
      }
    }
  }
  func request(_ kind: String, question: String = "", trigger: String = "explicit") async {
    guard model.bootstrap?.account.id == accountID, !working, running == nil, !locked, !contextBusy,
      mode != .solo, !companion.completing
    else { return }
    working = true
    helpSubmission = true
    failure = nil
    defer {
      working = false
      helpSubmission = false
    }
    let editGeneration = companion.generation
    do {
      if !question.isEmpty {
        await changeContext(
          CompanionUpdate(
            revision: companion.context.revision, operation: "discussion", text: question))
        guard companion.unavailable == nil else { return }
      }
      try await flush()
      if model.fixture {
        companion.context.digest = InterventionPolicy.digest(answer)
        companion.context.cycle =
          companion.context.digest + (companion.context.decisions.last?.id ?? "")
        companion.consume(answer: answer, trigger: trigger)
        let body =
          kind == "draft"
          ? "Make the failure behaviour explicit."
          : kind == "outline"
            ? "Start with local evaluation. Then cover configuration updates, failure handling and rollback."
            : kind == "example"
              ? "Evaluate flags locally from a versioned cache. Publish updates from a control plane. If it is unavailable, keep the last known good version and expose its age. Roll back by publishing a previous version."
              : "What happens to evaluation when a client cannot reach the control plane?"
        help.append(
          HelpResult(
            id: UUID().uuidString, status: "completed", kind: kind,
            revision: challenge.session?.revision ?? 0, body: body,
            suggestedAnswer: kind == "draft"
              ? "Evaluate flags locally using a versioned cache. Keep the last known good configuration when the control plane is unavailable. Publish a previous version to roll back safely."
              : nil))
        help[help.count - 1].capture = companion.capture(trigger: trigger)
        localCaptures[help.last!.id] = editGeneration
        await persistCompanion()
        return
      }
      guard !model.hasPendingWrites else {
        throw APIError(
          code: "sync",
          message: "Your answer is saved locally. Connect to sync it before asking for help.",
          status: 0)
      }
      let current: Challenge = try await model.api.send("challenges/" + challenge.id)
      challenge = current
      if let context = current.companion { companion.context = context }
      guard !composing, editGeneration == companion.generation, current.session?.answer == answer,
        mode.rawValue.lowercased() == companion.context.mode
      else { return }
      let capture = companion.capture(trigger: trigger)
      let command = UUID().uuidString
      let input = HelpInput(
        kind: kind, mode: companion.context.mode, question: question,
        revision: current.session?.revision ?? 0, capture: current.companion == nil ? nil : capture)
      companion.consume(answer: answer, trigger: trigger)
      localCaptures[command] = editGeneration
      await persistCompanion()
      // Persist identity before sending. A lost response is reconciled by reading this job, never by creating another.
      try await model.disk.cache(
        key: key + ":help-command",
        data: JSONEncoder().encode(PendingHelp(command: command, input: input)))
      let result: Job = try await model.api.send(
        "challenges/\(challenge.id)/help", method: "POST", body: input, command: command)
      help.append(
        HelpResult(
          id: result.id, status: result.status, kind: kind, revision: current.session?.revision ?? 0
        ))
    } catch {
      companion.unavailable = "Connection unavailable. Your writing is safe."
      companion.requestingSince = nil
      failure = trigger == "explicit" ? error.localizedDescription : nil
      await refreshHelp()
    }
  }
  func stop() async {
    guard let running else { return }
    do {
      let _: EmptyResponse = try await model.api.send("jobs/\(running.id)/cancel", method: "POST")
      await refreshHelp()
    } catch { failure = "Could not confirm Stop. Reconnect to check the request." }
  }
  func insert(_ source: HelpResult, operation: String) async {
    guard !working, !locked else { return }
    working = true
    failure = nil
    defer { working = false }
    do {
      try await flush()
      if model.fixture {
        previousFixtureAnswer = answer
        answer =
          operation == "append"
          ? answer + "\n\n" + (source.insertableText ?? "") : source.insertableText ?? answer
        undoEvent = AdoptionEvent(
          id: UUID().uuidString, sourceId: source.id, operation: operation, revision: 1)
        challenge.adoptions = [undoEvent!]
        try await model.save(challenge, answer: answer)
        return
      }
      guard !model.hasPendingWrites else {
        throw APIError(
          code: "sync", message: "Connect and sync before inserting. Your draft is safe.", status: 0
        )
      }
      // The preview belongs to this exact revision. Server-side checks catch edits from other devices.
      let input = AdoptionInput(
        sourceId: source.id, operation: operation, revision: challenge.session?.revision ?? 0)
      let command = UUID().uuidString
      try await model.disk.cache(
        key: key + ":adoption",
        data: JSONEncoder().encode(PendingAdoption(command: command, input: input)))
      locked = true
      let current: Challenge = try await model.api.send(
        "challenges/\(challenge.id)/adopt", method: "POST", body: input, command: command)
      await accept(current)
      undoEvent = current.adoptions?.first(where: { $0.id == command })
    } catch {
      failure = error.localizedDescription
      if locked { await reconcileAdoption() }
    }
  }
  func preparePreview() async -> Bool {
    do {
      try await flush()
      guard model.fixture || !model.hasPendingWrites else {
        throw APIError(
          code: "sync", message: "Connect and sync before previewing an insertion.", status: 0)
      }
      if !model.fixture {
        let current: Challenge = try await model.api.send("challenges/" + challenge.id)
        guard current.session?.answer == answer else {
          throw APIError(
            code: "conflict",
            message: "The cloud draft changed. Close and reopen this session before inserting.",
            status: 409)
        }
        challenge = current
      }
      return true
    } catch {
      failure = error.localizedDescription
      return false
    }
  }
  func undo() async {
    guard let event = undoEvent, !working, !locked else { return }
    working = true
    defer { working = false }
    if model.fixture {
      answer = previousFixtureAnswer
      undoEvent = nil
      await model.perform { try await model.save(challenge, answer: self.answer) }
      return
    }
    do {
      let command = UUID().uuidString
      let input = AdoptionInput(sourceId: event.id, operation: "undo", revision: event.revision)
      try await model.disk.cache(
        key: key + ":adoption",
        data: JSONEncoder().encode(PendingAdoption(command: command, input: input)))
      locked = true
      let current: Challenge = try await model.api.send(
        "challenges/\(challenge.id)/adopt", method: "POST", body: input, command: command)
      await accept(current)
      undoEvent = nil
    } catch {
      failure = error.localizedDescription
      await reconcileAdoption()
    }
  }
  private func accept(_ current: Challenge) async {
    challenge = current
    answer = await model.localAnswer(current)
    try? await model.disk.cache(key: key + ":adoption", data: Data())
    locked = false
  }
  func reconcileAdoption() async {
    do {
      if let data = try await model.disk.cached(key: key + ":adoption"), !data.isEmpty {
        let pending = try JSONDecoder().decode(PendingAdoption.self, from: data)
        do {
          let current: Challenge = try await model.api.send(
            "challenges/\(challenge.id)/adopt", method: "POST", body: pending.input,
            command: pending.command)
          await accept(current)
          undoEvent = current.adoptions?.first(where: {
            $0.id == pending.command && $0.operation != "undo"
              && $0.revision == current.session?.revision
          })
        } catch let error as APIError where error.status == 409 || error.status == 400 {
          let current: Challenge = try await model.api.send("challenges/" + challenge.id)
          await accept(current)
          failure = error.message
        }
      } else {
        let current: Challenge = try await model.api.send("challenges/" + challenge.id)
        await accept(current)
      }
    } catch { failure = "Reconnect to confirm the last insertion. Your saved answer is safe." }
  }
  func finish() async {
    guard !working, !locked else { return }
    companion.completing = true
    companion.suggestion = nil
    working = true
    saveTask?.cancel()
    defer { working = false }
    do {
      var result = try await model.finish(challenge, answer: answer)
      result.help = help
      result.adoptions = challenge.adoptions
      finished = result
    } catch { failure = error.localizedDescription }
  }
}

struct PracticeView: View {
  var model: AppModel
  var challenge: Challenge
  @State private var practice: PracticeController
  @State private var sheet: WorkspaceSheet?
  @State private var promptExpanded = true
  @State private var skipping = false
  @State private var confirmingFinish = false
  @State private var restoreFocusAfterCancel = false
  @FocusState private var focused: Bool
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.scenePhase) private var phase
  init(model: AppModel, challenge: Challenge) {
    self.model = model
    self.challenge = challenge
    _practice = State(initialValue: PracticeController(model: model, challenge: challenge))
  }
  var body: some View {
    Group {
      if !challenge.isActive {
        SessionDetailView(model: model, initial: challenge)
      } else if let finished = practice.finished {
        ReflectionView(model: model, initial: finished)
      } else {
        workspace
      }
    }
    .preferredColorScheme(
      model.fixture && ProcessInfo.processInfo.arguments.contains("--dark") ? .dark : nil
    )
    .onDisappear {
      practice.companion.foreground = false
      practice.companion.event(.visibilityChanged)
    }
    .task {
      practice.companion.foreground = true
      await practice.load()
      await practice.refreshHelp()
    }
    .task {
      while !Task.isCancelled {
        await practice.tickCompanion()
        try? await Task.sleep(for: .seconds(1))
      }
    }
    .onChange(of: sheet) { _, value in
      practice.companion.modal = value != nil
      practice.companion.event(.visibilityChanged)
    }
    .onChange(of: confirmingFinish) { _, value in
      practice.companion.modal = value
      practice.companion.event(.visibilityChanged)
    }
    .task(id: practice.running?.id) {
      guard practice.running != nil else { return }
      let started = Date()
      while !Task.isCancelled, practice.finished == nil, practice.running != nil {
        await practice.refreshHelp()
        try? await Task.sleep(for: .milliseconds(Date().timeIntervalSince(started) < 10 ? 500 : 1500))
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: UITextView.textDidChangeNotification)) {
      notification in
      if let editor = notification.object as? UITextView {
        practice.composing = editor.markedTextRange != nil
        practice.companion.event(.inputActivity)
      }
    }
    .onChange(of: phase) { _, value in
      practice.companion.foreground = value == .active
      practice.companion.event(.visibilityChanged)
      if value == .background {
        Task { try? await practice.flush() }
      } else if value == .active {
        Task {
          if practice.locked { await practice.reconcileAdoption() }
          await practice.refreshHelp()
        }
      }
    }
  }
  private var workspace: some View {
    VStack(alignment: .leading, spacing: 12) {
      if typeSize.isAccessibilitySize {
        Button("Read question", systemImage: "text.alignleft") {
          focused = false
          sheet = .question
        }.font(.subheadline).labelStyle(.titleOnly).padding(.horizontal, 24)
      } else {
        DisclosureGroup(isExpanded: $promptExpanded) {
          ScrollView { Text(challenge.prompt).frame(maxWidth: .infinity, alignment: .leading) }
            .frame(maxHeight: 180)
        } label: {
          Text(challenge.title).font(.headline)
        }.padding(.horizontal, 24)
      }
      TextEditor(text: Binding(get: { practice.answer }, set: { practice.edit($0) }))
        .simultaneousGesture(
          DragGesture(minimumDistance: 8).onChanged { _ in practice.companion.event(.inputActivity)
          }
        )
        .simultaneousGesture(TapGesture().onEnded { practice.companion.event(.inputActivity) })
        .focused($focused).scrollContentBackground(.hidden).padding(.horizontal, 16)
        .disabled(
          practice.locked || (practice.working && !practice.helpSubmission)
            || practice.companion.completing
        )
        .accessibilityLabel("Your answer").accessibilityIdentifier("answerEditor")
        .overlay(alignment: .topLeading) {
          if practice.answer.isEmpty {
            Text(typeSize.isAccessibilitySize ? "Your answer" : "Work through your reasoning…")
              .foregroundStyle(.tertiary).padding(.horizontal, 24)
              .padding(.top, 8).allowsHitTesting(false)
          }
        }
      if let failure = practice.failure {
        Text(failure).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 24)
      }
      if practice.locked {
        Button("Reconnect to check insertion") { Task { await practice.reconcileAdoption() } }
          .padding(.horizontal, 24)
      }
      if practice.mode != .solo {
        CompanionPanel(practice: practice) { sheet = .help }
      }
      HStack(spacing: 16) {
        Button {} label: {
          Image(systemName: "waveform")
            .font(.body.weight(.medium))
            .foregroundStyle(.tertiary)
            .frame(width: 44, height: 44)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(true)
        .accessibilityLabel("Live voice")
        .accessibilityValue("In development")
        .accessibilityIdentifier("liveVoice")
        Menu {
          ForEach(AssistanceMode.allCases) { mode in Button(mode.rawValue) { practice.select(mode) }
          }
        } label: {
          Text(practice.mode.rawValue).font(.subheadline)
        }
        .accessibilityLabel("Practice mode").accessibilityIdentifier("practiceMode")
        Spacer()
        saveLabel
      }.padding(.horizontal, 24).padding(.bottom, 12)
    }
    .navigationTitle("Practice").navigationBarTitleDisplayMode(.inline)
    .onChange(of: focused) { _, value in if value { promptExpanded = false } }
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Close") {
          Task {
            do {
              if !practice.locked { try await practice.flush() }
              model.presented = nil
            } catch { practice.failure = error.localizedDescription }
          }
        }.disabled(practice.working)
      }
      ToolbarItem(placement: .primaryAction) {
        Button("Finish") {
          restoreFocusAfterCancel = focused
          focused = false
          confirmingFinish = true
        }.disabled(
          !practice.nonempty || practice.working || practice.locked || practice.companion.completing
        )
      }
      ToolbarItem(placement: .topBarTrailing) {
        Button("Practice options", systemImage: "ellipsis") {
          focused = false
          sheet = .options
        }
      }
    }
    .sheet(item: $sheet) { item in
      NavigationStack {
        switch item {
        case .help: HelpView(practice: practice)
        case .question: QuestionSheet(challenge: challenge)
        case .options:
          PracticeOptions(
            practice: practice,
            skip: {
              sheet = nil
              skipping = true
            })
        }
      }.presentationDetents([.large])
    }
    .alert("Finish practice?", isPresented: $confirmingFinish) {
      Button("Keep writing", role: .cancel) { focused = restoreFocusAfterCancel }
      Button("Finish practice") { Task { await practice.finish() } }
    } message: {
      Text(
        "This saves your final answer and ends this practice. You can review it afterwards, but you can’t edit the finished answer."
      )
    }
    .confirmationDialog("Skip this challenge?", isPresented: $skipping) {
      Button("Skip challenge", role: .destructive) {
        Task {
          do {
            try await practice.flush()
            await model.skip(challenge.id)
          } catch { practice.failure = error.localizedDescription }
        }
      }
    }
  }
  private var helpButton: some View {
    Button {
      focused = false
      sheet = .help
    } label: {
      Label(
        practice.running != nil
          ? "Help is preparing"
          : practice.mode == .solo ? "Solo · Get help" : "\(practice.mode.rawValue) help",
        systemImage: "sparkle")
    }.accessibilityIdentifier("openHelp")
  }
  private var saveLabel: some View {
    Text(model.saveStatus).font(.caption).foregroundStyle(.secondary)
  }
}

struct QuestionSheet: View {
  let challenge: Challenge
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Text(challenge.title).font(.title2.weight(.semibold))
        Text(challenge.prompt).textSelection(.enabled)
      }.padding(24)
    }
    .navigationTitle("Question").navigationBarTitleDisplayMode(.inline).toolbar {
      Button("Done") { dismiss() }
    }
  }
}
struct PracticeOptions: View {
  var practice: PracticeController
  var skip: () -> Void
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    Form {
      Section("Assistance") {
        Picker("Mode", selection: Binding(get: { practice.mode }, set: { practice.select($0) })) {
          ForEach(AssistanceMode.allCases) { Text($0.rawValue).tag($0) }
        }
        Text(practice.mode.explanation).foregroundStyle(.secondary)
      }
      Section { Button("Skip challenge", role: .destructive, action: skip) }
    }.navigationTitle("Practice options").navigationBarTitleDisplayMode(.inline).toolbar {
      Button("Done") { dismiss() }
    }
  }
}
struct PreparationView: View {
  var model: AppModel
  var source: Challenge? = nil
  var onSubmitted: () -> Void = {}
  var submit: ((PreparationInput) -> Void)? = nil
  var recovery: PreparationInput? = nil
  @State private var focus = "System design"
  @State private var practiceArea = ""
  @State private var kind = "auto"
  @State private var engineeringLevel = "mid"
  @State private var instruction = ""
  @State private var interviewStyle = InterviewStyle.standard
  @State private var includeSource = true
  @State private var initialized = false
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    Form {
      Section {
        NavigationLink { PracticeAreaPicker(model: model, selection: $practiceArea) } label: {
          LabeledContent("Practice area", value: model.taxonomy.first { $0.id == practiceArea }?.label ?? "Automatic")
        }.accessibilityIdentifier("prepareArea")
        Picker("Target level", selection: $engineeringLevel) {
          ForEach(EngineeringLevel.choices, id: \.0) { Text($0.1).tag($0.0) }
        }.accessibilityIdentifier("prepareLevel")

      }
      if includeSource, let source, let reflection = source.reflection {
        Section("Building on your last session") {
          Text(reflection.improve).font(.subheadline)
          NavigationLink(source.title) { SessionDetailView(model: model, initial: source) }
          Button("Remove") { includeSource = false }
        }
      }
      Section {
        NavigationLink {
          InterviewStylePicker(selection: $interviewStyle)
        } label: {
          LabeledContent("Interview style", value: interviewStyle.title)
        }.accessibilityIdentifier("interviewStyle")
      }
      Section {
        TextField("Any custom instructions? (optional)", text: $instruction, axis: .vertical)
          .lineLimit(2...4).accessibilityLabel("Optional request")
      }
      Section {
        Button("Prepare question") {
          let input = PreparationInput(
            primaryConceptId: practiceArea.isEmpty ? nil : practiceArea, interviewStyle: interviewStyle, focus: "System design", kind: "design", difficulty: model.settings.difficulty,
            engineeringLevel: engineeringLevel,
            replaceId: model.bootstrap?.challenge?.lifecycle == "ready" ? model.bootstrap?.challenge?.id : nil,
            instruction: instruction,
            followUpId: includeSource && source?.reflection != nil ? source?.id : nil)
          if let submit { submit(input) }
          else {
            dismiss()
            onSubmitted()
            Task { await model.generate(input) }
          }
        }.buttonStyle(PracticeButtonStyle())
          .accessibilityIdentifier("submitPreparation")
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
          .disabled(focus.isEmpty || model.busy)
      } footer: {
        if model.bootstrap?.challenge?.lifecycle == "ready" {
          Text("Your current question stays until the new one is ready.")
        }
      }
    }.task { await model.loadTaxonomy() }.navigationTitle("New question").navigationBarTitleDisplayMode(.inline).toolbar {
      Button("Cancel") { dismiss() }
    }
    .onAppear {
      guard !initialized else { return }
      initialized = true
      focus = "System design"
      engineeringLevel = model.settings.selectedLevel
      if let recovery {
        interviewStyle = .standard
        practiceArea = recovery.primaryConceptId ?? ""
        engineeringLevel = recovery.engineeringLevel ?? EngineeringLevel.legacy(recovery.difficulty)
        kind = recovery.kind
        instruction = recovery.instruction
        includeSource = recovery.followUpId != nil
      }
    }
  }
}
