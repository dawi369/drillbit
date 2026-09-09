import SwiftUI

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
  private var editGeneration = 0
  private var savedGeneration = 0
  private var refreshing = false
  private var saveTask: Task<Void, Never>?
  var pending: PendingInterviewCommand?
  var key: String { "interview:" + account + ":" + challenge.id }
  var currentAccount: Bool { model.bootstrap?.account.id == account }
  var waiting: Bool { state.turns.contains(where: \.pending) }
  var failedTurn: InterviewTurn? { state.turns.last(where: { $0.status == "failed" }) }
  var locked: Bool { !loaded || busy || pending != nil || waiting }
  var canFinish: Bool { loaded && !busy && pending == nil && (!answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.turns.contains(where: { $0.kind == "answer" })) }
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
      loaded = true
      if pending != nil { await recover() }
      else { await refresh() }
    } catch { loaded = true; failure = error.localizedDescription }
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
    await model.sync()
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
  func submit(_ kind: String, text: String = "") async {
    guard !locked, failedTurn == nil else { return }
    busy = true
    failure = nil
    saveTask?.cancel()
    do {
      try await flush()
      if !model.fixture {
        guard !model.hasPendingWrites else { throw APIError(code: "sync_pending", message: "Your draft is saved. Connect and sync before sharing.", status: 0) }
        challenge = try await model.api.send("challenges/" + challenge.id)
        guard currentAccount else { throw CancellationError() }
      }
      let local = try await model.disk.load(account: account, challenge: challenge)
      guard model.fixture || (local.kind.isEmpty && !local.conflict) else {
        throw APIError(code: "sync_pending", message: "Your draft is saved. Connect and sync before sharing.", status: 0)
      }
      pending = PendingInterviewCommand(command: UUID().uuidString, input: InterviewInput(promptId: state.turns.last(where: { ["answer","continue"].contains($0.kind) && $0.result != nil })?.id ?? "original", kind: kind, revision: local.revision, text: kind == "answer" ? answer : text))
      try await persistPending()
    } catch { failure = error.localizedDescription; busy = false; return }
    busy = false
    await recover()
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
        try await Task.sleep(for: .milliseconds(500))
        let input = operation.input
        if !state.turns.contains(where: { $0.id == operation.command }) {
          let count = state.turns.filter { $0.kind == "answer" }.count
          let isAnswer = ["answer", "continue"].contains(input.kind)
          let result = InterviewResponse(outcome: isAnswer ? (count > 0 && input.kind != "continue" ? "wrap_up" : "follow_up") : "reply", text: isAnswer ? (count > 0 && input.kind != "continue" ? "We’ve explored your approach and its failure handling. Ready to wrap up?" : "What happens if a worker stops after completing the operation but before acknowledging it?") : "Consider what a retry can know about an operation that already happened.")
          state.turns.append(InterviewTurn(id: operation.command, ordinal: state.turns.count, kind: input.kind, prompt: state.prompt, text: input.text, createdAt: Date().ISO8601Format(), jobId: operation.command, status: "completed", result: result))
          if isAnswer { state.wrapUp = result.outcome == "wrap_up"; if !state.wrapUp { state.prompt = result.text } }
          if input.kind == "answer" { answer = "" }
          try await model.save(challenge, answer: answer)
          try await model.disk.cache(key: key + ":state", data: JSONEncoder().encode(state))
          challenge.interview = state
          model.bootstrap?.challenge = challenge
        }
      } else {
        let path = "challenges/" + challenge.id + "/interview" + (operation.retryTurn.map { "/" + $0 + "/retry" } ?? "")
        let response: InterviewState = try await model.api.send(path, method: "POST", body: operation.input, command: operation.command)
        guard currentAccount else { throw CancellationError() }
        state = response
        let fresh: Challenge = try await model.api.send("challenges/" + challenge.id)
        guard currentAccount else { throw CancellationError() }
        challenge = fresh
        let local = try await model.disk.load(account: account, challenge: fresh)
        answer = local.answer
        model.bootstrap?.challenge = fresh
      }
      pending = nil
      try await persistPending()
      failure = nil
    } catch let error as APIError where [400,409,422,429].contains(error.status) {
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

private enum InterviewSheet: String, Identifiable { case brief, conversation, ask; var id: String { rawValue } }
struct InterviewView: View {
  let model: AppModel
  let challenge: Challenge
  @State private var interview: InterviewController
  @State private var sheet: InterviewSheet?
  @State private var confirmFinish = false
  @State private var confirmSkip = false
  @State private var expanded = true
  @FocusState private var focused: Bool
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.scenePhase) private var phase
  init(model: AppModel, challenge: Challenge) {
    self.model = model; self.challenge = challenge
    _interview = State(initialValue: InterviewController(model: model, challenge: challenge))
  }
  var body: some View {
    Group {
      if let finished = interview.finished { ReflectionView(model: model, initial: finished) }
      else { workspace }
    }
    .preferredColorScheme(model.fixture && ProcessInfo.processInfo.arguments.contains("--dark") ? .dark : nil)
    .task { await interview.load() }
    .task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(3))
        if phase == .active && interview.waiting { await interview.refresh() }
      }
    }
    .onChange(of: phase) { _, value in
      if value == .background { Task { if !interview.locked { try? await interview.flush() } } }
      if value == .active { Task { await interview.refresh() } }
    }
  }
  private var workspace: some View {
    VStack(alignment: .leading, spacing: 12) {
      if interview.state.wrapUp {
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            Text("Ready to wrap up?").font(.title2.weight(.semibold))
            Text("Review your reasoning, or explore one more follow-up.").foregroundStyle(.secondary)
            Button("Conversation", systemImage: "text.bubble") { sheet = .conversation }
          }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
        }.frame(maxHeight: .infinity)
      } else {
      if typeSize.isAccessibilitySize {
        Button("Question") { sheet = .brief }.accessibilityLabel("Read question")
          .font(.subheadline).padding(.horizontal,24)
      } else {
        DisclosureGroup(isExpanded: $expanded) {
          ScrollView { Text(interview.state.prompt).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
            .frame(maxHeight: 180)
        } label: {
          Text(interview.state.turns.contains(where: { $0.kind == "answer" }) ? "Follow-up" : challenge.title).font(.headline).lineLimit(2)
        }.padding(.horizontal,24)
      }
      TextEditor(text: Binding(get: { interview.answer }, set: { interview.edit($0) }))
        .focused($focused).scrollContentBackground(.hidden).padding(.horizontal,16)
        .disabled(interview.locked || interview.failedTurn != nil || interview.state.wrapUp)
        .accessibilityLabel("Your answer").accessibilityIdentifier("answerEditor")
        .overlay(alignment: .topLeading) {
          if interview.answer.isEmpty {
            Text(interview.state.wrapUp ? "" : typeSize.isAccessibilitySize ? "Your answer" : "Talk through your approach…").foregroundStyle(.tertiary)
              .padding(.horizontal,24).padding(.top,8).allowsHitTesting(false)
          }
        }
      }
      if interview.waiting { LoadingStatus("Interviewer is considering your answer…") }
      if let failure = interview.failure ?? interview.failedTurn?.error {
        VStack(alignment: .leading, spacing: 8) {
          Text(failure).font(.footnote).foregroundStyle(.secondary)
          Button("Retry") { Task { await interview.retry() } }.disabled(interview.busy)
        }.padding(.horizontal,24)
      }
      if interview.state.wrapUp {
        VStack(alignment: .leading, spacing: 8) {
          Button("Keep going") { Task { await interview.submit("continue") } }.disabled(interview.locked)
        }.padding(.horizontal,24)
      }
      footer
    }
    .navigationTitle("Interview").navigationBarTitleDisplayMode(.inline)
    .onChange(of: focused) { _, value in if value { expanded = false } }
    .onChange(of: model.conflict?.id) { _, value in if value == nil { Task {
      await interview.refresh()
      interview.answer = await model.localAnswer(interview.challenge)
    } } }
    .onChange(of: interview.state.prompt) { _, _ in expanded = true }
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Close") { Task {
          do { if !interview.locked { try await interview.flush() }; model.presented = nil }
          catch { interview.failure = error.localizedDescription }
        } }
      }
      ToolbarItem(placement: .primaryAction) {
        Button("Finish") { focused = false; confirmFinish = true }.disabled(!interview.canFinish)
      }
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button("Ask interviewer", systemImage: "bubble.left") { sheet = .ask }
            .disabled(interview.locked || interview.failedTurn != nil)
          Button("Conversation", systemImage: "text.bubble") { sheet = .conversation }
            .disabled(interview.state.turns.isEmpty)
          Section("Interview style") {
            Button(interview.state.style.title, systemImage: "checkmark") {}.disabled(true)
          }
          Button("Original question", systemImage: "doc.text") { sheet = .brief }
          Button("Skip question", systemImage: "forward", role: .destructive) { confirmSkip = true }
        } label: { Image(systemName: "ellipsis") }
          .accessibilityLabel("Interview options").accessibilityIdentifier("interviewOptions")
      }
    }
    .confirmationDialog("Skip this question?", isPresented: $confirmSkip, titleVisibility: .visible) {
      Button("Skip question", role: .destructive) { Task { await model.skip(challenge.id) } }
    } message: { Text("End this interview without a review and return to Today.") }
    .alert("Finish interview?", isPresented: $confirmFinish) {
      Button("Keep writing", role: .cancel) {}
      Button("Finish interview") { Task { await interview.finish() } }
    } message: { Text("Your shared answers and current draft will be saved for review.") }
    .sheet(item: $sheet) { selection in
      NavigationStack {
        Group {
          switch selection {
          case .brief:
            ScrollView { VStack(alignment: .leading, spacing: 20) {
              if interview.state.prompt != challenge.prompt { Text("Current question").font(.headline); Text(interview.state.prompt); Divider() }
              Text(challenge.title).font(.title2.weight(.semibold)); Text(challenge.prompt)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(24).textSelection(.enabled) }.navigationTitle("Question")
          case .conversation: InterviewConversation(state: interview.state)
          case .ask: InterviewAskView(interview: interview)
          }
        }.navigationBarTitleDisplayMode(.inline).toolbar { Button("Done") { sheet = nil } }
      }
    }
  }
  private var footer: some View {
    VStack(spacing: 8) {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 12) { voice; Spacer(minLength: 4); share }
        VStack(spacing: 12) { HStack { voice; Spacer() }; share }
      }
      Text(interview.busy ? "Saving…" : typeSize.isAccessibilitySize ? (model.hasPendingWrites ? "Saved locally" : "Saved") : model.saveStatus).font(.caption2).foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }.padding(.horizontal,24).padding(.bottom,12)
  }
  private var voice: some View {
    Button {} label: { Image(systemName: "waveform").font(.system(size:20,weight:.medium)).foregroundStyle(.tertiary)
      .frame(width:44,height:44).background(.quaternary,in: RoundedRectangle(cornerRadius:12)) }
      .buttonStyle(.plain).disabled(true).accessibilityLabel("Live voice").accessibilityValue("In development").accessibilityIdentifier("liveVoice")
  }
  private var share: some View {
    Button(interview.state.wrapUp ? "Finish & review" : "Share answer") {
      focused = false
      if interview.state.wrapUp { confirmFinish = true } else { Task { await interview.submit("answer") } }
    }.font(.subheadline.weight(.semibold)).fixedSize(horizontal:true,vertical:true).padding(.horizontal,12).padding(.vertical,12).frame(minHeight:44)
      .background(Color.primary, in: RoundedRectangle(cornerRadius:12)).foregroundStyle(AppPalette.background)
      .disabled(interview.locked || interview.failedTurn != nil || (!interview.state.wrapUp && interview.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
      .opacity(interview.locked || (!interview.state.wrapUp && interview.answer.isEmpty) ? 0.4 : 1)
      .accessibilityIdentifier("shareAnswer")
  }
}
struct InterviewConversation: View {
  var state: InterviewState
  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 24) {
        ForEach(state.turns) { turn in
          VStack(alignment: .leading, spacing: 8) {
            if turn.kind == "answer" { Text(turn.prompt).font(.headline) }
            Text(turn.kind == "answer" ? "You" : "You · " + turn.kind.capitalized).font(.caption).foregroundStyle(.secondary)
            if !turn.text.isEmpty { Text(turn.text) }
            else { Text(turn.kind == "hint" ? "Give me a nudge" : turn.kind == "example" ? "Show an example" : "Keep going") }
            if let result = turn.result { Text("Interviewer").font(.caption).foregroundStyle(.secondary); Text(result.text) }
            else { Text(turn.status == "failed" ? "Response unavailable" : "Response pending").foregroundStyle(.secondary) }
          }
          Divider()
        }
      }.frame(maxWidth:.infinity,alignment:.leading).padding(24).textSelection(.enabled)
    }.navigationTitle("Conversation")
  }
}
struct InterviewAskView: View {
  @Bindable var interview: InterviewController
  @State private var question = ""
  var body: some View {
    Form {
      Section {
        TextField("What would you like to clarify?", text: $question, axis: .vertical).lineLimit(2...5).accessibilityIdentifier("interviewerQuestion")
        Button("Ask question") { let text = question; Task { await interview.submit("clarification", text: text); if interview.pending == nil { question = "" } } }
          .disabled(question.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || interview.locked || interview.failedTurn != nil)
      }
      Section {
        Button("Give me a nudge") { Task { await interview.submit("hint") } }
        Button("Show an example") { Task { await interview.submit("example") } }
      }.disabled(interview.locked || interview.failedTurn != nil)
      if interview.waiting || interview.busy { Section { LoadingStatus("Waiting for interviewer…") } }
      if let error = interview.failure ?? interview.failedTurn?.error { Section { Text(error); Button("Retry") { Task { await interview.retry() } } } }
      ForEach(interview.state.turns.filter { !["answer","continue"].contains($0.kind) }.reversed()) { turn in
        if let response = turn.result { Section(turn.kind == "example" ? "Example · assisted" : "Interviewer") { Text(response.text).textSelection(.enabled) } }
      }
    }.navigationTitle("Ask interviewer")
  }
}
struct InterviewStylePicker: View {
  @Binding var selection: InterviewStyle
  var body: some View {
    List(InterviewStyle.allCases) { style in
      Button { selection = style } label: {
        HStack(spacing:16) {
          VStack(alignment:.leading,spacing:4) { Text(style.title).foregroundStyle(.primary); Text(style.explanation).font(.subheadline).foregroundStyle(.secondary) }
          Spacer()
          if selection == style { Image(systemName:"checkmark").foregroundStyle(.primary) }
        }.padding(.vertical,4)
      }.accessibilityAddTraits(selection == style ? .isSelected : [])
    }.navigationTitle("Interview style").navigationBarTitleDisplayMode(.inline)
  }
}
