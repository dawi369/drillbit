import SwiftUI

struct CompletionHeading: View {
  var warmUp = false
  var mode: GuidanceMode = .coachMe
  private var copy: (eyebrow: String, title: String) {
    switch mode {
    case .learnTogether: ("Lesson recap", "Here’s what you worked out.")
    case .mockInterview: ("Interview debrief", "Here’s how the round went.")
    case .coachMe: ("Practice complete", "One idea to carry forward.")
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      DrillbitMark(size: 52, arrives: true).padding(.bottom, 4)
      SignalEyebrow(text: warmUp ? "Warm-up done" : copy.eyebrow)
      Text(copy.title)
        .font(.largeTitle.weight(.semibold)).tracking(-0.8)
        .accessibilityAddTraits(.isHeader)
    }
  }
}

/// Guided's ending: the ideas worked through together, then one attempt without help.
struct LessonRecap: View {
  let lesson: Lesson
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if !lesson.learned.isEmpty {
        SignalEyebrow(text: "What you worked out")
        ForEach(lesson.learned, id: \.self) { idea in
          Label {
            Text(idea).fixedSize(horizontal: false, vertical: true)
          } icon: {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(AppPalette.success)
          }
        }
      }
      SignalEyebrow(text: "Try it solo").padding(.top, lesson.learned.isEmpty ? 0 : 8)
      Text(lesson.tryAlone).fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("lessonRecap")
  }
}

