import SwiftUI

@MainActor @Observable final class LearningPlanCoordinator {
  struct Draft: Codable, Equatable {
    var page = 0
    var taste: String? = nil
    var situation = "studying"
    var level = "junior"
    var objective = "learn"
    var targetDate: Date? = nil
    var mode = "voice"
    var minutes = 10
  }
  var draft = Draft()
  var saving = false
  var failure: String?
}

/// One answer per card. Built for someone who has never designed a system: plain words, a reaction to every tap, and a
/// taste of the real thing before any question about them.
struct SetupView: View {
  @Bindable var model: AppModel
  /// Called with the finished draft; the host signs in (if needed), applies it, then opens the first question.
  var onFinish: (LearningPlanCoordinator.Draft) -> Void
  @State private var coordinator = LearningPlanCoordinator()
  @State private var movingForward = true
  @State private var bitCheers = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  static let pageCount = 7

  struct Option: Identifiable { let id: String; let title: String; let detail: String; let symbol: String }
  static let tastes = [
    Option(id: "server", title: "The server", detail: "It’s one machine doing everything", symbol: "cpu"),
    Option(id: "database", title: "The database", detail: "Everyone wants the same rows at once", symbol: "externaldrive"),
    Option(id: "unsure", title: "Honestly, no idea yet", detail: "That’s the whole point of being here", symbol: "questionmark.circle"),
  ]
  static let situations = [
    Option(id: "studying", title: "Still studying", detail: "CS degree, courses, side projects", symbol: "graduationcap"),
    Option(id: "bootcamp", title: "Bootcamp or self-taught", detail: "I can build things, the theory is patchy", symbol: "book"),
    Option(id: "firstjob", title: "On the job", detail: "Tickets, yes. Designing a whole system, no", symbol: "laptopcomputer"),
    Option(id: "interviewing", title: "Interviews are happening", detail: "And system design rounds scare me", symbol: "calendar.badge.clock"),
  ]
  static let levels = [
    Option(id: "intern", title: "I freeze", detail: "I don’t know where to even start", symbol: "snowflake"),
    Option(id: "junior", title: "I know the words", detail: "Cache, queue, shard. Not how they fit", symbol: "puzzlepiece"),
    Option(id: "mid", title: "I can wing it", detail: "Shakily. I lose the thread halfway", symbol: "figure.walk"),
    Option(id: "senior", title: "I’ve done real ones", detail: "I want sharper answers under pressure", symbol: "bolt"),
  ]
  static let wins = [
    Option(id: "interview", title: "Not panic in an interview", detail: "Walk in with a way to start", symbol: "person.wave.2"),
    Option(id: "learn", title: "Understand how big apps work", detail: "Why Instagram doesn’t fall over", symbol: "lightbulb"),
    Option(id: "stay_sharp", title: "Stay sharp", detail: "A rep now and then so it sticks", symbol: "flame"),
  ]
  static let modes = [
    Option(id: "voice", title: "Talking it out", detail: "Like the real interview. The interviewer talks back", symbol: "waveform"),
    Option(id: "text", title: "Typing, at my own pace", detail: "Think first, then write it down", symbol: "keyboard"),
    Option(id: "mix", title: "Depends on the day", detail: "Both count. Switch any time", symbol: "arrow.left.arrow.right"),
  ]
  static let paces = [
    Option(id: "5", title: "5 minutes, most days", detail: "One small decision a day", symbol: "hare"),
    Option(id: "10", title: "10 minutes, most days", detail: "A real question, not the whole system", symbol: "figure.run"),
    Option(id: "20", title: "20 minutes, a few times a week", detail: "Proper rounds, fewer of them", symbol: "tortoise"),
  ]
  private let questions = [
    "Quick one. No wrong answers.",
    "Where are you right now?",
    "When someone says ‘system design’, what happens?",
    "Four weeks from now, what’s the win?",
    "How do you think best?",
    "Be honest. How much time?",
    "Here’s where we start.",
  ]

