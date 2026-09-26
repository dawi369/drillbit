import SwiftUI
import UserNotifications

struct MemoryView: View {
  var model: AppModel
  var body: some View { LibraryView(model: model) }
}
struct SessionRow: View {
  var session: Challenge
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(session.title)
      Text(session.topic).font(.caption).foregroundStyle(.secondary)
      if let reflection = session.reflection {
        Text(reflection.takeaway).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
      }
    }
  }
}
struct HistoryView: View {
  var model: AppModel
  @State private var search = ""
  @State private var sessions: [Challenge] = []
  @State private var cursor: String?
  @State private var loading = false
  @State private var failure: String?
  var body: some View {
    SignalList {
      ForEach(sessions) { session in
        NavigationLink {
          SessionDetailView(model: model, initial: session)
        } label: {
          SessionRow(session: session)
        }
      }
      if let failure { Text(failure).foregroundStyle(.secondary) }
      if cursor != nil { Button("Load more") { Task { await load(more: true) } }.disabled(loading) }
    }.navigationTitle("All sessions").searchable(text: $search).task(id: search) {
      try? await Task.sleep(for: .milliseconds(300))
      if !Task.isCancelled { await load(more: false) }
    }
  }
  private func load(more: Bool) async {
    loading = true
    defer { loading = false }
    if model.fixture {
      sessions = model.memory.sessions
      return
    }
    var query = URLComponents()
    query.queryItems = [URLQueryItem(name: "q", value: search)]
    if more, let cursor { query.queryItems?.append(URLQueryItem(name: "cursor", value: cursor)) }
    do {
      let page: HistoryPage = try await model.api.send(
        "sessions?" + (query.percentEncodedQuery ?? ""))
      try Task.checkCancellation()
      sessions = more ? sessions + page.sessions : page.sessions
      cursor = page.nextCursor
      failure = nil
    } catch is CancellationError {} catch {
      if !more {
        sessions = model.memory.sessions.filter {
          search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
        }
      }
      failure = "Showing cached sessions. Connect to load more."
    }
  }
}
struct SessionDetailView: View {
  var model: AppModel
  var initial: Challenge
  @State private var current: Challenge?
  @State private var deleting = false
  @State private var preparing = false
  @State private var started: Challenge?
  init(model: AppModel, initial: Challenge) {
    self.model = model; self.initial = initial
    _current = State(initialValue: model.librarySessions[(model.bootstrap?.account.id ?? "") + ":" + initial.id])
  }
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    let challenge = current ?? initial
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        Text(challenge.title).font(.title.weight(.semibold))
        Text(challenge.levelLabel).foregroundStyle(.secondary)
        if let date = challenge.completedAt.flatMap({ Date.fromAPI($0) }) { Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
        Text(challenge.prompt).foregroundStyle(.secondary)
        if let interview = challenge.interview, !interview.turns.isEmpty {
          NavigationLink("Interview conversation") { InterviewConversation(state: interview) }
        }
        if let answer = challenge.session?.answer, !answer.isEmpty {
          Text("Your answer").font(.headline)
          Text(answer).textSelection(.enabled)
          ShareLink("Copy or share answer", item: answer)
        }
        AssistanceSummary(challenge: challenge)
        if let reflection = challenge.reflection {
          ReflectionContent(reflection: reflection)
          Button("Practise this next") { preparing = true }.buttonStyle(PracticeButtonStyle())
        } else if challenge.lifecycle == "completed" {
          Text("Feedback is pending. You can retry failed feedback from Home.").foregroundStyle(
            .secondary)
        }
        if let help = challenge.help, help.contains(where: { $0.body != nil }) {
          DisclosureGroup("Help history") {
            VStack(alignment: .leading, spacing: 16) {
              ForEach(help.filter { $0.body != nil }) { item in
                Text(item.title).font(.headline)
                Text(item.body ?? "").textSelection(.enabled)
                if let draft = item.suggestedAnswer { Text(draft).textSelection(.enabled) }
              }
            }
          }
        }
        if let turns = challenge.turns, !turns.isEmpty {
          DisclosureGroup("Assistance used") {
            ForEach(turns) { turn in
              Text(turn.text).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            }
          }
        }
        if challenge.example != nil {
          NavigationLink("Example answer viewed") {
            ExampleView(model: model, challenge: challenge)
          }
        }
      }.padding(24)
    }.background(AppPalette.background).navigationTitle("Session").navigationBarTitleDisplayMode(.inline)
      .sheet(isPresented: $preparing, onDismiss: { if let started { model.presented = started; self.started = nil } }) {
        QuestionFlow(model: model, source: challenge, onStart: { started = $0 })
      }
      .toolbar { Button("Delete", systemImage: AppIcon.delete.rawValue, role: .destructive) { deleting = true } }
      .confirmationDialog("Delete this session and its learning evidence?", isPresented: $deleting)
    {
      Button("Delete session", role: .destructive) {
        Task {
          await model.perform {
            let _: EmptyResponse = try await model.api.send(
              "challenges/" + challenge.id, method: "DELETE")
            try await model.refreshAfterSessionDeletion()
            dismiss()
          }
        }
      }
    }
      .task {
        guard !model.fixture, current?.session == nil, initial.session == nil else { return }
        await model.perform { current = try await model.api.send("challenges/" + initial.id) }
      }
  }
}
struct SettingsView: View {
  @Bindable var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var deleting = false
  @State private var discarding = false
  @State private var resettingPractice = false
  @State private var saving = false
  @State private var reminderPermissionPending = false
  @AppStorage("appearance") private var appearance = "dark"
  private var time: Binding<Date> {
    Binding(
      get: {
        Calendar.current.date(
          bySettingHour: model.settings.dailyMinutes / 60, minute: model.settings.dailyMinutes % 60,
          second: 0, of: Date()) ?? Date()
      },
      set: {
        model.settings.dailyMinutes =
          Calendar.current.component(.hour, from: $0) * 60
          + Calendar.current.component(.minute, from: $0)
      })
  }
  var body: some View {
    SignalList {
      Section {
        NavigationLink("Learning plan") { LearningPlanSettingsView(model: model) }
        NavigationLink("About your practice") { PracticeProfileView(model: model) }
      }
      Section("Practice") {
        Picker("Engineering level", selection: $model.settings.selectedLevel) {
          ForEach(EngineeringLevel.choices, id: \.0) { Text($0.1).tag($0.0) }
        }
        DatePicker("Reminder time", selection: time, displayedComponents: .hourAndMinute)
        NavigationLink { TimeZoneSelectionView(selection: $model.settings.timezone) } label: {
          HStack(spacing: 8) {
            Text("Time zone")
            Spacer(minLength: 8)
            Text(TimeZoneSelectionView.label(model.settings.timezone))
              .foregroundStyle(.secondary).lineLimit(1)
          }
        }
        Toggle("Daily reminder", isOn: Binding(
          get: { model.settings.reminderEnabled },
          set: { enabled in
            model.settings.reminderEnabled = enabled
            guard enabled else { return }
            reminderPermissionPending = true
            Task {
              let granted = await model.requestReminderPermission()
              reminderPermissionPending = false
              if !granted && model.settings.reminderEnabled {
                model.settings.reminderEnabled = false
                model.error = "Enable notifications for Drillbit in iPhone Settings to receive reminders."
              }
            }
          }
        )).disabled(reminderPermissionPending)
        ReminderPermissionRow()
      }
      Section { NavigationLink("LLM provider") { AIAccessView(model: model) } }
      Section("Appearance") {
        Picker("Appearance", selection: $appearance) {
          Text("System").tag("system")
          Text("Light").tag("light")
          Text("Dark").tag("dark")
        }.pickerStyle(.menu).accessibilityIdentifier("appearancePicker")
      }
      Section("Account") {
        NavigationLink("Export practice data") { PracticeExportView(model: model) }
        Button("Sign out") {
          Task {
            await model.perform {
              try await model.signOut()
              dismiss()
            }
            if model.hasPendingWrites || model.pendingSettings != nil { discarding = true }
          }
        }
        Button("Delete account", role: .destructive) { deleting = true }
      }
      if model.bootstrap?.capabilities?.developerTools == true {
        DeveloperSettingsSection(resetRequested: $resettingPractice)
      }
    }.navigationTitle("Settings")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            Task {
              saving = true
              defer { saving = false }
              await model.perform {
                try await model.saveSettingsLocally()
                dismiss()
              }
            }
          }.disabled(saving || reminderPermissionPending)
        }
      }
      .confirmationDialog("Delete your account and all practice data?", isPresented: $deleting) {
        Button("Delete account", role: .destructive) {
          Task {
            await model.perform {
              let _: [String: String] = try await model.api.send(
                "account", method: "DELETE", command: UUID().uuidString)
              try await model.signOut(discard: true, deleting: true)
              dismiss()
            }
          }
        }
      }
      .confirmationDialog("Some local edits have not synced", isPresented: $discarding) {
        Button("Discard local edits and sign out", role: .destructive) {
          Task {
            await model.perform {
              try await model.signOut(discard: true)
              dismiss()
            }
          }
        }
      }
      .confirmationDialog("Reset all Drillbit practice data?", isPresented: $resettingPractice) {
        Button("Reset Drillbit", role: .destructive) {
          Task {
            await model.perform {
              try await model.resetDeveloperPractice()
              appearance = "dark"
              dismiss()
            }
          }
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("This permanently removes your practice, Recall history, preferences, reminders and LLM key. You’ll stay signed in and return to onboarding.")
      }
  }
}
private struct DeveloperSettingsSection: View {
  @Binding var resetRequested: Bool
  var body: some View {
    Section {
      Button("Reset Drillbit", role: .destructive) { resetRequested = true }
    } header: {
      Text("Developer")
    } footer: {
      Text("Clears all Drillbit data and preferences, then returns to onboarding. Your sign-in stays active.")
    }
  }
}
struct LearningPlanSettingsView: View {
  @Bindable var model: AppModel
  private let objectives = [("interview","An upcoming interview"),("learn","Stronger system design skills"),("stay_sharp","Keep my skills fresh")]
  private let roles = [("general","General SWE"),("backend","Backend"),("frontend","Frontend"),("full_stack","Full-stack"),("platform","Platform / Infrastructure"),("data","Data"),("mobile","Mobile")]
  private let areas = PracticeAreaGroup.all.map { ($0.id, $0.title) }
  private var plan: Binding<LearningPlan> { Binding(get: { model.settings.learningPlan ?? LearningPlan() }, set: { model.settings.learningPlan = $0 }) }
  var body: some View {
    SignalList {
      Picker("Current priority", selection: plan.objective) { ForEach(objectives, id: \.0) { Text($0.1).tag($0.0) } }
        .onChange(of: plan.wrappedValue.objective) { _, value in if value != "interview" { var updated = plan.wrappedValue; updated.targetDate = nil; plan.wrappedValue = updated } }
      Picker("Role", selection: plan.roleTrack) { ForEach(roles, id: \.0) { Text($0.1).tag($0.0) } }
      Picker("Daily commitment", selection: plan.dailyGoalMinutes) { ForEach([5,10,15,20], id: \.self) { Text("\($0) minutes").tag($0) } }
      if plan.wrappedValue.objective == "interview" {
        Toggle("I have an interview date", isOn: Binding(get: { plan.wrappedValue.targetDate != nil }, set: { enabled in
          var value = plan.wrappedValue; value.targetDate = enabled ? formatted(Date()) : nil; plan.wrappedValue = value
        }))
        if plan.wrappedValue.targetDate != nil {
          DatePicker("Interview date", selection: Binding(get: { parsed(plan.wrappedValue.targetDate) ?? Date() }, set: { date in
            var value = plan.wrappedValue; value.targetDate = formatted(date); plan.wrappedValue = value
          }), in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)
        }
      }
      Section("Areas to work on") {
        Button { var value = plan.wrappedValue; value.weakAreas = []; plan.wrappedValue = value } label: { choice("Let Drillbit decide", selected: plan.wrappedValue.weakAreas.isEmpty) }
        ForEach(areas, id: \.0) { area in
          Button {
            var value = plan.wrappedValue
            if value.weakAreas.contains(area.0) { value.weakAreas.removeAll { $0 == area.0 } }
            else if value.weakAreas.count < 3 { value.weakAreas.append(area.0) }
            plan.wrappedValue = value
          } label: { choice(area.1, selected: plan.wrappedValue.weakAreas.contains(area.0)) }
          .disabled(!plan.wrappedValue.weakAreas.contains(area.0) && plan.wrappedValue.weakAreas.count == 3)
        }
      }
    }.navigationTitle("Learning plan").navigationBarTitleDisplayMode(.inline)
  }
  private func choice(_ title: String, selected: Bool) -> some View {
    HStack { Text(title).foregroundStyle(.primary); Spacer(); if selected { Image(systemName: "checkmark") } }
  }
  private func formatted(_ date: Date) -> String { let value = DateFormatter(); value.calendar = Calendar(identifier: .gregorian); value.locale = Locale(identifier: "en_US_POSIX"); value.timeZone = TimeZone(identifier: model.settings.timezone); value.dateFormat = "yyyy-MM-dd"; return value.string(from: date) }
  private func parsed(_ text: String?) -> Date? { guard let text else { return nil }; let value = DateFormatter(); value.calendar = Calendar(identifier: .gregorian); value.locale = Locale(identifier: "en_US_POSIX"); value.timeZone = TimeZone(identifier: model.settings.timezone); value.dateFormat = "yyyy-MM-dd"; return value.date(from: text) }
}
struct AIAccessView: View {
  @Bindable var model: AppModel
  @State private var key = ""
  @State private var suffix: String?
  @State private var validating = false
  var body: some View {
    SignalList {
      Section {
        Picker("Use", selection: $model.settings.aiMode) {
          Text("Included AI").tag("managed")
          Text("My OpenRouter key").tag("byok")
        }
      }
      Section("OpenRouter") {
        if let suffix = suffix ?? model.bootstrap?.credential?.suffix {
          Label("Key ending in \(suffix)", systemImage: AppIcon.completed.rawValue).foregroundStyle(
            AppPalette.success)
        }
        SecureField("OpenRouter key", text: $key).textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        Button("Validate and save") {
          Task {
            validating = true
            defer { validating = false }
            await model.perform {
              let result: Bootstrap.Credential = try await model.api.send(
                "credential", method: "PUT", body: KeyInput(key: key))
              suffix = result.suffix
              key = ""
              model.settings.aiMode = "byok"
              try await model.updateSettings()
            }
          }
        }.disabled(key.isEmpty || validating)
        Button("Remove key", role: .destructive) {
          Task {
            await model.perform {
              let _: EmptyResponse = try await model.api.send("credential", method: "DELETE")
              suffix = nil
              model.bootstrap?.credential = nil
              await model.refresh()
            }
          }
        }
        LabeledContent {
          Text("Gemini 3.1 Flash Lite").foregroundStyle(.secondary)
        } label: {
          Text("Model").foregroundStyle(.primary)
        }
      }
      Section {
        Text(
          "Your key is encrypted on Drillbit's servers so daily preparation can work while the app is closed. A rejected key never falls back to included AI."
        ).font(.footnote).foregroundStyle(.secondary)
      }
    }.navigationTitle("LLM provider")
  }
}

