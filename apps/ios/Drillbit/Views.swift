import ClerkKit
import SwiftUI

struct RootView: View {
  @Bindable var model: AppModel
  @State private var settingsOpen = false
  @State private var firstSessionSetup = false
  @State private var selectedTab = ProcessInfo.processInfo.arguments.contains("--fixture-recall") ? "recall" : "home"
  @AppStorage("appearance") private var appearance = "dark"
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.colorScheme) private var systemColorScheme
  var body: some View {
    Group {
      if model.restoringSession || model.launchError != nil {
        VStack(spacing: 16) {
          DrillbitLogo(compact: true)
          if let message = model.launchError {
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Try again") { Task { await model.launch() } }
          }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppPalette.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sessionRestoration")
      } else if let account = model.bootstrap?.account, account.status == "active" {
        if !model.settings.onboardingComplete {
          NavigationStack { SetupView(model: model) }
        } else {
          TabView(selection: $selectedTab) {
            Tab("Home", systemImage: AppIcon.home.rawValue, value: "home") {
              NavigationStack {
                HomeView(model: model, openSettings: { settingsOpen = true })
              }
            }
            Tab("Recall", systemImage: AppIcon.recall.rawValue, value: "recall") {
              NavigationStack {
                RecallView(model: model).drillbitTabClearance()
              }
            }
            Tab("Library", systemImage: AppIcon.library.rawValue, value: "library") {
              NavigationStack {
                MemoryView(model: model).drillbitTabClearance().toolbar {
                  Button("Settings", systemImage: AppIcon.settings.rawValue) { settingsOpen = true }
                }
              }
            }
          }
          .allowsHitTesting(model.firstUse.tourTab == nil)
          .accessibilityHidden(model.firstUse.tourTab != nil)
          .overlay(alignment: .bottom) {
            if model.firstUse.tourTab != nil && model.presented == nil {
              ViewThatFits(in: .vertical) {
                FirstUseTourTip(model: model)
                ScrollView { FirstUseTourTip(model: model) }
              }.padding(.bottom, 88)
            }
          }
        }
      } else {
        WelcomeView(model: model)
      }
    }
    .preferredColorScheme(model.fixture && ProcessInfo.processInfo.arguments.contains("--dark") ? .dark : appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
    .background(WindowFloorColor().allowsHitTesting(false))
    .onChange(of: model.firstUse.stage) { _, stage in
      if let tab = model.firstUse.tourTab { selectedTab = tab }
      if stage == .chooseMode { selectedTab = "home"; firstSessionSetup = true }
    }
    .onReceive(NotificationCenter.default.publisher(for: .init("OpenPractice"))) { _ in
      selectedTab = "home"
      Task { await model.refresh() }
    }
    .onReceive(NotificationCenter.default.publisher(for: .init("OpenRecall"))) { _ in
      selectedTab = "recall"
      Task { await model.loadRecall() }
    }
    .task {
      await model.launch()
      if let tab = model.firstUse.tourTab { selectedTab = tab }
      if model.firstUse.stage == .chooseMode { firstSessionSetup = true }
      #if DEBUG
        if model.fixture && ProcessInfo.processInfo.arguments.contains("--fixture-settings") {
          settingsOpen = true
        }
      #endif
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        Task { await model.refresh(); await model.ensureHomeQuestion() }
      } else if phase == .background {
        if !model.fixture { BackgroundRefresh.schedule() }
        Task { await model.sync() }
      }
    }
    .sheet(isPresented: $settingsOpen) {
      NavigationStack { SettingsView(model: model) }
        .environment(\.colorScheme, appearance == "dark" ? .dark : appearance == "light" ? .light : systemColorScheme)
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
        .interactiveDismissDisabled()
    }
    .sheet(item: $model.starterPreview) { challenge in
      QuestionFlow(model: model, initial: challenge, isStarter: true) { opened in model.presented = opened }
        .interactiveDismissDisabled(false)
    }
    .sheet(isPresented: $firstSessionSetup) {
      QuestionFlow(model: model) { opened in model.presented = opened }
    }
    .fullScreenCover(item: $model.presented) { challenge in
      NavigationStack {
        if challenge.id == FirstUseProgress.challengeID { FirstPracticeView(model: model) }
        else { InterviewView(model: model, challenge: challenge) }
      }
    }
    .sheet(item: $model.conflict) { challenge in
      NavigationStack {
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            Text("The answer changed on another device. Your local draft is still stored.")
            Text("Cloud answer").font(.headline)
            Text(challenge.session?.answer ?? "No answer").textSelection(.enabled)
            Button("Use cloud answer") { Task { await model.resolveConflict(keepLocal: false) } }
              .buttonStyle(PracticeButtonStyle())
            if challenge.isActive {
              Button("Keep my local answer") {
                Task { await model.resolveConflict(keepLocal: true) }
              }
            } else {
              Text("This session is already complete. Copy your local draft before replacing it.")
                .foregroundStyle(.secondary)
            }
            LocalRecoveryView(model: model, challenge: challenge)
          }.padding(24)
        }.navigationTitle("Review draft")
      }.interactiveDismissDisabled()
    }
    .alert(
      "Drillbit",
      isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })
    ) {
      Button("OK") { model.error = nil }
    } message: {
      Text(model.error ?? "")
    }
    .onOpenURL { url in
      if url.scheme == "dawi.drillbit" && url.host == "callback" { return }
      selectedTab = "home"
      Task { await model.refresh() }
    }
  }
}

