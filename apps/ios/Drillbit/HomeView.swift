import SwiftUI

struct HomeView: View {
  @Bindable var model: AppModel
  var openSettings: () -> Void
  @State private var flow: QuestionFlowEntry?
  @State private var started: Challenge?
  @State private var skipping: Challenge?
  @State private var chooseAfterSkip = false
  @Namespace private var zoom
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private enum Today {
    case preparing(QuestionDraft?)
    case warmUp(Challenge?)
    case chooseMode
    case question(Challenge)
    case failed(String)
    case done(Challenge)
    case empty
  }
  private var preparing: Bool {
    model.busy || model.bootstrap?.jobs.contains(where: { $0.kind == "generate" && ["pending", "running"].contains($0.status) }) == true
  }
  private var today: Today {
    if preparing { return .preparing(model.preparingDraft) }
    if model.firstUse.stage == .walkthrough { return .warmUp(model.bootstrap?.challenge.flatMap { $0.isWarmUp ? $0 : nil }) }
    if model.firstUse.stage == .chooseMode { return .chooseMode }
    if let challenge = model.bootstrap?.challenge { return .question(challenge) }
    if let failure = model.preparationFailure { return .failed(failure) }
    if let session = todaysSession { return .done(session) }
    return .empty
  }
  /// Changes when the ticket switches state, never while a title streams or jobs poll.
  private var todayState: String {
    switch today {
    case .preparing: "preparing"
    case .warmUp(let challenge): "warm-up|\(challenge?.id ?? "")|\(challenge?.lifecycle ?? "")"
    case .chooseMode: "choose"
    case .question(let challenge): "question|\(challenge.id)|\(challenge.lifecycle)"
    case .failed: "failed"
    case .done(let session): "done|\(session.id)"
    case .empty: "empty"
    }
  }
  private var todaysSession: Challenge? {
    model.memory.sessions.first { session in
      !session.isWarmUp && session.completedAt.flatMap(Date.fromAPI).map(Calendar.current.isDateInToday) == true
    }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        header
        VStack(alignment: .leading, spacing: 16) {
          todayTicket
            .id(todayState)
            .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 8)))
          afterTicket
        }
        .animation(reduceMotion ? nil : DrillbitMotion.reveal, value: todayState)
        ForEach(model.bootstrap?.jobs.filter { $0.status == "failed" && $0.kind != "help" } ?? []) { job in
          VStack(alignment: .leading, spacing: 8) {
            Text(job.error ?? "Preparation couldn’t finish.").font(.subheadline).foregroundStyle(.secondary)
            Button("Retry") { Task { await model.retry(job) } }.frame(minHeight: 44)
          }
        }
        if let plan = model.bootstrap?.todayPlan, plan.dueRecallCount > 0, model.firstUse.stage == .complete {
          recallRow(plan)
        }
      }
      .frame(maxWidth: 640, alignment: .leading).frame(maxWidth: .infinity)
      .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 40)
    }
    .drillbitTabClearance()
    .task(id: model.bootstrap?.account.id) { await model.ensureHomeQuestion() }
    .alert("Skip this question?", isPresented: Binding(get: { skipping != nil }, set: { if !$0 { skipping = nil } })) {
      Button("Keep practising", role: .cancel) { skipping = nil }
      Button("Skip question", role: .destructive) { if let question = skipping { let choose = chooseAfterSkip; Task { await model.skip(question.id); if choose, model.bootstrap?.challenge == nil { flow = QuestionFlowEntry() } } }; skipping = nil }
    } message: { Text("It goes to Skipped questions in Library. Your draft stays saved.") }
    .navigationTitle("Home").navigationBarTitleDisplayMode(.inline)
    .toolbar(.hidden, for: .navigationBar)
    .background(AppPalette.background)
    .refreshable { await model.refresh() }
    .sheet(item: $flow, onDismiss: {
      if let started { model.presented = started; self.started = nil }
    }) { entry in
      QuestionFlow(model: model, initial: entry.challenge, source: entry.source, recovery: entry.recovery, browseTopics: entry.browseTopics, area: entry.area, onStart: { started = $0 })
        .navigationTransition(.zoom(sourceID: "today", in: zoom))
    }
    .task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(4))
        if model.bootstrap?.jobs.contains(where: { ["pending", "running"].contains($0.status) }) == true { await model.refresh() }
      }
    }
  }

  // MARK: Header

  private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .center) {
        Text(Date.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
          .font(.caption.weight(.medium).monospaced()).textCase(.uppercase).tracking(0.8)
          .foregroundStyle(AppPalette.secondary)
        Spacer()
        Button("Settings", systemImage: AppIcon.settings.rawValue, action: openSettings)
          .labelStyle(.iconOnly)
          .buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.large)
          .accessibilityIdentifier("homeSettings")
      }
      Text(Date.now.formatted(.dateTime.weekday(.wide)))
        .font(.largeTitle.weight(.bold)).tracking(-0.6)
        .accessibilityAddTraits(.isHeader)
      Text(subtitle).font(.subheadline).foregroundStyle(AppPalette.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
  private var subtitle: String {
    if case .done = today { return "Today’s rep is in the bag." }
    if let countdown = Self.countdown(model.settings.learningPlan?.targetDate) { return countdown }
    return "One question, about \(model.settings.learningPlan?.dailyGoalMinutes ?? 10) minutes."
  }
  static func countdown(_ target: String?, now: Date = .now, calendar: Calendar = .current) -> String? {
    guard let target, let date = try? Date(target, strategy: .iso8601.year().month().day()) else { return nil }
    // The plan stores a calendar day, so compare days in the device's calendar rather than instants.
    let parts = Calendar(identifier: .gregorian).dateComponents(in: .gmt, from: date)
    guard let day = calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day)),
      let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: day).day, days >= 0 else { return nil }
    switch days {
    case 0: return "Interview’s today. You’ve got this."
    case 1: return "Interview tomorrow. One more rep."
    case 2...6: return "Interview \(day.formatted(.dateTime.weekday(.wide))), \(days) days out."
    default: return "Interview in \(days) days."
    }
  }

  // MARK: Today's ticket

  @ViewBuilder private var todayTicket: some View {
    switch today {
    case .preparing(let draft):
      Ticket {
        VStack(alignment: .leading, spacing: 12) {
          TicketHeader(number: model.firstUse.stage == .walkthrough ? "Warm-up" : nextNumber, detail: shortDate)
          StreamingLine(text: draft?.title ?? "", font: .title.weight(.semibold))
          if let prompt = draft?.prompt, !prompt.isEmpty {
            Text(QuestionMarkup.plain(prompt)).font(.subheadline).foregroundStyle(AppPalette.secondary).lineLimit(3)
          }
        }
      } stub: {
        DrillbitBit(working: true, height: 22)
          .frame(minHeight: 36)
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel("Picking today’s question")
      .accessibilityIdentifier("todayPreparing")
    case .warmUp(let challenge):
      ticketButton(identifier: "startPractice", spoken: challenge?.lifecycle == "in_progress" ? "Resume" : "Start", action: { flow = QuestionFlowEntry(challenge: challenge) }) {
        VStack(alignment: .leading, spacing: 12) {
          TicketHeader(number: "Warm-up", detail: "Doesn’t count")
          Text(challenge?.title ?? "Let’s try one together.").font(.title.weight(.semibold)).tracking(-0.6)
          Text("Built from your plan. It won’t count, so just try stuff.").font(.subheadline).foregroundStyle(AppPalette.secondary)
        }
      } stub: {
        stubRow(title: "Guided", note: GuidanceMode.learnTogether.stubNote, pill: challenge?.lifecycle == "in_progress" ? "Resume" : "Start")
      }
    case .chooseMode:
      ticketButton(identifier: "chooseFirstSession", spoken: "Choose", action: { flow = QuestionFlowEntry() }) {
        VStack(alignment: .leading, spacing: 12) {
          TicketHeader(number: nextNumber, detail: shortDate)
          Text("Your first real one.").font(.title.weight(.semibold)).tracking(-0.6)
          Text("Guided, Practice or Mock interview. Pick how much help you want.").font(.subheadline).foregroundStyle(AppPalette.secondary)
        }
      } stub: {
        stubRow(title: "This one counts", note: "Start whenever you’re ready", pill: "Choose")
      }
    case .question(let challenge):
      questionTicket(challenge)
    case .failed(let failure):
      Ticket {
        VStack(alignment: .leading, spacing: 12) {
          TicketHeader(number: nextNumber, detail: shortDate)
          Text("Couldn’t write today’s question.").font(.title2.weight(.semibold))
          Text(failure).font(.subheadline).foregroundStyle(AppPalette.secondary)
        }
      } stub: {
        Button { flow = QuestionFlowEntry(recovery: model.failedPreparation, source: model.failedPreparationSource) } label: {
          stubRow(title: "Your settings are safe", note: "Check them and try again", pill: "Review")
        }
        .buttonStyle(.plain)
      }
    case .done(let session):
      doneTicket(session)
    case .empty:
      ticketButton(identifier: "prepareQuestion", spoken: "Prepare", action: { flow = QuestionFlowEntry() }) {
        VStack(alignment: .leading, spacing: 12) {
          TicketHeader(number: nextNumber, detail: shortDate)
          Text("Nothing picked yet.").font(.title.weight(.semibold)).tracking(-0.6)
          Text("Choose an area and level, or let Drillbit pick.").font(.subheadline).foregroundStyle(AppPalette.secondary)
        }
      } stub: {
        stubRow(title: "Prepare a question", note: "Takes a few seconds", pill: "Prepare")
      }
    }
  }

  private func questionTicket(_ challenge: Challenge) -> some View {
    let resuming = challenge.lifecycle == "in_progress"
    let mode = challenge.guidanceMode ?? .coachMe
    let lastLine = challenge.interview.flatMap { $0.turns.isEmpty ? nil : QuestionMarkup.plain($0.prompt) }
    return ticketButton(identifier: "startPractice", spoken: resuming ? "Resume" : "Open", action: {
      if resuming { Task { await model.open(challenge) } } else { flow = QuestionFlowEntry(challenge: challenge) }
    }) {
      VStack(alignment: .leading, spacing: 12) {
        TicketHeader(number: challenge.ticketLabel(next: model.bootstrap?.todayPlan?.nextTicket), detail: "\(shortDate) · \(challenge.levelLabel)")
        Text(challenge.title).font(.title.weight(.semibold)).tracking(-0.6)
          .fixedSize(horizontal: false, vertical: true)
        Text(challenge.plainPrompt).font(.subheadline).foregroundStyle(AppPalette.secondary)
          .lineLimit(3).fixedSize(horizontal: false, vertical: true)
      }
    } stub: {
      if resuming {
        stubRow(title: "Where you left off", note: lastLine.map { "“\($0)”" } ?? mode.title, pill: "Resume")
      } else {
        stubRow(title: mode.title, note: mode.stubNote, pill: "Open")
      }
    }
    .contextMenu {
      if challenge.lifecycle == "ready" {
        Button("Regenerate", systemImage: AppIcon.retry.rawValue) { Task {
          do { _ = try await model.generateForPreview(PreparationInput(focus: "System design", kind: "design", difficulty: model.settings.difficulty, engineeringLevel: challenge.engineeringLevel, replaceId: challenge.id)) }
          catch { model.preparationFailure = error.localizedDescription }
        } }
        Button("Choose focus or level", systemImage: AppIcon.preferences.rawValue) { flow = QuestionFlowEntry() }
      }
      if resuming {
        Button("Choose another question", systemImage: AppIcon.regenerate.rawValue) { chooseAfterSkip = true; skipping = challenge }
      }
      Button("Skip question", systemImage: AppIcon.skip.rawValue, role: .destructive) { chooseAfterSkip = false; skipping = challenge }
    }
    .accessibilityAction(named: "Skip question") { chooseAfterSkip = false; skipping = challenge }
  }

  private func doneTicket(_ session: Challenge) -> some View {
    let evidence = session.reflection?.evidence ?? []
    let line = (evidence.first { $0.signal == "demonstrated" } ?? evidence.first)?.quote
    let guided = (session.reflection?.guidanceMode ?? session.guidanceMode) == .learnTogether
    let time = session.completedAt.flatMap(Date.fromAPI)?.formatted(date: .omitted, time: .shortened) ?? ""
    return NavigationLink { SessionDetailView(model: model, initial: session) } label: {
      Ticket {
        VStack(alignment: .leading, spacing: 8) {
          TicketHeader(number: session.ticketLabel(next: nil), detail: "Done \(time)")
          Text(session.title).font(.title3.weight(.semibold)).foregroundStyle(AppPalette.secondary)
        }
      } stub: {
        VStack(alignment: .leading, spacing: 8) {
          if let line, !guided {
            Text("Your line").font(.subheadline.weight(.medium)).foregroundStyle(AppPalette.secondary)
            YourLine(quote: line, font: .title3.weight(.medium))
          } else {
            Text(guided ? "Worked out together" : "One thing to carry forward").font(.subheadline.weight(.medium)).foregroundStyle(AppPalette.secondary)
            Text(session.reflection?.takeaway ?? "Open it to see how it went.").font(.body)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(TicketPressStyle())
    .matchedTransitionSource(id: "today", in: zoom)
    .accessibilityIdentifier("todayDone")
  }

  @ViewBuilder private var afterTicket: some View {
    if case .done = today {
      VStack(alignment: .leading, spacing: 4) {
        Text(tomorrowLine).font(.subheadline).foregroundStyle(AppPalette.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Button("One more?") { flow = QuestionFlowEntry() }
          .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
          .accessibilityIdentifier("oneMore")
      }
      .padding(.horizontal, 4)
    } else if case .question = today, let queued = model.bootstrap?.queuedNext {
      Text("Tomorrow: \(queued.label ?? queued.title), picked from your last answer.")
        .font(.subheadline).foregroundStyle(AppPalette.secondary).padding(.horizontal, 4)
    }
  }
  private var tomorrowLine: String {
    guard let queued = model.bootstrap?.queuedNext else { return "Next one’s picked when you open the app tomorrow." }
    return "Tomorrow: \(queued.label ?? queued.title), picked from today’s answer."
  }

  private func recallRow(_ plan: TodayPlan) -> some View {
    let now = Date.now
    let quote = model.recall.cards.first { Date.fromAPI($0.dueAt).map { $0 <= now } ?? false }?.evidence?.quote
    return Button { NotificationCenter.default.post(name: .init("OpenRecall"), object: nil) } label: {
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Recall").font(.subheadline.weight(.semibold)).foregroundStyle(AppPalette.primary)
          Text(quote.map { "“\($0)”" } ?? "A few things from past sessions, ready to test.")
            .font(.subheadline).foregroundStyle(AppPalette.secondary).lineLimit(2).multilineTextAlignment(.leading)
        }
        Spacer(minLength: 8)
        Text("\(plan.dueRecallCount) due").font(.caption.weight(.medium).monospaced()).textCase(.uppercase)
          .foregroundStyle(AppPalette.accent)
        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(AppPalette.elevated, in: RoundedRectangle(cornerRadius: 12))
      .contentShape(RoundedRectangle(cornerRadius: 12))
    }
    .buttonStyle(TicketPressStyle())
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Recall, \(plan.dueRecallCount) due")
    .accessibilityIdentifier("homeRecall")
    .task { if model.recall.cards.isEmpty { await model.loadRecall() } }
  }

  // MARK: Pieces

  private var shortDate: String { Date.now.formatted(.dateTime.day().month(.abbreviated)) }
  private var nextNumber: String {
    model.bootstrap?.todayPlan?.nextTicket.map { String(format: "No. %03d", $0) } ?? "Today"
  }

  private func ticketButton<Content: View, Stub: View>(identifier: String? = nil, spoken: String, action: @escaping () -> Void,
    @ViewBuilder content: @escaping () -> Content, @ViewBuilder stub: @escaping () -> Stub) -> some View {
    Button(action: action) {
      Ticket(content: content, stub: stub).contentShape(Rectangle())
    }
    .buttonStyle(TicketPressStyle())
    .matchedTransitionSource(id: "today", in: zoom)
    .accessibilityIdentifier(identifier ?? "todayTicket")
    // The printed pill is decorative for VoiceOver, but Voice Control users say what they see.
    .accessibilityInputLabels([Text(spoken), Text("Today’s question")])
  }

  private func stubRow(title: String, note: String, pill: String) -> some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 12) {
        stubText(title: title, note: note)
        Spacer(minLength: 8)
        StubPill(label: pill)
      }
      VStack(alignment: .leading, spacing: 12) {
        stubText(title: title, note: note)
        StubPill(label: pill)
      }
    }
  }
  private func stubText(title: String, note: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(AppPalette.primary)
      Text(note).font(.subheadline).foregroundStyle(AppPalette.secondary).lineLimit(2)
    }
    .multilineTextAlignment(.leading)
  }
}