@MainActor @Observable final class LearningPlanCoordinator {
  struct Draft: Codable, Equatable {
    // A new account sees the introduction; restored drafts keep their page.
    var page = -1
    var objective = "learn"
    var roleTrack = "general"
    var level = "mid"
    var weakAreas: Set<String> = []
    var dailyGoalMinutes = 10
    var targetDate: Date? = nil
    var reminderEnabled = false
    var dailyMinutes = 540
    var timezone = TimeZone.current.identifier
  }
  var draft = Draft()
  var saving = false
  var failure: String?
  var reminderNote: String?
}

struct SetupView: View {
  @Bindable var model: AppModel
  @State private var coordinator = LearningPlanCoordinator()
  @State private var reminderPermissionPending = false
  @State private var movingForward = true
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private let objectives = [("interview","An upcoming interview"),("learn","Stronger system design skills"),("stay_sharp","Keep my skills fresh")]
  private let roles = [("general","General SWE"),("backend","Backend"),("frontend","Frontend"),("full_stack","Full-stack"),("platform","Platform / Infrastructure"),("data","Data"),("mobile","Mobile")]
  private let areas = PracticeAreaGroup.all.map { ($0.id, $0.title) }
  private let startingPoints = [("junior", "New to system design"), ("mid", "I’ve designed a few systems"), ("senior", "I design systems regularly"), ("staff", "I lead architecture across teams")]

