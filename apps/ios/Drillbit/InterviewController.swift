import SwiftUI
import OSLog
import AVFAudio
import UIKit

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
  var selectedMode: GuidanceMode?
  var mode: GuidanceMode { selectedMode ?? state.guidanceMode ?? challenge.guidanceMode ?? .coachMe }
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
  private var cancelledAssistance: Set<String> = []
  private var cancellation: Task<Void, Never>?
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
        guard let self, self.currentAccount, !self.cancelledAssistance.contains(turn.id),
          let index = self.state.turns.firstIndex(where: { $0.id == turn.id && $0.jobId == turn.jobId }) else { return }
        self.recordFirstText(snapshot.text)
        self.state.turns[index].partial = snapshot.text
      }
      while busy || refreshing { try await Task.sleep(for: .milliseconds(20)) }
      try Task.checkCancellation()
      await refresh()
    } catch is CancellationError {} catch {
      guard !Task.isCancelled, currentAccount, !cancelledAssistance.contains(turn.id) else { return }
      failure = "The response was interrupted. Your answer is safe."
    }
  }
  /// Stops a nudge or example now: the interview unlocks locally, the server job is
  /// cancelled before the next command is sent, and any late reply is ignored.
  func cancelAssistance(_ id: String) {
    cancelledAssistance.insert(id)
    applyCancellations()
    guard !model.fixture else { return }
    let prior = cancellation
    let path = "challenges/" + challenge.id + "/interview/" + id + "/cancel"
    cancellation = Task { [model] in
      await prior?.value
      let _: InterviewState? = try? await model.api.send(path, method: "POST")
    }
  }
  private func applyCancellations() {
    for index in state.turns.indices where cancelledAssistance.contains(state.turns[index].id) && state.turns[index].pending {
      state.turns[index].status = "cancelled"
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
      if let data = try await model.disk.cached(key: key + ":guidanceMode") {
        selectedMode = try JSONDecoder().decode(GuidanceMode.self, from: data)
      }
      loaded = true
      if pending != nil { await recover() }
      else { await refresh() }
    } catch { loaded = true; failure = error.localizedDescription }
  }
  func selectMode(_ mode: GuidanceMode) async {
    guard !locked, voice?.blocksText != true, currentAccount else { return }
    do {
      try await model.disk.cache(key: key + ":guidanceMode", data: JSONEncoder().encode(mode))
      selectedMode = mode
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
    guard currentAccount, voice?.blocksText != true, !busy, !refreshing, pending == nil, !model.fixture else { return }
    refreshing = true
    defer { refreshing = false }
    let generation = editGeneration
    do {
      let fresh: Challenge = try await model.api.send("challenges/" + challenge.id)
      guard currentAccount, voice?.blocksText != true, !busy, generation == editGeneration, savedGeneration == generation else { return }
      guard (fresh.session?.revision ?? 0) >= (challenge.session?.revision ?? 0) else { return }
      let local = try await model.disk.load(account: account, challenge: fresh)
      guard currentAccount, voice?.blocksText != true, !busy, generation == editGeneration, local.kind.isEmpty, !local.conflict else { return }
      answer = local.answer
      if let interview = fresh.interview { state = interview }
      applyCancellations()
      challenge = fresh
      model.bootstrap?.challenge = fresh
      try await model.disk.cache(key: key + ":state", data: JSONEncoder().encode(state))
      if !fresh.isActive { finished = fresh }
    } catch { if waiting { failure = "The response couldn’t load. Try again." } }
  }
  func submit(_ kind: String, text: String = "", command: UUID? = nil, onAccepted: (() -> Void)? = nil) async {
    guard !locked, failedTurn == nil else { return }
    sentAt = Date()
    busy = true
    // A cancelled nudge must be stopped server-side before the next command is accepted.
    await cancellation?.value
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
        pending = try await model.disk.prepareInterviewAnswer(account: account, id: challenge.id, answer: answer, command: command.uuidString, promptID: promptID, style: style, guidanceMode: mode)
      } else {
        try await flush()
        let local = try await model.disk.load(account: account, challenge: challenge)
        guard model.fixture || (local.kind.isEmpty && !local.conflict) else {
          throw APIError(code: "draft_pending", message: local.conflict ? "Review the draft conflict before continuing." : "This action couldn’t finish. Try again shortly.", status: 0)
        }
        pending = PendingInterviewCommand(command: command.uuidString, input: InterviewInput(promptId: state.turns.last(where: { ["answer","continue"].contains($0.kind) && $0.result != nil })?.id ?? "original", kind: kind, revision: local.revision, text: kind == "answer" ? answer : text, style: style, guidanceMode: mode))
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
        let input = operation.input
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--fixture-slow-interview") { try await Task.sleep(for: .seconds(6)) }
        if ProcessInfo.processInfo.arguments.contains("--fixture-slow-assistance"), ["hint", "example"].contains(input.kind) {
          for _ in 0..<40 where !cancelledAssistance.contains(operation.command) { try await Task.sleep(for: .milliseconds(50)) }
        }
        #endif
        if !cancelledAssistance.contains(operation.command) { try await Task.sleep(for: .milliseconds(500)) }
        state.style = input.style ?? state.style
        state.guidanceMode = input.guidanceMode ?? state.guidanceMode
        if !state.turns.contains(where: { $0.id == operation.command }) {
          let isAnswer = ["answer", "continue"].contains(input.kind)
          let helpText = input.kind == "example"
            ? "For example, give each logical operation a stable key and store its result in the same transaction as the state change."
            : "Consider what a retry can know about an operation that already happened."
          var result = InterviewResponse(outcome: isAnswer ? "follow_up" : "reply", text: isAnswer ? "What happens if a worker stops after completing the operation but before acknowledging it?" : helpText)
          if isAnswer, mode == .learnTogether {
            result.choices = ["Store a done marker per job", "Make the work itself idempotent", "Not sure, show me"]
            result.step = min(state.turns.filter { $0.kind == "answer" }.count, 3)
          }
          do {
            state.turns.append(InterviewTurn(id: operation.command, ordinal: state.turns.count, kind: input.kind, prompt: state.prompt, text: input.text, createdAt: Date().ISO8601Format(), jobId: operation.command, status: "running"))
            outgoing = nil
            let words = result.text.split(separator: " ")
            for count in stride(from: 3, through: words.count, by: 3) {
              if cancelledAssistance.contains(operation.command) { break }
              state.turns[state.turns.count - 1].partial = words.prefix(count).joined(separator: " ")
              try await Task.sleep(for: .milliseconds(ProcessInfo.processInfo.arguments.contains("--fixture-slow-interview") ? 400 : 100))
            }
            state.turns.removeLast()
          }
          if cancelledAssistance.contains(operation.command) {
            state.turns.append(InterviewTurn(id: operation.command, ordinal: state.turns.count, kind: input.kind, prompt: state.prompt, text: input.text, createdAt: Date().ISO8601Format(), jobId: operation.command, status: "cancelled"))
          } else {
            state.turns.append(InterviewTurn(id: operation.command, ordinal: state.turns.count, kind: input.kind, prompt: state.prompt, text: input.text, createdAt: Date().ISO8601Format(), jobId: operation.command, status: "completed", result: result))
            if isAnswer { state.wrapUp = result.outcome == "wrap_up"; if !state.wrapUp { state.prompt = result.text } }
          }
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
        applyCancellations()
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
      // Cancel may have reached the server before this command created its job.
      if cancelledAssistance.contains(operation.command) { cancelAssistance(operation.command) }
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
