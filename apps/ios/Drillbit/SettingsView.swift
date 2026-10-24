import StoreKit
import SwiftUI
import UserNotifications

struct SettingsView: View {
  @Bindable var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var deleting = false
  @State private var showingManageSubscriptions = false
  @State private var discarding = false
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
  private var plan: Binding<LearningPlan> { Binding(get: { model.settings.learningPlan ?? LearningPlan() }, set: { model.settings.learningPlan = $0 }) }
  private static let objectives = [("interview", "An interview’s coming up"), ("learn", "Getting sharper"), ("stay_sharp", "Keeping fresh")]
  private static let modes = [("voice", "Talking it out"), ("text", "Typing"), ("mix", "Depends on the day")]
  /// What a student changes after week one, and nothing else. The plan's finer knobs, the free-text profile, the
  /// provider key and the export live under Developer; the data behind them is untouched.
  var body: some View {
    SignalList {
      Section("Practice") {
        Picker("Engineering level", selection: $model.settings.selectedLevel) {
          ForEach(EngineeringLevel.choices, id: \.0) { Text($0.1).tag($0.0) }
        }
        Picker("Practice", selection: Binding(get: { model.practiceMode }, set: { model.practiceMode = $0 })) {
          ForEach(Self.modes, id: \.0) { Text($0.1).tag($0.0) }
        }.accessibilityIdentifier("practiceModePicker")
        Picker("Here for", selection: plan.objective) { ForEach(Self.objectives, id: \.0) { Text($0.1).tag($0.0) } }
          .onChange(of: plan.wrappedValue.objective) { _, value in if value != "interview" { var updated = plan.wrappedValue; updated.targetDate = nil; plan.wrappedValue = updated } }
        if plan.wrappedValue.objective == "interview" {
          Toggle("I know the date", isOn: Binding(get: { plan.wrappedValue.targetDate != nil }, set: { enabled in
            var value = plan.wrappedValue; value.targetDate = enabled ? LearningPlanSettingsView.formatted(Date(), timezone: model.settings.timezone) : nil; plan.wrappedValue = value
          }))
          if plan.wrappedValue.targetDate != nil {
            DatePicker("Interview date", selection: Binding(get: { LearningPlanSettingsView.parsed(plan.wrappedValue.targetDate, timezone: model.settings.timezone) ?? Date() }, set: { date in
              var value = plan.wrappedValue; value.targetDate = LearningPlanSettingsView.formatted(date, timezone: model.settings.timezone); plan.wrappedValue = value
            }), in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)
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
        // The reminder time only matters while reminders are on; the time zone also sets the practice day.
        if model.settings.reminderEnabled {
          DatePicker("Reminder time", selection: time, displayedComponents: .hourAndMinute)
        }
        ReminderPermissionRow()
      }
      Section("Plan") {
        LabeledContent("Plan", value: model.isPro ? "Pro" : "Free").accessibilityIdentifier("planRow")
        if model.isPro {
          Button("Manage subscription") { showingManageSubscriptions = true }
            .manageSubscriptionsSheet(isPresented: $showingManageSubscriptions)
        } else {
          Text(model.repsLeftLine ?? "3 free reps a day, voice to taste. Pro has no limits.").font(.footnote).foregroundStyle(.secondary)
          Button("See Pro") { PlanCoordinator.shared.register(.practiceRep) { await model.refresh() } }.accessibilityIdentifier("settingsSeePro")
          Button("Restore purchases") { Task { try? await AppStore.sync(); await PlanCoordinator.shared.syncEntitlements() } }
        }
      }
      Section("Account") {
        Picker("Appearance", selection: $appearance) {
          Text("System").tag("system")
          Text("Light").tag("light")
          Text("Dark").tag("dark")
        }.pickerStyle(.menu).accessibilityIdentifier("appearancePicker")
        Button("Sign out") {
          Task {
            await model.perform {
              try await model.signOut()
              dismiss()
            }
            if model.hasPendingWrites || model.pendingSettings != nil { discarding = true }
          }
        }
        // Dialogs attach to their buttons so iOS presents them from the tapped row.
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
        Button("Delete account", role: .destructive) { deleting = true }
          .alert("Delete your account?", isPresented: $deleting) {
            Button("Delete", role: .destructive) {
              Task {
                await model.perform {
                  let _: [String: String] = try await model.api.send(
                    "account", method: "DELETE", command: UUID().uuidString)
                  try await model.signOut(discard: true, deleting: true)
                  dismiss()
                }
              }
            }
            Button("Cancel", role: .cancel) {}
          } message: {
            Text("This permanently deletes your account, practice, feedback, Recall and saved key. There’s no undo.")
          }
      }
      if model.bootstrap?.capabilities?.developerTools == true || model.fixture {
        DeveloperSettingsSection(model: model, appearance: $appearance, dismiss: { dismiss() })
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
  }
}
private struct DeveloperSettingsSection: View {
  @Bindable var model: AppModel
  @Binding var appearance: String
  var dismiss: () -> Void
  @State private var confirming: Reset?
  @State private var planPreview = AppModel.PlanPreview.live
  @State private var coachReplayed = false
  enum Reset: String, Identifiable { case practice, everything, reinvite; var id: String { rawValue } }

  var body: some View {
    // Parked from the main list for the MVP: still wired, just out of a student's way.
    Section("Developer · parked settings") {
      NavigationLink("Learning plan") { LearningPlanSettingsView(model: model) }
      NavigationLink("About your practice") { PracticeProfileView(model: model) }
      NavigationLink("LLM provider") { AIAccessView(model: model) }
      NavigationLink { TimeZoneSelectionView(selection: $model.settings.timezone) } label: {
        HStack(spacing: 8) {
          Text("Time zone")
          Spacer(minLength: 8)
          Text(TimeZoneSelectionView.label(model.settings.timezone)).foregroundStyle(.secondary).lineLimit(1)
        }
      }
      Toggle(isOn: $model.settings.formatsQuestions) {
        Text("Formatted questions")
        Text("Bold, italics and code blocks where they help")
      }.accessibilityIdentifier("questionFormatting")
      NavigationLink("Export practice data") { PracticeExportView(model: model) }
    }
    Section {
      Picker("Plan preview", selection: $planPreview) {
        Text("Live").tag(AppModel.PlanPreview.live)
        Text("Free · 2 reps left").tag(AppModel.PlanPreview.freeReps)
        Text("Free · spent").tag(AppModel.PlanPreview.freeSpent)
      }
      .onChange(of: planPreview) { _, value in model.previewPlan(value) }
      Button(coachReplayed ? "Tips will show again" : "Replay first-run tips") {
        for mark in CoachMark.allCases { UserDefaults.standard.removeObject(forKey: mark.storageKey) }
        coachReplayed = true
      }
      .disabled(coachReplayed)
      resetButton("Replay onboarding questions", .practice)
      resetButton("Back to the invite screen", .reinvite)
      resetButton("Reset Drillbit", .everything, role: .destructive)
    } header: {
      Text("Developer")
    } footer: {
      Text("Plan preview changes only what this device shows until the next refresh. Replay onboarding keeps you signed in and clears practice. Reset Drillbit wipes practice and device memory and signs you out, so the next launch is the very first one.")
    }
  }
  /// The dialog hangs off its own button, so the sheet points at what was tapped rather than the middle of the screen.
  private func resetButton(_ title: String, _ reset: Reset, role: ButtonRole? = nil) -> some View {
    Button(title, role: role) { confirming = reset }
      .confirmationDialog(label(reset), isPresented: Binding(get: { confirming == reset }, set: { if !$0 { confirming = nil } })) {
        Button(label(reset), role: .destructive) { run(reset) }
        Button("Cancel", role: .cancel) {}
      } message: { Text(message(reset)) }
  }

  private func label(_ reset: Reset) -> String {
    switch reset {
    case .practice: "Replay onboarding"
    case .reinvite: "Back to invite"
    case .everything: "Reset Drillbit"
    }
  }
  private func message(_ reset: Reset) -> String {
    switch reset {
    case .practice: "Removes your practice, Recall history, preferences, reminders and LLM key. You stay signed in and go straight to the setup questions."
    case .reinvite: "Everything in Replay onboarding, then signs you out and puts the account back behind the invite screen. You’ll need an unredeemed invite code."
    case .everything: "Removes your practice, Recall history, preferences, reminders and LLM key, forgets the walkthrough and tips on this device, and signs you out. The next launch is the first launch."
    }
  }
  private func run(_ reset: Reset) {
    Task {
      await model.perform {
        switch reset {
        case .practice: try await model.resetDeveloperPractice()
        case .reinvite: try await model.resetDeveloperEverything(reinvite: true)
        case .everything: try await model.resetDeveloperEverything(reinvite: false)
        }
        appearance = "dark"
        dismiss()
      }
    }
  }
}
struct LearningPlanSettingsView: View {
  @Bindable var model: AppModel
  private let objectives = [("interview","An interview’s coming up"),("learn","I want to get sharper"),("stay_sharp","Just keeping fresh")]
  private let roles = [("general","A mix of things"),("backend","Backend services"),("frontend","Web frontends"),("full_stack","Full-stack products"),("platform","Platforms and infrastructure"),("data","Data systems"),("mobile","Mobile apps")]
  private let areas = PracticeAreaGroup.all.map { ($0.id, $0.title) }
  private var plan: Binding<LearningPlan> { Binding(get: { model.settings.learningPlan ?? LearningPlan() }, set: { model.settings.learningPlan = $0 }) }
  var body: some View {
    SignalList {
      Picker("Current priority", selection: plan.objective) { ForEach(objectives, id: \.0) { Text($0.1).tag($0.0) } }
        .onChange(of: plan.wrappedValue.objective) { _, value in if value != "interview" { var updated = plan.wrappedValue; updated.targetDate = nil; plan.wrappedValue = updated } }
      Picker("You build", selection: plan.roleTrack) { ForEach(roles, id: \.0) { Text($0.1).tag($0.0) } }
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
  static func formatted(_ date: Date, timezone: String) -> String { let value = DateFormatter(); value.calendar = Calendar(identifier: .gregorian); value.locale = Locale(identifier: "en_US_POSIX"); value.timeZone = TimeZone(identifier: timezone); value.dateFormat = "yyyy-MM-dd"; return value.string(from: date) }
  static func parsed(_ text: String?, timezone: String) -> Date? { guard let text else { return nil }; let value = DateFormatter(); value.calendar = Calendar(identifier: .gregorian); value.locale = Locale(identifier: "en_US_POSIX"); value.timeZone = TimeZone(identifier: timezone); value.dateFormat = "yyyy-MM-dd"; return value.date(from: text) }
  private func formatted(_ date: Date) -> String { Self.formatted(date, timezone: model.settings.timezone) }
  private func parsed(_ text: String?) -> Date? { Self.parsed(text, timezone: model.settings.timezone) }
}
struct AIAccessView: View {
  @Bindable var model: AppModel
  @State private var key = ""
  @State private var modelID = ""
  @State private var saved: Bootstrap.Credential?
  @State private var validating = false
  private var credential: Bootstrap.Credential? { saved ?? model.bootstrap?.credential }
  var body: some View {
    SignalList {
      Section {
        Picker("Use", selection: $model.settings.aiMode) {
          Text("Included AI").tag("managed")
          Text("My OpenRouter key").tag("byok")
        }
      }
      Section {
        if let credential {
          Label("Key ending in \(credential.suffix)", systemImage: AppIcon.completed.rawValue).foregroundStyle(
            AppPalette.success)
          if let name = credential.model {
            LabeledContent("Model", value: name)
          }
        }
        SecureField(credential == nil ? "OpenRouter key" : "Replace with a new key", text: $key).textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .accessibilityIdentifier("openRouterKey")
        // The server falls back to its default model when none is given.
        TextField("Model ID", text: $modelID, prompt: Text("Model ID (optional, e.g. openai/gpt-6-luna)"))
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .keyboardType(.asciiCapable)
          .accessibilityIdentifier("openRouterModel")
        Button(validating ? "Checking key…" : "Validate and save") {
          Task {
            validating = true
            defer { validating = false }
            await model.perform {
              let trimmedModel = modelID.trimmingCharacters(in: .whitespaces)
              let result: Bootstrap.Credential = try await model.api.send(
                "credential", method: "PUT",
                body: KeyInput(key: key, model: trimmedModel.isEmpty ? nil : trimmedModel))
              saved = result
              model.bootstrap?.credential = result
              key = ""
              modelID = ""
              model.settings.aiMode = "byok"
              try await model.updateSettings()
            }
          }
        }.disabled(key.isEmpty || validating)
          .accessibilityIdentifier("validateKey")
        if credential != nil {
          Button("Remove key", role: .destructive) {
            Task {
              await model.perform {
                let _: EmptyResponse = try await model.api.send("credential", method: "DELETE")
                saved = nil
                model.bootstrap?.credential = nil
                if model.settings.aiMode == "byok" { model.settings.aiMode = "managed"; try await model.updateSettings() }
                await model.refresh()
              }
            }
          }
          .accessibilityIdentifier("removeKey")
        }
      } header: {
        Text("OpenRouter")
      } footer: {
        if model.settings.aiMode == "byok" && credential == nil {
          Text("Your key is set to be used, but none is saved yet. Add one, or switch back to Included AI.")
        }
      }
      Section {
        Text(
          "Your key is encrypted on Drillbit's servers so daily preparation can work while the app is closed. A rejected key never falls back to included AI. Removing it switches you back to Included AI."
        ).font(.footnote).foregroundStyle(.secondary)
      }
    }.navigationTitle("LLM provider")
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
  private func field(_ path: WritableKeyPath<PracticeProfile, String>) -> Binding<String> {
    Binding(get: { (model.settings.practiceProfile ?? PracticeProfile())[keyPath: path] }, set: { value in
      var profile = model.settings.practiceProfile ?? PracticeProfile()
      var bounded = String(value.prefix(600))
      while bounded.utf16.count > 600 { bounded.removeLast() }
      profile[keyPath: path] = bounded
      model.settings.practiceProfile = profile
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
        Button("Reset personalization", role: .destructive) { model.settings.practiceProfile = PracticeProfile() }
      }
    }.navigationTitle("About your practice").navigationBarTitleDisplayMode(.inline)
  }
}