  var body: some View {
    @Bindable var coordinator = coordinator
    GeometryReader { geometry in
      ScrollView {
        VStack(alignment: .leading, spacing: 32) {
          if coordinator.draft.page == -1 {
            SetupIntroduction()
              .frame(minHeight: max(0, geometry.size.height - 48))
          } else {
            VStack(alignment: .leading, spacing: 20) {
              SignalEyebrow(text: String(format: "%02d / 05", coordinator.draft.page + 1))
              AppPalette.hairline.frame(height: 1)
              Text(title(for: coordinator.draft.page))
                .font(.largeTitle.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            }
            pageContent(coordinator: coordinator)
            if let note = coordinator.reminderNote { Text(note).font(.footnote).foregroundStyle(AppPalette.secondary) }
            if let failure = coordinator.failure { Text(failure).font(.footnote).foregroundStyle(AppPalette.destructive) }
          }
        }
        .id(coordinator.draft.page)
        .transition(reduceMotion ? .opacity : .asymmetric(
          insertion: .move(edge: movingForward ? .trailing : .leading),
          removal: .move(edge: movingForward ? .leading : .trailing)))
        .frame(maxWidth: 560, alignment: .leading)
        .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 24)
        .frame(maxWidth: .infinity)
      }
    }.clipped()
    .background(AppPalette.background)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      VStack(spacing: 0) {
        AppPalette.hairline.frame(height: 1)
        HStack(spacing: 12) {
          if coordinator.draft.page >= 0 {
            Button("Back") { move(coordinator, to: coordinator.draft.page - 1) }
              .buttonStyle(PracticeButtonStyle(secondary: true))
              .transition(.opacity.combined(with: .offset(x: -12)))
              .disabled(coordinator.saving || reminderPermissionPending)
          }
          Button {
            if coordinator.draft.page == 4 { Task { await finish(coordinator) } }
            else { move(coordinator, to: coordinator.draft.page + 1) }
          } label: {
            HStack(spacing: 8) {
              if coordinator.draft.page == 4 {
                Image(systemName: "sparkles").symbolEffect(.bounce, options: .nonRepeating, value: !reduceMotion && coordinator.draft.page == 4)
                  .accessibilityHidden(true)
              }
              Text(coordinator.saving ? "Opening…" : coordinator.draft.page == -1 ? "Let's begin" : coordinator.draft.page == 4 ? "Start practice" : "Continue")
              if coordinator.draft.page == 4 { Image(systemName: "arrow.right").accessibilityHidden(true) }
            }
            .padding(.vertical, coordinator.draft.page == 4 ? 8 : 0)
          }.buttonStyle(PracticeButtonStyle()).disabled(coordinator.saving || reminderPermissionPending)
            .contentTransition(.opacity)
            .accessibilityIdentifier("onboardingContinue")
            .sensoryFeedback(.success, trigger: coordinator.draft.page == 4)
        }
        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 8)
        .animation(reduceMotion ? nil : .smooth(duration: 0.34, extraBounce: 0), value: coordinator.draft.page >= 0)
      }
      .background(AppPalette.background)
    }
    .toolbar(.hidden, for: .navigationBar)
    .task(id: model.bootstrap?.account.id) { await restore(coordinator) }
    .onChange(of: coordinator.draft) { _, _ in Task { await persist(coordinator) } }
  }

  private func move(_ coordinator: LearningPlanCoordinator, to page: Int) {
    movingForward = page > coordinator.draft.page
    withAnimation(reduceMotion ? nil : .smooth(duration: 0.38, extraBounce: 0)) {
      coordinator.draft.page = page
    }
  }

  @ViewBuilder private func pageContent(coordinator: LearningPlanCoordinator) -> some View {
    @Bindable var coordinator = coordinator
    switch coordinator.draft.page {
    case 0:
      VStack(alignment: .leading, spacing: 12) {
        Text("Your priority right now. You’ll learn and practise in every path.")
          .font(.subheadline).foregroundStyle(AppPalette.secondary)
        VStack(spacing: 0) {
          ForEach(objectives, id: \.0) { option in
            SignalChoiceRow(title: option.1, selected: coordinator.draft.objective == option.0) {
              coordinator.draft.objective = option.0
            }
            if option.0 != objectives.last?.0 { Divider().padding(.horizontal, 16) }
          }
        }
      }
    case 1:
      VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .leading, spacing: 12) {
          Text("What do you usually build?").font(.headline)
          Picker("Your work", selection: $coordinator.draft.roleTrack) {
            ForEach(roles, id: \.0) { option in
              Text(option.1).tag(option.0)
            }
          }.pickerStyle(.menu).frame(minHeight: 44)
        }
        VStack(alignment: .leading, spacing: 12) {
          Text("How familiar is system design?").font(.headline)
          Text("This sets the depth of your questions. You can change it later.").font(.subheadline).foregroundStyle(AppPalette.secondary)
          VStack(spacing: 0) {
            ForEach(startingPoints, id: \.0) { option in
              SignalChoiceRow(title: option.1, selected: coordinator.draft.level == option.0) { coordinator.draft.level = option.0 }
              if option.0 != startingPoints.last?.0 { Divider() }
            }
          }
        }
      }
    case 2:
      VStack(alignment: .leading, spacing: 12) {
        Text("Explore everything, or pick up to three areas.").font(.subheadline).foregroundStyle(AppPalette.secondary)
        VStack(spacing: 0) {
          SignalChoiceRow(title: "A bit of everything", selected: coordinator.draft.weakAreas.isEmpty) {
            coordinator.draft.weakAreas = []
          }
          Divider().padding(.horizontal, 16)
          ForEach(areas, id: \.0) { area in
            SignalChoiceRow(title: area.1, selected: coordinator.draft.weakAreas.contains(area.0)) {
              if coordinator.draft.weakAreas.contains(area.0) { coordinator.draft.weakAreas.remove(area.0) }
              else if coordinator.draft.weakAreas.count < 3 { coordinator.draft.weakAreas.insert(area.0) }
            }
            .disabled(!coordinator.draft.weakAreas.contains(area.0) && coordinator.draft.weakAreas.count == 3)
            if area.0 != areas.last?.0 { Divider().padding(.horizontal, 16) }
          }
        }
      }
    case 3:
      VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .leading, spacing: 12) {
          SignalEyebrow(text: "Daily commitment")
          VStack(spacing: 0) {
            ForEach([5,10,15,20], id: \.self) { minutes in
              SignalChoiceRow(title: "\(minutes) minutes", selected: coordinator.draft.dailyGoalMinutes == minutes) {
                coordinator.draft.dailyGoalMinutes = minutes
              }
              if minutes != 20 { Divider().padding(.horizontal, 16) }
            }
          }
        }
        VStack(alignment: .leading, spacing: 16) {
          if coordinator.draft.objective == "interview" {
            Toggle("I have an interview date", isOn: Binding(get: { coordinator.draft.targetDate != nil }, set: { coordinator.draft.targetDate = $0 ? Date() : nil }))
            if coordinator.draft.targetDate != nil { DatePicker("Interview date", selection: Binding(get: { coordinator.draft.targetDate ?? Date() }, set: { coordinator.draft.targetDate = $0 }), in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date) }
            Divider()
          }
          Toggle("Daily reminder", isOn: Binding(
            get: { coordinator.draft.reminderEnabled },
            set: { enabled in
              coordinator.draft.reminderEnabled = enabled
              guard enabled else { return }
              reminderPermissionPending = true
              Task {
                let granted = await model.requestReminderPermission()
                reminderPermissionPending = false
                if !granted && coordinator.draft.reminderEnabled {
                  coordinator.draft.reminderEnabled = false
                  coordinator.reminderNote = "Enable notifications in iPhone Settings to receive reminders."
                }
              }
            }
          )).disabled(reminderPermissionPending)
          if coordinator.draft.reminderEnabled {
            DatePicker("Time", selection: reminderTime(coordinator), displayedComponents: .hourAndMinute)
            NavigationLink { TimeZoneSelectionView(selection: $coordinator.draft.timezone) } label: {
              HStack(spacing: 8) {
                Text("Time zone")
                Spacer(minLength: 8)
                Text(TimeZoneSelectionView.label(coordinator.draft.timezone))
                  .foregroundStyle(.secondary).lineLimit(1)
              }
            }
          }
        }
        .tint(AppPalette.accent)
      }
    default:
      summary(coordinator.draft)
    }
  }

  private func summary(_ draft: LearningPlanCoordinator.Draft) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("\(draft.dailyGoalMinutes) minutes. One step at a time.").font(.title2.weight(.semibold))
      LabeledContent("Goal", value: objectives.first { $0.0 == draft.objective }?.1 ?? "Learn system design")
      Divider()
      LabeledContent("Role", value: roles.first { $0.0 == draft.roleTrack }?.1 ?? "General SWE")
      Divider()
      LabeledContent("Level", value: EngineeringLevel.choices.first { $0.0 == draft.level }?.1 ?? "Mid-level")
      Divider()
      LabeledContent("Focus", value: draft.weakAreas.isEmpty ? "Drillbit decides" : draft.weakAreas.compactMap { id in areas.first { $0.0 == id }?.1 }.sorted().joined(separator: ", "))
      Divider()
      LabeledContent("Routine", value: "\(draft.dailyGoalMinutes) minutes a day")
      Label("First, a one-minute walkthrough. No score, no pressure.", systemImage: "sparkles")
        .font(.subheadline).foregroundStyle(AppPalette.accent).padding(.top, 12)
    }
  }
  private func title(for page: Int) -> String { ["What brings you here?","Where are you starting?","What sparks your curiosity?","Find your rhythm.","Made for you."][max(0, min(page,4))] }
  private func reminderTime(_ coordinator: LearningPlanCoordinator) -> Binding<Date> { Binding(get: {
    Calendar.current.date(from: DateComponents(hour: coordinator.draft.dailyMinutes / 60, minute: coordinator.draft.dailyMinutes % 60)) ?? Date()
  }, set: { let parts = Calendar.current.dateComponents([.hour,.minute], from: $0); coordinator.draft.dailyMinutes = (parts.hour ?? 9) * 60 + (parts.minute ?? 0) }) }

  private func restore(_ coordinator: LearningPlanCoordinator) async {
    guard let account = model.bootstrap?.account.id else { return }
    if let data = try? await model.disk.cached(key: "onboarding:" + account), let draft = try? JSONDecoder().decode(LearningPlanCoordinator.Draft.self, from: data) { coordinator.draft = draft }
    else { coordinator.draft.level = model.settings.selectedLevel; coordinator.draft.dailyMinutes = model.settings.dailyMinutes; coordinator.draft.timezone = model.settings.timezone }
  }
  private func persist(_ coordinator: LearningPlanCoordinator) async {
    guard let account = model.bootstrap?.account.id, let data = try? JSONEncoder().encode(coordinator.draft) else { return }
    try? await model.disk.cache(key: "onboarding:" + account, data: data)
  }
  private func finish(_ coordinator: LearningPlanCoordinator) async {
    guard !coordinator.saving, let account = model.bootstrap?.account.id else { return }
    coordinator.saving = true; coordinator.failure = nil; coordinator.reminderNote = nil
    defer { coordinator.saving = false }
    if coordinator.draft.reminderEnabled, !(await model.requestReminderPermission()) {
      coordinator.draft.reminderEnabled = false
      coordinator.reminderNote = "Notifications stay off. Your chosen time is saved, and you can enable reminders later."
    }
    let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: coordinator.draft.timezone); formatter.dateFormat = "yyyy-MM-dd"
    model.settings.learningPlan = LearningPlan(objective: coordinator.draft.objective, roleTrack: coordinator.draft.roleTrack,
      weakAreas: coordinator.draft.weakAreas.sorted(), dailyGoalMinutes: coordinator.draft.dailyGoalMinutes,
      targetDate: coordinator.draft.objective == "interview" ? coordinator.draft.targetDate.map { formatter.string(from: $0) } : nil)
    model.settings.selectedLevel = coordinator.draft.level
    model.settings.dailyMinutes = coordinator.draft.dailyMinutes
    model.settings.timezone = coordinator.draft.timezone
    model.settings.reminderEnabled = coordinator.draft.reminderEnabled
    do {
      try await model.setFirstUse(FirstUseProgress(stage: .walkthrough))
      model.settings.onboardingComplete = true
      try await model.saveSettingsLocally()
      try? await model.disk.cache(key: "onboarding:" + account, data: Data())
      model.starterPreview = FirstUseProgress.challenge
    } catch { model.settings.onboardingComplete = false; coordinator.failure = error.localizedDescription }
  }
}

