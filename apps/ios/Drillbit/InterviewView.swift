import AVFAudio
import SwiftUI
import UIKit

private enum InterviewSheet: String, Identifiable { case style, assistance; var id: String { rawValue } }
struct InterviewView: View {
  @State private var liveVoice: LiveVoice?
  @State private var showingVoiceRoom = false
  @State private var voiceQuestionCollapsed = true
  @State private var checkingVoice = false
  @State private var voiceExplanation: String?
  @State private var voicePermissionNeedsSettings = false
  @State private var assistanceRequestID: String?
  @State private var assistanceTitle = "Help"
  @State private var assistanceText: String?
  @State private var assistanceError: String?
  @State private var requestingAssistance = false
  let model: AppModel
  let challenge: Challenge
  @State private var interview: InterviewController
  @State private var sheet: InterviewSheet?
  @State private var confirmFinish = false
  @State private var confirmSkip = false
  @State private var reading = InterviewReadingState()
  @State private var arrivingAnswerID: String?
  @State private var acceptedAnswerID: String?
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
  /// The warm-up opens locked; the guided tour releases it.
  @State private var guiding: Bool
  @State private var guideStep: WarmUpStep?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var phase
  @State private var menuFrame: CGRect?
  @State private var showingTools = false
  init(model: AppModel, challenge: Challenge) {
    self.model = model; self.challenge = challenge
    _interview = State(initialValue: InterviewController(model: model, challenge: challenge))
    _guiding = State(initialValue: challenge.isWarmUp)
  }
  private var guideKey: String { interview.key + ":guided" }
  private func advanceGuide() {
    if let next = guideStep?.next {
      guideStep = next
      return
    }
    guideStep = nil
    withAnimation(reduceMotion ? nil : DrillbitMotion.page) { guiding = false }
    Task { try? await model.disk.cache(key: guideKey, data: Data()) }
  }
  private var exchanges: [InterviewExchange] { InterviewExchange.document(original: challenge.displayPrompt, state: interview.displayState) }
  private var activeID: String { exchanges.last?.id ?? "original" }
  private var completedAssistance: String? {
    guard let assistanceRequestID else { return nil }
    return interview.state.turns.first(where: { $0.id == assistanceRequestID })?.result?.text
  }
  private var assistanceProgress: String {
    guard let assistanceRequestID,
      let turn = interview.state.turns.first(where: { $0.id == assistanceRequestID })
    else { return "" }
    return turn.result?.text ?? turn.partial ?? ""
  }
  private var acceptedPending: Bool { interview.pending.map { pending in pending.input.kind == "answer" && interview.state.turns.contains { $0.id == pending.command } } ?? false }
  private var waitingForAnswer: Bool { interview.displayState.turns.contains { ["answer", "continue"].contains($0.kind) && $0.pending } }
  private var documentMotion: Animation? { reduceMotion || !sessionRestored || stagingAnswer ? nil : DrillbitMotion.document }
  private var sendMotion: Animation? { reduceMotion || !sessionRestored ? nil : DrillbitMotion.send }
  private var disclosureMotion: Animation? { documentMotion }
  private var showsDraft: Bool { interview.loaded && !waitingForAnswer && interview.outgoing == nil && !interview.state.wrapUp && exchanges.last?.hasAnswer == false && !acceptedPending }
  var body: some View {
    ZStack {
      if let finished = interview.finished { ReflectionView(model: model, initial: finished).transition(.opacity) }
      else if showingVoiceRoom, let voice = liveVoice {
        InterviewVoiceRoom(voice: voice, interview: interview, question: { questionDisclosure(collapsed: voiceQuestionCollapsed) { voiceQuestionCollapsed.toggle() } }, leave: leaveVoiceRoom)
      } else { workspace }
    }
    .overlayPreferenceValue(WarmUpAnchorKey.self) { anchors in
      if guiding && interview.finished == nil { WarmUpGuide(step: guideStep, anchors: anchors, menuFrame: menuFrame, advance: advanceGuide).transition(.opacity) }
    }
    .animation(reduceMotion ? nil : DrillbitMotion.page, value: interview.finished != nil)
    .sensoryFeedback(.impact(weight: .light), trigger: acceptedAnswerID) { _, accepted in accepted != nil }
    .background(AppPalette.background)
    .containerBackground(AppPalette.background, for: .navigation)
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
      voice.prepareIfAllowed()
      sessionRestored = true
      if guiding {
        if (try? await model.disk.cached(key: guideKey)) != nil { guiding = false; return }
        // A moment to take in the screen, then the question opens and the tour starts at the reply box.
        try? await Task.sleep(for: .seconds(1.2))
        withAnimation(disclosureMotion) { _ = reading.collapsed.remove("original") }
        try? await Task.sleep(for: .milliseconds(450))
        withAnimation(documentMotion) { position.scrollTo(id: "draft", anchor: .bottom) }
        guideStep = .reply
      }
    }
    .task(id: "\(interview.streamTurn?.jobId ?? ""):\(interview.streamEpoch):\(phase == .active)") {
      if phase == .active { await interview.watchResponse() }
    }
    .onChange(of: phase) { _, value in
      if value != .active { interview.acceptsVoiceInput = false; interview.voice?.discardPreparation(); interview.voice?.interrupt("Voice stopped while the app was inactive.") }
      if value == .background { persistReading(); Task { if !interview.locked { try? await interview.flush() } } }
      if value == .active { interview.acceptsVoiceInput = true; Task { await interview.refresh() } }
    }
    .alert("Voice", isPresented: Binding(get: { voiceExplanation != nil }, set: { if !$0 { voiceExplanation = nil } })) {
      if voicePermissionNeedsSettings {
        Button("Open Settings") {
          if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
          voiceExplanation = nil
        }
      }
      Button("Done", role: .cancel) { voiceExplanation = nil }
    } message: { Text(voiceExplanation ?? "") }
    .onChange(of: completedAssistance) { _, value in
      guard let value, !value.isEmpty else { return }
      assistanceText = value
      assistanceRequestID = nil
      requestingAssistance = false
    }
    .onChange(of: assistanceProgress) { _, value in
      guard !value.isEmpty else { return }
      assistanceText = value
    }
    .onAppear { interview.acceptsVoiceInput = phase == .active }
    .onDisappear { interview.acceptsVoiceInput = false; interview.voice?.discardPreparation(); interview.voice?.interrupt("Voice ended."); persistReading() }
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
                  InterviewRowLabel(text: "Your reply")
                  GrowingInterviewEditor(text: Binding(get: { interview.answer }, set: { interview.edit($0) }),
                    focused: Binding(get: { focused }, set: { focused = $0 }),
                    accessibilityLabel: "Your reply or question",
                    enabled: !interview.locked && interview.failedTurn == nil && interview.voice?.blocksText != true,
                    revealCaret: revealCaret)
                    .fixedSize(horizontal: false, vertical: true)
                    .warmUpAnchor(.step(.reply))
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { editorFrame = $0 }
                    .overlay(alignment: .topLeading) {
                      if interview.answer.isEmpty { Text("Answer or ask a question…").foregroundStyle(.tertiary).padding(.top, 8).allowsHitTesting(false).accessibilityHidden(true) }
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
        .animation(sendMotion, value: showsDraft)
        .animation(documentMotion, value: interview.displayState.turns.map { $0.id + ($0.result == nil ? ":pending" : ":ready") })
        .animation(disclosureMotion, value: reading.collapsed)
        .animation(disclosureMotion, value: reading.expandedAnswers)
        // Streamed line growth moves subsequent rows without replaying text fades.
        .animation(reduceMotion || !sessionRestored ? nil : DrillbitMotion.stream, value: exchanges.last?.prompt)
        .animation(reduceMotion ? nil : DrillbitMotion.stream, value: interview.state.turns.last?.voice?.count)
        .scrollTargetLayout()
        .opacity(readingLoaded ? 1 : 0)
        .allowsHitTesting(readingLoaded)
        .accessibilityHidden(!readingLoaded)
    }
    .accessibilityIdentifier("interviewDocument")
    .warmUpAnchor(.document)
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
    .toolbarBackground(AppPalette.background, for: .navigationBar)
    .toolbarBackground(.visible, for: .navigationBar)
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
      // The warm-up has no way out but through: no Close, no Skip.
      if !challenge.isWarmUp {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") {
            persistReading()
            model.presented = nil
            Task { if !interview.locked { try? await interview.flush() } }
          }
        }
      }
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          if interview.state.wrapUp { Button("Continue interview") { Task { await interview.submit("continue") } } }
        // The tour's last step opens the tools as a popover the guide can see; the system menu gives no open event.
        if guideStep == .menu || showingTools {
          Button { showingTools = true } label: { Image(systemName: AppIcon.more.rawValue) }
            .accessibilityLabel("Interview options").accessibilityIdentifier("interviewOptions")
            .popover(isPresented: $showingTools, arrowEdge: .top) {
              WarmUpTools(
                nudge: interview.mode == .mockInterview ? nil : { useTool { requestAssistance("hint", title: "Nudge") } },
                example: { useTool { requestAssistance("example", title: "Example") } },
                finish: interview.canFinish ? { useTool { focused = false; confirmFinish = true } } : nil)
                .presentationCompactAdaptation(.popover)
            }
            .onChange(of: showingTools) { _, open in if open, guideStep == .menu { advanceGuide() } }
        } else {
          if interview.mode != .mockInterview {
            Button { requestAssistance("hint", title: "Nudge") } label: { menuLabel("Need a nudge?", "lightbulb", hint: "A hint toward your next step") }
              .disabled(requestingAssistance || interview.locked || interview.failedTurn != nil || liveVoice?.blocksText == true)
          }
          Button { requestAssistance("example", title: "Example") } label: { menuLabel("Show an example", AppIcon.text.rawValue, hint: "How a strong answer could go") }
            .disabled(requestingAssistance || interview.locked || interview.failedTurn != nil || liveVoice?.blocksText == true)
          Button("Session style", systemImage: AppIcon.preferences.rawValue) { sheet = .style }.disabled(interview.locked || liveVoice?.blocksText == true)
          Button { focused = false; confirmFinish = true } label: { menuLabel("Finish interview", AppIcon.checkmark.rawValue, hint: "Wrap up and get your feedback") }
            .disabled(!interview.canFinish)
          if !challenge.isWarmUp {
            Divider()
            Button("Skip question", systemImage: AppIcon.skip.rawValue, role: .destructive) { confirmSkip = true }.disabled(interview.voice?.blocksText == true)
          }
        } label: {
          Image(systemName: AppIcon.more.rawValue)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { menuFrame = $0 }
        }
          .disabled(guiding && guideStep != .menu)
          .accessibilityLabel("Interview options").accessibilityIdentifier("interviewOptions")
      }
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
    .sheet(item: $sheet, onDismiss: resetAssistance) { selection in
      switch selection {
      case .style:
        NavigationStack {
          GuidanceModePicker(
            selection: Binding(get: { interview.mode }, set: { value in Task { await interview.selectMode(value) } }),
            onDismiss: { sheet = nil })
        }
      case .assistance:
        assistancePopup
      }
    }
  }
  private var assistancePopup: some View {
    VStack(alignment: .leading, spacing: 20) {
      Label(assistanceTitle, systemImage: assistanceTitle == "Example" ? AppIcon.text.rawValue : AppIcon.hint.rawValue)
        .font(.headline)
        .labelStyle(AssistanceTitleStyle())
      if let assistanceText {
        ScrollView {
          Text(assistanceText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .frame(maxHeight: 240)
        .transition(.opacity)
      } else if requestingAssistance {
        ProgressView()
          .controlSize(.small)
          .frame(maxWidth: .infinity, minHeight: 44)
          .accessibilityLabel("Preparing \(assistanceTitle.lowercased())")
          .accessibilityIdentifier("assistanceLoading")
      } else {
        Text(assistanceError ?? "That didn’t load. Your reply is unchanged.")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      Button(requestingAssistance ? "Cancel" : "Got it") { dismissAssistance() }
        .buttonStyle(PracticeButtonStyle(secondary: requestingAssistance))
    }
    .animation(reduceMotion ? nil : DrillbitMotion.reveal, value: assistanceText == nil)
    .padding(24)
    .frame(maxWidth: 420)
    .presentationDetents([requestingAssistance ? .height(220) : .height(360)])
    .presentationDragIndicator(.visible)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("assistancePopup")
  }
  private var originalQuestion: some View {
    questionDisclosure(collapsed: reading.collapsed.contains("original")) {
      followingLiveEnd = false
      if reading.collapsed.contains("original") { reading.collapsed.remove("original") } else { reading.collapsed.insert("original") }
      persistReading()
    }
  }
  /// During the warm-up each tool says what it is for.
  @ViewBuilder private func menuLabel(_ title: String, _ symbol: String, hint: String) -> some View {
    Text(title)
    if challenge.isWarmUp { Text(hint) }
    Image(systemName: symbol)
  }
  /// Lets the tools popover finish closing before a sheet or alert takes over.
  private func useTool(_ action: @escaping () -> Void) {
    showingTools = false
    Task {
      try? await Task.sleep(for: .milliseconds(350))
      action()
    }
  }
  private func questionDisclosure(collapsed: Bool, toggle: @escaping () -> Void) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Button(action: toggle) {
          HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
              InterviewRowLabel(text: "Original question")
              // Keep the title outside the clipped description.
              Text(challenge.title).font(.headline).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            DisclosureChevron(expanded: !collapsed)
          }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(InterviewDisclosureButtonStyle())
          .accessibilityLabel("Original question. " + challenge.displayPrompt)
          .accessibilityValue(collapsed ? "Collapsed" : "Expanded")
          .accessibilityHint(collapsed ? "Expand exchange" : "Collapse exchange")
          .accessibilityIdentifier("exchange-original")
        InterviewDisclosureText(text: challenge.displayPrompt, expanded: !collapsed,
          identifier: "original" == activeID ? "interviewPrompt" : "earlierPrompt-original")
    }.animation(disclosureMotion, value: collapsed)
  }
  private func enterVoice() async {
    guard !checkingVoice, let voice = liveVoice, !voice.blocksText else { return }
    checkingVoice = true
    voicePermissionNeedsSettings = false
    defer { checkingVoice = false }
    do {
      var capability = model.bootstrap?.capabilities?.voice
      if model.fixture {
        if ProcessInfo.processInfo.arguments.contains("--fixture-voice-unavailable") {
          voiceExplanation = "Live voice is currently unavailable. You can continue in text."; return
        }
      } else if capability?.isFresh() != true {
        let refreshed: Bootstrap = try await model.api.send("bootstrap")
        guard interview.currentAccount, refreshed.account.id == interview.account else { return }
        capability = refreshed.capabilities?.voice
        model.bootstrap?.capabilities = refreshed.capabilities
      }
      guard interview.currentAccount, phase == .active else { return }
      if let capability, !capability.available {
        voiceExplanation = capability.reason ?? "Live voice is currently unavailable. You can continue in text."; return
      }
      if !model.fixture {
        let allowed = await AVAudioApplication.requestRecordPermission()
        guard interview.currentAccount, phase == .active else { return }
        guard allowed else {
          voicePermissionNeedsSettings = true
          voiceExplanation = "Allow microphone access to use live voice."
          return
        }
        voice.prepareIfAllowed()
      }
      // Older compatible servers may not advertise the field; Start remains authoritative.
      focused = false
      voiceQuestionCollapsed = false
      showingVoiceRoom = true
      voice.dismiss()
    } catch { voiceExplanation = "Voice isn’t reachable right now. Your reply is unchanged." }
  }
  private func requestAssistance(_ kind: String, title: String) {
    guard !requestingAssistance else { return }
    focused = false
    requestingAssistance = true
    assistanceTitle = title
    assistanceText = nil
    assistanceError = nil
    let command = UUID()
    assistanceRequestID = command.uuidString
    sheet = .assistance
    Task {
      await interview.submit(kind, command: command)
      guard assistanceRequestID == command.uuidString else { return }
      if let failure = interview.failure {
        assistanceError = failure
        assistanceRequestID = nil
        requestingAssistance = false
      } else if let completedAssistance {
        assistanceText = completedAssistance
        assistanceRequestID = nil
        requestingAssistance = false
      }
    }
  }
  private func dismissAssistance() {
    if requestingAssistance, let id = assistanceRequestID { interview.cancelAssistance(id) }
    assistanceRequestID = nil
    sheet = nil
  }
  /// Runs after the sheet has gone, so its button never changes label mid-dismissal.
  private func resetAssistance() {
    if requestingAssistance, let id = assistanceRequestID { interview.cancelAssistance(id) }
    assistanceRequestID = nil
    assistanceText = nil
    assistanceError = nil
    requestingAssistance = false
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
      if !collapsed {
        ForEach(exchange.turns.filter { $0.kind == "clarification" }) { turn in
          clarification(turn)
            .transition(.opacity.combined(with: .offset(y: -4)))
        }
      }
      ForEach(exchange.turns) { turn in
        // A completed answer and its follow-up live together in the next block.
        if turn.kind != "clarification" && turn.status != "cancelled" && !(turn.kind == "answer" && turn.result?.outcome != "wrap_up") && !(turn.kind == "voice" && (turn.voice ?? []).allSatisfy { $0.text.isEmpty }) {
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
              Text(turn.kind == "example" ? "Example · assisted" : "Nudge").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
              if !turn.text.isEmpty { Text(turn.text).textSelection(.enabled) }
              Text(turn.result?.text ?? turn.partial ?? "").fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            if turn.status == "failed" { recovery(turn.error ?? "The response couldn’t load.") }
          }
        }
      }
    }
  }
  private func clarification(_ turn: InterviewTurn) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      InterviewRowLabel(text: "Clarification")
      if !turn.text.isEmpty { Text(turn.text).font(.subheadline.weight(.medium)).textSelection(.enabled) }
      if let reply = turn.result?.text ?? turn.partial, !reply.isEmpty {
        Text(reply).font(.subheadline).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
      } else if turn.status != "failed" {
        ProgressView().controlSize(.small).accessibilityLabel("Interviewer is answering")
      }
      if turn.status == "failed" { recovery(turn.error ?? "The response couldn’t load.") }
    }
    .padding(.leading, 16)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(alignment: .leading) { AppPalette.hairline.frame(width: 1) }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("clarification-" + turn.id)
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
    .task(id: turn.id + (acceptedAnswerID == turn.id ? ":accepted" : ":waiting")) {
      guard turn.id == arrivingAnswerID, acceptedAnswerID == turn.id else { return }
      // Let the submitted snapshot lay out at its full height before compressing.
      // It stays opaque throughout, instead of fading in already collapsed.
      try? await Task.sleep(for: .milliseconds(40))
      guard !Task.isCancelled else { return }
      stagingAnswer = false
      withAnimation(disclosureMotion) {
        reading.expandedAnswers?.remove(turn.id)
        reading.collapsed.insert("original")
        if let submittedQuestionID { reading.collapsed.insert(submittedQuestionID) }
        arrivingAnswerID = nil
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
    await interview.submit("answer", command: command, onAccepted: { acceptedAnswerID = command.uuidString })
    stagingAnswer = false
  }
  private func sendMessage() async {
    if InterviewComposerIntent.isQuestion(interview.answer) {
      let question = interview.answer.trimmingCharacters(in: .whitespacesAndNewlines)
      await interview.submit("clarification", text: question)
      if interview.failure == nil { interview.edit("") }
    } else {
      await shareAnswer()
    }
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
          Button(voice.blocksText ? "Try again" : "Dismiss") { Task { if voice.blocksText { await voice.retrySync() } else { voice.dismiss() } } }
        }
      }

      HStack(spacing: 16) {
      Button { Task { await enterVoice() } } label: {
        Image(systemName: AppIcon.voice.rawValue).font(.system(size: 20, weight: .medium))
          .frame(width: 24, height: 24)
      }
        .buttonStyle(DrillbitIconButtonStyle())
        .disabled(checkingVoice || liveVoice == nil || interview.locked || interview.voice?.blocksText == true).accessibilityLabel("Live voice").accessibilityIdentifier("liveVoice")
        .warmUpAnchor(.step(.voice))
      Spacer(minLength: 0)
        Button {
          focused = false
          followingLiveEnd = true
          Task { await sendMessage() }
        } label: {
          Image(systemName: AppIcon.send.rawValue)
            .font(.system(size: 20, weight: .semibold))
            .frame(width: 24, height: 24)
        }.buttonStyle(DrillbitIconButtonStyle(prominent: true))
          .accessibilityLabel("Send")
          .disabled(interview.voice?.blocksText == true || interview.locked || interview.failedTurn != nil || interview.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          .accessibilityIdentifier("shareAnswer")
          .warmUpAnchor(.step(.send))
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
private struct AssistanceTitleStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 8) {
      configuration.icon.foregroundStyle(AppPalette.accent)
      configuration.title
    }
  }
}

struct GuidanceModePicker: View {
  @Binding var selection: GuidanceMode
  var onDismiss: (() -> Void)? = nil
  var body: some View {
    List(GuidanceMode.allCases) { style in
      Button { selection = style; onDismiss?() } label: {
        HStack(spacing:16) {
          VStack(alignment:.leading,spacing:4) { Text(style.title).foregroundStyle(.primary); Text(style.explanation).font(.subheadline).foregroundStyle(.secondary) }
          Spacer()
          if style == selection { Image(systemName:AppIcon.checkmark.rawValue).foregroundStyle(.primary) }
        }.padding(.vertical,4)
      }
        .accessibilityAddTraits(style == selection ? .isSelected : [])
    }
    .navigationTitle("Session style")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if let onDismiss {
        ToolbarItem(placement: .cancellationAction) { Button("Back", action: onDismiss) }
      }
    }
  }
}
