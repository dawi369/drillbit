import SwiftUI

struct QuestionFlowEntry: Identifiable {
  let id = UUID()
  var challenge: Challenge? = nil
  var recovery: PreparationInput? = nil
  var source: Challenge? = nil
  var browseTopics = false
  var area: PracticeAreaGroup? = nil
}
struct QuestionFlow: View {
  @Bindable var model: AppModel
  var initial: Challenge? = nil
  var source: Challenge? = nil
  var recovery: PreparationInput? = nil
  var browseTopics = false
  var area: PracticeAreaGroup? = nil
  var onStart: (Challenge) -> Void
  @State private var selectedTopic: PracticeConcept?
  @State private var selectedArea: PracticeAreaGroup?
  @State private var topicSearch = ""
  @State private var customTopic = ""
  @State private var selectedCustomTopic: String?
  @State private var showingPreview = false
  @State private var question: Challenge?
  @State private var draft: QuestionDraft?
  /// Actions arrive only once the whole question has been written out.
  @State private var revealed = false
  @State private var instantReveal = false
  @State private var clock = RevealClock()
  /// While the old question streams out, the new one is written into `held` instead of the page.
  @State private var rewinding = false
  @State private var holding = false
  @State private var heldDraft: QuestionDraft?
  @State private var heldQuestion: Challenge?
  @State private var afterRewind: (() -> Void)?
  @State private var starting = false
  @State private var failure: String?
  @State private var retryInput: PreparationInput?
  @State private var account: String?
  @State private var visible = true
  @State private var initialized = false
  // Warm-up rerolls are capped silently; the button just goes away.
  @State private var rerolls = 0
  private var warmingUp: Bool { model.firstUse.stage == .walkthrough }
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// The warm-up's framing is on the plan page already, so its preview carries no note.
  private var previewNote: String? {
    let guided = (question?.guidanceMode ?? draft?.guidanceMode) == .learnTogether
    let warmUp = question?.isWarmUp ?? draft?.warmUp ?? false
    guard guided, !warmUp, failure == nil else { return nil }
    return "Guided practice helps you structure the approach."
  }
  /// Eyebrow and note are fixed copy but still written out, so the page reads as one voice.
  private var previewSegments: [StreamSegment] {
    var segments = [
      StreamSegment(style: .eyebrow, text: AttributedString("The scenario".uppercased()), fixed: true),
      StreamSegment(style: .title, text: AttributedString(QuestionMarkup.plain(question?.title ?? draft?.title ?? "")), placeholder: true),
    ]
    if let previewNote { segments.append(StreamSegment(style: .note, text: AttributedString(previewNote), fixed: true)) }
    let blocks = QuestionMarkup.blocks(question?.displayPrompt ?? draft?.prompt ?? "", formatted: model.settings.formatsQuestions)
    for (index, block) in blocks.enumerated() {
      switch block {
      case .text(let value):
        let ask = QuestionMarkup.isAsk(index, of: blocks) && (question != nil || String(value.characters).hasSuffix("?"))
        segments.append(StreamSegment(style: ask ? .ask : .body, text: value, identifier: index == 0 ? "previewPrompt" : nil))
      case .bullets(let items):
        segments += items.map { StreamSegment(style: .bullet, text: $0) }
      case .code(let value): segments.append(StreamSegment(style: .code, text: AttributedString(value)))
      }
    }
    return segments
  }
  private func arrival(_ order: Int) -> AnyTransition {
    reduceMotion ? .opacity : .asymmetric(
      insertion: .opacity.combined(with: .offset(y: 12)).animation(DrillbitMotion.entrance.delay(Double(order) * 0.08)),
      removal: .opacity.animation(DrillbitMotion.fast))
  }
  var body: some View {
    NavigationStack {
      if browseTopics && selectedTopic == nil && selectedCustomTopic == nil && model.firstUse.stage != .walkthrough {
        SignalList {
          Section("Core areas") {
            if let selectedArea {
              ForEach(model.taxonomy.filter { selectedArea.concepts.contains($0.id) && (topicSearch.isEmpty || $0.label.localizedCaseInsensitiveContains(topicSearch)) }) { concept in
              Button {
                selectedTopic = concept
                retryInput = PreparationInput(primaryConceptId: concept.id, focus: "System design", kind: "design", difficulty: model.settings.difficulty, engineeringLevel: model.settings.selectedLevel, replaceId: model.bootstrap?.challenge?.lifecycle == "ready" ? model.bootstrap?.challenge?.id : nil)
              } label: {
                HomeTopicRow(concept: concept, coverage: model.libraryCoverage.first(where: { $0.conceptId == concept.id }), loaded: model.libraryCoverageLoaded)
              }.buttonStyle(DrillbitRowButtonStyle())
              }
            } else {
              ForEach(PracticeAreaGroup.all.filter { topicSearch.isEmpty || $0.title.localizedCaseInsensitiveContains(topicSearch) || $0.detail.localizedCaseInsensitiveContains(topicSearch) }) { area in
                Button { selectedArea = area } label: { PracticeAreaGroupRow(area: area) }.buttonStyle(DrillbitRowButtonStyle())
                  .accessibilityIdentifier("browse-area-" + area.id)
              }
            }
          }
          Section("Your own topic") {
            TextField("For example, search ranking", text: $customTopic)
            Button("Continue") { selectedCustomTopic = customTopic.trimmingCharacters(in: .whitespacesAndNewlines) }
              .disabled(customTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        }.searchable(text: $topicSearch, prompt: "Find a core area")
          .navigationTitle(selectedArea?.title ?? "System design").navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              if selectedArea != nil { Button("Back") { selectedArea = nil; topicSearch = "" } }
              else { Button("Close") { dismiss() } }
            }
          }.task { await model.loadTaxonomy() }
      } else if showingPreview {
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            StreamingDocument(
              clock: clock, segments: previewSegments, finished: question != nil || failure != nil,
              paused: (revealed || failure != nil) && !rewinding, instant: instantReveal,
              settled: {
                if rewinding { rewinding = false; afterRewind?(); afterRewind = nil }
                else if question != nil { withAnimation(DrillbitMotion.entrance) { revealed = true } }
              })
            if let failure {
              Text(failure).foregroundStyle(.secondary).transition(.opacity)
              if warmingUp { Button("Try again") { prepare(nil) } }
              else { Button("Back to preparation") { showingPreview = false } }
            }
          }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
          .accessibilityIdentifier("questionPreviewScroll")
        .safeAreaInset(edge: .bottom) {
          VStack(spacing: 12) {
            if let question, revealed {
              let title = question.lifecycle == "in_progress" ? "Resume" : question.isWarmUp ? "Start warm-up" : "Start interview"
              Button {
                guard !starting else { return }
                starting = true
                Task {
                  do {
                    let opened = try await model.openForPreview(question)
                    if visible, scenePhase == .active, account == model.bootstrap?.account.id { onStart(opened); dismiss() }
                  } catch { failure = error.localizedDescription }
                  starting = false
                }
              } label: {
                // The label gives way to the bit turning in place: same size, same colour, no spinner.
                ZStack {
                  Text(title)
                    .opacity(starting ? 0 : 1)
                    .blur(radius: starting && !reduceMotion ? 6 : 0)
                  DrillbitBit(working: starting, height: 22, color: AppPalette.actionInk)
                    .opacity(starting ? 1 : 0)
                    .scaleEffect(starting || reduceMotion ? 1 : 0.4)
                }
                .animation(.spring(duration: 0.3, bounce: 0.2), value: starting)
              }.buttonStyle(PracticeButtonStyle())
                .allowsHitTesting(!starting)
                .accessibilityLabel(starting ? "Opening" : title)
                .accessibilityIdentifier("previewStart")
                .transition(arrival(0))
            }
            if let question, revealed, question.lifecycle == "ready" && (!question.isWarmUp || rerolls < 3) {
              Button("Choose another question") { chooseAnother(question) }
                .disabled(starting)
                .transition(arrival(1))
            }
          }.padding(16).background(AppPalette.background)
        }.navigationTitle("Question preview").navigationBarTitleDisplayMode(.inline)
          .containerBackground(AppPalette.background, for: .navigation)
          .toolbar { if !warmingUp { Button("Close") { dismiss() } } }
      } else {
        PreparationView(model: model, source: source, initialCustomTopic: selectedCustomTopic, submit: { prepare($0) }, recovery: retryInput ?? recovery)
      }
    }.background(AppPalette.background)
      .presentationBackground(AppPalette.background)
      .interactiveDismissDisabled(warmingUp)
      .onAppear {
      visible = true
      guard !initialized else { return }
      initialized = true
      account = model.bootstrap?.account.id
      selectedArea = area
      if let initial { question = initial; showingPreview = true; instantReveal = true; revealed = true }
      else if warmingUp { prepare(nil) }
    }
    .onDisappear { visible = false }
    .onChange(of: scenePhase) { _, phase in if phase == .background { visible = false; dismiss() } }
    .onChange(of: model.bootstrap?.account.id) { _, value in if value != account { dismiss() } }
  }
  /// During onboarding the model turns a nil input into the warm-up request.
  private func prepare(_ input: PreparationInput?) {
    showingPreview = true
    question = nil
    draft = nil
    failure = nil
    revealed = false
    instantReveal = false
    // Waits out the sheet's own arrival before the first letter appears.
    clock.reset(after: 0.35)
    generate(input)
  }
  /// The current question streams out; the next one is already being written and takes the page once it is gone.
  private func chooseAnother(_ current: Challenge) {
    withAnimation(DrillbitMotion.fast) { revealed = false }
    instantReveal = false
    rewinding = true
    clock.rewind(over: 0.5)
    guard current.isWarmUp else {
      afterRewind = { showingPreview = false; question = nil; draft = nil }
      return
    }
    rerolls += 1
    holding = true
    heldDraft = nil
    heldQuestion = nil
    afterRewind = {
      draft = heldDraft
      question = heldQuestion
      holding = false
      instantReveal = false
      clock.reset(after: 0.12)
    }
    generate(nil)
  }
  private func generate(_ input: PreparationInput?) {
    let capturedAccount = model.bootstrap?.account.id
    Task {
      do {
        let result = try await model.generateForPreview(input) { written in
          if holding { heldDraft = written } else { draft = written }
        }
        guard capturedAccount == model.bootstrap?.account.id else { return }
        if holding { heldQuestion = result } else { question = result }
      } catch {
        guard capturedAccount == model.bootstrap?.account.id else { return }
        holding = false
        failure = error.localizedDescription
        model.preparationFailure = error.localizedDescription
        model.failedPreparation = input
        model.failedPreparationSource = source
        retryInput = input
      }
    }
  }
}
