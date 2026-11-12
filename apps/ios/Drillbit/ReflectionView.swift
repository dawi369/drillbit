import StoreKit
import SwiftUI

/// The end of a rep: Bit hops in above two lines on the interview's background, then Home takes over by itself.
/// A different pair each time, in the same voice as the "next boss fight" reminder.
struct RepDoneMoment: View {
  static let lines: [(title: String, line: String)] = [
    ("Well done.", "That’s one in the bag."),
    ("Boss down.", "Loot: one design call that’ll stick."),
    ("GG.", "Respawn tomorrow. Same time, tougher boss."),
    ("Rep logged.", "Your future interviewer has no idea what’s coming."),
    ("Shipped.", "Straight to production, zero rollbacks."),
    ("Achievement unlocked.", "Thought about failure modes on purpose."),
    ("That’s a wrap.", "The servers stayed up. Mostly thanks to you."),
    ("Merged.", "Clean diff, no reviewer nitpicks."),
    ("Level up.", "Plus one design call in the skill tree."),
    ("Cache warmed.", "Next time this comes up, it’s a hit."),
    ("Load handled.", "Ten thousand users, zero tears."),
    ("Checkpoint saved.", "Progress kept. Close the app guilt-free."),
    ("Build passed.", "Green checks all the way down."),
    ("Nailed it.", "Your interviewer would’ve nodded at least twice."),
    ("Combo extended.", "Another rep stacked on the pile."),
    ("100% uptime.", "Your brain stayed up the whole rep."),
    ("Quest complete.", "Reward: one fewer thing to panic about."),
    ("Ticket closed.", "Done before standup. Legend."),
    ("Bottleneck found.", "And for once it wasn’t you."),
    ("Saved to disk.", "Not just memory. This one’s staying."),
  ]
  @AppStorage("repDone.lastTitle") private var lastTitle = ""
  @State private var pick: (title: String, line: String)?
  @State private var shown = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// Any pair but the last one shown, so a rep never ends on the same joke twice running.
  static func next(after last: String) -> (title: String, line: String) {
    lines.filter { $0.title != last }.randomElement() ?? lines[0]
  }
  var body: some View {
    let pick = pick ?? Self.lines[0]
    VStack(spacing: 8) {
      BitView(mood: .happy, greets: true).frame(height: 88).padding(.bottom, 12)
      Text(pick.title).font(.largeTitle.weight(.semibold)).tracking(-0.8).foregroundStyle(AppPalette.primary)
      Text(pick.line).font(.title3).foregroundStyle(AppPalette.secondary)
    }
    .multilineTextAlignment(.center)
    .padding(.horizontal, 32)
    .opacity(shown ? 1 : 0)
    .offset(y: shown || reduceMotion ? 0 : 8)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(AppPalette.background.ignoresSafeArea())
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("repDone")
    .onAppear {
      if self.pick == nil {
        let chosen = Self.next(after: lastTitle)
        self.pick = chosen
        lastTitle = chosen.title
      }
      withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { shown = true }
    }
  }
}

struct CompletionHeading: View {
  var warmUp = false
  var mode: GuidanceMode = .coachMe
  private var title: String {
    if warmUp { return "That’s the whole loop." }
    return switch mode {
    case .learnTogether: "Here’s what you worked out."
    case .mockInterview: "Here’s how the round went."
    case .coachMe: "Here’s how it went."
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      BitView(greets: true).frame(height: 64)
      Text(title)
        .font(.largeTitle.weight(.semibold)).tracking(-0.8)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
    }
  }
}