private struct SetupIntroduction: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var revealed = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      DrillbitLogo(compact: true)
      Spacer(minLength: 40)
      ZStack {
        SignalParticleField(density: 420)
          .frame(maxWidth: 320, maxHeight: 320)
        SignalWaveform()
      }
      .frame(maxWidth: .infinity)
      .frame(height: 280)
      .scaleEffect(revealed ? 1 : 0.94)
      .opacity(revealed ? 1 : 0)
      Spacer(minLength: 40)
      VStack(alignment: .leading, spacing: 16) {
        SignalEyebrow(text: "Practice, out loud")
        Text("Think out loud.\nGet sharper.")
          .font(.system(.largeTitle, design: .default, weight: .semibold))
          .tracking(-0.8)
          .fixedSize(horizontal: false, vertical: true)
        Text("A focused system design interviewer, wherever you find a few minutes.")
          .font(.body)
          .foregroundStyle(AppPalette.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .opacity(revealed ? 1 : 0)
      .offset(y: revealed ? 0 : 12)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .task {
      guard !revealed else { return }
      if reduceMotion { revealed = true }
      else { withAnimation(.smooth(duration: 0.55, extraBounce: 0).delay(0.08)) { revealed = true } }
    }
  }
}

struct AssistanceSummary: View {
  var challenge: Challenge
  var body: some View {
    Text(
      !(challenge.adoptions ?? []).isEmpty
        ? "Practised with an assisted draft"
        : (challenge.help ?? []).contains(where: { $0.body != nil })
          || (challenge.interview?.turns ?? []).contains(where: { ["hint", "example"].contains($0.kind) })
          || !(challenge.turns ?? []).isEmpty || challenge.example != nil
          ? "Practised with help" : "No explicit help recorded"
    )
    .font(.footnote).foregroundStyle(.secondary)
  }
}

