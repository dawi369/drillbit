import SwiftUI

struct HomeView: View {
  @Bindable var model: AppModel
  var openSettings: () -> Void
  @State private var flow: QuestionFlowEntry?
  @State private var started: Challenge?
  @State private var skipping: Challenge?
  @State private var chooseAfterSkip = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// Changes when the question area switches state, never while typing or polling.
  private var questionState: String {
    let challenge = model.bootstrap?.challenge
    let preparing = model.busy || model.bootstrap?.jobs.contains(where: { $0.kind == "generate" && ["pending", "running"].contains($0.status) }) == true
    return "\(model.firstUse.stage)|\(challenge?.id ?? "")|\(challenge?.lifecycle ?? "")|\(preparing)|\(model.preparationFailure != nil)"
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 32) {
        HStack {
          DrillbitLogo(compact: true)
          Spacer()
          Button("Settings", systemImage: AppIcon.settings.rawValue, action: openSettings)
            .labelStyle(.iconOnly).buttonStyle(DrillbitIconButtonStyle())
            .accessibilityIdentifier("homeSettings")
        }
        if let account = model.completionNoticeAccount, account == model.bootstrap?.account.id {
          HStack(alignment: .top, spacing: 12) {
            CompletionHeading()
            Spacer(minLength: 0)
            Button { model.completionNoticeAccount = nil } label: {
              Image(systemName: "xmark").frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Dismiss practice completion")
          }
          .accessibilityIdentifier("practiceCompletionNotice")
          .transition(.opacity)
          Divider()
        }
        VStack(alignment: .leading, spacing: 20) {
          HStack {
            SignalEyebrow(text: "The next question")
            Spacer()
            if let challenge = model.bootstrap?.challenge, model.firstUse.stage == .complete {
              Menu {
                if challenge.lifecycle == "ready" {
                  Button("Regenerate", systemImage: AppIcon.retry.rawValue) { Task {
                    do { _ = try await model.generateForPreview(PreparationInput(focus: "System design", kind: "design", difficulty: model.settings.difficulty, engineeringLevel: challenge.engineeringLevel, replaceId: challenge.id)) }
                    catch { model.preparationFailure = error.localizedDescription }
                  } }
                  Button("Choose focus or level", systemImage: AppIcon.preferences.rawValue) { flow = QuestionFlowEntry() }
                }
                if challenge.lifecycle == "in_progress" {
                  Button("Choose another question", systemImage: AppIcon.regenerate.rawValue) { chooseAfterSkip = true; skipping = challenge }
                }
                Button("Skip question", systemImage: AppIcon.skip.rawValue, role: .destructive) { chooseAfterSkip = false; skipping = challenge }
              } label: { Image(systemName: AppIcon.more.rawValue).frame(width: 44, height: 44) }
                .accessibilityLabel("Question actions").accessibilityIdentifier("homeQuestionActions")
                .disabled(model.busy)
            }
          }
          VStack(alignment: .leading, spacing: 20) {
          if model.firstUse.stage == .walkthrough {
            Text("Let’s try one together.").font(.largeTitle.weight(.semibold))
            Text("A one-minute walkthrough. Your progress starts with your first real session.").font(.subheadline).foregroundStyle(AppPalette.secondary)
            Button("Resume walkthrough") { flow = QuestionFlowEntry(challenge: FirstUseProgress.challenge) }
              .buttonStyle(PracticeButtonStyle()).accessibilityIdentifier("startPractice")
          } else if model.firstUse.stage == .chooseMode {
            Text("Make it your session.").font(.largeTitle.weight(.semibold))
            Text("Guided, Practice, or Mock interview. Choose the support you want today.").foregroundStyle(AppPalette.secondary)
            Button("Choose my session") { flow = QuestionFlowEntry() }.buttonStyle(PracticeButtonStyle())
          } else if let challenge = model.bootstrap?.challenge {
            VStack(alignment: .leading, spacing: 20) {
              Text(challenge.title).font(.largeTitle.weight(.semibold)).tracking(-0.8)
                .fixedSize(horizontal: false, vertical: true)
              DrillbitMetadata(text: "\(challenge.topic) · \(challenge.levelLabel)")
              Text(challenge.displayPrompt).font(.subheadline).foregroundStyle(AppPalette.secondary)
                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
              SignalJourney(inProgress: challenge.lifecycle == "in_progress")
              Button(challenge.lifecycle == "in_progress" ? "Resume" : "Open question") {
                if challenge.lifecycle == "in_progress" { Task { await model.open(challenge) } }
                else { flow = QuestionFlowEntry(challenge: challenge) }
              }.buttonStyle(PracticeButtonStyle()).accessibilityIdentifier("startPractice")
            }
            .id(challenge.id)
            .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 8)))
          } else if !model.busy {
            Button("Prepare question") { flow = QuestionFlowEntry() }.buttonStyle(PracticeButtonStyle())
          }
          if model.busy || model.bootstrap?.jobs.contains(where: { $0.kind == "generate" && ["pending", "running"].contains($0.status) }) == true {
            LoadingStatus("Preparing your question…").transition(.opacity)
          }
          if let failure = model.preparationFailure {
            Text(failure).font(.subheadline).foregroundStyle(.secondary)
            Button("Review preparation") { flow = QuestionFlowEntry(recovery: model.failedPreparation, source: model.failedPreparationSource) }
          }
          ForEach(model.bootstrap?.jobs.filter { $0.status == "failed" && $0.kind != "help" } ?? []) { job in
            VStack(alignment: .leading, spacing: 8) {
              Text(job.error ?? "Preparation could not finish.").foregroundStyle(.secondary)
              Button("Retry") { Task { await model.retry(job) } }
            }
          }
          }
          .animation(reduceMotion ? nil : DrillbitMotion.reveal, value: questionState)
        }
        if model.bootstrap?.todayPlan?.completedTotal != 0 {
          VStack(alignment: .leading, spacing: 12) {
            SignalEyebrow(text: "Your practice")
            HomeRecommendation(plan: model.bootstrap?.todayPlan)
            PracticeOverview(memory: model.memory)
          }
        }
        if let revisit = model.homeRevisit { revisitSection(revisit).transition(.opacity) }
        exploreSection
      }.frame(maxWidth: 640, alignment: .leading).frame(maxWidth: .infinity)
        .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 40)
        .animation(reduceMotion ? nil : DrillbitMotion.reveal, value: model.homeRevisit == nil)
        .animation(reduceMotion ? nil : DrillbitMotion.reveal, value: model.completionNoticeAccount)
    }.drillbitTabClearance()
      .task(id: model.bootstrap?.account.id) { await model.ensureHomeQuestion() }
      .alert("Skip this question?", isPresented: Binding(get: { skipping != nil }, set: { if !$0 { skipping = nil } })) {
        Button("Keep practising", role: .cancel) { skipping = nil }
        Button("Skip question", role: .destructive) { if let question = skipping { let choose = chooseAfterSkip; Task { await model.skip(question.id); if choose, model.bootstrap?.challenge == nil { flow = QuestionFlowEntry() } } }; skipping = nil }
      } message: { Text("Keep it in Skipped questions and return to Home. Your saved draft is preserved.") }
      .navigationTitle("Home").navigationBarTitleDisplayMode(.inline)
      .toolbar(.hidden, for: .navigationBar)
      .background(AppPalette.background)
      .refreshable { await model.refresh() }
      .sheet(item: $flow, onDismiss: {
        if let started { model.presented = started; self.started = nil }
      }) { entry in
        QuestionFlow(model: model, initial: entry.challenge, source: entry.source, recovery: entry.recovery, browseTopics: entry.browseTopics, area: entry.area, onStart: { started = $0 })
      }
      .task {
        while !Task.isCancelled {
          try? await Task.sleep(for: .seconds(4))
          if model.bootstrap?.jobs.contains(where: { ["pending", "running"].contains($0.status) }) == true { await model.refresh() }
        }
      }
  }
  private func prepare(_ concept: PracticeConcept, source: Challenge? = nil) {
    flow = QuestionFlowEntry(recovery: PreparationInput(primaryConceptId: concept.id, focus: "System design", kind: "design", difficulty: model.settings.difficulty, engineeringLevel: model.settings.selectedLevel, replaceId: model.bootstrap?.challenge?.lifecycle == "ready" ? model.bootstrap?.challenge?.id : nil, followUpId: source?.id), source: source)
  }
  private func revisitSection(_ item: HomeRevisit) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        SignalEyebrow(text: "Revisit").accessibilityAddTraits(.isHeader)
        Spacer()
        Button { Task { await model.dismissHomeRevisit(item) } } label: {
          Image(systemName: "xmark").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).frame(width: 44, height: 44)
        }.buttonStyle(.plain).accessibilityLabel("Dismiss revisit suggestion")
      }
      VStack(alignment: .leading, spacing: 8) {
        Text(model.taxonomy.first(where: { $0.id == item.evidence.conceptId })?.label ?? "From your practice")
          .font(.title3.weight(.semibold))
        Text(item.evidence.observation).font(.subheadline).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 24) { revisitLinks(item) }
        VStack(alignment: .leading, spacing: 0) { revisitLinks(item) }
      }
      .font(.body.weight(.medium))
    }
  }
  @ViewBuilder private func revisitLinks(_ item: HomeRevisit) -> some View {
    NavigationLink("Review reasoning") { SessionDetailView(model: model, initial: item.source) }
      .frame(minHeight: 44)
    if let concept = model.taxonomy.first(where: { $0.id == item.evidence.conceptId }) {
      Button { prepare(concept, source: item.source) } label: {
        HStack(spacing: 4) {
          Text("Practise this concept")
          Image(systemName: "arrow.right").font(.subheadline.weight(.semibold)).accessibilityHidden(true)
        }
      }
      .frame(minHeight: 44)
    }
  }
  private var exploreSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      SignalEyebrow(text: "Explore system design")
      VStack(spacing: 0) {
        let areas = suggestedAreas
        ForEach(areas) { area in
          Button { flow = QuestionFlowEntry(browseTopics: true, area: area) } label: {
            PracticeAreaGroupRow(area: area)
          }.buttonStyle(DrillbitRowButtonStyle())
          if area.id != areas.last?.id { Divider() }
        }
      }
      Button { flow = QuestionFlowEntry(browseTopics: true) } label: {
        HStack(spacing: 4) {
          Text("See all areas")
          Image(systemName: "arrow.right").font(.subheadline.weight(.semibold)).accessibilityHidden(true)
        }
      }
      .frame(minHeight: 44)
    }.task { await model.loadTaxonomy() }
  }

  private var suggestedAreas: [PracticeAreaGroup] {
    let concepts = HomeTopicRanking.ranked(PracticeAreaCatalog.curated(model.taxonomy), coverage: model.libraryCoverage)
    var areas: [PracticeAreaGroup] = []
    for concept in concepts {
      if let area = PracticeAreaGroup.all.first(where: { $0.concepts.contains(concept.id) }),
         !areas.contains(where: { $0.id == area.id }) { areas.append(area) }
    }
    for area in PracticeAreaGroup.all where !areas.contains(where: { $0.id == area.id }) { areas.append(area) }
    return Array(areas.prefix(3))
  }

}
struct PracticeOverview: View {
  var memory: MemoryResponse
  @Environment(\.dynamicTypeSize) private var typeSize
  private var headline: String {
    guard let stats = memory.statistics else { return "Ready when you are." }
    if stats.completed == 0 { return "Let’s make the first one count." }
    if stats.lastSevenDays >= 4 { return "You’re building real momentum." }
    if stats.lastSevenDays > 0 { return "Nice work showing up." }
    return "Your next rep is waiting."
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text(headline).font(.subheadline).foregroundStyle(.secondary)
      let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .top, spacing: 24))
      if let statistics = memory.statistics, statistics.completed > 0 {
        layout {
          metric("Completed", value: statistics.completed)
          metric("Last 7 days", value: statistics.lastSevenDays)
        }
      }
      if let value = memory.statistics, let date = Date.fromAPI(value.asOf), Date().timeIntervalSince(date) > 300 {
        Text("Updated \(date.formatted(date: .abbreviated, time: .shortened))")
          .font(.caption).foregroundStyle(.secondary)
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
  private func metric(_ title: String, value: Int) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(String(value)).font(.system(.title, design: .rounded, weight: .bold)).monospacedDigit()
        .contentTransition(.numericText(value: Double(value)))
        .animation(DrillbitMotion.reveal, value: value)
      Text(title).font(.subheadline).foregroundStyle(.secondary)
    }.frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("\(title), \(value)")
  }
}

