import SwiftUI
import OSLog

@MainActor @Observable final class InterviewController {
  let model: AppModel
  let account: String
  var challenge: Challenge
  var state: InterviewState
  var answer = ""
  var busy = false
  var loaded = false
  var failure: String?
  var finished: Challenge?
  var acceptsVoiceInput = true
  weak var voice: LiveVoice?
  private var editGeneration = 0
  private var savedGeneration = 0
  private var refreshing = false
  private var retrySubmission: (kind: String, text: String, command: UUID?)?
  private var saveTask: Task<Void, Never>?
  var selectedStyle: InterviewStyle?
  var style: InterviewStyle { .standard }
  var pending: PendingInterviewCommand?
  var outgoing: InterviewTurn?
  private var sentAt: Date?
  private let latencyLog = Logger(subsystem: "dawi.drillbit", category: "inference")
  private func recordFirstText(_ text: String) {
    guard !text.isEmpty, let started = sentAt else { return }
    sentAt = nil
    let milliseconds = Int(Date().timeIntervalSince(started) * 1000)
    latencyLog.info("send_to_first_text_ms=\(milliseconds, privacy: .public)")
  }
  var streamEpoch = 0
  var displayState: InterviewState {
    var value = state
    if let outgoing, !value.turns.contains(where: { $0.id == outgoing.id }) { value.turns.append(outgoing) }
    return value
  }
  var streamTurn: InterviewTurn? { state.turns.first(where: \.pending) }
  func watchResponse() async {
    guard !model.fixture, let turn = streamTurn else { return }
    do {
      try await model.api.interviewStream(id: challenge.id, turn: turn.id) { [weak self] snapshot in
        guard let self, self.currentAccount, let index = self.state.turns.firstIndex(where: { $0.id == turn.id && $0.jobId == turn.jobId }) else { return }
        self.recordFirstText(snapshot.text)
        self.state.turns[index].partial = snapshot.text
      }
      while busy || refreshing { try await Task.sleep(for: .milliseconds(20)) }
      try Task.checkCancellation()
      await refresh()
    } catch is CancellationError {} catch {
      guard !Task.isCancelled, currentAccount else { return }
      failure = "The response was interrupted. Your answer is safe."
    }
  }
  var key: String { "interview:" + account + ":" + challenge.id }
  var currentAccount: Bool { model.bootstrap?.account.id == account && !model.isLocallySkipped(account: account, id: challenge.id) }
  var waiting: Bool { state.turns.contains(where: \.pending) }
  var failedTurn: InterviewTurn? { state.turns.last(where: { $0.status == "failed" }) }
  var locked: Bool { !loaded || busy || pending != nil || waiting }
  var canFinish: Bool { voice?.blocksText != true && loaded && !busy && pending == nil && (!answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.turns.contains(where: { $0.kind == "answer" || $0.voice?.contains(where: { $0.speaker == "user" }) == true })) }
  init(model: AppModel, challenge: Challenge) {
    self.model = model
    self.challenge = challenge
    account = model.bootstrap?.account.id ?? ""
    state = challenge.interview ?? InterviewState(style: challenge.interviewStyle ?? .standard, prompt: challenge.prompt)
  }
  func load() async {
    guard !loaded else { return }
    answer = await model.localAnswer(challenge)
    do {
      if let data = try await model.disk.cached(key: key + ":pending") {
        pending = try JSONDecoder().decode(PendingInterviewCommand?.self, from: data)
      }
      if let data = try await model.disk.cached(key: key + ":state") {
        state = try JSONDecoder().decode(InterviewState.self, from: data)
      }
      if let data = try await model.disk.cached(key: key + ":style") {
        selectedStyle = try JSONDecoder().decode(InterviewStyle.self, from: data)
      }
      loaded = true
      if pending != nil { await recover() }
      else { await refresh() }
    } catch { loaded = true; failure = error.localizedDescription }
  }
  func selectStyle(_ style: InterviewStyle) async {
    guard style == .standard, !locked, currentAccount else { return }
    do {
      try await model.disk.cache(key: key + ":style", data: JSONEncoder().encode(style))
      selectedStyle = style
    } catch { failure = error.localizedDescription }
  }
  func edit(_ value: String) {
    guard !locked else { return }
    answer = value
    editGeneration += 1
    saveTask?.cancel()
    saveTask = Task {
      do {
        try await Task.sleep(for: .milliseconds(300))
        try await flush()
      } catch is CancellationError {} catch { failure = error.localizedDescription }
    }
  }
  func flush() async throws {
    guard currentAccount else { throw CancellationError() }
    let generation = editGeneration
    try await model.save(challenge, answer: answer)
    savedGeneration = generation
    await model.sync(challengeID: challenge.id)
    guard currentAccount else { throw CancellationError() }
  }
  func refresh() async {
    guard currentAccount, !busy, !refreshing, pending == nil, !model.fixture else { return }
    refreshing = true
    defer { refreshing = false }
    let generation = editGeneration
    do {
      let fresh: Challenge = try await model.api.send("challenges/" + challenge.id)
      guard currentAccount, !busy, generation == editGeneration, savedGeneration == generation else { return }
      guard (fresh.session?.revision ?? 0) >= (challenge.session?.revision ?? 0) else { return }
      let local = try await model.disk.load(account: account, challenge: fresh)
      guard currentAccount, !busy, generation == editGeneration, local.kind.isEmpty, !local.conflict else { return }
      answer = local.answer
      if let interview = fresh.interview { state = interview }
      challenge = fresh
      model.bootstrap?.challenge = fresh
      try await model.disk.cache(key: key + ":state", data: JSONEncoder().encode(state))
      if !fresh.isActive { finished = fresh }
    } catch { if waiting { failure = "Your answer is saved. Reconnect to get the interviewer's response." } }
  }
  func submit(_ kind: String, text: String = "", command: UUID? = nil, onAccepted: (() -> Void)? = nil) async {
    guard !locked, failedTurn == nil else { return }
    sentAt = Date()
    busy = true
    let command = command ?? UUID()
    if kind == "answer" {
      outgoing = InterviewTurn(id: command.uuidString, ordinal: state.turns.count, kind: kind, prompt: state.prompt, text: answer, createdAt: Date().ISO8601Format(), jobId: command.uuidString, status: "pending")
    }
    failure = nil
    retrySubmission = (kind, text, command)
    saveTask?.cancel()
    do {
      if kind == "answer", !model.fixture {
        await saveTask?.value
        await model.waitForCurrentSync()
        guard currentAccount else { throw CancellationError() }
        let promptID = state.turns.last(where: { ["answer", "continue"].contains($0.kind) && $0.result != nil })?.id ?? "original"
        pending = try await model.disk.prepareInterviewAnswer(account: account, id: challenge.id, answer: answer, command: command.uuidString, promptID: promptID, style: style)
      } else {
        try await flush()
        let local = try await model.disk.load(account: account, challenge: challenge)
        guard model.fixture || (local.kind.isEmpty && !local.conflict) else {
          throw APIError(code: "sync_pending", message: local.conflict ? "Resolve the draft conflict before sharing." : "Couldn’t sync this answer. Check your connection and retry.", status: 0)
        }
        pending = PendingInterviewCommand(command: command.uuidString, input: InterviewInput(promptId: state.turns.last(where: { ["answer","continue"].contains($0.kind) && $0.result != nil })?.id ?? "original", kind: kind, revision: local.revision, text: kind == "answer" ? answer : text, style: style))
        try await persistPending()
      }
      retrySubmission = nil
    } catch { outgoing = nil; failure = error.localizedDescription; busy = false; return }
    onAccepted?()
    busy = false
    await recover()
  }
  /// Future voice adapters call this only for a finalized user turn. The normal
  /// durable answer command generates and stores the reply, so text and voice
  /// share one transcript instead of importing a second conversation on exit.
  func receiveFinalizedAnswer(_ incoming: FinalizedInterviewAnswer) async throws {
    // Speech finalizers may retain edge whitespace; use the same canonical text
    // as durable submission so reconnect replay recognizes the original turn.
    var event = incoming
    event.text = event.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard acceptsVoiceInput, finished == nil, challenge.isActive, currentAccount, event.account == account, event.challengeID == challenge.id else {
      throw APIError(code: "stale_voice_context", message: "This interview is no longer active.", status: 0)
    }
    if let existing = state.turns.first(where: { $0.id == event.id.uuidString }) {
      guard existing.kind == "answer", existing.text == event.text else {
        throw APIError(code: "voice_turn_conflict", message: "This turn was already used for another answer.", status: 0)
      }
      return
    }
    if let pending, pending.command == event.id.uuidString {
      guard pending.input.text == event.text else {
        throw APIError(code: "voice_turn_conflict", message: "This turn was already used for another answer.", status: 0)
      }
      return // Recovery retains the original command; never send a second request.
    }
    let promptID = state.turns.last(where: { ["answer", "continue"].contains($0.kind) && $0.result != nil })?.id ?? "original"
    guard loaded, !locked, failedTurn == nil, !state.wrapUp, event.promptID == promptID else {
      throw APIError(code: "voice_turn_not_ready", message: "Wait for the current interview turn to finish.", status: 0)
    }
    guard !event.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw APIError(code: "empty_voice_turn", message: "The transcript is empty.", status: 0)
    }
    guard answer.isEmpty || answer == event.text else {
      throw APIError(code: "existing_draft", message: "Share or clear the written draft before starting a voice answer.", status: 0)
    }
    edit(event.text)
    await submit("answer", command: event.id)
    if let failure { throw APIError(code: "voice_submission_pending", message: failure, status: 0) }
  }
  private func persistPending() async throws {
    try await model.disk.cache(key: key + ":pending", data: JSONEncoder().encode(pending))
  }
  func recover() async {
    guard let operation = pending, !busy, currentAccount else { return }
    busy = true
    defer { busy = false }
    do {
      if model.fixture {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--fixture-slow-interview") { try await Task.sleep(for: .seconds(6)) }
        #endif
        try await Task.sleep(for: .milliseconds(500))
        let input = operation.input
        state.style = input.style ?? state.style
        if !state.turns.contains(where: { $0.id == operation.command }) {
          let isAnswer = ["answer", "continue"].contains(input.kind)
          let result = InterviewResponse(outcome: isAnswer ? "follow_up" : "reply", text: isAnswer ? "What happens if a worker stops after completing the operation but before acknowledging it?" : "Consider what a retry can know about an operation that already happened.")
          do {
            state.turns.append(InterviewTurn(id: operation.command, ordinal: state.turns.count, kind: input.kind, prompt: state.prompt, text: input.text, createdAt: Date().ISO8601Format(), jobId: operation.command, status: "running"))
            outgoing = nil
            let words = result.text.split(separator: " ")
            for count in stride(from: 3, through: words.count, by: 3) {
              state.turns[state.turns.count - 1].partial = words.prefix(count).joined(separator: " ")
              try await Task.sleep(for: .milliseconds(ProcessInfo.processInfo.arguments.contains("--fixture-slow-interview") ? 400 : 100))
            }
            state.turns.removeLast()
          }
          state.turns.append(InterviewTurn(id: operation.command, ordinal: state.turns.count, kind: input.kind, prompt: state.prompt, text: input.text, createdAt: Date().ISO8601Format(), jobId: operation.command, status: "completed", result: result))
          if isAnswer { state.wrapUp = result.outcome == "wrap_up"; if !state.wrapUp { state.prompt = result.text } }
          if input.kind == "answer" { answer = "" }
          try await model.save(challenge, answer: answer)
          try await model.disk.cache(key: key + ":state", data: JSONEncoder().encode(state))
          guard currentAccount else { throw CancellationError() }
          challenge.interview = state
          model.bootstrap?.challenge = challenge
        }
      } else {
        let path = "challenges/" + challenge.id + "/interview" + (operation.retryTurn.map { "/" + $0 + "/retry" } ?? "")
        let response: InterviewState = try await model.api.send(path, method: "POST", body: operation.input, command: operation.command)
        guard currentAccount else { throw CancellationError() }
        if let turn = response.turns.last { recordFirstText(turn.result?.text ?? turn.partial ?? "") }
        state = response
        let fresh: Challenge = try await model.api.send("challenges/" + challenge.id)
        guard currentAccount else { throw CancellationError() }
        challenge = fresh
        if let latest = fresh.interview { state = latest }
        if operation.input.saveDraft == true, let revision = fresh.session?.revision {
          try await model.disk.acknowledgeInterviewAnswer(account: account, id: challenge.id, text: operation.input.text, revision: revision)
        }
        let local = try await model.disk.load(account: account, challenge: fresh)
        guard currentAccount else { throw CancellationError() }
        answer = local.answer
        model.bootstrap?.challenge = fresh
      }
      pending = nil
      outgoing = nil
      try await persistPending()
      failure = nil
    } catch let error as APIError where [400,409,422,429].contains(error.status) {
      outgoing = nil
      pending = nil
      try? await persistPending()
      failure = error.localizedDescription
      if error.code == "revision_conflict", currentAccount {
        try? await model.disk.markConflict(account: account, id: challenge.id)
        model.conflict = try? await model.api.send("challenges/" + challenge.id)
      }
    } catch { failure = error.localizedDescription }
  }
  func retry() async {
    if pending != nil { await recover(); return }
    if waiting { streamEpoch += 1; failure = nil; await refresh(); return }
    if let submission = retrySubmission { await submit(submission.kind, text: submission.text, command: submission.command); return }
    guard let turn = failedTurn, !busy else { await refresh(); return }
    pending = PendingInterviewCommand(command: UUID().uuidString, input: InterviewInput(kind: turn.kind, revision: challenge.session?.revision ?? 0), retryTurn: turn.id)
    do { try await persistPending(); await recover() } catch { failure = error.localizedDescription }
  }
  func finish() async {
    guard canFinish else { return }
    busy = true
    saveTask?.cancel()
    defer { busy = false }
    do {
      try await flush()
      challenge.interview = state
      finished = try await model.finish(challenge, answer: answer)
    } catch { failure = error.localizedDescription }
  }
}