struct TimeZoneSelectionView: View {
  @Binding var selection: String
  @State private var search = ""
  @Environment(\.dismiss) private var dismiss
  static let zones = ["UTC", "America/Los_Angeles", "America/Denver", "America/Chicago", "America/New_York", "America/Toronto", "America/Sao_Paulo", "Europe/London", "Europe/Prague", "Europe/Berlin", "Europe/Paris", "Africa/Johannesburg", "Asia/Dubai", "Asia/Kolkata", "Asia/Singapore", "Asia/Hong_Kong", "Asia/Tokyo", "Asia/Seoul", "Australia/Sydney", "Pacific/Auckland"]
  static func label(_ id: String) -> String {
    let city = id == "America/Sao_Paulo" ? "São Paulo" : String(id.split(separator: "/").last ?? Substring(id)).replacingOccurrences(of: "_", with: " ")
    let minutes = (TimeZone(identifier: id)?.secondsFromGMT() ?? 0) / 60
    return city + String(format: " (UTC%@%02d:%02d)", minutes < 0 ? "−" : "+", abs(minutes) / 60, abs(minutes) % 60)
  }
  var body: some View {
    SignalList {
      Button("Use current device time zone") { selection = TimeZone.current.identifier; dismiss() }
      ForEach(Array(Set(Self.zones + [selection, TimeZone.current.identifier])).sorted().filter { search.isEmpty || Self.label($0).localizedCaseInsensitiveContains(search) || $0.localizedCaseInsensitiveContains(search) }, id: \.self) { zone in
        Button { selection = zone; dismiss() } label: {
          HStack { Text(Self.label(zone)).foregroundStyle(.primary); Spacer(); if selection == zone { Image(systemName: AppIcon.checkmark.rawValue) } }
        }.accessibilityAddTraits(selection == zone ? .isSelected : [])
      }
    }.searchable(text: $search).navigationTitle("Time zone").navigationBarTitleDisplayMode(.inline)
  }
}

