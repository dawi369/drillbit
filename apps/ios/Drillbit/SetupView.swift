import SwiftUI

@MainActor @Observable final class LearningPlanCoordinator {
  struct Draft: Codable, Equatable {
    var page = 0
    var objective = "learn"
    var level = "mid"
    var targetDate: Date? = nil
  }
  var draft = Draft()
  var saving = false
  var failure: String?
}

struct SetupView: View {
  @Bindable var model: AppModel
  @State private var coordinator = LearningPlanCoordinator()
  @State private var movingForward = true
  @State private var scroll = ScrollPosition(edge: .top)
  @State private var showingQuestion = false
  @State private var startedFirstRep: Challenge?
  @State private var bitCheers = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private let objectives = [("interview","An interview’s coming up"),("learn","I want to get sharper"),("stay_sharp","Just keeping fresh")]
  private let startingPoints = [("junior", "New to system design"), ("mid", "I’ve designed a few systems"), ("senior", "I design systems regularly"), ("staff", "I lead architecture across teams")]
  private let questions = ["What are we drilling for?", "How much system design have you done?"]

  var body: some View {
    @Bindable var coordinator = coordinator
    let page = min(max(coordinator.draft.page, 0), 1)
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        BitAsks(question: questions[page], cheers: bitCheers)
          .pageCascade(0)
        pageContent(coordinator: coordinator)
        if let failure = coordinator.failure { Text(failure).font(.footnote).foregroundStyle(AppPalette.destructive) }
      }
      .id(page)
      .transition(reduceMotion ? .identity : .deal(forward: movingForward))
      .frame(maxWidth: 560, alignment: .leading)
      .padding(24)
      .frame(maxWidth: .infinity)
    }
    .scrollPosition($scroll)
    .clipped()
    .background(AppPalette.background)
    .containerBackground(AppPalette.background, for: .navigation)
    .safeAreaInset(edge: .top, spacing: 0) {
      SignalStepProgress(step: page + 1, total: 2)
        .frame(maxWidth: 560).padding(.horizontal, 24).padding(.top, 16)
        .frame(maxWidth: .infinity)
        .background(AppPalette.background)
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      VStack(spacing: 0) {
        AppPalette.hairline.frame(height: 1)
        HStack(spacing: 12) {
          if page > 0 {
            Button("Back") { move(coordinator, to: 0) }
              .buttonStyle(PracticeButtonStyle(secondary: true))
              .frame(width: 88)
              .transition(.opacity.combined(with: .offset(x: -12)))
              .disabled(coordinator.saving)
          }
          let label = coordinator.saving ? "Opening…" : page == 1 ? "Show me a question" : "Continue"
          Button {
            if page == 1 { Task { await finish(coordinator) } } else { move(coordinator, to: 1) }
          } label: {
            Text(label)
          }.buttonStyle(PracticeButtonStyle()).disabled(coordinator.saving)
            .contentTransition(.opacity)
            .accessibilityLabel(label)
            .accessibilityIdentifier("onboardingContinue")
        }
        .frame(maxWidth: 560).padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : DrillbitMotion.page, value: page > 0)
      }
      .background(AppPalette.background)
    }
    .toolbar(.hidden, for: .navigationBar)
    .task(id: model.bootstrap?.account.id) { await restore(coordinator) }
    .onChange(of: coordinator.draft) { _, _ in Task { await persist(coordinator) } }
    // The first question rises over this page and the interview replaces it; Home appears once the rep is done.
    .sheet(isPresented: $showingQuestion, onDismiss: {
      guard let started = startedFirstRep else { return }
      startedFirstRep = nil
      model.presented = started
    }) {
      // A started first rep resumes; anything else is written fresh from the plan.
      QuestionFlow(model: model, initial: model.bootstrap?.challenge.flatMap { $0.lifecycle == "in_progress" ? $0 : nil }) { startedFirstRep = $0 }
    }
  }

  private func move(_ coordinator: LearningPlanCoordinator, to page: Int) {
    movingForward = page > coordinator.draft.page
    bitCheers += 1
    withAnimation(reduceMotion ? nil : DrillbitMotion.page) {
      coordinator.draft.page = page
    }
    scroll.scrollTo(edge: .top)
  }

  @ViewBuilder private func pageContent(coordinator: LearningPlanCoordinator) -> some View {
    @Bindable var coordinator = coordinator
    if coordinator.draft.page <= 0 {
      VStack(alignment: .leading, spacing: 16) {
        SignalChoiceList(options: objectives.map { SignalChoice(id: $0.0, title: $0.1) },
          isSelected: { coordinator.draft.objective == $0 }, cascadeFrom: 1) { coordinator.draft.objective = $0 }
        if coordinator.draft.objective == "interview" {
          VStack(alignment: .leading, spacing: 12) {
            Toggle("I know the date", isOn: Binding(get: { coordinator.draft.targetDate != nil }, set: { coordinator.draft.targetDate = $0 ? Date() : nil }))
            if let date = coordinator.draft.targetDate {
              DatePicker("Interview date", selection: Binding(get: { date }, set: { coordinator.draft.targetDate = $0 }), in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)
              Text(Self.countdown(to: date))
                .font(.headline)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : DrillbitMotion.selection, value: date)
                .accessibilityIdentifier("interviewCountdown")
            }
          }
          .tint(AppPalette.accent)
          .transition(.opacity)
        }
      }
      .animation(reduceMotion ? nil : DrillbitMotion.reveal, value: coordinator.draft.objective == "interview")
      .animation(reduceMotion ? nil : DrillbitMotion.reveal, value: coordinator.draft.targetDate != nil)
    } else {
      VStack(alignment: .leading, spacing: 12) {
        Text("This sets how deep your questions go. You can change it any time.")
          .font(.subheadline).foregroundStyle(AppPalette.secondary)
          .pageCascade(1)
        SignalChoiceList(options: startingPoints.map { SignalChoice(id: $0.0, title: $0.1) },
          isSelected: { coordinator.draft.level == $0 }, cascadeFrom: 2) { coordinator.draft.level = $0 }
      }
    }
  }

  /// Arithmetic from the person's own date: honest, never a promise.
  static func countdown(to date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
    switch days {
    case ..<1: return "That’s today. One quick rep to warm up."
    case 1: return "That’s tomorrow. One good rep tonight."
    default: return "\(days) days out. A rep a day gets you \(days) shots."
    }
  }

  private func restore(_ coordinator: LearningPlanCoordinator) async {
    guard let account = model.bootstrap?.account.id else { return }
    if let data = try? await model.disk.cached(key: "onboarding-v2:" + account), let draft = try? JSONDecoder().decode(LearningPlanCoordinator.Draft.self, from: data) { coordinator.draft = draft }
    else { coordinator.draft.level = model.settings.selectedLevel }
  }
  private func persist(_ coordinator: LearningPlanCoordinator) async {
    guard let account = model.bootstrap?.account.id, let data = try? JSONEncoder().encode(coordinator.draft) else { return }
    try? await model.disk.cache(key: "onboarding-v2:" + account, data: data)
  }
  private func finish(_ coordinator: LearningPlanCoordinator) async {
    guard !coordinator.saving, model.bootstrap?.account.id != nil else { return }
    coordinator.saving = true; coordinator.failure = nil
    defer { coordinator.saving = false }
    let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: model.settings.timezone); formatter.dateFormat = "yyyy-MM-dd"
    // Role, focus and daily minutes take defaults; Settings and preparation can change them later.
    var plan = model.settings.learningPlan ?? LearningPlan()
    plan.objective = coordinator.draft.objective
    plan.targetDate = coordinator.draft.objective == "interview" ? coordinator.draft.targetDate.map { formatter.string(from: $0) } : nil
    model.settings.learningPlan = plan
    model.settings.selectedLevel = coordinator.draft.level
    do {
      try await model.setFirstUse(FirstUseProgress(stage: .firstRep))
      // The plan syncs now so the first question is written from it; setup completes when that rep does.
      try await model.saveSettingsLocally()
      showingQuestion = true
    } catch { coordinator.failure = error.localizedDescription }
  }
}