  var body: some View {
    @Bindable var coordinator = coordinator
    let page = min(max(coordinator.draft.page, 0), Self.pageCount - 1)
    let last = page == Self.pageCount - 1
    VStack(alignment: .leading, spacing: 16) {
      BitAsks(question: questions[page], cheers: bitCheers, mood: bitMood(page: page), font: .title3.weight(.semibold))
        .pageCascade(0)
      pageContent(coordinator: coordinator, page: page)
      if let failure = coordinator.failure { Text(failure).font(.footnote).foregroundStyle(AppPalette.destructive) }
      Spacer(minLength: 0)
    }
    .id(page)
    .transition(reduceMotion ? .identity : .deal(forward: movingForward))
    .frame(maxWidth: 560, alignment: .topLeading)
    .padding(.horizontal, 20).padding(.top, 28)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .clipped()
    .background(AppPalette.background)
    .containerBackground(AppPalette.background, for: .navigation)
    .safeAreaInset(edge: .top, spacing: 0) {
      SignalStepProgress(step: page + 1, total: Self.pageCount)
        .frame(maxWidth: 560).padding(.horizontal, 24).padding(.top, 16)
        .frame(maxWidth: .infinity)
        .background(AppPalette.background)
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      VStack(spacing: 0) {
        AppPalette.hairline.frame(height: 1)
        HStack(spacing: 12) {
          if page > 0 {
            Button("Back") { move(coordinator, to: page - 1) }
              .buttonStyle(PracticeButtonStyle(secondary: true))
              .frame(width: 88)
              .transition(.opacity.combined(with: .offset(x: -12)))
              .disabled(coordinator.saving)
          }
          let label = last ? "Show me my first question" : "Continue"
          Button {
            if last { Task { await finish(coordinator) } } else { move(coordinator, to: page + 1) }
          } label: {
            Text(label)
          }.buttonStyle(PracticeButtonStyle())
            // The taste wants an answer; everything after has a sensible default.
            .disabled(coordinator.saving || (page == 0 && coordinator.draft.taste == nil))
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
    .task { await restore(coordinator) }
    .onChange(of: coordinator.draft) { _, _ in Task { await persist(coordinator) } }
  }

  private func bitMood(page: Int) -> BitMood {
    switch page {
    case 0: coordinator.draft.taste == nil ? .thinking : .idle
    case Self.pageCount - 1: .idle
    default: .idle
    }
  }

  private func move(_ coordinator: LearningPlanCoordinator, to page: Int) {
    movingForward = page > coordinator.draft.page
    bitCheers += 1
    withAnimation(reduceMotion ? nil : DrillbitMotion.page) {
      coordinator.draft.page = page
    }
  }

  @ViewBuilder private func pageContent(coordinator: LearningPlanCoordinator, page: Int) -> some View {
    @Bindable var coordinator = coordinator
    switch page {
    case 0:
      VStack(alignment: .leading, spacing: 12) {
        TicketStub(padding: 16) {
          VStack(alignment: .leading, spacing: 6) {
            Text("Scenario").font(.caption2.weight(.medium).monospaced()).textCase(.uppercase).tracking(0.8).foregroundStyle(AppPalette.accent)
            Text("Your side project hits Reddit. Ten thousand people open it in the same minute. What gives first?")
              .font(.headline).fixedSize(horizontal: false, vertical: true)
          }
        }
        .pageCascade(1)
        .accessibilityIdentifier("tasteScenario")
        ChoiceCards(options: Self.tastes, selected: coordinator.draft.taste, cascadeFrom: 2) { coordinator.draft.taste = $0 }
        if let taste = coordinator.draft.taste {
          reaction(Self.tasteReaction(taste), value: taste, order: nil).accessibilityIdentifier("tasteReaction")
            .transition(.opacity.combined(with: .offset(y: 8)))
        }
      }
      .animation(reduceMotion ? nil : DrillbitMotion.reveal, value: coordinator.draft.taste != nil)
    case 1:
      VStack(alignment: .leading, spacing: 12) {
        ChoiceCards(options: Self.situations, selected: coordinator.draft.situation, cascadeFrom: 1) { coordinator.draft.situation = $0 }
        reaction(Self.situationReaction(coordinator.draft.situation), value: coordinator.draft.situation, order: 6).accessibilityIdentifier("situationReaction")
      }
    case 2:
      VStack(alignment: .leading, spacing: 12) {
        ChoiceCards(options: Self.levels, selected: coordinator.draft.level, cascadeFrom: 1) { coordinator.draft.level = $0 }
        reaction(Self.levelReaction(coordinator.draft.level), value: coordinator.draft.level, order: 5).accessibilityIdentifier("levelPromise")
      }
    case 3:
      VStack(alignment: .leading, spacing: 12) {
        ChoiceCards(options: Self.wins, selected: coordinator.draft.objective, cascadeFrom: 1) { coordinator.draft.objective = $0 }
        if coordinator.draft.objective == "interview" {
          VStack(alignment: .leading, spacing: 12) {
            Toggle("I know the date", isOn: Binding(get: { coordinator.draft.targetDate != nil }, set: { coordinator.draft.targetDate = $0 ? Date() : nil }))
            if let date = coordinator.draft.targetDate {
              DatePicker("Interview date", selection: Binding(get: { date }, set: { coordinator.draft.targetDate = $0 }), in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)
              InterviewCountdown(days: Self.daysUntil(date), line: Self.countdown(to: date))
                .animation(reduceMotion ? nil : DrillbitMotion.selection, value: date)
                .accessibilityIdentifier("interviewCountdown")
            }
          }
          .tint(AppPalette.accent)
          .transition(.opacity)
        }
        // Once the date is in, the countdown says it better than the reaction would.
        if coordinator.draft.targetDate == nil || coordinator.draft.objective != "interview" {
          reaction(Self.winReaction(coordinator.draft.objective), value: coordinator.draft.objective, order: 4).accessibilityIdentifier("winReaction")
            .transition(.opacity)
        }
      }
      .animation(reduceMotion ? nil : DrillbitMotion.reveal, value: coordinator.draft.objective == "interview")
      .animation(reduceMotion ? nil : DrillbitMotion.reveal, value: coordinator.draft.targetDate == nil)
      .animation(reduceMotion ? nil : DrillbitMotion.reveal, value: coordinator.draft.targetDate != nil)
    case 4:
      VStack(alignment: .leading, spacing: 12) {
        ChoiceCards(options: Self.modes, selected: coordinator.draft.mode, cascadeFrom: 1) { coordinator.draft.mode = $0 }
        reaction(Self.modeReaction(coordinator.draft.mode), value: coordinator.draft.mode, order: 4).accessibilityIdentifier("modeReaction")
      }
    case 5:
      VStack(alignment: .leading, spacing: 12) {
        ChoiceCards(options: Self.paces, selected: String(coordinator.draft.minutes), cascadeFrom: 1) { coordinator.draft.minutes = Int($0) ?? 10 }
        reaction(Self.paceReaction(minutes: coordinator.draft.minutes, targetDate: coordinator.draft.objective == "interview" ? coordinator.draft.targetDate : nil), value: coordinator.draft.minutes, order: 4).accessibilityIdentifier("paceReaction")
      }
    default:
      PlanTicket(draft: coordinator.draft).pageCascade(1)
    }
  }

  /// Bit's one-line answer to the tap, in the amber card every page uses.
  private func reaction<V: Equatable>(_ text: String, value: V, order: Int?) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "sparkle").font(.caption.weight(.semibold)).foregroundStyle(AppPalette.accent).padding(.top, 3)
      Text(text)
        .font(.subheadline)
        .foregroundStyle(AppPalette.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .contentTransition(.opacity)
    }
    .padding(.horizontal, 4).padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .animation(reduceMotion ? nil : DrillbitMotion.selection, value: value)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(text)
    .pageCascade(order)
  }

  // MARK: Copy

  static func tasteReaction(_ taste: String) -> String {
    switch taste {
    case "server": "Good instinct, sometimes true. Usually the server’s fine and the database behind it is gasping: everyone wants the same few rows."
    case "database": "Yep. Ten thousand people, the same hot rows. Finding what everyone’s queuing behind is half of system design."
    default: "Perfect answer. Most guess the server; it’s usually the database behind it. First move: find what everyone’s queuing behind."
    }
  }
  static func situationReaction(_ situation: String) -> String {
    switch situation {
    case "studying": "Courses teach the pieces. Nobody makes you connect them under pressure. That’s this."
    case "bootcamp": "You can ship, which is the hard part. We’ll put names on things you’ve already half-built."
    case "firstjob": "Classic. The big picture lives in someone else’s head. Let’s move it into yours."
    default: "Then no pep talk. Every rep here is shaped like the round you’re walking into."
    }
  }
  static func levelReaction(_ level: String) -> String {
    switch level {
    case "intern": "Everyone does, the first time. We start with one question so small you can’t freeze on it."
    case "junior": "Further along than you think. We stop collecting words and start seeing why each exists."
    case "mid": "Losing the thread is a structure problem, not a knowledge one. You’ll get an order to think in."
    default: "Then straight to the hard tradeoffs, with pushback. You’ll have to defend things."
    }
  }
  static func winReaction(_ objective: String) -> String {
    switch objective {
    case "interview": "The panic is not knowing how to begin. By rep three you’ll have an opening move on autopilot."
    case "learn": "Every question here is a real app, pulled apart one decision at a time."
    default: "Short reps, spaced out. Warm muscle, no chore."
    }
  }
  static func modeReaction(_ mode: String) -> String {
    switch mode {
    case "text": "Same grilling, in writing. Switch to voice any time."
    case "mix": "Talk when you can, type when you can’t. Both count."
    default: "Brave, and right. Out loud is where most people wobble, so that’s where we practise."
    }
  }
  /// Reps a week each pace roughly works out to; used for an honest estimate, never a promise.
  static func repsPerWeek(minutes: Int) -> Int { minutes >= 20 ? 3 : minutes >= 10 ? 5 : 6 }
  static func paceReaction(minutes: Int, targetDate: Date?, now: Date = .now, calendar: Calendar = .current) -> String {
    let perWeek = repsPerWeek(minutes: minutes)
    if let targetDate {
      let days = daysUntil(targetDate, now: now, calendar: calendar)
      if days >= 2 {
        let reps = max(1, Int((Double(days) / 7 * Double(perWeek)).rounded()))
        return "\(days) days out. Keep that up and that’s about \(reps) rep\(reps == 1 ? "" : "s") before the interview."
      }
      return "Tight. One good rep now beats five rushed ones."
    }
    switch minutes {
    case 20: return "Fewer, deeper. Each one a full round."
    case 10: return "The sweet spot. One real question a day adds up fast."
    default: return "Small and daily beats big and never. Five minutes is one decision, done properly."
    }
  }
  /// Where a plan starts, by level: newcomers get the two areas every app question comes back to.
  static func startingAreas(level: String, taste: String? = nil) -> [String] {
    let byLevel: [String] = switch level {
    case "intern", "junior": ["data", "traffic"]
    case "mid": ["async", "reliability"]
    default: []
    }
    // The taste answer picks the first question's ground; the level fills in the rest.
    let first: String? = switch taste {
    case "database": "data"
    case "server": "traffic"
    default: nil
    }
    guard let first else { return byLevel }
    return Array(([first] + byLevel.filter { $0 != first }).prefix(3))
  }
  static func profile(for draft: LearningPlanCoordinator.Draft) -> PracticeProfile {
    let situation: String = switch draft.situation {
    case "bootcamp": "Bootcamp or self-taught; can build things, theory is patchy."
    case "firstjob": "Working as an engineer on tickets; has not designed a whole system yet."
    case "interviewing": "Interviewing now; system design rounds are the scary part."
    default: "Still studying computer science, with courses and side projects."
    }
    let level: String = switch draft.level {
    case "intern": "Freezes on open-ended design questions and does not know where to start."
    case "junior": "Knows the words (cache, queue, shard) but not how they fit together."
    case "mid": "Has shipped features; wants practice with trade-offs and failure cases."
    default: "Comfortable with design; wants harder, more ambiguous problems."
    }
    let win: String = switch draft.objective {
    case "interview": "Walk into a system design interview with a way to start and not panic."
    case "stay_sharp": "Stay sharp with a rep now and then."
    default: "Understand how big apps actually work and why they do not fall over."
    }
    let taste: String = switch draft.taste {
    case "database": " Suspects the database is the first thing to break when everyone wants the same rows."
    case "server": " Suspects one server doing everything is the first thing to break."
    default: ""
    }
    return PracticeProfile(goals: win + taste, background: situation + " " + level, preferences: "")
  }
  static func planHeadline(level: String) -> String {
    switch level {
    case "intern": "Building blocks first."
    case "junior": "Why each piece exists."
    case "mid": "An order to think in."
    default: "Straight to the tradeoffs."
    }
  }
  static func roleTrack(situation: String) -> String? {
    switch situation {
    case "firstjob": "backend"
    default: nil
    }
  }

  /// Arithmetic from the person's own date: honest, never a promise.
  static func daysUntil(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> Int {
    calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
  }
  static func countdown(to date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
    let days = daysUntil(date, now: now, calendar: calendar)
    switch days {
    case ..<1: return "That’s today. One quick rep to warm up."
    case 1: return "That’s tomorrow. One good rep tonight."
    default: return "\(days) days until your interview. Let’s find one thing to sharpen today."
    }
  }

  static let draftKey = "onboarding-draft-v5"
  private func restore(_ coordinator: LearningPlanCoordinator) async {
    if let data = UserDefaults.standard.data(forKey: Self.draftKey), let draft = try? JSONDecoder().decode(LearningPlanCoordinator.Draft.self, from: data) { coordinator.draft = draft }
  }
  private func persist(_ coordinator: LearningPlanCoordinator) async {
    guard let data = try? JSONEncoder().encode(coordinator.draft) else { return }
    UserDefaults.standard.set(data, forKey: Self.draftKey)
  }
  private func finish(_ coordinator: LearningPlanCoordinator) async {
    guard !coordinator.saving else { return }
    onFinish(coordinator.draft)
  }
  /// Writes the draft into settings; the host calls this once an account exists, right before the first question.
  static func apply(_ draft: LearningPlanCoordinator.Draft, to model: AppModel) async throws {
    let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: model.settings.timezone); formatter.dateFormat = "yyyy-MM-dd"
    var plan = model.settings.learningPlan ?? LearningPlan()
    plan.objective = draft.objective
    plan.targetDate = draft.objective == "interview" ? draft.targetDate.map { formatter.string(from: $0) } : nil
    plan.weakAreas = startingAreas(level: draft.level, taste: draft.taste)
    plan.dailyGoalMinutes = draft.minutes
    if let role = roleTrack(situation: draft.situation) { plan.roleTrack = role }
    model.settings.learningPlan = plan
    model.settings.selectedLevel = draft.level
    // The cards become the self-reported profile the question writer reads, unless they already wrote their own.
    if (model.settings.practiceProfile ?? PracticeProfile()) == PracticeProfile() {
      model.settings.practiceProfile = profile(for: draft)
    }
    model.practiceMode = draft.mode
    try await model.setFirstUse(FirstUseProgress(stage: .firstRep))
    // The plan syncs now so the first question is written from it; setup completes when that rep does.
    try await model.saveSettingsLocally()
  }
}

/// Option cards: a symbol, the answer in their words, and one line of what it means. Selected cards turn amber.
private struct ChoiceCards: View {
  let options: [SetupView.Option]
  let selected: String?
  var cascadeFrom: Int? = nil
  let select: (String) -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    VStack(spacing: 8) {
      ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
        let on = selected == option.id
        Button { select(option.id) } label: {
          HStack(spacing: 12) {
            Image(systemName: option.symbol)
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(on ? AppPalette.actionInk : AppPalette.accent)
              .frame(width: 36, height: 36)
              .background(on ? AppPalette.action : AppPalette.inset, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
              Text(option.title).font(.subheadline.weight(.semibold)).foregroundStyle(AppPalette.primary)
              Text(option.detail).font(.caption).foregroundStyle(AppPalette.secondary).lineLimit(1)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(AppPalette.accent)
              .opacity(on ? 1 : 0).scaleEffect(on ? 1 : 0.6)
          }
          .padding(.horizontal, 14).padding(.vertical, 12)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(on ? AppPalette.accentSoft : AppPalette.surface, in: RoundedRectangle(cornerRadius: 12))
          .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(on ? AppPalette.accent : AppPalette.hairline, lineWidth: on ? 1.5 : 1) }
          .contentShape(RoundedRectangle(cornerRadius: 12))
          .animation(reduceMotion ? nil : DrillbitMotion.selection, value: on)
        }
        .buttonStyle(DrillbitPressStyle(scale: 0.98))
        .accessibilityLabel(option.title)
        .accessibilityHint(option.detail)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("choice-" + option.id)
        .pageCascade(cascadeFrom.map { $0 + index })
      }
    }
    .sensoryFeedback(.selection, trigger: selected)
  }
}