/// Mock interview's ending: the verdict first, then how each part of the round landed.
struct DebriefCard: View {
  let debrief: Debrief
  private var verdict: (title: String, symbol: String, color: Color) {
    switch debrief.verdict {
    case .pass: ("You’d pass this round.", "checkmark.seal.fill", AppPalette.success)
    case .borderline: ("Borderline. Could go either way.", "circle.lefthalf.filled", AppPalette.accent)
    case .notYet: ("Not this round, yet.", "arrow.uturn.backward.circle.fill", AppPalette.destructive)
    }
  }
  private static let areas = ["requirements": "Requirements", "design": "Design", "trade_offs": "Trade-offs", "communication": "Communication"]
  private static func rating(_ value: String) -> (String, Color) {
    switch value {
    case "strong": ("Strong", AppPalette.success)
    case "mixed": ("Mixed", AppPalette.accent)
    case "weak": ("Weak", AppPalette.destructive)
    default: ("Not shown", AppPalette.secondary)
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label {
        Text(verdict.title).font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
      } icon: {
        Image(systemName: verdict.symbol).foregroundStyle(verdict.color)
      }
      .accessibilityIdentifier("debriefVerdict")
      Text(debrief.reason).foregroundStyle(AppPalette.secondary).fixedSize(horizontal: false, vertical: true)
      VStack(spacing: 0) {
        ForEach(debrief.signals) { signal in
          let rating = Self.rating(signal.rating)
          HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
              Text(Self.areas[signal.area] ?? signal.area).font(.subheadline.weight(.semibold))
              if !signal.note.isEmpty {
                Text(signal.note).font(.footnote).foregroundStyle(AppPalette.secondary)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
            Spacer(minLength: 8)
            Text(rating.0).font(.footnote.weight(.semibold)).foregroundStyle(rating.1)
          }
          .padding(.vertical, 12)
          .accessibilityElement(children: .combine)
          if signal.id != debrief.signals.last?.id { Divider() }
        }
      }
      .padding(.horizontal, 16)
      .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 12))
      if !debrief.toPass.isEmpty {
        SignalEyebrow(text: "To pass")
        Text(debrief.toPass).fixedSize(horizontal: false, vertical: true)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("debrief")
  }
}
struct ReflectionView: View {
  @State private var waitingForFeedback = true
  @State private var feedbackCheck = 0
  @State private var preparingFollowUp = false
  @State private var startedFollowUp: Challenge?
  @State private var retryingTurn: String?
  @State private var retryFailure: String?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var model: AppModel
  var initial: Challenge
  @State private var current: Challenge?
  private var hasReflection: Bool { (current ?? initial).reflection != nil }
  private var warmUp: Bool { initial.isWarmUp }
  private var mode: GuidanceMode { (current ?? initial).reflection?.guidanceMode ?? (current ?? initial).guidanceMode ?? .coachMe }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        CompletionHeading(warmUp: warmUp, mode: mode)
        AssistanceSummary(challenge: current ?? initial)
        if let reflection = (current ?? initial).reflection {
          Group {
          if let debrief = reflection.debrief { DebriefCard(debrief: debrief) }
          if let lesson = reflection.lesson { LessonRecap(lesson: lesson) }
          ReflectionContent(reflection: reflection)
          // Branch retries and Recall would make the uncounted warm-up count.
          if warmUp {
            Text("That’s the whole loop. This one didn’t count; your real practice starts after a quick tour.")
              .foregroundStyle(AppPalette.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Show me around") { leave() }.buttonStyle(PracticeButtonStyle())
              .accessibilityIdentifier("warmUpTour")
          } else {
          completionAction(reflection: reflection)
          if let turns = (current ?? initial).interview?.turns.filter({ $0.kind == "answer" }), !turns.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
              SignalEyebrow(text: "Other moments")
              ForEach(turns.suffix(3)) { turn in
                Button {
                  Task {
                    retryingTurn = turn.id; retryFailure = nil
                    defer { retryingTurn = nil }
                    do { model.presented = try await model.retryMoment(challenge: current ?? initial, turn: turn) }
                    catch { retryFailure = error.localizedDescription }
                  }
                } label: {
                  HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                      Text(turn.prompt).lineLimit(2).multilineTextAlignment(.leading)
                      Text("Start a clean branch here").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if retryingTurn == turn.id { ProgressView().controlSize(.small) }
                    else { Image(systemName: "arrow.branch").foregroundStyle(.secondary).accessibilityHidden(true) }
                  }
                  .frame(minHeight: 56)
                  .contentShape(Rectangle())
                }.buttonStyle(DrillbitRowButtonStyle()).disabled(retryingTurn != nil)
              }
            }
          }
          }
          }
          .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 8)))
          if let retryFailure { Text(retryFailure).font(.subheadline).foregroundStyle(AppPalette.destructive) }
        } else {
          if model.hasPendingWrites && !model.fixture {
            Text("Saved on this device. Your answer will sync when connected.").foregroundStyle(.secondary)
          } else if waitingForFeedback {
            LoadingStatus("Your answer is saved. Feedback is being prepared.")
              .accessibilityLabel("Preparing feedback")
          } else {
            Text(warmUp ? "Your warm-up is done. Feedback will show up here in a moment." : "Your practice is complete. Feedback will appear here and in your library when it’s ready.").foregroundStyle(.secondary)
          }
          if !waitingForFeedback { Button("Check feedback") { feedbackCheck += 1 }.frame(minHeight: 44) }
          if let job = model.bootstrap?.jobs.first(where: { $0.challengeId == initial.id && $0.kind == "summarize" && $0.status == "failed" }) {
            Button("Retry feedback") { Task { await model.retry(job); feedbackCheck += 1 } }
          }
        }
        if let reflection = (current ?? initial).reflection, !warmUp {
          Button("Review in Recall") {
            model.presented = nil
            NotificationCenter.default.post(name: .init("OpenRecall"), object: nil)
          }.buttonStyle(PracticeButtonStyle(secondary: true))
          Button("Practise this next") { preparingFollowUp = true }
            .buttonStyle(PracticeButtonStyle(secondary: true))
          if hasLearningAction(reflection) {
            Button("Done for today") { leave() }
          }
        }
      }.padding(24)
        .animation(reduceMotion ? nil : DrillbitMotion.reveal, value: hasReflection)
    }.background(AppPalette.background)
      .sensoryFeedback(.success, trigger: hasReflection) { before, now in !before && now }
      .navigationTitle("Reflection").navigationBarBackButtonHidden()
      .sheet(isPresented: $preparingFollowUp, onDismiss: {
        if let startedFollowUp { model.presented = startedFollowUp; self.startedFollowUp = nil }
      }) {
        QuestionFlow(model: model, source: current ?? initial, onStart: { startedFollowUp = $0 })
      }
      .task(id: feedbackCheck) {
        guard !model.fixture else { return }
        waitingForFeedback = true
        defer { waitingForFeedback = false }
        let account = model.bootstrap?.account.id
        let started = Date()
        while Date().timeIntervalSince(started) < 90 {
          if let detail: Challenge = try? await model.api.send("challenges/" + initial.id) {
            guard account == model.bootstrap?.account.id, !Task.isCancelled else { return }
            current = detail
            if detail.reflection != nil { await model.loadMemory(); await model.loadRecall(); return }
          }
          try? await Task.sleep(for: .milliseconds(Date().timeIntervalSince(started) < 10 ? 500 : 1500))
          if Task.isCancelled { return }
        }
      }
  }
  @ViewBuilder private func completionAction(reflection: Reflection) -> some View {
    let challenge = current ?? initial
    let matched = reflection.evidence?.first(where: { $0.signal == "needs_practice" && $0.sourceTurnId != nil })
      .flatMap { evidence in challenge.interview?.turns.first { $0.id == evidence.sourceTurnId } }
    if let turn = matched {
      Button("Retry this moment") { Task {
        retryingTurn = turn.id
        defer { retryingTurn = nil }
        do { model.presented = try await model.retryMoment(challenge: challenge, turn: turn) }
        catch { retryFailure = error.localizedDescription }
      } }.buttonStyle(PracticeButtonStyle()).disabled(retryingTurn != nil)
    } else if model.recall.dueCount > 0 {
      let count = min(model.recall.dueCount, model.bootstrap?.todayPlan?.recommendedRecallCount ?? model.recall.dueCount)
      let minutes = Int(ceil(Double(count) / 2.0))
      Button("Review \(count) cards · about \(minutes) minutes") {
        model.presented = nil; NotificationCenter.default.post(name: .init("OpenRecall"), object: nil)
      }.buttonStyle(PracticeButtonStyle())
    } else {
      Button("Done for today") { leave() }.buttonStyle(PracticeButtonStyle())
    }
  }
  private func hasLearningAction(_ reflection: Reflection) -> Bool {
    reflection.evidence?.contains { $0.signal == "needs_practice" && $0.sourceTurnId != nil } == true
      || model.recall.dueCount > 0
  }
  private func leave() { model.presented = nil; Task { await model.refresh() } }
}
struct ReflectionContent: View {
  var reflection: Reflection
  private var featuredEvidence: LearningEvidence? {
    reflection.evidence?.first { $0.signal == "needs_practice" } ?? reflection.evidence?.first
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      if let evidence = featuredEvidence {
        SignalEyebrow(text: "From this answer")
        Text("“\(evidence.quote)”")
          .font(.title2.weight(.medium)).textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
        SignalRule()
        SignalEyebrow(text: evidence.signal == "demonstrated" ? "What worked" : "The missing guard")
        Text(evidence.observation).font(.title2.weight(.semibold))
          .fixedSize(horizontal: false, vertical: true)
      } else {
        SignalEyebrow(text: "Your reflection")
        Text(reflection.takeaway).font(.title2.weight(.semibold))
      }
      if !reflection.summary.isEmpty {
        Text(reflection.summary).foregroundStyle(AppPalette.secondary)
      }
      DisclosureGroup("Full feedback") {
        VStack(alignment: .leading, spacing: 16) {
          if !reflection.worked.isEmpty {
            SignalEyebrow(text: "What worked")
            ForEach(reflection.worked, id: \.self) { Text($0) }
          }
          if !reflection.improve.isEmpty {
            SignalEyebrow(text: "Next time")
            Text(reflection.improve)
          }
          if let evidence = reflection.evidence {
            ForEach(evidence.filter { $0.id != featuredEvidence?.id }) { item in
              VStack(alignment: .leading, spacing: 4) {
                Text("“\(item.quote)”").textSelection(.enabled)
                Text(item.observation).foregroundStyle(AppPalette.secondary)
              }
            }
          }
          if let exercise = reflection.nextExercise {
            SignalEyebrow(text: "Practise next")
            Text(exercise)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
      }
    }
  }
}
struct ExampleView: View {
  var model: AppModel
  var challenge: Challenge
  @State private var answer: ExampleAnswer?
  @State private var loading = false
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        if let answer {
          Text(answer.overview)
          ForEach(answer.sections) { part in
            VStack(alignment: .leading, spacing: 8) {
              Text(part.heading).font(.headline)
              Text(part.body)
            }
          }
          Text("Trade-offs").font(.headline)
          ForEach(answer.tradeoffs, id: \.self) { Text($0) }
          Text("Pitfalls").font(.headline)
          ForEach(answer.pitfalls, id: \.self) { Text($0) }
        } else if loading {
          LoadingStatus("Preparing an example")
        } else {
          Text("See one possible answer. Your own answer will stay unchanged.")
          Button("Reveal example") {
            Task {
              loading = true
              defer { loading = false }
              await model.perform {
                let result: GenerationResponse = try await model.api.send(
                  "challenges/\(challenge.id)/example", method: "POST", command: UUID().uuidString)
                if let id = result.id { try await model.waitForJob(id) }
                let current: Challenge = try await model.api.send("challenges/" + challenge.id)
                answer = current.example
              }
            }
          }.buttonStyle(PracticeButtonStyle())
        }
      }.padding(24).textSelection(.enabled)
    }.background(AppPalette.background).navigationTitle("Example answer").task { answer = challenge.example }
  }
}