struct PracticeAreaPicker: View {
  var model: AppModel
  @Binding var selection: String
  @Binding var customTopic: String
  @State private var search = ""
  @State private var expandedAreas: Set<String> = []
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    SignalList {
      Button { selection = ""; customTopic = ""; dismiss() } label: {
        HStack { Text("Automatic"); Spacer(); if selection.isEmpty { Image(systemName: AppIcon.checkmark.rawValue) } }
      }.foregroundStyle(.primary)
      ForEach(PracticeAreaGroup.all) { area in
        let matches = model.taxonomy.filter { area.concepts.contains($0.id) && (search.isEmpty || $0.label.localizedCaseInsensitiveContains(search) || area.title.localizedCaseInsensitiveContains(search)) }
        if !matches.isEmpty {
          DisclosureGroup(isExpanded: Binding(get: { !search.isEmpty || expandedAreas.contains(area.id) }, set: { if $0 { expandedAreas.insert(area.id) } else { expandedAreas.remove(area.id) } })) {
            ForEach(matches) { concept in
              Button { selection = concept.id; customTopic = ""; dismiss() } label: {
                HStack { Text(concept.label); Spacer(); if selection == concept.id { Image(systemName: AppIcon.checkmark.rawValue) } }
              }.foregroundStyle(.primary).accessibilityAddTraits(selection == concept.id ? .isSelected : [])
            }
          } label: { Text(area.title).foregroundStyle(AppPalette.primary) }
        }
      }
      Section("Your own topic") {
        TextField("For example, collaborative editing", text: $customTopic)
          .textInputAutocapitalization(.sentences)
          .onChange(of: customTopic) { if !customTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { selection = "" } }
        Button("Use this topic") { dismiss() }
          .disabled(customTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }.navigationTitle("Practice area").searchable(text: $search).task {
      await model.loadTaxonomy()
      if let area = PracticeAreaGroup.all.first(where: { $0.concepts.contains(selection) }) { expandedAreas.insert(area.id) }
    }
  }
}

struct LibraryView: View {
  var model: AppModel
  var skipped = false
  var initialConcept: String? = nil
  @State private var questions: [LibraryQuestion] = []
  @State private var search = ""
  @State private var tags: Set<String> = []
  @State private var level = ""
  @State private var days = 0
  @State private var cursor: String?
  @State private var failure: String?
  @State private var loading = false
  @State private var filterOpen = false
  @State private var coverage: [CoverageResponse.Entry] = []
  @State private var loadedIdentity: String?
  @State private var requestID = UUID()
  init(model: AppModel, skipped: Bool = false, initialConcept: String? = nil) {
    self.model = model; self.skipped = skipped; self.initialConcept = initialConcept
    let selected: Set<String> = initialConcept.map { [$0] } ?? []
    _tags = State(initialValue: selected)
    let identity = Self.cacheIdentity(search: "", tags: selected, level: "", days: 0, skipped: skipped)
    let key = "library:" + (model.bootstrap?.account.id ?? "") + ":" + identity
    let cached = model.librarySnapshots[key]
    _questions = State(initialValue: cached?.questions ?? [])
    _cursor = State(initialValue: cached?.nextCursor)
    _loadedIdentity = State(initialValue: cached == nil ? nil : identity)
  }
  private static func cacheIdentity(search: String, tags: Set<String>, level: String, days: Int, skipped: Bool) -> String {
    [search, tags.sorted().joined(separator: ","), level, String(days), String(skipped)].joined(separator: "|")
  }
  private var query: String {
    var components = URLComponents()
    var items = [URLQueryItem(name: "q", value: search), URLQueryItem(name: "skipped", value: skipped ? "true" : "false"), URLQueryItem(name: "concepts", value: tags.sorted().joined(separator: ","))]
    if !level.isEmpty { items.append(URLQueryItem(name: "level", value: level)) }
    if days > 0 { items.append(URLQueryItem(name: "since", value: Date().addingTimeInterval(-Double(days) * 86400).ISO8601Format())) }
    components.queryItems = items
    return components.percentEncodedQuery ?? ""
  }
  // Keep the task identity independent of the current clock.
  private var identity: String { Self.cacheIdentity(search: search, tags: tags, level: level, days: days, skipped: skipped) }
  var body: some View {
    SignalList {
      if !skipped {
        SignalEyebrow(text: "Questions / evidence")
          .listRowBackground(AppPalette.background)
      }
      if !skipped { NavigationLink("Practice evidence") { PracticeEvidenceView(model: model) } }
      if tags.count == 1, let id = tags.first, let value = coverage.first(where: { $0.conceptId == id }) {
        Section {
          LabeledContent("Completed attempts", value: String(value.completedAttempts))
          LabeledContent("Different questions", value: String(value.distinctQuestions))
          if let date = value.lastPractised.flatMap({ Date.fromAPI($0) }) { LabeledContent("Last practised", value: date.formatted(date: .abbreviated, time: .omitted)) }
        }
      }
      if questions.isEmpty && loadedIdentity == identity && !loading && failure == nil {
        ContentUnavailableView(skipped ? "No skipped questions" : "Your question library", systemImage: AppIcon.books.rawValue, description: Text(skipped ? "Questions you skip will be kept here." : "Completed questions and repeat attempts will appear here."))
      }
      ForEach(questions) { question in
        VStack(alignment: .leading, spacing: 8) {
          NavigationLink { LibraryQuestionView(model: model, initial: question) } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text(question.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
              DrillbitMetadata(text: question.scenario + " · " + question.levelLabel)
              if let date = question.lastActivity.flatMap({ Date.fromAPI($0) }) {
                DrillbitMetadata(text: date.formatted(date: .abbreviated, time: .omitted) + ((question.attemptCount ?? 0) > 1 ? " · \(question.attemptCount!) attempts" : ""))
              }
            }
          }.accessibilityIdentifier("library-question-" + question.id)
          ForEach(Array(question.conceptIds.prefix(2)), id: \.self) { id in
            Button(model.taxonomy.first { $0.id == id }?.label ?? id) { tags = [id] }
              .font(.caption).buttonStyle(.borderless).foregroundStyle(AppPalette.accent)
          }
        }.padding(.vertical, 8).listRowBackground(AppPalette.background)
      }
      if let failure { Text(failure).font(.footnote).foregroundStyle(.secondary); Button("Retry") { Task { await load() } } }
      if cursor != nil { Button("Load more") { Task { await load(more: true) } }.disabled(loading) }
    }
    .listStyle(.plain)
    .navigationTitle(skipped ? "Skipped questions" : "Library")
    .searchable(text: $search)
    .toolbar {
      Button("Filters", systemImage: AppIcon.filter.rawValue) { filterOpen = true }
      if !skipped {
        Menu {
          NavigationLink { LibraryView(model: model, skipped: true) } label: { Label("Skipped questions", systemImage: AppIcon.skip.rawValue) }
        } label: { Image(systemName: AppIcon.more.rawValue) }.accessibilityLabel("Library menu")
      }
    }
    .sheet(isPresented: $filterOpen) {
      NavigationStack {
        SignalList {
          Section("Concepts") {
            ForEach(model.taxonomy) { concept in
              Toggle(concept.label, isOn: Binding(get: { tags.contains(concept.id) }, set: { if $0 { tags.insert(concept.id) } else { tags.remove(concept.id) } }))
            }
          }
          Picker("Engineering level", selection: $level) {
            Text("All levels").tag("")
            ForEach(EngineeringLevel.choices, id: \.0) { Text($0.1).tag($0.0) }
          }
          Picker("Completed", selection: $days) { Text("Any time").tag(0); Text("Last 7 days").tag(7); Text("Last 30 days").tag(30) }
          Button("Clear filters") { tags = []; level = ""; days = 0 }
        }.navigationTitle("Filters").toolbar { Button("Done") { filterOpen = false } }
      }
    }
    .task { if model.taxonomy.isEmpty { await model.loadTaxonomy() }; coverage = model.libraryCoverage }
    .task(id: identity + String(model.libraryVersion)) {
      await model.preloadLibrary()
      await load()
    }
    .onChange(of: model.libraryVersion) { _, _ in
      guard let account = model.bootstrap?.account.id, let page = model.librarySnapshots["library:" + account + ":" + identity] else { return }
      questions = page.questions; cursor = page.nextCursor; coverage = model.libraryCoverage
    }
  }
  private func load(more: Bool = false) async {
    guard let account = model.bootstrap?.account.id else { return }
    if !more, let page = model.librarySnapshots["library:" + account + ":" + identity] {
      if questions != page.questions { questions = page.questions }
      cursor = page.nextCursor; loadedIdentity = identity
      return
    }
    let captured = identity, base = query
    let request = UUID(); requestID = request
    loading = true
    defer { if requestID == request { loading = false } }
    let key = "library:" + account + ":" + identity
    if loadedIdentity != captured {
      let cached = model.librarySnapshots[key]
      questions = cached?.questions ?? []; cursor = cached?.nextCursor; failure = nil
      if cached == nil, let data = try? await model.disk.cached(key: key), let page = try? JSONDecoder().decode(LibraryPage.self, from: data), requestID == request, model.bootstrap?.account.id == account {
        questions = page.questions; cursor = page.nextCursor
      }
      guard requestID == request, captured == identity, model.bootstrap?.account.id == account else { return }
      loadedIdentity = captured
    }
    do {
      var url = "library?" + base
      if more, let cursor { var c = URLComponents(); c.queryItems = [URLQueryItem(name: "cursor", value: cursor)]; url += "&" + (c.percentEncodedQuery ?? "") }
      let page = try await model.libraryResponse(path: url)
      try Task.checkCancellation()
      guard requestID == request, captured == identity, model.bootstrap?.account.id == account else { return }
      // An unchanged first page must not discard already loaded history or move the viewport.
      if more {
        questions += page.questions.filter { next in !questions.contains { $0.id == next.id } }
        cursor = page.nextCursor
      } else if page.questions.isEmpty || Array(questions.prefix(page.questions.count)) != page.questions || questions.count <= page.questions.count {
        if questions != page.questions { questions = page.questions }
        cursor = page.nextCursor
      }
      failure = nil
      let snapshot = LibraryPage(questions: questions, nextCursor: cursor)
      model.librarySnapshots[key] = snapshot
      try await model.disk.cache(key: key, data: JSONEncoder().encode(snapshot))
    } catch is CancellationError {} catch {
      guard requestID == request, captured == identity, model.bootstrap?.account.id == account else { return }
      failure = "Couldn’t refresh. Saved results may be incomplete."
    }
  }
}

