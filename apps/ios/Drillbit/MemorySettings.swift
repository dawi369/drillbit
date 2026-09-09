import SwiftUI

struct MemoryView: View {
  @Bindable var model: AppModel
  var body: some View {
    List {
      if model.memory.sessions.isEmpty {
        ContentUnavailableView(
          "Your practice will live here", systemImage: "book.closed",
          description: Text("Finish a session to see its reflection."))
      } else {
        if !model.memory.patterns.isEmpty {
          Section("Recurring patterns") {
            ForEach(model.memory.patterns) { pattern in
              NavigationLink {
                List(model.memory.sessions.filter { pattern.sessionIds.contains($0.id) }) {
                  session in
                  NavigationLink(session.title) {
                    SessionDetailView(model: model, initial: session)
                  }
                }.navigationTitle(pattern.label)
              } label: {
                VStack(alignment: .leading, spacing: 4) {
                  Text(pattern.label)
                  Text(
                    "\(pattern.sessionIds.count) sessions · \(pattern.kind == "strengths" ? "Strength" : "Practice next")"
                  ).font(.caption).foregroundStyle(.secondary)
                }
              }
            }
          }
        }
        Section("Recent sessions") {
          ForEach(model.memory.sessions.prefix(10)) { session in
            NavigationLink {
              SessionDetailView(model: model, initial: session)
            } label: {
              SessionRow(session: session)
            }
          }
        }
        NavigationLink("All sessions") { HistoryView(model: model) }
      }
    }.navigationTitle("Memory").navigationBarTitleDisplayMode(.inline).refreshable {
      await model.loadMemory()
    }.task {
      await model.loadMemory()
    }
  }
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
    List {
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
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    let challenge = current ?? initial
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        Text(challenge.title).font(.title.weight(.semibold))
        Text(challenge.prompt).foregroundStyle(.secondary)
        if let answer = challenge.session?.answer {
          Text("Your answer").font(.headline)
          Text(answer).textSelection(.enabled)
          ShareLink("Copy or share answer", item: answer)
        }
        AssistanceSummary(challenge: challenge)
        if let reflection = challenge.reflection {
          ReflectionContent(reflection: reflection)
        } else {
          Text("Feedback is pending. You can retry failed feedback from Today.").foregroundStyle(
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
    }.navigationTitle("Session").navigationBarTitleDisplayMode(.inline)
      .toolbar { Button("Delete", systemImage: "trash", role: .destructive) { deleting = true } }
      .confirmationDialog("Delete this session and its learning evidence?", isPresented: $deleting)
    {
      Button("Delete session", role: .destructive) {
        Task {
          await model.perform {
            let _: EmptyResponse = try await model.api.send(
              "challenges/" + challenge.id, method: "DELETE")
            await model.loadMemory()
            dismiss()
          }
        }
      }
    }
      .task {
        guard !model.fixture else { return }
        await model.perform { current = try await model.api.send("challenges/" + initial.id) }
      }
  }
}
struct SettingsView: View {
  @Bindable var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var deleting = false
  @State private var discarding = false
  @State private var saving = false
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
    Form {
      Section("Practice") {
        NavigationLink { FocusView(model: model) } label: {
          LabeledContent("Focus") { Text(model.settings.focus).lineLimit(2) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Focus, \(model.settings.focus)")
        }
        Picker("Engineering level", selection: $model.settings.selectedLevel) {
          ForEach(EngineeringLevel.choices, id: \.0) { Text($0.1).tag($0.0) }
        }
        DatePicker("Daily challenge", selection: time, displayedComponents: .hourAndMinute)
        NavigationLink { TimeZoneSelectionView(selection: $model.settings.timezone) } label: {
          LabeledContent("Time zone", value: TimeZoneSelectionView.label(model.settings.timezone))
        }
        Toggle("Daily reminder", isOn: $model.settings.reminderEnabled)
      }
      Section { NavigationLink("LLM provider") { AIAccessView(model: model) } }
      Section("Account") {
        Button("Sign out") {
          Task {
            await model.perform {
              try await model.signOut()
              dismiss()
            }
            if model.hasPendingWrites { discarding = true }
          }
        }
        Button("Delete account", role: .destructive) { deleting = true }
      }
    }.navigationTitle("Settings")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            Task {
              saving = true
              defer { saving = false }
              await model.perform {
                try await model.updateSettings()
                dismiss()
              }
            }
          }.disabled(saving)
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
  }
}
struct FocusView: View {
  @Bindable var model: AppModel
  var body: some View {
    Form {
      Section("Start with a focus") {
        ForEach(PracticeFocus.choices, id: \.self) {
          focus in
          Button {
            model.settings.focus = focus
          } label: {
            HStack {
              Text(focus)
              Spacer()
              if model.settings.focus == focus { Image(systemName: "checkmark") }
            }
          }
        }
      }
      Section("Make it specific") {
        TextEditor(text: $model.settings.focus).frame(minHeight: 160).accessibilityLabel(
          "Practice focus")
      }
    }.navigationTitle("Focus")
  }
}
struct AIAccessView: View {
  @Bindable var model: AppModel
  @State private var key = ""
  @State private var suffix: String?
  @State private var validating = false
  var body: some View {
    Form {
      Section {
        Picker("Use", selection: $model.settings.aiMode) {
          Text("Included AI").tag("managed")
          Text("My OpenRouter key").tag("byok")
        }
      }
      Section("OpenRouter") {
        if let suffix = suffix ?? model.bootstrap?.credential?.suffix {
          Label("Key ending in \(suffix)", systemImage: "checkmark.circle").foregroundStyle(
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

struct SetupView: View {
  @Bindable var model: AppModel
  @State private var saving = false
  var body: some View {
    Form {
      Section {
        Text("Choose what you want to think through. You can change this at any time.")
          .foregroundStyle(.secondary)
      }
      Section("Your practice") {
        NavigationLink {
          FocusView(model: model)
        } label: {
          LabeledContent("Focus", value: model.settings.focus)
        }
        Picker("Engineering level", selection: $model.settings.selectedLevel) {
          ForEach(EngineeringLevel.choices, id: \.0) { Text($0.1).tag($0.0) }
        }
      }
      Section {
        Button("Start practicing") {
          Task {
            saving = true
            defer { saving = false }
            await model.perform {
              model.settings.onboardingComplete = true
              do {
                try await model.updateSettings()
                await model.generate()
              } catch {
                model.settings.onboardingComplete = false
                throw error
              }
            }
          }
        }.disabled(
          saving || model.settings.focus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }.navigationTitle("Make it your practice")
  }
}

struct AssistanceSummary: View {
  var challenge: Challenge
  var body: some View {
    Text(
      !(challenge.adoptions ?? []).isEmpty
        ? "Practised with an assisted draft"
        : (challenge.help ?? []).contains(where: { $0.body != nil })
          || !(challenge.turns ?? []).isEmpty || challenge.example != nil
          ? "Practised with help" : "No help used"
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
    List {
      Button("Use current device time zone") { selection = TimeZone.current.identifier; dismiss() }
      ForEach(Array(Set(Self.zones + [selection, TimeZone.current.identifier])).sorted().filter { search.isEmpty || Self.label($0).localizedCaseInsensitiveContains(search) || $0.localizedCaseInsensitiveContains(search) }, id: \.self) { zone in
        Button { selection = zone; dismiss() } label: {
          HStack { Text(Self.label(zone)).foregroundStyle(.primary); Spacer(); if selection == zone { Image(systemName: "checkmark") } }
        }.accessibilityAddTraits(selection == zone ? .isSelected : [])
      }
    }.searchable(text: $search).navigationTitle("Time zone").navigationBarTitleDisplayMode(.inline)
  }
}