/// The plan as a ticket, the same object Home deals every day: where we start, how deep, how, how often.
private struct PlanTicket: View {
  let draft: LearningPlanCoordinator.Draft
  var body: some View {
    let areas = SetupView.startingAreas(level: draft.level).compactMap { id in PracticeAreaGroup.all.first { $0.id == id } }
    VStack(alignment: .leading, spacing: 16) {
      Ticket {
        VStack(alignment: .leading, spacing: 14) {
          TicketHeader(number: "Your plan", detail: Date.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
          Text(SetupView.planHeadline(level: draft.level)).font(.title3.weight(.semibold)).tracking(-0.3)
          VStack(alignment: .leading, spacing: 8) {
            row("map", "Start with", areas.isEmpty ? "Whatever you’re weakest at. Drillbit picks." : areas.map(\.title).joined(separator: " and "))
            row("mic", "Practice", SetupView.modes.first { $0.id == draft.mode }?.title ?? "Talking it out")
            row("clock", "Pace", "\(draft.minutes) min · about \(SetupView.repsPerWeek(minutes: draft.minutes)) reps a week")
            if draft.objective == "interview", let date = draft.targetDate {
              row("calendar", "Interview", SetupView.daysUntil(date) >= 2 ? "\(SetupView.daysUntil(date)) days away" : SetupView.countdown(to: date))
            }
          }
        }
      } stub: {
        VStack(alignment: .leading, spacing: 4) {
          Text("First question’s on us.").font(.subheadline.weight(.semibold))
          Text(areas.isEmpty ? "It’ll read like a real interview question, not a quiz." : "It’ll be about \(areas[0].title.lowercased()), and small enough to finish.").font(.footnote).foregroundStyle(AppPalette.secondary)
        }
      }
      .accessibilityIdentifier("planTicket")
    }
  }
  private func row(_ symbol: String, _ title: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Image(systemName: symbol).font(.footnote.weight(.semibold)).foregroundStyle(AppPalette.accent).frame(width: 18)
      Text(title).font(.subheadline).foregroundStyle(AppPalette.secondary).frame(width: 76, alignment: .leading)
      Text(value).font(.subheadline.weight(.medium)).foregroundStyle(AppPalette.primary).fixedSize(horizontal: false, vertical: true)
    }
  }
}

/// The person's own date as one big number; today and tomorrow read as a sentence instead.
private struct InterviewCountdown: View {
  let days: Int
  let line: String
  @ScaledMetric(relativeTo: .largeTitle) private var numeral: CGFloat = 64
  var body: some View {
    Group {
      if days >= 2 {
        VStack(alignment: .leading, spacing: 4) {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(days)")
              .font(.system(size: numeral, weight: .bold))
              .monospacedDigit()
              .contentTransition(.numericText(value: Double(days)))
              .foregroundStyle(AppPalette.accent)
            Text("days until your interview").font(.title3.weight(.semibold))
              .fixedSize(horizontal: false, vertical: true)
          }
          Text("Let’s find one thing to sharpen today.").font(.subheadline).foregroundStyle(AppPalette.secondary)
        }
      } else {
        Text(line).font(.headline).fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(line)
  }
}
