import SwiftUI

struct HomeView: View {
  @Bindable var model: AppModel
  var openSettings: () -> Void
  @State private var flow: QuestionFlowEntry?
  @State private var started: Challenge?
  /// False from the moment the zoom leaves the ticket until the sheet is fully gone; the shadow then fades in instead of snapping.
  @State private var ticketSettled = true
  @State private var skipping: Challenge?
  @State private var chooseAfterSkip = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var bitCheers = 0
  @State private var milestoneImage: Image?
  @Environment(\.colorScheme) private var colorScheme
  @Namespace private var zoom

  private enum Today {
    case preparing(QuestionDraft?)
    case question(Challenge)
    case failed(String)
    case done(Challenge)
    /// Free reps are spent; the date they come back, or nil when they don't (lifetime).
    case waiting(Date?)
    case empty
  }
  private var preparing: Bool {
    model.busy || model.bootstrap?.jobs.contains(where: { $0.kind == "generate" && ["pending", "running"].contains($0.status) }) == true
  }
  /// The last draft, kept on the ticket after the job finished until its lines have written themselves out.
  @State private var settlingDraft: QuestionDraft?
  @State private var settledLines: Set<String> = []
  /// A question that has just finished writing arrives in steps: level, then the stub, then the pill and the tap.
  /// Nothing moves; the parts that could not be known while it streamed fade in, in reading order.
  @State private var arriving: (id: String, step: Int)?
  private static let arrivalSteps = 3
  private var today: Today {
    if preparing { return .preparing(model.preparingDraft) }
    if let settlingDraft { return .preparing(settlingDraft) }
    if let challenge = model.bootstrap?.challenge { return .question(challenge) }
    if let failure = model.preparationFailure { return .failed(failure) }
    if let session = todaysSession { return .done(session) }
    if model.freeRepsSpent { return .waiting(model.nextFreeRep) }
    return .empty
  }
  /// Changes when the ticket switches state, never while a title streams or jobs poll.
  private var todayState: String {
    switch today {
    // The draft and the question it becomes share one identity, so the finished text is not torn down and faded back in.
    case .preparing: "today"
    case .question(let challenge): challenge.lifecycle == "in_progress" ? "question|\(challenge.id)|resume" : "today"
    case .failed: "failed"
    case .done(let session): "done|\(session.id)"
    case .waiting: "waiting"
    case .empty: "empty"
    }
  }
  private var todaysSession: Challenge? {
    model.memory.sessions.first { session in
      !session.isWarmUp && session.completedAt.flatMap(Date.fromAPI).map(Calendar.current.isDateInToday) == true
    }
  }