/// The original prompt is one persistent text view. Only its allocated height
/// changes, so neither its first line nor its preview is replaced mid-animation.
private struct InterviewDisclosureText: View {
  let text: String
  let expanded: Bool
  let identifier: String
  var previewLines = 3
  var dimsPreview = true
  var onOverflowChange: (Bool) -> Void = { _ in }
  @State private var fullHeight: CGFloat?
  @State private var previewHeight: CGFloat?
  var body: some View {
    Text(text)
      .font(.body)
      .foregroundStyle(expanded || !dimsPreview ? Color.primary : Color.secondary)
      .lineLimit(!expanded && previewHeight == nil ? previewLines : nil)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
      .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
      .overlay(alignment: .topLeading) {
        Text(text).font(.body).lineLimit(previewLines)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
          .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { previewHeight = $0 }
          .hidden().accessibilityHidden(true)
      }
      .frame(height: expanded ? fullHeight : previewHeight, alignment: .top)
      .clipped()
      .textSelection(.enabled)
      .accessibilityIdentifier(identifier)
      .onChange(of: fullHeight) { _, _ in reportOverflow() }
      .onChange(of: previewHeight) { _, _ in reportOverflow() }
  }
  private func reportOverflow() {
    guard let fullHeight, let previewHeight else { return }
    onOverflowChange(fullHeight > previewHeight + 0.5)
  }
}