/// The keyboard's rounded corners reveal the host window, outside SwiftUI's
/// keyboard-safe area. Keep that window on the same adaptive app floor.
private struct WindowFloorColor: UIViewRepresentable {
  func makeUIView(context: Context) -> FloorView { FloorView() }
  func updateUIView(_ view: FloorView, context: Context) { view.window?.backgroundColor = AppPalette.backgroundUIColor }

  final class FloorView: UIView {
    override func didMoveToWindow() {
      super.didMoveToWindow()
      window?.backgroundColor = AppPalette.backgroundUIColor
    }
  }
}
struct LocalRecoveryView: View {
  var model: AppModel
  var challenge: Challenge
  @State private var local = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Local answer").font(.headline)
      Text(local).textSelection(.enabled)
      ShareLink("Export local answer", item: local)
    }.task { local = await model.localAnswer(challenge) }
  }
}
struct HomeView: View {
  @Bindable var model: AppModel
  var openSettings: () -> Void
  @State private var flow: QuestionFlowEntry?
  @State private var started: Challenge?
  @State private var skipping: Challenge?
  @State private var chooseAfterSkip = false
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
          } else if !model.busy {
            Button("Prepare question") { flow = QuestionFlowEntry() }.buttonStyle(PracticeButtonStyle())
          }
          if model.busy || model.bootstrap?.jobs.contains(where: { $0.kind == "generate" && ["pending", "running"].contains($0.status) }) == true {
            LoadingStatus("Preparing your question…")
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
        }
        if model.bootstrap?.todayPlan?.completedTotal != 0 {
          VStack(alignment: .leading, spacing: 12) {
            SignalEyebrow(text: "Your practice")
            HomeRecommendation(plan: model.bootstrap?.todayPlan)
            PracticeOverview(memory: model.memory)
          }
        }
        if let revisit = model.homeRevisit { revisitSection(revisit) }
        exploreSection
      }.frame(maxWidth: 640, alignment: .leading).frame(maxWidth: .infinity)
        .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 40)
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
        DrillbitSectionHeader(title: "Revisit")
        Spacer()
        Button { Task { await model.dismissHomeRevisit(item) } } label: {
          Image(systemName: "xmark").foregroundStyle(.secondary).frame(width: 44, height: 44)
        }.buttonStyle(.plain).accessibilityLabel("Dismiss revisit suggestion")
      }
      VStack(alignment: .leading, spacing: 12) {
        Text(model.taxonomy.first(where: { $0.id == item.evidence.conceptId })?.label ?? "From your practice")
          .font(.headline)
        Text(item.evidence.observation).font(.subheadline).foregroundStyle(.secondary)
        NavigationLink("Review reasoning") { SessionDetailView(model: model, initial: item.source) }
          .frame(minHeight: 44)
        if let concept = model.taxonomy.first(where: { $0.id == item.evidence.conceptId }) {
          Button("Practise this concept") { prepare(concept, source: item.source) }
            .buttonStyle(PracticeButtonStyle(secondary: true))
        }
      }
      .padding(.top, 16)
      .overlay(alignment: .top) { AppPalette.hairline.frame(height: 1) }
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
          }.buttonStyle(.plain)
          if area.id != areas.last?.id { Divider() }
        }
      }
      Button("See all areas", systemImage: "arrow.right") { flow = QuestionFlowEntry(browseTopics: true) }
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
  var isStarter = false
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
  @State private var loading = false
  @State private var starting = false
  @State private var failure: String?
  @State private var retryInput: PreparationInput?
  @State private var account: String?
  @State private var visible = true
  @State private var initialized = false
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
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
              }.buttonStyle(.plain)
              }
            } else {
              ForEach(PracticeAreaGroup.all.filter { topicSearch.isEmpty || $0.title.localizedCaseInsensitiveContains(topicSearch) || $0.detail.localizedCaseInsensitiveContains(topicSearch) }) { area in
                Button { selectedArea = area } label: { PracticeAreaGroupRow(area: area) }.buttonStyle(.plain)
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
        Group {
          if loading {
            LoadingStatus("Preparing your question…", centered: true)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          } else {
            ScrollView {
              VStack(alignment: .leading, spacing: 16) {
                if let question {
                  SignalEyebrow(text: "The scenario")
                  Text(question.title).font(.largeTitle.weight(.semibold)).tracking(-0.8)
                    .fixedSize(horizontal: false, vertical: true)
                  if question.guidanceMode == .learnTogether {
                    Text(question.id == FirstUseProgress.challengeID ? "A short, guided warm-up. It won’t count toward your practice." : "Guided practice helps you structure the approach.")
                      .font(.subheadline).foregroundStyle(.secondary)
                  }
                  Text(question.displayPrompt)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled).accessibilityIdentifier("previewPrompt")
                }
                if let failure {
                  Text(failure).foregroundStyle(.secondary)
                  Button("Back to preparation") { showingPreview = false }
                }
              }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
              .accessibilityIdentifier("questionPreviewScroll")
          }
        }.safeAreaInset(edge: .bottom) {
          if let question, !loading {
            VStack(spacing: 12) {
              Button(question.lifecycle == "in_progress" ? "Resume" : isStarter ? "Start practice" : "Start interview") {
                starting = true
                Task {
                  do {
                    let opened = try await model.openForPreview(question)
                    if visible, scenePhase == .active, account == model.bootstrap?.account.id { onStart(opened); dismiss() }
                  } catch { failure = error.localizedDescription }
                  starting = false
                }
              }.buttonStyle(PracticeButtonStyle()).disabled(starting)
                .accessibilityIdentifier("previewStart")
              if question.lifecycle == "ready" && question.id != FirstUseProgress.challengeID {
                Button("Choose another question") { showingPreview = false; failure = nil }.disabled(starting)
              }
            }.padding(16).background(AppPalette.background)
          }
        }.navigationTitle("Question preview").navigationBarTitleDisplayMode(.inline)
          .toolbar { Button("Close") { dismiss() } }
      } else {
        PreparationView(model: model, source: source, initialCustomTopic: selectedCustomTopic, submit: { input in
          showingPreview = true
          loading = true
          question = nil
          failure = nil
          let capturedAccount = model.bootstrap?.account.id
          Task {
            do {
              let result = try await model.generateForPreview(input)
              guard capturedAccount == model.bootstrap?.account.id else { return }
              question = result
            } catch {
              guard capturedAccount == model.bootstrap?.account.id else { return }
              failure = error.localizedDescription
              model.preparationFailure = error.localizedDescription
              model.failedPreparation = input
              model.failedPreparationSource = source
              retryInput = input
            }
            loading = false
          }
        }, recovery: retryInput ?? recovery)
      }
    }.background(AppPalette.background).onAppear {
      visible = true
      guard !initialized else { return }
      initialized = true
      account = model.bootstrap?.account.id
      selectedArea = area
      if model.firstUse.stage == .walkthrough { question = FirstUseProgress.challenge; showingPreview = true }
      else if let initial { question = initial; showingPreview = true }
    }
    .onDisappear { visible = false }
    .onChange(of: scenePhase) { _, phase in if phase == .background { visible = false; dismiss() } }
    .onChange(of: model.bootstrap?.account.id) { _, value in if value != account { dismiss() } }
  }
}
private struct CompletionHeading: View {
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

private struct HomeTopicRow: View {
  var concept: PracticeConcept
  var coverage: CoverageResponse.Entry?
  var loaded: Bool
  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(concept.label).font(.body.weight(.medium)).foregroundStyle(.primary)
        if loaded {
          DrillbitMetadata(text: (coverage?.completedAttempts ?? 0) == 0 ? (concept.description ?? "A core system design decision.") : "\((coverage?.completedAttempts ?? 0)) completed sessions")
        }
      }
      Spacer(minLength: 0)
      Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
    }.padding(.vertical, 16).frame(maxWidth: .infinity, minHeight: 60, alignment: .leading).contentShape(Rectangle())
  }
}

private struct SignalJourney: View {
  let inProgress: Bool
  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      step("01", "Question", active: !inProgress)
      Rectangle().fill(AppPalette.hairline).frame(height: 1).padding(.top, 8)
      step("02", "Interview", active: inProgress)
      Rectangle().fill(AppPalette.hairline).frame(height: 1).padding(.top, 8)
      step("03", "Recall", active: false)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(inProgress ? "Interview in progress; Recall follows" : "Question ready; interview and Recall follow")
  }
  private func step(_ number: String, _ title: String, active: Bool) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Circle().fill(active ? AppPalette.action : AppPalette.elevated)
        .frame(width: 16, height: 16)
        .overlay { Circle().stroke(active ? AppPalette.action : AppPalette.hairline, lineWidth: 1) }
      Text(title).font(.caption.weight(active ? .semibold : .regular))
        .foregroundStyle(active ? AppPalette.primary : AppPalette.secondary)
      Text(number).font(.caption2.monospaced()).foregroundStyle(AppPalette.secondary)
    }
  }
}