private struct HomeRecommendation: View {
  var plan: TodayPlan?
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.title2.weight(.semibold))
      if let detail { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
      if plan?.state == "review_due" {
        Button("Open Recall") { NotificationCenter.default.post(name: .init("OpenRecall"), object: nil) }.frame(minHeight: 44)
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
  private var title: String { switch plan?.state {
    case "resume": "Pick up where you left off."
    case "review_due": "A few useful things are ready to revisit."
    case "question_ready": "Your next practice is ready."
    case "complete_today": "Good work. You’re done for today."
    case "prepare": "Ready for another one?"
    default: "Your practice is ready."
  } }
  private var detail: String? {
    guard let plan, plan.state == "review_due" else { return nil }
    return "\(plan.dueRecallCount) due · start with \(plan.recommendedRecallCount) · about \(plan.estimatedRecallMinutes) min"
  }
}

struct HomeTopicRow: View {
  var concept: PracticeConcept
  var coverage: CoverageResponse.Entry?
  var loaded: Bool
  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(concept.label).font(.body.weight(.medium)).foregroundStyle(.primary)
        if loaded {
          DrillbitMetadata(text: (coverage?.completedAttempts ?? 0) == 0 ? (concept.description ?? "A core system design decision.") : "\(coverage?.completedAttempts ?? 0) completed \(coverage?.completedAttempts == 1 ? "session" : "sessions")")
        }
      }
      Spacer(minLength: 0)
      Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
    }.padding(.vertical, 16).frame(maxWidth: .infinity, minHeight: 60, alignment: .leading).contentShape(Rectangle())
  }
}