/// Disclosure feedback belongs to the chevron, not a fade of the reading content.
private struct InterviewDisclosureButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
  }
}

/// Labels stay opaque but inherit document placement animation with their rows.
private struct InterviewRowLabel: View {
  let text: String
  var body: some View {
    Text(text)
      .font(.subheadline.weight(.medium))
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .transition(.identity)
  }
}

/// Measure the actual SwiftUI text at the current width and Dynamic Type size.
/// Short turns remain plain text; a longer turn gets a 44-point disclosure target.
private struct InterviewTurnRow: View {
  let title: String
  let text: String
  let expanded: Bool
  let identifier: String
  let textIdentifier: String
  let toggle: () -> Void
  @State private var overflows = false
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      InterviewRowLabel(text: title)
      InterviewDisclosureText(text: text, expanded: expanded,
        identifier: textIdentifier, previewLines: 1, dimsPreview: false,
        onOverflowChange: { overflows = $0 })
    }
    .padding(.trailing, 36)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(alignment: .topTrailing) {
      if overflows {
        Button(action: toggle) {
          Image(systemName: expanded ? "chevron.down" : "chevron.right")
            .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            .frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain)
          .accessibilityLabel(title + ". " + text)
          .accessibilityValue(expanded ? "Expanded" : "Collapsed")
          .accessibilityIdentifier(identifier)
      }
    }
  }
}

