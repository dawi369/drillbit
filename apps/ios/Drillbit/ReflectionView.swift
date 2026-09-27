import SwiftUI

struct CompletionHeading: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalEyebrow(text: "Practice complete")
      Text("One idea to carry forward.")
        .font(.largeTitle.weight(.semibold)).tracking(-0.8)
    }
  }
}
struct ReflectionView: View {
  @State private var waitingForFeedback = true
  @State private var feedbackCheck = 0
  @State private var preparingFollowUp = false
  @State private var startedFollowUp: Challenge?
  @State private var retryingTurn: String?
  @State private var retryFailure: String?
  var model: AppModel
  var initial: Challenge
  @State private var current: Challenge?
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        CompletionHeading()
        AssistanceSummary(challenge: current ?? initial)
        if let reflection = (current ?? initial).reflection {
          ReflectionContent(reflection: reflection)
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
                    VStack(alignment: .leading, spacing: 3) {
                      Text(turn.prompt).lineLimit(2).multilineTextAlignment(.leading)
                      Text("Start a clean branch here").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if retryingTurn == turn.id { ProgressView().controlSize(.small) }
                    else { Image(systemName: "arrow.branch").foregroundStyle(.secondary) }
                  }
                }.buttonStyle(.plain).disabled(retryingTurn != nil)
              }
            }
          }
          if let retryFailure { Text(retryFailure).font(.subheadline).foregroundStyle(AppPalette.destructive) }
        } else {
          Text(
            model.hasPendingWrites && !model.fixture
              ? "Saved on this device. Your answer will sync when connected."
              : waitingForFeedback ? "Your answer is saved. Feedback is being prepared." : "Your practice is complete. Feedback will appear here and in your library when it’s ready."
          ).foregroundStyle(
            .secondary)
          if waitingForFeedback { ProgressView().accessibilityLabel("Preparing feedback") }
          else { Button("Check feedback") { feedbackCheck += 1 } }
          if let job = model.bootstrap?.jobs.first(where: { $0.challengeId == initial.id && $0.kind == "summarize" && $0.status == "failed" }) {
            Button("Retry feedback") { Task { await model.retry(job); feedbackCheck += 1 } }
          }
        }
        if let reflection = (current ?? initial).reflection {
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
    }.background(AppPalette.background)
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
        Rectangle().fill(AppPalette.action).frame(height: 2)
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