private struct SignalJourney: View {
  let inProgress: Bool
  @Environment(\.dynamicTypeSize) private var typeSize
  var body: some View {
    Group {
      // Three columns split words mid-syllable at accessibility sizes.
      if typeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 12) {
          step("01", "Question", active: !inProgress)
          step("02", "Interview", active: inProgress)
          step("03", "Recall", active: false)
        }
      } else {
        HStack(alignment: .top, spacing: 0) {
          step("01", "Question", active: !inProgress)
          Rectangle().fill(AppPalette.hairline).frame(height: 1).padding(.top, 8)
          step("02", "Interview", active: inProgress)
          Rectangle().fill(AppPalette.hairline).frame(height: 1).padding(.top, 8)
          step("03", "Recall", active: false)
        }
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(inProgress ? "Interview in progress; Recall follows" : "Question ready; interview and Recall follow")
  }
  @ViewBuilder private func step(_ number: String, _ title: String, active: Bool) -> some View {
    let marker = Circle().fill(active ? AppPalette.action : AppPalette.elevated)
      .frame(width: 16, height: 16)
      .overlay { Circle().stroke(active ? AppPalette.action : AppPalette.hairline, lineWidth: 1) }
    let label = Text(title).font(.caption.weight(active ? .semibold : .regular))
      .foregroundStyle(active ? AppPalette.primary : AppPalette.secondary)
    if typeSize.isAccessibilitySize {
      HStack(spacing: 12) { marker; label }
    } else {
      VStack(alignment: .leading, spacing: 8) {
        marker
        label
        Text(number).font(.caption2.monospaced()).foregroundStyle(AppPalette.secondary)
      }
    }
  }
}
