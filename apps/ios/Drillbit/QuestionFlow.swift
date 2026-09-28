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
  private var previewNote: String? {
    let guided = (question?.guidanceMode ?? draft?.guidanceMode) == .learnTogether
    guard guided, failure == nil else { return nil }
    return (question?.isWarmUp ?? draft?.warmUp ?? false) ? "Built from your plan, just to warm up. It won’t count toward your practice." : "Guided practice helps you structure the approach."
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
            StreamedQuestion(
              clock: clock, title: question?.title ?? draft?.title ?? "", note: previewNote,
              prompt: question?.displayPrompt ?? draft?.prompt ?? "", finished: question != nil || failure != nil,
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
              Button {
                starting = true
                Task {
                  do {
                    let opened = try await model.openForPreview(question)
                    if visible, scenePhase == .active, account == model.bootstrap?.account.id { onStart(opened); dismiss() }
                  } catch { failure = error.localizedDescription }
                  starting = false
                }
              } label: {
                HStack(spacing: 8) {
                  if starting { ProgressView().controlSize(.small).tint(AppPalette.actionInk).transition(.iconPop) }
                  Text(question.lifecycle == "in_progress" ? "Resume" : question.isWarmUp ? "Start warm-up" : "Start interview")
                }
                .animation(DrillbitMotion.fast, value: starting)
              }.buttonStyle(PracticeButtonStyle()).disabled(starting)
                .accessibilityLabel(question.lifecycle == "in_progress" ? "Resume" : question.isWarmUp ? "Start warm-up" : "Start interview")
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

/// Paces revealed glyphs so bursty network text reads as steady writing, and runs it backwards to stream out.
@MainActor final class RevealClock {
  private(set) var cursor = 0.0
  private var last: Date?
  private var start = Date.distantPast
  private var rewindRate: Double?
  private var reported = false
  var rewinding: Bool { rewindRate != nil }
  func reset(after delay: TimeInterval) {
    cursor = 0; last = nil; start = .now + delay; rewindRate = nil; reported = false
  }
  func rewind(over duration: TimeInterval) {
    rewindRate = max(cursor, 1) / duration; reported = false
  }
  /// `report` fires once, when the page is fully written or fully streamed out.
  func tick(_ now: Date, target: Double, instant: Bool, finished: Bool, report: () -> Void) -> Double {
    let elapsed = last.map { min(max(now.timeIntervalSince($0), 0), 1.0 / 20) } ?? 0
    last = now
    if let rewindRate {
      cursor = instant ? 0 : max(0, cursor - rewindRate * elapsed)
      if cursor == 0, !reported { reported = true; report() }
      return cursor
    }
    if instant { cursor = target }
    else if now >= start, cursor < target {
      // A steady hand that speeds up with the backlog, so a burst never trails by much more than a second.
      cursor = min(target, cursor + max(48, (target - cursor) / 0.9) * elapsed)
    }
    if finished, cursor >= target, !reported { reported = true; report() }
    return cursor
  }
}

/// Draws glyphs up to `shown`; the leading edge rises out of a slight blur. The caret trails the last visible glyph.
private struct RevealRenderer: TextRenderer {
  var shown: Double
  var caret: Double
  var caretColor: Color
  var motion: Bool
  static let edge = 8.0

  func draw(layout: Text.Layout, in context: inout GraphicsContext) {
    var index = 0.0
    var tail: CGRect?
    lines: for line in layout {
      let count = Double(line.reduce(0) { $0 + $1.count })
      if index + count + Self.edge <= shown {
        context.draw(line)
        index += count
        tail = line.typographicBounds.rect
        continue
      }
      for run in line {
        for glyph in run {
          let progress = (shown - index) / Self.edge
          guard progress > 0 else { break lines }
          index += 1
          tail = glyph.typographicBounds.rect
          if progress >= 1 { context.draw(glyph); continue }
          let eased = progress * progress * (3 - 2 * progress)
          var glyphContext = context
          glyphContext.opacity = eased
          if motion {
            glyphContext.translateBy(x: 0, y: (1 - eased) * 3)
            glyphContext.addFilter(.blur(radius: (1 - eased) * 2.5))
          }
          glyphContext.draw(glyph)
        }
      }
    }
    guard caret > 0, let first = layout.first?.typographicBounds.rect else { return }
    let bounds = tail ?? CGRect(x: first.minX, y: first.minY, width: 0, height: first.height)
    var caretContext = context
    caretContext.opacity = caret
    caretContext.fill(
      Path(roundedRect: CGRect(x: bounds.maxX + 2, y: bounds.minY + bounds.height * 0.12, width: 2, height: bounds.height * 0.76), cornerRadius: 1),
      with: .color(caretColor))
  }
}

/// The preview page, written out glyph by glyph. Fixed copy is written too, so the page reads as one voice.
private struct StreamedQuestion: View {
  let clock: RevealClock
  let title: String
  let note: String?
  let prompt: String
  let finished: Bool
  let paused: Bool
  let instant: Bool
  let settled: () -> Void
  @State private var slow = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private static let eyebrow = "The scenario".uppercased()
  private static let gap = 8.0

  var body: some View {
    let eyebrowLength = Double(Self.eyebrow.count), titleLength = Double(title.count)
    let noteLength = Double(note?.count ?? 0), promptLength = Double(prompt.count)
    let titleStart = eyebrowLength + Self.gap
    let noteStart = titleStart + titleLength + Self.gap
    let promptStart = noteStart + (note == nil ? 0 : noteLength + Self.gap)
    // The title is complete once the prompt has started; structured output writes them in that order.
    let titleDone = finished || !prompt.isEmpty
    let target = titleDone ? promptStart + promptLength + (finished ? RevealRenderer.edge : 0) : titleStart + titleLength
    TimelineView(.animation(paused: paused)) { timeline in
      let cursor = clock.tick(timeline.date, target: target, instant: instant || reduceMotion, finished: finished) {
        Task { @MainActor in settled() }
      }
      let caughtUp = cursor >= target - 0.01
      let pulse = 0.5 + 0.5 * cos(timeline.date.timeIntervalSinceReferenceDate * 2 * .pi / 1.1)
      let caret = clock.rewinding || instant || reduceMotion ? 0
        : finished ? max(0, min(1, (target - cursor) / RevealRenderer.edge))
        : caughtUp ? 0.3 + 0.7 * pulse : 1
      let caretAt = cursor < noteStart || !titleDone ? 1 : cursor < promptStart && note != nil ? 2 : 3
      VStack(alignment: .leading, spacing: 16) {
        Text(Self.eyebrow)
          .font(.caption2.weight(.semibold).monospaced()).tracking(1.2).foregroundStyle(AppPalette.accent)
          .textRenderer(renderer(cursor, caret: 0))
        Text(title.isEmpty ? " " : title)
          .font(.largeTitle.weight(.semibold)).tracking(-0.8)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
          .textRenderer(renderer(title.isEmpty ? 0 : cursor - titleStart, caret: caretAt == 1 ? caret : 0))
          .accessibilityHidden(title.isEmpty)
        if slow && title.isEmpty && !finished {
          Text("Writing your question…").font(.footnote).foregroundStyle(.secondary)
            .transition(.opacity)
        }
        if let note {
          Text(note).font(.subheadline).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .textRenderer(renderer(cursor - noteStart, caret: caretAt == 2 ? caret : 0))
            .accessibilityHidden(cursor <= noteStart)
        }
        if !prompt.isEmpty {
          Text(prompt)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textRenderer(renderer(cursor - promptStart, caret: caretAt == 3 ? caret : 0))
            .textSelection(.enabled).accessibilityIdentifier("previewPrompt")
        }
      }
    }
    .animation(DrillbitMotion.reveal, value: slow && title.isEmpty && !finished)
    .task(id: title.isEmpty && !finished) {
      slow = false
      guard title.isEmpty, !finished else { return }
      // Only mention the wait if it is noticeable.
      do { try await Task.sleep(for: .seconds(1.6)) } catch { return }
      slow = true
    }
  }

  private func renderer(_ shown: Double, caret: Double) -> RevealRenderer {
    RevealRenderer(shown: paused ? .infinity : shown, caret: caret, caretColor: AppPalette.accent, motion: !reduceMotion)
  }
}
