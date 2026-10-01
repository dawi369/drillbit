import SwiftUI
import UserNotifications

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
  @State private var hasMoved = false
  @State private var scroll = ScrollPosition(edge: .top)
  @State private var warmingUp = false
  @State private var startedWarmUp: Challenge?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private let objectives = [("interview","An upcoming interview"),("learn","Strengthen up my skills"),("stay_sharp","Keep my skills fresh")]
  private let roles = [("general","A mix of things"),("backend","Backend services"),("frontend","Web frontends"),("full_stack","Full-stack products"),("platform","Platforms and infrastructure"),("data","Data systems"),("mobile","Mobile apps")]
  private let areas = PracticeAreaGroup.all.map { ($0.id, $0.title) }
  private let startingPoints = [("junior", "New to system design"), ("mid", "I’ve designed a few systems"), ("senior", "I design systems regularly"), ("staff", "I lead architecture across teams")]

  var body: some View {
    @Bindable var coordinator = coordinator
    GeometryReader { geometry in
      ScrollView {
        VStack(alignment: .leading, spacing: 32) {
          if coordinator.draft.page == -1 {
            SetupIntroduction(animatesIn: !hasMoved)
              .frame(minHeight: max(0, geometry.size.height - 48))
          } else {
            Text(title(for: coordinator.draft.page))
              .font(.largeTitle.weight(.semibold))
              .fixedSize(horizontal: false, vertical: true)
              .accessibilityAddTraits(.isHeader)
              .pageCascade(0)
            pageContent(coordinator: coordinator)
            if let note = coordinator.reminderNote { Text(note).font(.footnote).foregroundStyle(AppPalette.secondary) }
            if let failure = coordinator.failure { Text(failure).font(.footnote).foregroundStyle(AppPalette.destructive) }
          }
        }
        .id(coordinator.draft.page)
        .transition(reduceMotion ? .identity : .deal(forward: movingForward))
        .frame(maxWidth: 560, alignment: .leading)
        .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 24)
        .frame(maxWidth: .infinity)
      }
      .scrollPosition($scroll)
      .scrollDismissesKeyboard(.interactively)
    }.clipped()
    .background(AppPalette.background)
    .containerBackground(AppPalette.background, for: .navigation)
    .safeAreaInset(edge: .top, spacing: 0) {
      if coordinator.draft.page >= 0 {
        SignalStepProgress(step: coordinator.draft.page + 1, total: 5, drill: true)
          .frame(maxWidth: 560).padding(.horizontal, 24).padding(.top, 16)
          .frame(maxWidth: .infinity)
          .background(AppPalette.background)
          .transition(.opacity)
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      VStack(spacing: 0) {
        AppPalette.hairline.frame(height: 1)
        HStack(spacing: 12) {
          if coordinator.draft.page >= 0 {
            Button("Back") { move(coordinator, to: coordinator.draft.page - 1) }
              .buttonStyle(PracticeButtonStyle(secondary: true))
              .frame(width: 88)
              .transition(.opacity.combined(with: .offset(x: -12)))
              .disabled(coordinator.saving || reminderPermissionPending)
          }
          Button {
            if coordinator.draft.page == 4 { Task { await finish(coordinator) } }
            else { move(coordinator, to: coordinator.draft.page + 1) }
          } label: {
            HStack(spacing: 8) {
              Text(coordinator.saving ? "Opening…" : coordinator.draft.page == -1 ? "Let’s begin" : coordinator.draft.page == 4 ? "Try the warm-up" : "Continue")
              if coordinator.draft.page == 4 { Image(systemName: "arrow.right").accessibilityHidden(true) }
            }
            .padding(.vertical, coordinator.draft.page == 4 ? 8 : 0)
          }.buttonStyle(PracticeButtonStyle()).disabled(coordinator.saving || reminderPermissionPending)
            .contentTransition(.opacity)
            .accessibilityLabel(coordinator.saving ? "Opening…" : coordinator.draft.page == -1 ? "Let’s begin" : coordinator.draft.page == 4 ? "Try the warm-up" : "Continue")
            .accessibilityIdentifier("onboardingContinue")
            .sensoryFeedback(.success, trigger: coordinator.draft.page == 4) { _, reached in reached }
        }
        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 8)
        .animation(reduceMotion ? nil : DrillbitMotion.page, value: coordinator.draft.page >= 0)
      }
      .background(AppPalette.background)
    }
    .toolbar(.hidden, for: .navigationBar)
    .task(id: model.bootstrap?.account.id) { await restore(coordinator) }
    .onChange(of: coordinator.draft) { _, _ in Task { await persist(coordinator) } }
    // The warm-up preview rises over this page, and the interview replaces it; Home only appears once the warm-up is done.
    .sheet(isPresented: $warmingUp, onDismiss: {
      guard let started = startedWarmUp else { return }
      startedWarmUp = nil
      model.presented = started
    }) {
      QuestionFlow(model: model, initial: model.bootstrap?.challenge.flatMap { $0.isWarmUp && $0.isActive ? $0 : nil }) { startedWarmUp = $0 }
    }
  }

  private func move(_ coordinator: LearningPlanCoordinator, to page: Int) {
    movingForward = page > coordinator.draft.page
    hasMoved = true
    withAnimation(reduceMotion ? nil : DrillbitMotion.page) {
      coordinator.draft.page = page
    }
    scroll.scrollTo(edge: .top)
  }

  @ViewBuilder private func pageContent(coordinator: LearningPlanCoordinator) -> some View {
    @Bindable var coordinator = coordinator
    switch coordinator.draft.page {
    case 0:
      VStack(alignment: .leading, spacing: 12) {
        Text("Your priority right now. You’ll learn and practise in every path.")
          .font(.subheadline).foregroundStyle(AppPalette.secondary)
          .pageCascade(1)
        SignalChoiceList(options: objectives.map { SignalChoice(id: $0.0, title: $0.1) },
          isSelected: { coordinator.draft.objective == $0 }, cascadeFrom: 2) { coordinator.draft.objective = $0 }
      }
    case 1:
      VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .leading, spacing: 12) {
          Text("What do you usually build?").font(.headline)
          Menu {
            Picker("Your work", selection: $coordinator.draft.roleTrack) {
              ForEach(roles, id: \.0) { option in Text(option.1).tag(option.0) }
            }
          } label: {
            HStack(spacing: 8) {
              Text(roles.first { $0.0 == coordinator.draft.roleTrack }?.1 ?? "A mix of things")
                .foregroundStyle(AppPalette.primary)
              Spacer(minLength: 8)
              Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold))
                .foregroundStyle(AppPalette.secondary)
            }
            .padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 56)
            .background(AppPalette.inset, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
          }
          .accessibilityLabel("Your work")
          .accessibilityValue(roles.first { $0.0 == coordinator.draft.roleTrack }?.1 ?? "A mix of things")
        }
        .pageCascade(1)
        VStack(alignment: .leading, spacing: 12) {
          Text("How familiar is system design?").font(.headline)
          Text("This sets the depth of your questions. You can change it later.").font(.subheadline).foregroundStyle(AppPalette.secondary)
          SignalChoiceList(options: startingPoints.map { SignalChoice(id: $0.0, title: $0.1) },
            isSelected: { coordinator.draft.level == $0 }, cascadeFrom: 3) { coordinator.draft.level = $0 }
        }
        .pageCascade(2)
      }
    case 2:
      VStack(alignment: .leading, spacing: 12) {
        Text("Explore everything, or pick up to three areas.").font(.subheadline).foregroundStyle(AppPalette.secondary)
          .pageCascade(1)
        SignalChoiceList(options: [SignalChoice(id: "", title: "A bit of everything")] + areas.map { SignalChoice(id: $0.0, title: $0.1) },
          isSelected: { $0.isEmpty ? coordinator.draft.weakAreas.isEmpty : coordinator.draft.weakAreas.contains($0) },
          isDisabled: { !$0.isEmpty && !coordinator.draft.weakAreas.contains($0) && coordinator.draft.weakAreas.count == 3 }, cascadeFrom: 2) { id in
          if id.isEmpty { coordinator.draft.weakAreas = [] }
          else if coordinator.draft.weakAreas.contains(id) { coordinator.draft.weakAreas.remove(id) }
          else if coordinator.draft.weakAreas.count < 3 { coordinator.draft.weakAreas.insert(id) }
        }
      }
    case 3:
      VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .leading, spacing: 12) {
          SignalEyebrow(text: "Daily commitment")
          SignalChoiceList(options: [5, 10, 15, 20].map { SignalChoice(id: $0, title: "\($0) minutes") },
            isSelected: { coordinator.draft.dailyGoalMinutes == $0 }, cascadeFrom: 1) { coordinator.draft.dailyGoalMinutes = $0 }
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
            DatePicker("Reminder time", selection: reminderTime(coordinator), displayedComponents: .hourAndMinute)
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
        .animation(reduceMotion ? nil : DrillbitMotion.reveal, value: coordinator.draft.reminderEnabled)
        .animation(reduceMotion ? nil : DrillbitMotion.reveal, value: coordinator.draft.targetDate != nil)
        .pageCascade(5)
      }
    default:
      summary(coordinator.draft)
    }
  }

  private func summary(_ draft: LearningPlanCoordinator.Draft) -> some View {
    let pace = "\(draft.dailyGoalMinutes) minutes a day"
    let headline = draft.objective == "interview" ? "Interview prep, \(pace)." : draft.objective == "stay_sharp" ? "Staying sharp, \(pace)." : "Leveling up, \(pace)."
    return VStack(alignment: .leading, spacing: 16) {
      Text(headline).font(.title2.weight(.semibold)).pageCascade(1)
      Group {
        LabeledContent("Goal", value: objectives.first { $0.0 == draft.objective }?.1 ?? "Learn system design").pageCascade(2)
        Divider()
        LabeledContent("You build", value: roles.first { $0.0 == draft.roleTrack }?.1 ?? "A mix of things").pageCascade(3)
        Divider()
        LabeledContent("Experience", value: startingPoints.first { $0.0 == draft.level }?.1 ?? "I’ve designed a few systems").pageCascade(4)
        Divider()
        LabeledContent("Focus", value: draft.weakAreas.isEmpty ? "A bit of everything" : draft.weakAreas.compactMap { id in areas.first { $0.0 == id }?.1 }.sorted().joined(separator: ", ")).pageCascade(5)
      }
      Text("First up is a warm-up question. It doesn’t count, so just try stuff.")
        .font(.subheadline).foregroundStyle(AppPalette.secondary).padding(.top, 12)
        .pageCascade(6)
    }
  }
  private func title(for page: Int) -> String { ["What brings you here?","Where are you starting?","What sparks your curiosity?","Find your rhythm.","Here’s your plan."][max(0, min(page,4))] }
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
    guard !coordinator.saving, model.bootstrap?.account.id != nil else { return }
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
      // The plan syncs now so the warm-up is generated from it; setup completes when the warm-up does.
      try await model.saveSettingsLocally()
      warmingUp = true
    } catch { coordinator.failure = error.localizedDescription }
  }
}

private struct SetupIntroduction: View {
  var animatesIn = true
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      DrillbitLogo(compact: true).signalEntrance(0, active: animatesIn)
      Spacer(minLength: 40)
      SignalPresence(density: 640)
        .frame(maxWidth: 320, maxHeight: 320)
        .frame(maxWidth: .infinity)
        .frame(height: 280)
        .signalEntrance(1, active: animatesIn)
      Spacer(minLength: 40)
      VStack(alignment: .leading, spacing: 16) {
        SignalEyebrow(text: "Welcome to Drillbit")
        Text("Let’s shape\nyour practice.")
          .font(.largeTitle.weight(.semibold))
          .tracking(-0.8)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityAddTraits(.isHeader)
        Text("Five quick questions tune your first interview. It takes about a minute, and you can change anything later.")
          .font(.body)
          .foregroundStyle(AppPalette.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .signalEntrance(2, active: animatesIn)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