struct LibraryQuestionView: View {
  var model: AppModel
  var initial: LibraryQuestion
  @State private var detail: LibraryDetail?
  @State private var failure: String?
  @State private var busy = false
  @State private var preview = false
  @State private var preparing = false
  @State private var started: Challenge?
  @State private var startCommand = UUID().uuidString
  init(model: AppModel, initial: LibraryQuestion) {
    self.model = model; self.initial = initial
    _detail = State(initialValue: model.libraryDetailSnapshots["library-detail:" + (model.bootstrap?.account.id ?? "") + ":" + initial.id])
  }
  private var question: LibraryQuestion { detail?.question ?? initial }
  var body: some View {
    SignalList {
      Section {
        Text(question.title).font(.title2.weight(.semibold))
        DisclosureGroup("Original question") { Text(question.prompt).textSelection(.enabled) }
      }
      Section {
        ForEach(question.conceptIds, id: \.self) { id in
          NavigationLink(model.taxonomy.first { $0.id == id }?.label ?? id) { LibraryView(model: model, initialConcept: id) }
        }
      } header: { Text("Concepts") } footer: { Text("Explore related questions in your library.") }
      Section {
        Button((detail?.attempts.contains { $0.lifecycle == "completed" } ?? false) ? "Try again" : "Practise now") { preview = true }
        Button("Practise this concept") { preparing = true }
        if question.eligible { Text("Available in your question pool").foregroundStyle(.secondary) }
        else if detail?.attempts.contains(where: { $0.lifecycle == "skipped" }) == true {
          Button("Add back to pool") { Task { busy = true; defer { busy = false }; do { try await model.queueEligibility(question, eligible: true); if let account = model.bootstrap?.account.id { detail = model.libraryDetailSnapshots["library-detail:" + account + ":" + initial.id] ?? detail } } catch { failure = error.localizedDescription } } }.disabled(busy)
        }
      }
      Section("Attempts") {
        ForEach(detail?.attempts ?? []) { attempt in
          NavigationLink { SessionDetailView(model: model, initial: attempt) } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text(attempt.lifecycle == "completed" ? "Completed" : attempt.lifecycle == "skipped" ? "Skipped" : "In progress")
              if let date = (attempt.completedAt ?? attempt.createdAt).flatMap({ Date.fromAPI($0) }) { Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
            }
          }
        }
        if detail?.nextCursor != nil { Button("Earlier attempts") { Task { await load(more: true) } } }
      }
      if let failure { Text(failure).foregroundStyle(.secondary); Button("Refresh") { Task { await load() } } }
    }.navigationTitle("Question").navigationBarTitleDisplayMode(.inline)
    .task { if detail == nil { await load() } }
    .onChange(of: model.libraryVersion) { _, _ in
      if let account = model.bootstrap?.account.id { detail = model.libraryDetailSnapshots["library-detail:" + account + ":" + initial.id] ?? detail }
    }
    .sheet(isPresented: $preview, onDismiss: { if let started { model.presented = started; self.started = nil } }) {
      NavigationStack {
        ScrollView { VStack(alignment: .leading, spacing: 16) { Text(question.title).font(.title2.weight(.semibold)); Text(question.prompt).textSelection(.enabled); if let failure { Text(failure).foregroundStyle(.secondary) } }.frame(maxWidth: .infinity, alignment: .leading).padding(24) }
          .safeAreaInset(edge: .bottom) {
            Button("Start practice") {
              Task {
                busy = true; defer { busy = false }
                let account = model.bootstrap?.account.id
                do {
                  let attempt = try await model.startLibraryQuestion(question, command: startCommand)
                  guard model.bootstrap?.account.id == account, let account else { return }
                  _ = try await model.disk.load(account: account, challenge: attempt)
                  model.bootstrap?.challenge = attempt; started = attempt; preview = false
                } catch { failure = error.localizedDescription }
              }
            }.buttonStyle(PracticeButtonStyle()).disabled(busy).padding(24).background(AppPalette.background)
          }.navigationTitle("Question preview").navigationBarTitleDisplayMode(.inline).toolbar { Button("Close") { preview = false } }
      }
    }
    .sheet(isPresented: $preparing, onDismiss: { if let started { model.presented = started; self.started = nil } }) {
      QuestionFlow(model: model, recovery: PreparationInput(primaryConceptId: question.primaryConceptId, focus: "System design", kind: "design", difficulty: model.settings.difficulty, engineeringLevel: question.engineeringLevel), onStart: { started = $0 })
    }
  }
  private func load(more: Bool = false) async {
    guard let account = model.bootstrap?.account.id else { return }
    let key = "library-detail:" + account + ":" + initial.id
    if detail == nil, let data = try? await model.disk.cached(key: key), model.bootstrap?.account.id == account {
      detail = try? JSONDecoder().decode(LibraryDetail.self, from: data)
    }
    do {
      var path = "questions/" + initial.id
      if more, let cursor = detail?.nextCursor { var c = URLComponents(); c.queryItems = [URLQueryItem(name: "cursor", value: cursor)]; path += "?" + (c.percentEncodedQuery ?? "") }
      var response = try await model.libraryDetail(id: initial.id, path: path)
      guard model.bootstrap?.account.id == account else { return }
      if more { response.attempts = (detail?.attempts ?? []) + response.attempts }
      detail = response; model.libraryDetailSnapshots[key] = response; failure = nil
      try await model.disk.cache(key: key, data: JSONEncoder().encode(response))
    } catch {
      guard model.bootstrap?.account.id == account, !Task.isCancelled else { return }
      failure = "Couldn’t refresh. Showing saved details if available."
    }
  }
}