extension GuidanceMode {
  /// What the style means on the ticket's stub, in a few words.
  var stubNote: String { switch self {
    case .learnTogether: "Step by step, with examples"
    case .coachMe: "Nudges if you ask"
    case .mockInterview: "No nudges, on the clock"
  } }
}

/// The ticket's call to action, printed on the stub; the whole ticket is the button.
struct StubPill: View {
  let label: String
  var body: some View {
    Text(label)
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(AppPalette.actionInk)
      .padding(.horizontal, 16)
      .frame(minHeight: 36)
      .background(AppPalette.action, in: Capsule())
      .accessibilityHidden(true)
  }
}

/// Tickets sink slightly under a finger, like pressing on card stock.
struct TicketPressStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
      .opacity(configuration.isPressed && reduceMotion ? 0.8 : 1)
      .animation(.smooth(duration: 0.18), value: configuration.isPressed)
  }
}

/// A single line that streams in as it's written, with the same reveal as the question preview.
struct StreamingLine: View {
  let text: String
  var font: Font
  @State private var clock = RevealClock()
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    TimelineView(.animation) { timeline in
      let target = Double(text.count)
      let cursor = clock.tick(timeline.date, target: target, instant: reduceMotion, finished: false) {}
      Text(text.isEmpty ? " " : text)
        .font(font).tracking(-0.6)
        .fixedSize(horizontal: false, vertical: true)
        .textRenderer(RevealRenderer(shown: text.isEmpty ? 0 : cursor, caret: text.count > Int(cursor) || text.isEmpty ? 1 : 0, caretColor: AppPalette.accent, motion: !reduceMotion))
    }
    .accessibilityLabel(text)
  }
}

struct HomeTopicRow: View {
  var concept: PracticeConcept
  var coverage: CoverageResponse.Entry?
  var loaded: Bool
  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(concept.label).font(.body.weight(.medium)).foregroundStyle(.primary)
        if loaded {
          DrillbitMetadata(text: (coverage?.completedAttempts ?? 0) == 0 ? (concept.description ?? "A core system design decision.") : "\(coverage?.completedAttempts ?? 0) completed \(coverage?.completedAttempts == 1 ? "session" : "sessions")")
        }
      }
      Spacer(minLength: 0)
      Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
    }.padding(.vertical, 16).frame(maxWidth: .infinity, minHeight: 60, alignment: .leading).contentShape(Rectangle())
  }
}