private enum InterviewSheet: String, Identifiable { case ask, style; var id: String { rawValue } }
struct InterviewView: View {
  @State private var liveVoice: LiveVoice?
  @State private var showingVoiceRoom = false
  let model: AppModel
  let challenge: Challenge
  @State private var interview: InterviewController
  @State private var sheet: InterviewSheet?
  @State private var confirmFinish = false
  @State private var confirmSkip = false
  @State private var reading = InterviewReadingState()
  @State private var arrivingAnswerID: String?
  @State private var stagingAnswer = false
  @State private var submittedQuestionID: String?
  @State private var position = ScrollPosition(y: 0)
  @State private var readingLoaded = false
  @State private var sessionRestored = false
  @State private var persistenceTask: Task<Void, Never>?
  @State private var viewportHeight: CGFloat = 0
  @State private var activeFrame = CGRect.zero
  @State private var followingLiveEnd = true
  @State private var userScrolling = false
  @State private var editorFrame = CGRect.zero
  @State private var footerFrame = CGRect.zero
  @State private var scrollFrame = CGRect.zero
  @State private var topInset: CGFloat = 0
  @State private var lastCaret: CGRect?
  @State private var focused = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var phase
  init(model: AppModel, challenge: Challenge) {
    self.model = model; self.challenge = challenge
    _interview = State(initialValue: InterviewController(model: model, challenge: challenge))
  }
  private var exchanges: [InterviewExchange] { InterviewExchange.document(original: challenge.prompt, state: interview.displayState) }
  private var activeID: String { exchanges.last?.id ?? "original" }
  private var acceptedPending: Bool { interview.pending.map { pending in pending.input.kind == "answer" && interview.state.turns.contains { $0.id == pending.command } } ?? false }
  private var waitingForAnswer: Bool { interview.displayState.turns.contains { ["answer", "continue"].contains($0.kind) && $0.pending } }
  private var documentMotion: Animation? { reduceMotion || !sessionRestored || stagingAnswer ? nil : .smooth(duration: 0.3, extraBounce: 0) }
  private var disclosureMotion: Animation? { documentMotion }
  private var showsDraft: Bool { interview.loaded && !waitingForAnswer && interview.outgoing == nil && !interview.state.wrapUp && exchanges.last?.hasAnswer == false && !acceptedPending }
  var body: some View {
    ZStack {
      if let finished = interview.finished { ReflectionView(model: model, initial: finished) }
      else if showingVoiceRoom, let voice = liveVoice {
        InterviewVoiceRoom(voice: voice, interview: interview, question: { originalQuestion }, leave: leaveVoiceRoom)
          .transition(reduceMotion ? .opacity : .scale(scale: 0.96, anchor: .bottomLeading).combined(with: .opacity))
      } else { workspace.transition(.opacity) }
    }
    .animation(reduceMotion ? .easeOut(duration: 0.18) : .smooth(duration: 0.3, extraBounce: 0), value: showingVoiceRoom)
    .task {
      guard !readingLoaded else { return }
      // Restore disclosure choices before exposing interactive content. Loading
      // them after the network refresh could overwrite a user's fresh tap.
      if let data = try? await model.disk.cached(key: interview.key + ":reading"),
         let saved = try? JSONDecoder().decode(InterviewReadingState.self, from: data) { reading = saved; followingLiveEnd = false }
      readingLoaded = true
      await Task.yield()
      position.scrollTo(y: reading.offset)
      await interview.load()
      let voice = LiveVoice(interview: interview)
      liveVoice = voice
      interview.voice = voice
      await voice.restore()
      sessionRestored = true
    }
    .task(id: "\(interview.streamTurn?.jobId ?? ""):\(interview.streamEpoch):\(phase == .active)") {
      if phase == .active { await interview.watchResponse() }
    }
    .onChange(of: phase) { _, value in
      if value != .active { interview.acceptsVoiceInput = false; interview.voice?.interrupt("Voice stopped while the app was inactive.") }
      if value == .background { persistReading(); Task { if !interview.locked { try? await interview.flush() } } }
      if value == .active { interview.acceptsVoiceInput = true; Task { await interview.refresh() } }
    }
    .onAppear { interview.acceptsVoiceInput = phase == .active }
    .onDisappear { interview.acceptsVoiceInput = false; interview.voice?.interrupt("Voice ended."); persistReading() }
  }
  private var workspace: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        ForEach(exchanges) { exchange in
          VStack(alignment: .leading, spacing: 12) {
            exchangeContent(exchange)
            if exchange.id == activeID {
              if showsDraft {
                VStack(alignment: .leading, spacing: 12) {
                  Divider().accessibilityIdentifier("answerDivider")
                  InterviewRowLabel(text: "Your answer")
                  GrowingInterviewEditor(text: Binding(get: { interview.answer }, set: { interview.edit($0) }),
                    focused: Binding(get: { focused }, set: { focused = $0 }),
                    enabled: !interview.locked && interview.failedTurn == nil && interview.voice?.blocksText != true,
                    revealCaret: revealCaret)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { editorFrame = $0 }
                    .overlay(alignment: .topLeading) {
                      if interview.answer.isEmpty { Text("Talk through your approach…").foregroundStyle(.tertiary).padding(.top, 8).allowsHitTesting(false).accessibilityHidden(true) }
                    }
                }.id("draft").transition(.identity)
              }
              if let failure = interview.failure, interview.failedTurn == nil {
                recovery(failure)
              }
            }
          }
          .id(exchange.id)
          .transition(.identity)
          .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("interviewDocument")) } action: { frame in
            if exchange.id == activeID { activeFrame = frame }
          }
          if exchange.id != activeID { Divider() }
        }
      }.padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 24).frame(maxWidth: .infinity, alignment: .leading)
        // Animate structural changes together. Typing does not change these keys.
        .animation(documentMotion, value: exchanges.map(\.id))
        .animation(documentMotion, value: showsDraft)
        .animation(documentMotion, value: interview.displayState.turns.map { $0.id + ($0.result == nil ? ":pending" : ":ready") })
        .animation(disclosureMotion, value: reading.collapsed)
        .animation(disclosureMotion, value: reading.expandedAnswers)
        // Streamed line growth moves subsequent rows without replaying text fades.
        .animation(reduceMotion || !sessionRestored ? nil : .easeOut(duration: 0.18), value: exchanges.last?.prompt)
        .animation(reduceMotion ? nil : .easeOut(duration:0.18), value: interview.state.turns.last?.voice?.count)
        .scrollTargetLayout()
        .opacity(readingLoaded ? 1 : 0)
        .allowsHitTesting(readingLoaded)
        .accessibilityHidden(!readingLoaded)
    }
    .accessibilityIdentifier("interviewDocument")
    .coordinateSpace(name: "interviewDocument")
    .scrollPosition($position)
    .scrollDismissesKeyboard(.interactively)
    .onScrollPhaseChange { _, value in userScrolling = value == .interacting || value == .decelerating }
    .onScrollGeometryChange(for: Bool.self) { $0.visibleRect.maxY >= $0.contentSize.height - 80 } action: { _, atEnd in
      if userScrolling { followingLiveEnd = atEnd }
    }
    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { scrollFrame = $0; viewportHeight = $0.height }
    .onScrollGeometryChange(for: CGFloat.self) { $0.contentInsets.top } action: { _, value in topInset = value }
    .onScrollGeometryChange(for: Double.self) { Double(max(0, $0.contentOffset.y + $0.contentInsets.top)) } action: { _, offset in
      guard readingLoaded else { return }
      reading.offset = offset
      persistenceTask?.cancel()
      persistenceTask = Task {
        do { try await Task.sleep(for: .milliseconds(400)); persistReading() } catch {}
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) { footer }
    .navigationTitle(challenge.scenario?.split(whereSeparator: \.isWhitespace).prefix(2).joined(separator: " ") ?? "System design").navigationBarTitleDisplayMode(.inline)
    .task(id: activeID) {
      guard sessionRestored, followingLiveEnd, sheet == nil, phase == .active else { return }
      // Let the keyboard and document settle before revealing the new block.
      // This task cancels if its target changes; manual scrolling always wins.
      do { try await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 340)) } catch { return }
      guard !Task.isCancelled, followingLiveEnd, !userScrolling, sheet == nil, phase == .active else { return }
      withAnimation(documentMotion) { position.scrollTo(id: activeID, anchor: .bottom) }
    }
    .onChange(of: model.conflict?.id) { _, value in if value == nil { Task {
      await interview.refresh()
      interview.answer = await model.localAnswer(interview.challenge)
    } } }
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Close") { Task {
          do { persistReading(); if !interview.locked { try await interview.flush() }; model.presented = nil }
          catch { interview.failure = error.localizedDescription }
        } }
      }
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button("Finish interview", systemImage: "checkmark") { focused = false; confirmFinish = true }.disabled(!interview.canFinish)
          if interview.state.wrapUp { Button("Continue interview") { Task { await interview.submit("continue") } } }
          Button("Ask interviewer", systemImage: "bubble.left") { sheet = .ask }.disabled(interview.voice?.blocksText == true)
            .disabled(interview.locked || interview.failedTurn != nil)
          Button("Interview style", systemImage: "slider.horizontal.3") { sheet = .style }.disabled(interview.locked)
          Button("Skip question", systemImage: "forward", role: .destructive) { confirmSkip = true }.disabled(interview.voice?.blocksText == true)
        } label: { Image(systemName: "ellipsis") }
          .accessibilityLabel("Interview options").accessibilityIdentifier("interviewOptions")
      }
    }
    .alert("Skip this question?", isPresented: $confirmSkip) {
      Button("Keep practising", role: .cancel) {}
      Button("Skip question", role: .destructive) { Task { await model.skip(challenge.id, answer: interview.answer) } }
    } message: { Text("End this interview without a review and return to Home.") }
    .alert("Finish interview?", isPresented: $confirmFinish) {
      Button("Keep writing", role: .cancel) {}
      Button("Finish interview") { Task { await interview.finish() } }
    } message: { Text("Your shared answers and current draft will be saved for review.") }
    .sheet(item: $sheet) { selection in
      NavigationStack {
        Group {
          switch selection {
          case .ask: InterviewAskView(interview: interview)
          case .style:
            InterviewStylePicker(selection: Binding(get: { interview.style }, set: { value in Task { await interview.selectStyle(value) } }))
          }
        }.navigationBarTitleDisplayMode(.inline).toolbar { Button("Done") { sheet = nil } }
      }
    }
  }
  private var originalQuestion: some View {
    let collapsed = reading.collapsed.contains("original")
    return VStack(alignment: .leading, spacing: 4) {
        Button {
          followingLiveEnd = false
          if collapsed { reading.collapsed.remove("original") } else { reading.collapsed.insert("original") }
          persistReading()
        } label: {
          HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
              InterviewRowLabel(text: "Original question")
              // Keep the title outside the clipped description.
              Text(challenge.title).font(.headline).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: collapsed ? "chevron.right" : "chevron.down").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
          }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(InterviewDisclosureButtonStyle())
          .accessibilityLabel("Original question. " + challenge.prompt)
          .accessibilityValue(collapsed ? "Collapsed" : "Expanded")
          .accessibilityHint(collapsed ? "Expand exchange" : "Collapse exchange")
          .accessibilityIdentifier("exchange-original")
        InterviewDisclosureText(text: challenge.prompt, expanded: !collapsed,
          identifier: "original" == activeID ? "interviewPrompt" : "earlierPrompt-original")
    }.animation(disclosureMotion, value: reading.collapsed)
  }
  private func leaveVoiceRoom() {
    // Route changes never own audio lifetime. End stops local audio before any
    // network finalization; the shell retains the outbox after returning.
    liveVoice?.stopAudioImmediately()
    Task { await liveVoice?.end() }
    focused = false
    showingVoiceRoom = false
  }
  @ViewBuilder private func exchangeContent(_ exchange: InterviewExchange) -> some View {
    let collapsed = reading.collapsed.contains(exchange.id)
    VStack(alignment: .leading, spacing: 4) {
      // Pair the submitted snapshot with the follow-up it produced, outside the
      // question disclosure so folding the question can never hide the answer.
      if let answer = interview.displayState.turns.first(where: { $0.id == exchange.id && $0.kind == "answer" }) {
        sentAnswer(answer).padding(.bottom, 4)
        if answer.status == "failed" { recovery(answer.error ?? "The response couldn’t load.") }
      }
      if exchange.id == "original" {
        originalQuestion
      } else {
        InterviewTurnRow(title: "Interviewer", text: exchange.prompt, expanded: !collapsed,
          identifier: "exchange-" + exchange.id,
          textIdentifier: exchange.id == activeID ? "interviewPrompt" : "earlierPrompt-" + exchange.id) {
            followingLiveEnd = false
            withAnimation(disclosureMotion) {
              if collapsed { reading.collapsed.remove(exchange.id) } else { reading.collapsed.insert(exchange.id) }
            }
            persistReading()
          }
      }
      ForEach(exchange.turns) { turn in
        // A completed answer and its follow-up live together in the next block.
        if !(turn.kind == "answer" && turn.result?.outcome != "wrap_up") && !(turn.kind == "voice" && (turn.voice ?? []).allSatisfy { $0.text.isEmpty }) {
          VStack(alignment: .leading, spacing: 12) {
            if turn.kind == "answer" {
              Divider()
              sentAnswer(turn)
              if let response = turn.result, response.outcome != "wrap_up" {
                InterviewRowLabel(text: "Interviewer")
                Text(response.text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
              }
            } else if turn.kind == "voice" {
              Divider().accessibilityIdentifier("voiceSessionDivider")
              ForEach(VoiceTranscript.rows(turn.voice ?? [])) { row in
                InterviewTurnRow(title: row.speaker == "user" ? "You" : "Interviewer", text: row.text,
                  expanded: !reading.collapsed.contains("voice-" + row.id), identifier: "voice-row-" + row.id,
                  textIdentifier: "voice-text-" + row.id) {
                    withAnimation(disclosureMotion) {
                      let key = "voice-" + row.id
                      if reading.collapsed.contains(key) { reading.collapsed.remove(key) } else { reading.collapsed.insert(key) }
                    }
                    persistReading()
                  }
              }
            } else if turn.kind != "continue" {
              Text(turn.kind == "example" ? "Example · assisted" : turn.kind == "hint" ? "Nudge" : "Clarification").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
              if !turn.text.isEmpty { Text(turn.text).textSelection(.enabled) }
              Text(turn.result?.text ?? turn.partial ?? "").fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            if turn.status == "failed" { recovery(turn.error ?? "The response couldn’t load.") }
          }
        }
      }
    }
  }
  private func sentAnswer(_ turn: InterviewTurn) -> some View {
    let expanded = reading.expandedAnswers?.contains(turn.id) == true
    return InterviewTurnRow(title: "You", text: turn.text, expanded: expanded,
      identifier: "answer-" + turn.id, textIdentifier: "sentAnswer-" + turn.id) {
        withAnimation(disclosureMotion) {
          var answers = reading.expandedAnswers ?? []
          if expanded { answers.remove(turn.id) } else { answers.insert(turn.id) }
          reading.expandedAnswers = answers
        }
        persistReading()
      }
    .task(id: turn.id) {
      guard turn.id == arrivingAnswerID else { return }
      // Let the submitted snapshot lay out at its full height before compressing.
      // It stays opaque throughout, instead of fading in already collapsed.
      try? await Task.sleep(for: .milliseconds(40))
      guard !Task.isCancelled else { return }
      stagingAnswer = false
      withAnimation(disclosureMotion) {
        reading.expandedAnswers?.remove(turn.id)
        if let submittedQuestionID { reading.collapsed.insert(submittedQuestionID) }
      }
      persistReading()
    }
  }
  private func shareAnswer() async {
    let command = UUID()
    stagingAnswer = true
    submittedQuestionID = activeID
    arrivingAnswerID = command.uuidString
    var answers = reading.expandedAnswers ?? []
    answers.insert(command.uuidString)
    reading.expandedAnswers = answers
    await interview.submit("answer", command: command)
    stagingAnswer = false
  }

  private func recovery(_ message: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(message).font(.footnote).foregroundStyle(.secondary)
      Button("Retry") { Task { await interview.retry() } }.disabled(interview.busy)
    }
  }
  private func persistReading() {
    guard readingLoaded else { return }
    let snapshot = reading
    Task { try? await model.disk.cache(key: interview.key + ":reading", data: JSONEncoder().encode(snapshot)) }
  }
  private var footer: some View {
    VStack(spacing: 8) {
      if let voice = liveVoice, voice.phase == .unavailable {
        HStack {
          Text(voice.message ?? "Voice could not connect.").font(.footnote).foregroundStyle(.secondary)
          Button(voice.blocksText ? "Sync" : "Dismiss") { Task { if voice.blocksText { await voice.retrySync() } else { voice.dismiss() } } }
        }
      }

      HStack(spacing: 16) {
      Button { focused = false; showingVoiceRoom = true; Task { guard showingVoiceRoom else { return }; await liveVoice?.start() } } label: { Image(systemName: "waveform").font(.system(size: 20, weight: .medium)).foregroundStyle(.tertiary)
        .frame(width: 44, height: 44).background(.quaternary, in: RoundedRectangle(cornerRadius: 12)) }
        .buttonStyle(.plain).disabled(liveVoice == nil || interview.locked || interview.voice?.blocksText == true).accessibilityLabel("Live voice").accessibilityIdentifier("liveVoice")
      Spacer(minLength: 0)
        Button {
          focused = false
          followingLiveEnd = true
          if interview.state.wrapUp { confirmFinish = true } else { Task { await shareAnswer() } }
        } label: {
          Image(systemName: interview.state.wrapUp ? "checkmark" : "arrow.up")
            .font(.system(size: 20, weight: .semibold))
            .frame(width: 44, height: 44)
            .background(Color.primary, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(AppPalette.background)
        }.buttonStyle(.plain)
          .accessibilityLabel(interview.state.wrapUp ? "Finish and review" : "Share answer")
          .disabled(interview.voice?.blocksText == true || interview.locked || interview.failedTurn != nil || (!interview.state.wrapUp && interview.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
          .opacity(interview.locked || (!interview.state.wrapUp && interview.answer.isEmpty) ? 0.4 : 1)
          .accessibilityIdentifier("shareAnswer")
      }
    }.padding(16)
      .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { footerFrame = $0; if followingLiveEnd, sheet == nil, let lastCaret { revealCaret(lastCaret) } }
  }
  private func revealCaret(_ caret: CGRect) {
    lastCaret = caret
    guard focused, sheet == nil, !userScrolling, footerFrame != .zero else { return }
    let bottom = editorFrame.minY + caret.maxY
    let top = editorFrame.minY + caret.minY
    let lowerLimit = footerFrame.minY - 12
    let upperLimit = scrollFrame.minY + topInset + 12
    if bottom > lowerLimit { position.scrollTo(y: max(0, reading.offset + bottom - lowerLimit)) }
    else if top < upperLimit { position.scrollTo(y: max(0, reading.offset + top - upperLimit)) }
  }
}

/// UITextView supplies selection/caret geometry; vertical scrolling belongs exclusively to the document.
private struct GrowingInterviewEditor: UIViewRepresentable {
  @Binding var text: String
  @Binding var focused: Bool
  var enabled: Bool
  var revealCaret: (CGRect) -> Void
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeUIView(context: Context) -> UITextView {
    let view = UITextView()
    view.delegate = context.coordinator
    view.isScrollEnabled = false
    view.backgroundColor = .clear
    view.textColor = .label
    view.font = .preferredFont(forTextStyle: .body)
    view.adjustsFontForContentSizeCategory = true
    view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
    view.textContainer.lineFragmentPadding = 0
    view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    view.accessibilityLabel = "Your answer"
    view.accessibilityIdentifier = "answerEditor"
    return view
  }
  func updateUIView(_ view: UITextView, context: Context) {
    context.coordinator.parent = self
    if view.text != text { view.text = text; view.invalidateIntrinsicContentSize() }
    context.coordinator.reconcileInteraction(view)
  }
  func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
    guard let width = proposal.width, width > 0 else { return nil }
    let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    return CGSize(width: width, height: max((uiView.font?.lineHeight ?? 22) * 6 + 16, size.height))
  }
  @MainActor final class Coordinator: NSObject, UITextViewDelegate {
    var parent: GrowingInterviewEditor
    private var interactionUpdateQueued = false
    init(_ parent: GrowingInterviewEditor) { self.parent = parent }
    func reconcileInteraction(_ textView: UITextView) {
      guard !interactionUpdateQueued else { return }
      interactionUpdateQueued = true
      // Resigning (including isEditable = false) asks the SwiftUI host for its next
      // responder. Doing that inside updateUIView re-enters the active view graph.
      DispatchQueue.main.async { [weak self, weak textView] in
        guard let self else { return }
        self.interactionUpdateQueued = false
        guard let textView else { return }
        if !self.parent.focused && textView.isFirstResponder { textView.resignFirstResponder() }
        if textView.isEditable != self.parent.enabled { textView.isEditable = self.parent.enabled }
      }
    }
    func textViewDidBeginEditing(_ textView: UITextView) { parent.focused = true; reveal(textView) }
    func textViewDidEndEditing(_ textView: UITextView) { parent.focused = false }
    func textViewDidChange(_ textView: UITextView) {
      parent.text = textView.text
      textView.invalidateIntrinsicContentSize()
      reveal(textView)
    }
    func textViewDidChangeSelection(_ textView: UITextView) { if textView.isFirstResponder { reveal(textView) } }
    private func reveal(_ textView: UITextView) {
      // Wait for the growing view to be measured before locating the caret in the document.
      DispatchQueue.main.async { [weak self, weak textView] in
        guard let self, let textView, textView.isFirstResponder, let selection = textView.selectedTextRange else { return }
        self.parent.revealCaret(textView.caretRect(for: selection.end))
      }
    }
  }
}
/// Presentation only: the interview shell owns the connection and pending receipts.
private struct InterviewVoiceRoom<Question: View>: View {
  let voice: LiveVoice
  let interview: InterviewController
  @ViewBuilder var question: () -> Question
  var leave: () -> Void
  @State private var selection = "Question"
  var body: some View {
    VStack(spacing: 0) {
      Picker("Voice view", selection: $selection) {
        Text("Question").tag("Question")
        Text("Conversation").tag("Conversation")
      }.pickerStyle(.segmented).padding(.horizontal, 24).padding(.vertical, 12)
      // Both positions survive selector changes, with only the selected content
      // exposed to interaction and accessibility. No session-start view tasks.
      ZStack {
        ScrollView { question().padding(24).frame(maxWidth: .infinity, alignment: .leading) }
          .opacity(selection == "Question" ? 1 : 0)
          .allowsHitTesting(selection == "Question").accessibilityHidden(selection != "Question")
        InterviewConversation(state: interview.displayState)
          .opacity(selection == "Conversation" ? 1 : 0)
          .allowsHitTesting(selection == "Conversation").accessibilityHidden(selection != "Conversation")
      }
    }
    .background(AppPalette.background)
    .safeAreaInset(edge: .bottom, spacing: 0) { controls }
    .navigationTitle(interview.challenge.scenario?.split(whereSeparator: \.isWhitespace).prefix(2).joined(separator: " ") ?? "Voice interview")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Back", systemImage: "chevron.left", action: leave).accessibilityLabel("Back to writing; end voice") } }
  }
  private var status: String {
    switch voice.phase {
    case .idle: "Voice ended"
    case .connecting: "Connecting…"
    case .active: voice.muted ? "Microphone muted" : "Microphone on"
    case .ending: "Voice ended · saving conversation"
    case .unavailable: "Voice unavailable"
    }
  }
  private var controls: some View {
    VStack(spacing: 12) {
      Text(status).font(.subheadline).foregroundStyle(.secondary)
      if let message = voice.message { Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center) }
      HStack(spacing: 16) {
        if voice.phase == .active {
          Button { voice.toggleMute() } label: {
            Image(systemName: voice.muted ? "mic.slash.fill" : "mic.fill")
              .font(.system(size: 20, weight: .medium)).frame(width: 52, height: 52)
              .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
          }.buttonStyle(.plain).accessibilityLabel(voice.muted ? "Unmute microphone" : "Mute microphone").accessibilityIdentifier("voiceMute")
        }
        if voice.phase == .unavailable {
          Button(voice.blocksText ? "Sync" : "Retry") { Task {
            if voice.blocksText { await voice.retrySync() }
            else { await voice.start() }
          } }.frame(minWidth: 44, minHeight: 52)
        }
        Button(action: leave) {
          Text(voice.phase == .connecting ? "Cancel" : voice.phase == .active ? "End voice" : "Back to writing")
            .font(.body.weight(.medium)).frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.primary, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(AppPalette.background)
        }.buttonStyle(.plain).accessibilityIdentifier("voiceEnd")
      }
      #if DEBUG
      if interview.model.fixture, ProcessInfo.processInfo.arguments.contains("--fixture-voice"), voice.phase == .active {
        Button("Simulate speech") { Task { await voice.fixtureSpeech() } }.font(.system(size: 17)).accessibilityIdentifier("voiceFixtureSpeech")
      }
      #endif
    }.padding(24).background(AppPalette.background)
  }
}

struct InterviewConversation: View {
  var state: InterviewState
  @State private var position = ScrollPosition(edge: .bottom)
  @State private var following = true
  @State private var scrolling = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private var visibleTurns: [InterviewTurn] { state.turns.filter { $0.kind != "voice" || ($0.voice ?? []).contains { !$0.text.isEmpty } } }
  private var contentIdentity: String { state.turns.map { $0.id + String($0.voice?.count ?? 0) + ($0.result?.text ?? $0.partial ?? "") }.joined() }
  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 24) {
        ForEach(visibleTurns) { turn in
          VStack(alignment: .leading, spacing: 8) {
            if turn.kind == "voice" {
              ForEach(VoiceTranscript.rows(turn.voice ?? [])) { row in
                Text(row.speaker == "user" ? "You" : "Interviewer").font(.caption).foregroundStyle(.secondary)
                Text(row.text)
              }
            } else {
            if turn.kind == "answer" { Text(turn.prompt).font(.headline) }
            Text(turn.kind == "answer" ? "You" : "You · " + turn.kind.capitalized).font(.caption).foregroundStyle(.secondary)
            if !turn.text.isEmpty { Text(turn.text) }
            else { Text(turn.kind == "hint" ? "Give me a nudge" : turn.kind == "example" ? "Show an example" : "Keep going") }
            if let result = turn.result { Text("Interviewer").font(.caption).foregroundStyle(.secondary); Text(result.text) }
            else { Text(turn.status == "failed" ? "Response unavailable" : "Response pending").foregroundStyle(.secondary) }
            }
          }
          Divider()
        }
        Color.clear.frame(height: 1).id("voiceLatest")
      }.frame(maxWidth:.infinity,alignment:.leading).padding(24).textSelection(.enabled)
    }
    .scrollPosition($position)
    .onScrollPhaseChange { _, phase in scrolling = phase == .interacting || phase == .decelerating }
    .onScrollGeometryChange(for: Bool.self) { $0.visibleRect.maxY >= $0.contentSize.height - 80 } action: { _, atEnd in
      if scrolling { following = atEnd }
    }
    .onChange(of: contentIdentity) { _, _ in
      guard following, !scrolling else { return }
      withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { position.scrollTo(edge: .bottom) }
    }
    .overlay(alignment: .bottomTrailing) {
      if !following { Button("Latest", systemImage: "arrow.down") { following = true; position.scrollTo(edge: .bottom) }
        .buttonStyle(.bordered).padding(16) }
    }
  }
}
struct InterviewAskView: View {
  @Bindable var interview: InterviewController
  @Environment(\.dismiss) private var dismiss
  @State private var question = ""
  var body: some View {
    Form {
      Section {
        Button("Give me a nudge") { send("hint") }
        Button("Show an example") { send("example") }
      }.disabled(interview.locked || interview.failedTurn != nil)
      Section {
        TextField("What are you stuck on?", text: $question, axis: .vertical)
          .lineLimit(2...5).accessibilityIdentifier("interviewerQuestion")
        Button("Ask question") { send("clarification", text: question.trimmingCharacters(in: .whitespacesAndNewlines)) }
          .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || interview.locked || interview.failedTurn != nil)
      }
      if let error = interview.failure ?? interview.failedTurn?.error {
        Section { Text(error); Button("Retry") { Task { await interview.retry() } } }
      }
    }.navigationTitle("Ask interviewer")
  }
  private func send(_ kind: String, text: String = "") {
    Task {
      // Dismiss only after the command and existing answer are durably saved.
      await interview.submit(kind, text: text, onAccepted: { dismiss() })
    }
  }
}
struct InterviewStylePicker: View {
  @Binding var selection: InterviewStyle
  var body: some View {
    List(InterviewStyle.allCases) { style in
      Button { selection = style } label: {
        HStack(spacing:16) {
          VStack(alignment:.leading,spacing:4) { Text(style.title).foregroundStyle(.primary); Text(style == .standard ? style.explanation : "Coming later").font(.subheadline).foregroundStyle(.secondary) }
          Spacer()
          if style == .standard { Image(systemName:"checkmark").foregroundStyle(.primary) }
        }.padding(.vertical,4)
      }.disabled(style != .standard).opacity(style == .standard ? 1 : 0.4)
        .accessibilityAddTraits(style == .standard ? .isSelected : [])
    }.navigationTitle("Interview style").navigationBarTitleDisplayMode(.inline)
  }
}