struct ReminderPermissionRow: View {
  @State private var denied = false
  @Environment(\.scenePhase) private var phase
  var body: some View {
    Group {
      if denied {
        Link("Enable reminders in iPhone Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
      }
    }.task(id: phase) {
      denied = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }
  }
}

struct PracticeProfileView: View {
  @Bindable var model: AppModel
  @State private var preview: String?
  @State private var previewing = false
  @State private var failure: String?
  private func field(_ path: WritableKeyPath<PracticeProfile, String>) -> Binding<String> {
    Binding(get: { (model.settings.practiceProfile ?? PracticeProfile())[keyPath: path] }, set: { value in
      var profile = model.settings.practiceProfile ?? PracticeProfile()
      var bounded = String(value.prefix(600))
      while bounded.utf16.count > 600 { bounded.removeLast() }
      profile[keyPath: path] = bounded
      model.settings.practiceProfile = profile
      preview = nil
    })
  }
  var body: some View {
    SignalList {
      Section {
        TextField("Preparing for senior interviews, getting better at trade-offs…", text: field(\.goals), axis: .vertical).lineLimit(3...6)
          .accessibilityLabel("Your goals").accessibilityIdentifier("practiceGoals")
      } header: { Text("What are you working toward?") }
      Section {
        TextField("Backend engineer, comfortable with SQL, new to distributed systems…", text: field(\.background), axis: .vertical).lineLimit(3...6)
          .accessibilityLabel("Your background")
      } header: { Text("What should I know about you?") }
      Section {
        TextField("Be direct, use examples, challenge my assumptions. Pirate voice welcome…", text: field(\.preferences), axis: .vertical).lineLimit(3...6)
          .accessibilityLabel("Your preferences").accessibilityIdentifier("practicePreferences")
      } header: { Text("What works for you?") } footer: {
        Text("Goals and background inform practice questions. Preferences shape your interviewer in text and voice. Save with Done in Settings; restart voice to apply changes to an active session.")
      }
      Section {
        Button(previewing ? "Trying it…" : "Try it") {
          let profile = model.settings.practiceProfile ?? PracticeProfile()
          let account = model.bootstrap?.account.id
          previewing = true; failure = nil
          Task {
            defer { previewing = false }
            do {
              let result: PersonalizationPreview = try await model.api.send("settings/preview", method: "POST", body: profile)
              guard account == model.bootstrap?.account.id, profile == (model.settings.practiceProfile ?? PracticeProfile()) else { return }
              preview = result.text
            } catch { if account == model.bootstrap?.account.id { failure = error.localizedDescription } }
          }
        }.disabled(previewing)
        if let preview { Text(preview).textSelection(.enabled) }
        if let failure { Text(failure).foregroundStyle(.secondary) }
      } footer: { Text("A short sample using AI. It won’t save your changes or create a practice session.") }
      Section {
        Button("Reset personalization", role: .destructive) { model.settings.practiceProfile = PracticeProfile(); preview = nil; failure = nil }
      }
    }.navigationTitle("About your practice").navigationBarTitleDisplayMode(.inline)
  }
}