/// Guided's ending: the ideas worked through together. The next step lives in the actions below, not here.
struct LessonRecap: View {
  let lesson: Lesson
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      SignalEyebrow(text: "Worked out together")
      ForEach(lesson.learned, id: \.self) { idea in
        Label {
          Text(idea).fixedSize(horizontal: false, vertical: true)
        } icon: {
          Image(systemName: "checkmark.circle.fill").foregroundStyle(AppPalette.success)
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("lessonRecap")
  }
}

/// Mock interview's ending: how the round went, then a note per part of it. No per-part ratings: a single rep
/// is practice, not a scorecard.
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
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label {
        Text(verdict.title).font(.headline).fixedSize(horizontal: false, vertical: true)
      } icon: {
        Image(systemName: verdict.symbol).foregroundStyle(verdict.color)
      }
      .accessibilityIdentifier("debriefVerdict")
      Text(debrief.reason).foregroundStyle(AppPalette.secondary).fixedSize(horizontal: false, vertical: true)
      let notes = debrief.signals.filter { !$0.note.isEmpty }
      if !notes.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(notes) { signal in
            (Text((Self.areas[signal.area] ?? signal.area) + ". ").fontWeight(.semibold) + Text(signal.note))
              .font(.subheadline)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 12))
      }
      if !debrief.toPass.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          Text("Next round").font(.headline)
          Text(debrief.toPass).fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("debrief")
  }
}

