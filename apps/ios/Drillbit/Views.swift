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
            Tab("Today", systemImage: "sun.max") {
              NavigationStack {
                TodayView(model: model).toolbar {
                  Button("Settings", systemImage: "gearshape") { settingsOpen = true }
                }
              }
            }
            Tab("Memory", systemImage: "book.closed") {
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
      NavigationStack { PracticeView(model: model, challenge: challenge) }
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
struct TodayView: View {
  @Bindable var model: AppModel
  @State private var preparing = false
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        if let challenge = model.bootstrap?.challenge {
          Text(challenge.topic).font(.subheadline).foregroundStyle(.secondary)
          Text(challenge.title).font(.title.weight(.semibold))
          Text(challenge.prompt).font(.body).lineSpacing(4)
          Button(challenge.lifecycle == "in_progress" ? "Resume" : "Start") {
            Task { await model.open(challenge) }
          }.buttonStyle(PracticeButtonStyle()).accessibilityIdentifier(
            "startPractice")
          if challenge.lifecycle == "ready" {
            Button("Choose another question") { preparing = true }.disabled(model.busy)
          }
          if model.busy { ProgressView("Preparing another question") }
        } else if model.busy
          || model.bootstrap?.jobs.contains(where: {
            $0.kind == "generate" && ["pending", "running"].contains($0.status)
          }) == true
        {
          VStack(alignment: .leading, spacing: 16) {
            Text("A question worth thinking about").font(.title).redacted(reason: .placeholder)
            Text("Preparing your next practice session.").foregroundStyle(.secondary)
            ProgressView()
          }
        } else {
          PracticeOverview(memory: model.memory)
          Button("New question") { preparing = true }
            .buttonStyle(PracticeButtonStyle())
        }
        ForEach(model.bootstrap?.jobs.filter { $0.status == "failed" && $0.kind != "help" } ?? []) {
          job in
          VStack(alignment: .leading, spacing: 8) {
            Label(
              job.error ?? "Preparation could not finish.", systemImage: "exclamationmark.circle"
            ).foregroundStyle(AppPalette.destructive)
            Button("Retry") { Task { await model.retry(job) } }
          }
        }
      }.frame(maxWidth: 640, alignment: .leading).padding(24)
    }.navigationTitle("Today").navigationBarTitleDisplayMode(.inline).refreshable {
      await model.refresh()
    }
    .sheet(isPresented: $preparing) {
      NavigationStack { PreparationView(model: model) }
    }
    .task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(4))
        if model.bootstrap?.jobs.contains(where: { ["pending", "running"].contains($0.status) })
          == true
        {
          await model.refresh()
        }
      }
    }
  }
}
struct ReflectionView: View {
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
        Button("Practise a similar question") {
          model.presented = nil
          Task {
            await model.generate(
              PreparationInput(
                focus: initial.topic, kind: "auto", difficulty: model.settings.difficulty, engineeringLevel: model.settings.selectedLevel,
                followUpId: initial.id))
          }
        }.buttonStyle(PracticeButtonStyle(secondary: true))
      }.padding(24)
    }.navigationTitle("Reflection").navigationBarBackButtonHidden()
      .task {
        guard !model.fixture else { return }
        for _ in 0..<45 {
          if let detail: Challenge = try? await model.api.send("challenges/" + initial.id) {
            current = detail
            if detail.reflection != nil { return }
          }
          try? await Task.sleep(for: .seconds(2))
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
          ProgressView("Preparing an example")
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
      if let session = memory.sessions.first {
        Divider()
        VStack(alignment: .leading, spacing: 4) {
          Text("Last session").font(.caption).foregroundStyle(.secondary)
          Text(session.title).font(.subheadline).lineLimit(2)
          let level: String? = session.levelLabel
          let finished = session.completedAt.flatMap(Date.fromAPI)
          if level != nil || finished != nil {
            Text([level, finished.map { "Finished " + $0.formatted(date: .abbreviated, time: .shortened) }].compactMap { $0 }.joined(separator: " · "))
              .font(.caption).foregroundStyle(.secondary)
          }
        }
      } else if memory.statistics?.completed == 0 {
        Text("Your first session starts here.").font(.subheadline).foregroundStyle(.secondary)
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
