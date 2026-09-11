import ClerkKit
import SwiftUI

struct RootView: View {
  @Bindable var model: AppModel
  @State private var settingsOpen = false
  @Environment(\.scenePhase) private var scenePhase
  var body: some View {
    Group {
      if let account = model.bootstrap?.account, account.status == "active" {
        if !model.settings.onboardingComplete {
          NavigationStack { SetupView(model: model) }
        } else {
          TabView {
            Tab("Home", systemImage: "house") {
              NavigationStack {
                HomeView(model: model).toolbar {
                  Button("Settings", systemImage: "gearshape") { settingsOpen = true }
                }
              }
            }
            Tab("Library", systemImage: "book.closed") {
              NavigationStack {
                MemoryView(model: model).toolbar {
                  Button("Settings", systemImage: "gearshape") { settingsOpen = true }
                }
              }
            }
          }
        }
      } else {
        WelcomeView(model: model)
      }
    }
    .preferredColorScheme(model.fixture && ProcessInfo.processInfo.arguments.contains("--dark") ? .dark : nil)
    .task { await model.launch() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        Task { await model.refresh() }
      } else if phase == .background {
        if !model.fixture { BackgroundRefresh.schedule() }
        Task { await model.sync() }
      }
    }
    .sheet(isPresented: $settingsOpen) {
      NavigationStack { SettingsView(model: model) }.interactiveDismissDisabled()
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
      Task {
        if url.host == "challenge", let id = url.pathComponents.last, id != "/" {
          await model.perform {
            let challenge: Challenge = try await model.api.send("challenges/" + id)
            await model.open(challenge)
          }
        } else {
          await model.refresh()
          if let challenge = model.bootstrap?.challenge { await model.open(challenge) }
        }
      }
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
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        PracticeOverview(memory: model.memory)
        Divider()
        if let challenge = model.bootstrap?.challenge {
          VStack(alignment: .leading, spacing: 12) {
            Text(challenge.lifecycle == "in_progress" ? "In progress" : "Ready to practise")
              .font(.caption).foregroundStyle(.secondary)
            Text(challenge.title).font(.headline).lineLimit(2)
            Text("\(challenge.topic) · \(challenge.levelLabel)").font(.subheadline).foregroundStyle(.secondary)
            if challenge.lifecycle == "ready", let reason = challenge.selectionReason { Text(reason).font(.caption).foregroundStyle(.secondary) }
            Button(challenge.lifecycle == "in_progress" ? "Resume" : "Preview question") {
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
      }.frame(maxWidth: 640, alignment: .leading).padding(24)
    }.safeAreaPadding(.bottom, 24)
      .navigationTitle("Home").navigationBarTitleDisplayMode(.inline)
      .refreshable { await model.refresh() }
      .sheet(item: $flow, onDismiss: {
        if let started { model.presented = started; self.started = nil }
      }) { entry in
        QuestionFlow(model: model, initial: entry.challenge, source: entry.source, recovery: entry.recovery, onStart: { started = $0 })
      }
      .task {
        while !Task.isCancelled {
          try? await Task.sleep(for: .seconds(4))
          if model.bootstrap?.jobs.contains(where: { ["pending", "running"].contains($0.status) }) == true { await model.refresh() }
        }
      }
  }
}
struct QuestionFlowEntry: Identifiable {
  let id = UUID()
  var challenge: Challenge? = nil
  var recovery: PreparationInput? = nil
  var source: Challenge? = nil
}
struct QuestionFlow: View {
  @Bindable var model: AppModel
  var initial: Challenge? = nil
  var source: Challenge? = nil
  var recovery: PreparationInput? = nil
  var onStart: (Challenge) -> Void
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
      if showingPreview {
        Group {
          if loading {
            LoadingStatus("Preparing your question…")
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          } else {
            ScrollView {
              VStack(alignment: .leading, spacing: 16) {
                if let question {
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
        PreparationView(model: model, source: source, submit: { input in
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
struct ReflectionView: View {
  @State private var preparingFollowUp = false
  @State private var startedFollowUp: Challenge?
  var model: AppModel
  var initial: Challenge
  @State private var current: Challenge?
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        Text("Practice complete").font(.title.weight(.semibold))
        AssistanceSummary(challenge: current ?? initial)
        if let reflection = (current ?? initial).reflection {
          ReflectionContent(reflection: reflection)
        } else {
          Text(
            model.hasPendingWrites && !model.fixture
              ? "Saved on this device. Your answer will sync when connected."
              : "Your answer is saved. Feedback is being prepared."
          ).foregroundStyle(
            .secondary)
          ProgressView()
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
      .task {
        guard !model.fixture else { return }
        let started = Date()
        while Date().timeIntervalSince(started) < 90 {
          if let detail: Challenge = try? await model.api.send("challenges/" + initial.id) {
            current = detail
            if detail.reflection != nil { return }
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
      VStack(alignment: .leading, spacing: 8) {
        Text("Next time").font(.headline)
        Text(reflection.improve)
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
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Your practice").font(.title2.weight(.semibold))
      let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .top, spacing: 24))
      layout {
        metric("Completed", value: memory.statistics?.completed)
        metric("Last 7 days", value: memory.statistics?.lastSevenDays)
      }
      if let value = memory.statistics, let date = Date.fromAPI(value.asOf), Date().timeIntervalSince(date) > 300 {
        Text("Updated \(date.formatted(date: .abbreviated, time: .shortened))")
          .font(.caption).foregroundStyle(.secondary)
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
  private func metric(_ title: String, value: Int?) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(value.map(String.init) ?? "—").font(.title.weight(.semibold)).monospacedDigit()
      Text(title).font(.subheadline).foregroundStyle(.secondary)
    }.frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("\(title), \(value.map(String.init) ?? "not synced yet")")
  }
}