  @State private var askingReminder = false
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        header
        VStack(alignment: .leading, spacing: 16) {
          todayTicket
            .id(todayState)
            .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 8)))
        }
        .animation(reduceMotion ? nil : DrillbitMotion.reveal, value: todayState)
        .onChange(of: model.preparingDraft) { old, new in
          // The job is done but the ticket may still be writing: hold the draft, marked finished, until it settles.
          guard let old, new == nil, !old.title.isEmpty, model.bootstrap?.challenge != nil else { return }
          var held = old; held.textDone = true
          settledLines = []
          settlingDraft = held
        }
        .task(id: settlingDraft != nil) {
          guard settlingDraft != nil else { return }
          // A line that never reports (no prompt, or an empty one) must not hold the question back.
          try? await Task.sleep(for: .seconds(2.5))
          guard !Task.isCancelled, settlingDraft != nil else { return }
          settled()
        }
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
    // The end of onboarding: the first rep is done, so ask once about a daily nudge. Settings has it after that.
    .task(id: model.offersReminder && !model.reminderHeldBack && model.firstUse.stage == .complete) {
      guard model.offersReminder, !model.reminderHeldBack, model.firstUse.stage == .complete else { return }
      try? await Task.sleep(for: .milliseconds(700))
      if !Task.isCancelled { askingReminder = true }
    }
    .drillbitConfirm("Want a nudge tomorrow?", isPresented: $askingReminder,
                     message: "Every day at \(model.reminderTimeText). Change it in Settings.", actions: [
      ConfirmAction("Remind me", style: .primary) { Task { await model.answerReminderOffer(true) } },
      ConfirmAction("No thanks") { Task { await model.answerReminderOffer(false) } },
    ])
    .drillbitConfirm("Skip this question?", isPresented: Binding(get: { skipping != nil }, set: { if !$0 { skipping = nil } }),
                     message: "It goes to Skipped questions in Library. Your draft stays saved.", actions: [
      ConfirmAction("Skip question", style: .destructive) {
        if let question = skipping { let choose = chooseAfterSkip; Task { await model.skip(question.id); if choose, model.bootstrap?.challenge == nil { flow = QuestionFlowEntry() } } }
        skipping = nil
      },
      ConfirmAction("Keep practising") { skipping = nil },
    ])
    .navigationTitle("Home").navigationBarTitleDisplayMode(.inline)
    .toolbar(.hidden, for: .navigationBar)
    .background(AppPalette.background)
    .refreshable { await model.refresh() }
    .onChange(of: flow != nil) { _, presenting in if presenting { ticketSettled = false } }
    .sheet(item: $flow, onDismiss: {
      withAnimation(reduceMotion ? nil : .easeOut(duration: 0.45)) { ticketSettled = true }
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
      HStack(alignment: .top, spacing: 0) {
        Text(subtitle).font(.subheadline).foregroundStyle(AppPalette.secondary)
          .fixedSize(horizontal: false, vertical: true)
        // Accessibility sizes give the title and subtitle the full width.
        if !typeSize.isAccessibilitySize {
          Spacer(minLength: 8)
          BitView(mood: bitMood, cheers: bitCheers)
            .frame(height: 72)
            .padding(.top, -32)
            .padding(.horizontal, -8)
            .padding(.bottom, -16)
        }
      }
      HomeWeekStrip(days: repDays).padding(.top, 20)
    }
    // Today's dot filling is the cue for Bit's hop; a fresh launch that finds it already filled stays still.
    .onChange(of: model.bootstrap?.todayPlan?.completedToday) { old, new in
      if let old, let new, old == 0, new > 0 { bitCheers += 1 }
    }
  }
  /// Days this week (and before) with a finished rep, from the same history Home's done ticket reads.
  private var repDays: Set<Date> {
    let calendar = Calendar.current
    var days = Set(model.memory.sessions.filter { !$0.isWarmUp && $0.lifecycle == "completed" }
      .compactMap { $0.completedAt.flatMap(Date.fromAPI).map(calendar.startOfDay) })
    if (model.bootstrap?.todayPlan?.completedToday ?? 0) > 0 { days.insert(calendar.startOfDay(for: .now)) }
    return days
  }
  /// Bit only reflects what Home already says in text.
  private var bitMood: BitMood {
    switch today {
    case .preparing: .drilling
    case .failed: .concerned
    case .done: .idle
    default: .idle
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

  private func lineSettled(_ line: String, needsPrompt: Bool) {
    guard settlingDraft != nil else { return }
    settledLines.insert(line)
    if settledLines.contains("title"), !needsPrompt || settledLines.contains("prompt") { settled() }
  }
  /// The text is in; the rest of the ticket arrives over about half a second, Bit cheering as the pill lands.
  private func settled() {
    settlingDraft = nil
    guard let id = model.bootstrap?.challenge?.id else { bitCheers += 1; return }
    arriving = (id, 0)
    Task {
      for step in 1...Self.arrivalSteps {
        // Level, then the stub's words, then a longer breath before the pill: three beats, not one flash.
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : step == 1 ? 120 : step == 2 ? 200 : 320))
        guard arriving?.id == id else { return }
        withAnimation(reduceMotion ? nil : step == Self.arrivalSteps ? DrillbitMotion.selection : DrillbitMotion.reveal) { arriving = (id, step) }
        if step == Self.arrivalSteps { bitCheers += 1 }
      }
      try? await Task.sleep(for: .milliseconds(400))
      if arriving?.id == id { arriving = nil }
    }
  }
  private func arrival(_ challenge: Challenge) -> Int { arriving?.id == challenge.id ? arriving!.step : Self.arrivalSteps }
  @ViewBuilder private var todayTicket: some View {
    switch today {
    case .preparing(let draft):
      Ticket {
        VStack(alignment: .leading, spacing: 12) {
          TicketHeader(number: nextNumber, detail: shortDate)
          // The title's caret stops once the prompt starts; the prompt carries it through the quiet tail of generation.
          let textDone = draft?.textDone ?? false
          let hasPrompt = !(draft?.prompt ?? "").isEmpty
          StreamingLine(text: draft?.title ?? "", font: .title.weight(.semibold), streaming: !hasPrompt,
                        finished: hasPrompt || textDone, settled: { lineSettled("title", needsPrompt: hasPrompt) })
          if let prompt = draft?.prompt, hasPrompt {
            StreamingLine(text: QuestionMarkup.plain(prompt), font: .subheadline, tracking: 0, color: AppPalette.secondary, lineLimit: 3,
                          streaming: !textDone, finished: textDone, settled: { lineSettled("prompt", needsPrompt: true) })
              .transition(.opacity)
          }
        }
      } stub: {
        // Bit drills in the header meanwhile; one animated Bit per screen.
        stubText(title: "Drilling one out", note: "Takes a few seconds")
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel("Picking today’s question")
      .accessibilityIdentifier("todayPreparing")
    case .question(let challenge):
      questionTicket(challenge)
    case .failed(let failure) where model.preparationLimited:
      Ticket {
        VStack(alignment: .leading, spacing: 12) {
          TicketHeader(number: nextNumber, detail: shortDate)
          Text("Good day’s work.").font(.title2.weight(.semibold))
          Text(failure).font(.subheadline).foregroundStyle(AppPalette.secondary)
        }
      } stub: {
        stubText(title: "Back tomorrow", note: "Library and Recall are still open")
      }
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("practiceLimit")
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
    case .waiting(let next):
      Ticket {
        VStack(alignment: .leading, spacing: 12) {
          TicketHeader(number: nextNumber, detail: shortDate)
          Text(next.map { AppModel.freeRepLine($0) } ?? AppModel.lifetimeSpentLine).font(.title2.weight(.semibold)).tracking(-0.4)
            .fixedSize(horizontal: false, vertical: true)
          ProNudge(message: next == nil ? "Your reps stay in Library and Recall. Pro gets you practising again." : "Recall and Library are still open in the meantime. Pro skips the wait.",
                   placement: .practiceRep) { await model.refresh() }
        }
      } stub: {
        if next == nil {
          let limit = model.bootstrap?.practice?.limit ?? 2
          stubText(title: "Free reps", note: "\(limit == 2 ? "Two" : String(limit)) to try it, on the house")
        } else {
          stubText(title: "Free reps", note: "Three a day, on the house")
        }
      }
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("freeRepWaiting")
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
    let step = arrival(challenge)
    let ready = step >= Self.arrivalSteps
    return ticketButton(identifier: "startPractice", spoken: resuming ? "Resume" : "Open", action: {
      if resuming { Task { await model.open(challenge) } } else { flow = QuestionFlowEntry(challenge: challenge) }
    }) {
      VStack(alignment: .leading, spacing: 12) {
        // The level is the one header fact the stream couldn't know; it joins the date once the question is real.
        TicketHeader(number: challenge.ticketLabel(next: model.bootstrap?.todayPlan?.nextTicket), detail: step >= 1 ? "\(shortDate) · \(challenge.levelLabel)" : shortDate)
          .contentTransition(.opacity)
        Text(challenge.title).font(.title.weight(.semibold)).tracking(-0.6)
          .fixedSize(horizontal: false, vertical: true)
        Text(challenge.plainPrompt).font(.subheadline).foregroundStyle(AppPalette.secondary)
          .lineLimit(3).fixedSize(horizontal: false, vertical: true)
      }
    } stub: {
      // Same stub geometry as while preparing: the words change in place, then the pill lands.
      ZStack(alignment: .leading) {
        stubText(title: "Drilling one out", note: "Takes a few seconds").opacity(step >= 2 ? 0 : 1).accessibilityHidden(step >= 2)
        Group {
          if resuming {
            stubRow(title: "Where you left off", note: lastLine.map { "“\($0)”" } ?? mode.title, pill: "Resume", pillShown: ready)
          } else {
            stubRow(title: mode.title, note: mode.stubNote, pill: "Open", pillShown: ready)
          }
        }
        .opacity(step >= 2 ? 1 : 0).accessibilityHidden(step < 2)
      }
    }
    .disabled(!ready)
    .animation(reduceMotion ? nil : DrillbitMotion.reveal, value: step)
    .contextMenu {
      if challenge.lifecycle == "ready" && model.mayStartRep(swapping: challenge) {
        Button("Regenerate", systemImage: AppIcon.retry.rawValue) { Task {
          do { _ = try await model.generateForPreview(PreparationInput(focus: "System design", kind: "design", difficulty: model.settings.difficulty, engineeringLevel: challenge.engineeringLevel, replaceId: challenge.id)) }
          catch { model.failPreparation(error) }
        } }
        Button("Choose focus or level", systemImage: AppIcon.preferences.rawValue) { flow = QuestionFlowEntry() }
      }
      if resuming && model.mayStartRep() {
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
    let takeaway = session.reflection?.takeaway ?? "Open it to see how it went."
    let spentLine = model.freeRepsLine
    let milestone = Milestone.line(for: session.ticket)
    // The ticket opens today's attempt; its stub carries the next move, so nothing hangs underneath.
    return Ticket(foil: milestone != nil) {
      VStack(alignment: .leading, spacing: 16) {
        NavigationLink { SessionDetailView(model: model, initial: session) } label: {
          VStack(alignment: .leading, spacing: 8) {
            TicketHeader(number: session.ticketLabel(next: nil), detail: "Done \(time)")
            Text(session.title).font(.title3.weight(.semibold)).foregroundStyle(AppPalette.secondary)
              .multilineTextAlignment(.leading)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
        }
        .buttonStyle(TicketPressStyle())
        .accessibilityLabel("\(session.title). \(line ?? takeaway)")
        .accessibilityIdentifier("todayDone")
        if let milestone, let ticket = session.ticket {
          HStack(alignment: .center, spacing: 12) {
            Text(milestone).font(.headline).foregroundStyle(AppPalette.primary)
              .fixedSize(horizontal: false, vertical: true)
              .accessibilityIdentifier("milestoneLine")
            Spacer(minLength: 8)
            if let milestoneImage {
              ShareLink(item: milestoneImage, message: Text("\(milestone) Practising system design on Drillbit."),
                        preview: SharePreview(String(format: "Drillbit No. %03d", ticket), image: milestoneImage)) {
                Image(systemName: "square.and.arrow.up").font(.body.weight(.semibold)).foregroundStyle(AppPalette.accent)
                  .frame(width: 44, height: 44).contentShape(Rectangle())
              }
              .accessibilityLabel("Share milestone")
              .accessibilityIdentifier("shareMilestone")
            }
          }
          .task(id: "\(ticket)|\(colorScheme)") {
            milestoneImage = MilestoneShareCard.image(ticket: ticket, line: milestone, scheme: colorScheme)
          }
        }
      }
    } stub: {
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          if let line, !guided {
            // The underline already marks it as the person's own words.
            YourLine(quote: line, font: .body.weight(.medium))
          } else {
            Text(guided ? "Worked out together" : "One thing to carry forward").font(.subheadline.weight(.medium)).foregroundStyle(AppPalette.secondary)
            Text(takeaway).font(.body).fixedSize(horizontal: false, vertical: true)
          }
          if let spentLine {
            Text(spentLine).font(.footnote).foregroundStyle(AppPalette.secondary)
              .fixedSize(horizontal: false, vertical: true)
              .accessibilityIdentifier("freeRepNotice")
          }
        }
        Spacer(minLength: 8)
        if spentLine != nil {
          Button { PlanCoordinator.shared.register(.practiceRep) { await model.refresh() } } label: { StubPill(label: "See Pro") }
            .buttonStyle(TicketPressStyle())
            .accessibilityLabel("See Pro")
            .accessibilityIdentifier("seePro")
        } else {
          Button { flow = QuestionFlowEntry() } label: { StubPill(label: "One more") }
            .buttonStyle(TicketPressStyle())
            .accessibilityLabel("One more question")
            .accessibilityIdentifier("oneMore")
        }
      }
    }
  }

  private func recallRow(_ plan: TodayPlan) -> some View {
    let now = Date.now
    let quote = model.recall.cards.first { Date.fromAPI($0.dueAt).map { $0 <= now } ?? false }?.evidence?.quote
    // The first rep's cards get one plain introduction instead of a tab tour.
    let introducing = model.firstUse.firstRepID != nil && !model.firstUse.recallIntroduced
    let count = plan.dueRecallCount
    return Button {
      if introducing { Task { await model.markRecallIntroduced() } }
      NotificationCenter.default.post(name: .init("OpenRecall"), object: nil)
    } label: {
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Recall").font(.subheadline.weight(.semibold)).foregroundStyle(AppPalette.primary)
          Text(introducing ? "\(count) \(count == 1 ? "card" : "cards") from your first rep. A quick check now makes it stick." : quote.map { "“\($0)”" } ?? "A few things from past sessions, ready to test.")
            .font(.subheadline).foregroundStyle(AppPalette.secondary).lineLimit(introducing ? 3 : 2).multilineTextAlignment(.leading)
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
      Ticket(shadowed: false, content: content, stub: stub).contentShape(Rectangle())
    }
    .buttonStyle(TicketPressStyle())
    // The source is the ticket itself, clipped to its corners and nothing more: a fill of its own would show
    // through the notches and linger as a square while the system fades the source out after the zoom returns.
    .matchedTransitionSource(id: "today", in: zoom) { source in
      source.clipShape(RoundedRectangle(cornerRadius: 12))
    }
    // The shadow sits outside the source, where the clip can't cut it off. The source's own shadow option fills the
    // whole rounded rectangle and shows dark through the notches; this one follows the ticket's real outline, the
    // same as while it's drilling.
    .shadow(color: AppPalette.ticketContact.opacity(ticketSettled ? 1 : 0), radius: 1, y: 1)
    .shadow(color: AppPalette.ticketShadow.opacity(ticketSettled ? 1 : 0), radius: 14, y: 12)
    .accessibilityIdentifier(identifier ?? "todayTicket")
    // The printed pill is decorative for VoiceOver, but Voice Control users say what they see.
    .accessibilityInputLabels([Text(spoken), Text("Today’s question")])
  }

  // One row, same height as the drilling stub: the pill sits beside the words and never pushes them down.
  private func stubRow(title: String, note: String, pill: String, pillShown: Bool = true) -> some View {
    HStack(spacing: 12) {
      stubText(title: title, note: note)
      Spacer(minLength: 8)
      StubPill(label: pill)
        .scaleEffect(pillShown ? 1 : 0.86)
        .opacity(pillShown ? 1 : 0)
    }
  }
  private func stubText(title: String, note: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(AppPalette.primary)
      Text(note).font(.subheadline).foregroundStyle(AppPalette.secondary).lineLimit(1)
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
  var tracking: CGFloat = -0.6
  var color: Color = AppPalette.primary
  var lineLimit: Int? = nil
  /// While the stream is still open the caret keeps blinking after the line is written, so a quiet tail never reads as a freeze.
  var streaming = true
  /// The text is complete: the trailing glyphs fade all the way in and `settled` fires once they have.
  var finished = false
  var settled: () -> Void = {}
  @State private var clock = RevealClock()
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
      // The write head trails the cursor by the fade edge; only a finished line gets to write the edge out.
      let target = Double(text.count) + (finished ? RevealRenderer.edge : 0)
      let cursor = clock.tick(timeline.date, target: target, instant: reduceMotion, finished: finished) {
        Task { @MainActor in settled() }
      }
      let writing = Double(text.count) > cursor || text.isEmpty
      let blink = reduceMotion ? 1.0 : (sin(timeline.date.timeIntervalSinceReferenceDate * 2 * .pi / 1.1) > 0 ? 1.0 : 0.15)
      Text(text.isEmpty ? " " : text)
        .font(font).tracking(tracking)
        .foregroundStyle(color)
        .lineLimit(lineLimit)
        .fixedSize(horizontal: false, vertical: true)
        .textRenderer(RevealRenderer(shown: text.isEmpty ? 0 : cursor, caret: writing ? 1 : streaming ? blink : 0, caretColor: AppPalette.accent, motion: !reduceMotion,
                                     total: lineLimit == nil ? nil : Double(text.count)))
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