/// The end of a rep: one thing that worked and one to fix, in the person's own words, then one way out.
/// Feedback is written after Finish; until it lands the screen says where it is, and Done always works.
struct ReflectionView: View {
  @State private var waitingForFeedback = true
  @State private var waitStarted = Date()
  @State private var feedbackCheck = 0
  @State private var preparingFollowUp = false
  @State private var startedFollowUp: Challenge?
  @State private var retryingTurn: String?
  @State private var retryFailure: String?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.requestReview) private var requestReview
  var model: AppModel
  var initial: Challenge
  /// Leaving for Home or a new rep. The interview uses it to offer Pro after a first rep.
  var onLeave: ((ReflectionExit) -> Void)? = nil
  @State private var current: Challenge?
  private var challenge: Challenge { current ?? initial }
  private var reflection: Reflection? { challenge.reflection }
  private var warmUp: Bool { initial.isWarmUp }
  private var mode: GuidanceMode { reflection?.guidanceMode ?? challenge.guidanceMode ?? .coachMe }
  private var failedJob: Job? {
    model.bootstrap?.jobs.first { $0.challengeId == initial.id && $0.kind == "summarize" && $0.status == "failed" }
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        CompletionHeading(warmUp: warmUp, mode: mode)
        if warmUp {
          Text("This one didn’t count. The next one does.")
            .foregroundStyle(AppPalette.secondary).fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("feedbackLead")
        } else if let reflection {
          VStack(alignment: .leading, spacing: 24) {
            ReflectionContent(reflection: reflection, showsEnding: true)
            AssistanceSummary(challenge: challenge)
          }
          .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 8)))
        } else {
          feedbackStatus
        }
        actions
      }
      .padding(24)
      .animation(reduceMotion ? nil : DrillbitMotion.reveal, value: reflection != nil)
      .animation(reduceMotion ? nil : DrillbitMotion.reveal, value: waitingForFeedback)
    }
    .background(AppPalette.background)
    .sensoryFeedback(.success, trigger: reflection != nil) { before, now in !before && now }
    .toolbar(.hidden, for: .navigationBar)
    .accessibilityIdentifier("reflection")
    .sheet(isPresented: $preparingFollowUp, onDismiss: {
      if let startedFollowUp { onLeave?(.newRep); model.presented = startedFollowUp; self.startedFollowUp = nil }
    }) {
      QuestionFlow(model: model, source: challenge, onStart: { startedFollowUp = $0 })
    }
    .task(id: feedbackCheck) { await waitForFeedback() }
    .task(id: reflection != nil) { await askForReview() }
    // The map line names the concept, so the vocabulary has to be on hand.
    .task { await model.loadTaxonomy() }
  }

  /// Apple's review prompt, while finishing a rep still feels good and before any mention of money: shortly after
  /// the feedback loads, once per app version. Apple decides whether it shows (at most three times a year).
  private func askForReview() async {
    guard reflection != nil, !warmUp, !model.fixture, initial.lifecycle == "completed",
      let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
      UserDefaults.standard.string(forKey: Self.reviewKey) != version else { return }
    try? await Task.sleep(for: .seconds(1.5))
    // Leaving the screen first cancels this task, so nobody is asked on their way out.
    guard !Task.isCancelled else { return }
    UserDefaults.standard.set(version, forKey: Self.reviewKey)
    requestReview()
  }
  static let reviewKey = "reviewRequestedVersion"

  /// Where the feedback is while it isn't here: on its way, slow, failed or waiting for a connection.
  @ViewBuilder private var feedbackStatus: some View {
    VStack(alignment: .leading, spacing: 12) {
      if model.hasPendingWrites && !model.fixture {
        Text("Saved on your phone. Feedback comes once you’re back online.")
          .foregroundStyle(AppPalette.secondary).fixedSize(horizontal: false, vertical: true)
      } else if let job = failedJob {
        Text("Feedback didn’t come through this time. Your rep is saved.")
          .foregroundStyle(AppPalette.secondary).fixedSize(horizontal: false, vertical: true)
        Button("Try again") { Task { await model.retry(job); feedbackCheck += 1 } }
          .frame(minHeight: 44)
          .accessibilityIdentifier("retryFeedback")
      } else if waitingForFeedback {
        TimelineView(.periodic(from: waitStarted, by: 1)) { context in
          LoadingStatus(context.date.timeIntervalSince(waitStarted) < 15
            ? "Saved. Your feedback’s on its way."
            : "Still writing it. Sometimes it takes a minute.")
        }
        .accessibilityLabel("Preparing feedback")
      } else {
        Text("Feedback lands here and in Library when it’s ready.")
          .foregroundStyle(AppPalette.secondary).fixedSize(horizontal: false, vertical: true)
        Button("Check again") { feedbackCheck += 1 }.frame(minHeight: 44)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("feedbackStatus")
  }

  /// One way out, always there. At most one other step, and only once there's feedback to act on.
  @ViewBuilder private var actions: some View {
    VStack(alignment: .leading, spacing: 12) {
      // While a retry is being set up, leaving would race it back onto the screen.
      Button(warmUp ? "Done" : "Done for today") { leave(.home) }
        .buttonStyle(PracticeButtonStyle())
        .disabled(retryingTurn != nil)
        .accessibilityIdentifier(warmUp ? "warmUpTour" : "completionDone")
      if !warmUp, let reflection, model.mayStartRep() {
        if let turn = retryTurn(reflection) {
          Button {
            Task {
              retryingTurn = turn.id; retryFailure = nil
              defer { retryingTurn = nil }
              do {
                let started = try await model.retryMoment(challenge: challenge, turn: turn)
                onLeave?(.newRep)
                model.presented = started
              } catch { retryFailure = error.localizedDescription }
            }
          } label: {
            HStack(spacing: 8) {
              Text("Retry the tricky moment")
              if retryingTurn != nil { ProgressView().controlSize(.small) }
            }
          }
          .buttonStyle(PracticeButtonStyle(secondary: true))
          .disabled(retryingTurn != nil)
          .accessibilityIdentifier("retryMoment")
        } else {
          Button("Practise this next") { preparingFollowUp = true }
            .buttonStyle(PracticeButtonStyle(secondary: true))
            .accessibilityIdentifier("practiseNext")
        }
      }
      if let retryFailure { Text(retryFailure).font(.subheadline).foregroundStyle(AppPalette.destructive) }
      if let ask = proAsk { proAskView(ask).padding(.top, 4) }
    }
  }

  /// At most one Pro ask on a free rep's feedback, the most useful first: reps used up, the voice mock just spent,
  /// then what this rep put on Bit's map. Everything it says comes from this rep; nothing is guessed.
  private enum ProAsk { case repsSpent(String), voiceUsed, map(label: String, held: Bool) }
  private var proAsk: ProAsk? {
    guard !warmUp, let reflection, model.bootstrap?.practice?.freeReps == true else { return nil }
    if !model.mayStartRep(), let line = model.freeRepsLine { return .repsSpent(line) }
    if usedFreeVoice { return .voiceUsed }
    let evidence = reflection.evidence ?? []
    if let mark = evidence.first(where: { $0.signal == "demonstrated" }) ?? evidence.first(where: { $0.signal == "needs_practice" }),
       let label = model.taxonomy.first(where: { $0.id == mark.conceptId })?.label {
      return .map(label: label, held: mark.signal == "demonstrated")
    }
    return nil
  }
  /// This rep spoke with the interviewer, and that was the free voice mock: voice is now Pro.
  private var usedFreeVoice: Bool {
    guard let voice = model.bootstrap?.capabilities?.voice, voice.plan == "free", !voice.available else { return false }
    return (challenge.interview?.turns ?? []).contains { turn in
      (turn.voice ?? []).contains { $0.speaker == "user" && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
  }
  @ViewBuilder private func proAskView(_ ask: ProAsk) -> some View {
    switch ask {
    case .repsSpent(let line):
      if let reflection, retryTurn(reflection) != nil {
        // The most useful next step stays in view, behind Pro, rather than vanishing once free reps run out.
        VStack(alignment: .leading, spacing: 12) {
          Text(line).font(.subheadline).foregroundStyle(AppPalette.secondary).fixedSize(horizontal: false, vertical: true)
          Button { offerPro(.practiceRep) } label: {
            Label("Retry the tricky moment", systemImage: "lock.fill")
          }
          .buttonStyle(PracticeButtonStyle(secondary: true))
          .accessibilityLabel("Retry the tricky moment. Part of Pro.")
          .accessibilityIdentifier("retryMomentPro")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("freeRepNotice")
      } else {
        ProNudge(message: line, placement: .practiceRep) { await model.refresh() }
          .accessibilityIdentifier("freeRepNotice")
      }
    case .voiceUsed:
      proCard(title: "That was your free voice mock.", line: "Pro keeps voice open for every rep.", action: "See Pro") { offerPro(.voiceSession) }
        .accessibilityIdentifier("voiceUsedNotice")
    case .map(let label, let held):
      proCard(eyebrow: "Bit’s map", title: "\(label): \(held ? "Held up." : "Worth another go.")", line: nil, action: "See your map with Pro") { offerPro(.knowledgeMap) }
        .accessibilityIdentifier("mapTease")
    }
  }
  private func proCard(eyebrow: String? = nil, title: String, line: String?, action: String, tap: @escaping () -> Void) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      if let eyebrow { SignalEyebrow(text: eyebrow) }
      Text(title).font(.headline).fixedSize(horizontal: false, vertical: true)
      if let line { Text(line).font(.subheadline).foregroundStyle(AppPalette.secondary).fixedSize(horizontal: false, vertical: true) }
      Button(action, action: tap)
        .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
        .accessibilityIdentifier("seePro")
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 12))
    .accessibilityElement(children: .contain)
  }
  /// One ask is enough: once Pro has been shown from the feedback, leaving it doesn't show it again.
  private func offerPro(_ placement: PaywallPlacement) {
    model.noteProOffered()
    PlanCoordinator.shared.register(placement) { await model.refresh() }
  }

  /// The answer behind the gap, when the feedback points at one: retrying it is the most useful next step.
  private func retryTurn(_ reflection: Reflection) -> InterviewTurn? {
    reflection.evidence?.first { $0.signal == "needs_practice" && $0.sourceTurnId != nil }
      .flatMap { evidence in challenge.interview?.turns.first { $0.id == evidence.sourceTurnId } }
  }

  /// Polls for the written feedback for up to 90 seconds, checking now and then whether the job gave up.
  private func waitForFeedback() async {
    // Fixtures carry their feedback, or a parked state, from the start; there's nothing to poll.
    guard !model.fixture, !warmUp else { waitingForFeedback = reflection == nil && failedJob == nil; return }
    waitingForFeedback = true
    waitStarted = .now
    defer { waitingForFeedback = false }
    let account = model.bootstrap?.account.id
    var polls = 0
    while Date().timeIntervalSince(waitStarted) < 90 {
      if let detail: Challenge = try? await model.api.send("challenges/" + initial.id) {
        guard account == model.bootstrap?.account.id, !Task.isCancelled else { return }
        current = detail
        if detail.reflection != nil { await model.loadMemory(); await model.loadRecall(); return }
      }
      polls += 1
      // The job list says when feedback gave up; it isn't worth fetching on every poll.
      if polls % 8 == 0 { await model.refresh(); if failedJob != nil { return } }
      try? await Task.sleep(for: .milliseconds(Date().timeIntervalSince(waitStarted) < 10 ? 500 : 1500))
      if Task.isCancelled { return }
    }
    await model.refresh()
  }

  private func leave(_ exit: ReflectionExit) {
    onLeave?(exit)
    model.presented = nil
    Task { await model.refresh() }
  }
}

/// Where someone went after their feedback: back to Home, or straight into another rep.
enum ReflectionExit { case home, newRep }

struct ReflectionContent: View {
  var reflection: Reflection
  /// The live completion shows Guided's recap or Mock's debrief under the lead.
  var showsEnding = false
  private var strength: LearningEvidence? { reflection.evidence?.first { $0.signal == "demonstrated" } }
  private var gap: LearningEvidence? { reflection.evidence?.first { $0.signal == "needs_practice" } }
  private var workedLine: String? { strength == nil ? reflection.workedLine : nil }
  private var fixLine: String? { gap == nil ? reflection.fixLine : nil }
  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      // One thing that worked and one to fix, in the person's own words where the feedback quotes them.
      if strength != nil || workedLine != nil || gap != nil || fixLine != nil {
        VStack(alignment: .leading, spacing: 16) {
          if strength != nil || workedLine != nil { point("What worked", evidence: strength, line: workedLine) }
          if (strength != nil || workedLine != nil) && (gap != nil || fixLine != nil) { SignalRule() }
          if gap != nil || fixLine != nil { point("What to fix", evidence: gap, line: fixLine) }
        }
        .accessibilityIdentifier("feedbackLead")
      } else {
        // Nothing technical to go on yet (a hello, a pause): say so, and what would help, without padding it.
        VStack(alignment: .leading, spacing: 8) {
          Text(reflection.summary).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
          if !reflection.improve.isEmpty {
            Text(reflection.improve).foregroundStyle(AppPalette.secondary).fixedSize(horizontal: false, vertical: true)
          }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("feedbackLead")
      }
      if showsEnding {
        if let debrief = reflection.debrief { DebriefCard(debrief: debrief) }
        if let lesson = reflection.lesson, !lesson.learned.isEmpty { LessonRecap(lesson: lesson) }
      }
      if hasMore {
        DisclosureGroup("More from this rep") {
          VStack(alignment: .leading, spacing: 16) {
            if !reflection.summary.isEmpty, reflection.hasTechnicalWork {
              Text(reflection.summary).foregroundStyle(AppPalette.secondary)
            }
            if let evidence = reflection.evidence {
              ForEach(evidence.filter { $0.id != strength?.id && $0.id != gap?.id }) { item in
                VStack(alignment: .leading, spacing: 4) {
                  Text("“\(item.quote)”").textSelection(.enabled)
                  Text(item.observation).foregroundStyle(AppPalette.secondary)
                }
              }
            }
            if let exercise = reflection.nextExercise, reflection.hasTechnicalWork {
              VStack(alignment: .leading, spacing: 4) {
                Text("Try next").font(.headline)
                Text(exercise)
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.top, 12)
        }
        .accessibilityIdentifier("moreFeedback")
      }
    }
  }
  private var hasMore: Bool {
    reflection.hasTechnicalWork && (!reflection.summary.isEmpty || reflection.nextExercise != nil
      || (reflection.evidence ?? []).contains { $0.id != strength?.id && $0.id != gap?.id })
  }
  private func point(_ title: String, evidence: LearningEvidence?, line: String?) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalEyebrow(text: title)
      if let evidence {
        Text("“\(evidence.quote)”")
          .font(.title3.weight(.medium)).textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
        Text(evidence.observation).font(.body)
          .foregroundStyle(AppPalette.secondary)
          .fixedSize(horizontal: false, vertical: true)
      } else if let line {
        Text(line).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
      }
    }
    .accessibilityElement(children: .combine)
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
          Text("One way to answer it. Yours stays as you wrote it.")
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
