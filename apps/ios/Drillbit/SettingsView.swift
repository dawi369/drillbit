import SwiftUI
import UserNotifications

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
        NavigationLink { TimeZoneSelectionView(selection: $model.settings.timezone) } label: {
          HStack(spacing: 8) {
            Text("Time zone")
            Spacer(minLength: 8)
            Text(TimeZoneSelectionView.label(model.settings.timezone))
              .foregroundStyle(.secondary).lineLimit(1)
          }
        }
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
