import ClerkKit
import SwiftUI

struct RootView: View {
  @Bindable var model: AppModel
  @State private var settingsOpen = false
  @State private var selectedTab = "home"
  @AppStorage("appearance") private var appearance = "system"
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
        .background(.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sessionRestoration")
      } else if let account = model.bootstrap?.account, account.status == "active" {
        if !model.settings.onboardingComplete {
          NavigationStack { SetupView(model: model) }
        } else {
          TabView(selection: $selectedTab) {
            Tab("Home", systemImage: AppIcon.home.rawValue, value: "home") {
              NavigationStack {
                HomeView(model: model).toolbar {
                  Button("Settings", systemImage: AppIcon.settings.rawValue) { settingsOpen = true }
                }
              }
            }
            Tab("Library", systemImage: AppIcon.library.rawValue, value: "library") {
              NavigationStack {
                MemoryView(model: model).toolbar {
                  Button("Settings", systemImage: AppIcon.settings.rawValue) { settingsOpen = true }
                }
              }
            }
          }
        }
      } else {
        WelcomeView(model: model)
      }
    }
    .preferredColorScheme(model.fixture && ProcessInfo.processInfo.arguments.contains("--dark") ? .dark : appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
    .onReceive(NotificationCenter.default.publisher(for: .init("OpenPractice"))) { _ in
      selectedTab = "home"
      Task { await model.refresh() }
    }
    .task { await model.launch() }
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
    .fullScreenCover(item: $model.presented) { challenge in
      NavigationStack { InterviewView(model: model, challenge: challenge) }
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
  @State private var flow: QuestionFlowEntry?
  @State private var started: Challenge?
  @State private var skipping: Challenge?
  @State private var chooseAfterSkip = false
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
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
        VStack(alignment: .leading, spacing: 12) {
          DrillbitSectionHeader(title: "Your practice")
          PracticeOverview(memory: model.memory)
        }
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            DrillbitSectionHeader(title: "Next question")
            Spacer()
            if let challenge = model.bootstrap?.challenge {
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
          VStack(alignment: .leading, spacing: 16) {
          if let challenge = model.bootstrap?.challenge {
            VStack(alignment: .leading, spacing: 12) {
              Text(challenge.title).font(.title2.weight(.semibold)).lineLimit(2)
              DrillbitMetadata(text: "\(challenge.topic) · \(challenge.levelLabel)")
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
          }.drillbitHeroSurface()
        }
        if let revisit = model.homeRevisit { revisitSection(revisit) }
        exploreSection
      }.frame(maxWidth: 640, alignment: .leading).frame(maxWidth: .infinity).padding(20)
    }.safeAreaPadding(.bottom, 24)
      .task(id: model.bootstrap?.account.id) { await model.ensureHomeQuestion() }
      .alert("Skip this question?", isPresented: Binding(get: { skipping != nil }, set: { if !$0 { skipping = nil } })) {
        Button("Keep practising", role: .cancel) { skipping = nil }
        Button("Skip question", role: .destructive) { if let question = skipping { let choose = chooseAfterSkip; Task { await model.skip(question.id); if choose, model.bootstrap?.challenge == nil { flow = QuestionFlowEntry() } } }; skipping = nil }
      } message: { Text("Keep it in Skipped questions and return to Home. Your saved draft is preserved.") }
      .navigationTitle("Home").navigationBarTitleDisplayMode(.inline)
      .background(AppPalette.background)
      .refreshable { await model.refresh() }
      .sheet(item: $flow, onDismiss: {
        if let started { model.presented = started; self.started = nil }
      }) { entry in
        QuestionFlow(model: model, initial: entry.challenge, source: entry.source, recovery: entry.recovery, browseTopics: entry.browseTopics, onStart: { started = $0 })
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
      }.drillbitSurface()
    }
  }
  private var exploreSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      DrillbitSectionHeader(title: "Explore system design")
      VStack(spacing: 0) {
        let ranked = HomeTopicRanking.ranked(PracticeAreaCatalog.curated(model.taxonomy), coverage: model.libraryCoverage)
        ForEach(Array(ranked.prefix(3))) { concept in
          Button { prepare(concept) } label: {
            HomeTopicRow(concept: concept, coverage: model.libraryCoverage.first(where: { $0.conceptId == concept.id }), loaded: model.libraryCoverageLoaded)
          }.buttonStyle(.plain)
          if concept.id != ranked.prefix(3).last?.id { Divider().padding(.horizontal, 16) }
        }
      }.background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(AppPalette.hairline, lineWidth: 0.5) }
      Button("See all topics", systemImage: "arrow.right") { flow = QuestionFlowEntry(browseTopics: true) }
        .frame(minHeight: 44)
    }.task { await model.loadTaxonomy() }
  }

}
struct QuestionFlowEntry: Identifiable {
  let id = UUID()
  var challenge: Challenge? = nil
  var recovery: PreparationInput? = nil
  var source: Challenge? = nil
  var browseTopics = false
}
struct QuestionFlow: View {
  @Bindable var model: AppModel
  var initial: Challenge? = nil
  var source: Challenge? = nil
  var recovery: PreparationInput? = nil
  var browseTopics = false
  var onStart: (Challenge) -> Void
  @State private var selectedTopic: PracticeConcept?
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
      if browseTopics && selectedTopic == nil && selectedCustomTopic == nil {
        List {
          Section("Core areas") {
            ForEach(PracticeAreaCatalog.curated(model.taxonomy).filter { topicSearch.isEmpty || $0.label.localizedCaseInsensitiveContains(topicSearch) }) { concept in
              Button {
                selectedTopic = concept
                retryInput = PreparationInput(primaryConceptId: concept.id, focus: "System design", kind: "design", difficulty: model.settings.difficulty, engineeringLevel: model.settings.selectedLevel, replaceId: model.bootstrap?.challenge?.lifecycle == "ready" ? model.bootstrap?.challenge?.id : nil)
              } label: {
                HomeTopicRow(concept: concept, coverage: model.libraryCoverage.first(where: { $0.conceptId == concept.id }), loaded: model.libraryCoverageLoaded)
              }.buttonStyle(.plain)
            }
          }
          Section("Your own topic") {
            TextField("For example, search ranking", text: $customTopic)
            Button("Continue") { selectedCustomTopic = customTopic.trimmingCharacters(in: .whitespacesAndNewlines) }
              .disabled(customTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        }.searchable(text: $topicSearch, prompt: "Find a core area")
          .navigationTitle("System design").navigationBarTitleDisplayMode(.inline)
          .toolbar { Button("Close") { dismiss() } }
      } else if showingPreview {
        Group {
          if loading {
            LoadingStatus("Preparing your question…", centered: true)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          } else {
            ScrollView {
              VStack(alignment: .leading, spacing: 16) {
                if let question {
                  Text("YOUR NEXT BOSS FIGHT")
                    .font(.caption2.weight(.semibold)).tracking(0.8)
                    .foregroundStyle(AppPalette.accent)
                  Text(question.title).font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                  Text(question.prompt)
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
              Button(question.lifecycle == "in_progress" ? "Resume" : "Start interview") {
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
              if question.lifecycle == "ready" {
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
    }.onAppear {
      visible = true
      guard !initialized else { return }
      initialized = true
      account = model.bootstrap?.account.id
      if let initial { question = initial; showingPreview = true }
    }
    .onDisappear { visible = false }
    .onChange(of: scenePhase) { _, phase in if phase == .background { visible = false; dismiss() } }
    .onChange(of: model.bootstrap?.account.id) { _, value in if value != account { dismiss() } }
  }
}
private struct CompletionHeading: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Boss fight logged.").font(.title2.weight(.semibold))
      Text("Practice done. Future you says thanks.").font(.subheadline).foregroundStyle(.secondary)
    }
  }
}
struct ReflectionView: View {
  @State private var waitingForFeedback = true
  @State private var feedbackCheck = 0
  @State private var preparingFollowUp = false
  @State private var startedFollowUp: Challenge?
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
        Button("Done") {
          model.presented = nil
          Task { await model.refresh() }
        }.buttonStyle(PracticeButtonStyle())
        if (current ?? initial).reflection != nil {
          Button("Practise this next") { preparingFollowUp = true }
            .buttonStyle(PracticeButtonStyle(secondary: true))
        }
      }.padding(24)
    }.navigationTitle("Reflection").navigationBarBackButtonHidden()
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
            if detail.reflection != nil { await model.loadMemory(); return }
          }
          try? await Task.sleep(for: .milliseconds(Date().timeIntervalSince(started) < 10 ? 500 : 1500))
          if Task.isCancelled { return }
        }
      }
  }
}
struct ReflectionContent: View {
  var reflection: Reflection
  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      Text(reflection.summary)
      if !reflection.worked.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text("What worked").font(.headline)
          ForEach(reflection.worked, id: \.self) { Text($0) }
        }
      }
      if !reflection.improve.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text("Next time").font(.headline)
          Text(reflection.improve)
        }
      }
      if let exercise = reflection.nextExercise {
        VStack(alignment: .leading, spacing: 8) {
          Text("Practise next").font(.headline)
          Text(exercise)
        }
      }
      Text(reflection.takeaway).foregroundStyle(.secondary)
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
    }.navigationTitle("Example answer").task { answer = challenge.example }
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
      if let statistics = memory.statistics {
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

private struct HomeTopicRow: View {
  var concept: PracticeConcept
  var coverage: CoverageResponse.Entry?
  var loaded: Bool
  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(concept.label).font(.body.weight(.medium)).foregroundStyle(.primary)
        if loaded {
          DrillbitMetadata(text: (coverage?.completedAttempts ?? 0) == 0 ? "Not explored yet" : "\((coverage?.completedAttempts ?? 0)) completed sessions")
        }
      }
      Spacer(minLength: 0)
      Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
    }.padding(16).frame(maxWidth: .infinity, minHeight: 60, alignment: .leading).contentShape(Rectangle())
  }
}
