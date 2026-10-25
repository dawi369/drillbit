import SwiftUI

/// Presentation only: the interview shell owns the connection and pending receipts.
/// The stage is the conversation itself: the question, then every line said, following the latest. Bit sits beside
/// the microphone from the moment it connects, reacting to whoever is talking.
struct InterviewVoiceRoom<Question: View>: View {
  let voice: LiveVoice
  let interview: InterviewController
  /// "2 of 3 free voice sessions left.", when the account is on the free plan.
  var allowance: String? = nil
  /// True while the shell is about to start voice itself; the room reads as connecting until it does.
  var opening = false
  @ViewBuilder var question: () -> Question
  /// Ends voice and returns to the written interview.
  var leave: () -> Void
  /// Ends voice and lands in the editor with the keyboard up.
  var text: () -> Void
  /// First-run tip over Start; `Show me` on it performs the keyboard tap.
  var coach: CoachMark? = nil
  /// Voice-first: the tip's Show me performs the keyboard tap. Text-first: they came from the keyboard, so it just closes.
  var coachReturnsToText = true
  var dismissCoach: (CoachMark) -> Void = { _ in }
  @State private var warned = false
  /// The mute hint shows for the first muted stretch only; after they've unmuted once it stays quiet.
  @State private var unmutedOnce = false
  /// Set on the way out: the room keeps the face it had while it fades, instead of flashing through ending states.
  @State private var leavingAs: LiveVoice.Phase?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private var phase: LiveVoice.Phase { leavingAs ?? (opening && voice.phase == .idle ? .connecting : voice.phase) }
  private var showsBit: Bool { phase == .connecting || phase == .active }
  /// Bit and the way out arrive together, on the same spring.
  private var pop: AnyTransition {
    reduceMotion ? .opacity : .asymmetric(
      insertion: .scale(scale: 0.6).combined(with: .opacity).animation(DrillbitMotion.pop),
      removal: .scale(scale: 0.8).combined(with: .opacity).animation(DrillbitMotion.fast))
  }
  private func exit(_ action: () -> Void) {
    guard leavingAs == nil else { return }
    leavingAs = phase
    action()
  }

  var body: some View {
    stage
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(AppPalette.background)
      // A bar, not an inset: the conversation softly blurs and fades under the controls, like it does under the
      // system's own bars, instead of running straight into them.
      .safeAreaBar(edge: .bottom, spacing: 0) { dock }
      .scrollEdgeEffectStyle(.soft, for: .bottom)
      .coachMark(coach, action: coachReturnsToText ? nil : "Got it") { mark in dismissCoach(mark); if mark == .voice, coachReturnsToText { exit(text) } }
      .navigationTitle("Talk it through")
      .navigationBarTitleDisplayMode(.inline)
      .navigationBarBackButtonHidden()
      .toolbar { ToolbarItem(placement: .principal) { VoiceRoomClock(voice: voice, warned: $warned) } }
      .sensoryFeedback(.impact(weight: .medium), trigger: voice.phase == .active) { _, live in live }
      .sensoryFeedback(.warning, trigger: warned) { _, now in now }
      .onChange(of: voice.phase) { _, phase in
        switch phase {
        case .connecting: warned = false
        case .active: AccessibilityNotification.Announcement("Connected. Unmute when you’re ready to talk.").post()
        case .ending: AccessibilityNotification.Announcement("Voice ended.").post()
        default: break
        }
      }
      .onChange(of: warned) { _, now in if now { AccessibilityNotification.Announcement("Two minutes left in this voice session.").post() } }
      .onChange(of: voice.muted) { _, muted in if !muted { unmutedOnce = true } }
  }

  // MARK: Stage

  private var stage: some View {
    InterviewConversation(state: interview.displayState, style: .room, latestIdentifier: "voiceCaption") {
      question().frame(maxWidth: 560, alignment: .leading)
    }
  }
  private var latestInterviewerLine: String? {
    guard let turn = interview.displayState.turns.last(where: { $0.kind == "voice" }) else { return nil }
    return VoiceTranscript.rows(turn.voice ?? []).last { $0.speaker == "assistant" && !$0.text.isEmpty }?.text
  }

  private var micState: MicControl.State {
    switch phase {
    case .idle: .start
    case .connecting: .connecting
    default: voice.muted ? .muted : .live
    }
  }

  // MARK: Dock

  @ViewBuilder private var dock: some View {
    VStack(spacing: 8) {
      if let message = voice.message {
        Text(message).font(.footnote).foregroundStyle(AppPalette.secondary)
          .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
      }
      switch phase {
      case .idle, .connecting, .active:
        // The microphone sits dead centre in every state; Bit keeps it company on the left, and the way out hangs off
        // to the right like a phone call's hang-up.
        MicControl(state: micState) {
          switch phase {
          case .idle: Task { await voice.start() }
          case .active: voice.toggleMute()
          default: break
          }
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topLeading) {
          if showsBit {
            // Same slot as the controls on the right, sitting a touch below the microphone's centre so he rests
            // beside it rather than floating.
            VoiceBit(voice: voice, phase: phase)
              .frame(height: 64)
              .frame(width: 88, height: 80)
              .padding(.top, 8)
              .padding(.leading, 16)
              .transition(pop)
          }
        }
        .overlay(alignment: .trailing) {
          Group {
            switch phase {
            case .idle:
              RoomControl(title: "Type", symbol: "keyboard", fill: AppPalette.elevated, ink: AppPalette.primary,
                identifier: "voiceBack", spoken: "Type instead") { exit(text) }
                .accessibilityHint("Returns to writing")
                .coachAnchor(.voice)
                .transition(pop)
            case .connecting:
              // The first rep has no way out of its own opening; the line either comes up or fails to Try again.
              if interview.model.firstUse.stage != .firstRep {
                RoomControl(title: "Cancel", symbol: "xmark", fill: AppPalette.elevated, ink: AppPalette.primary,
                  identifier: "voiceCancel") { exit(leave) }
                  .accessibilityHint("Stops connecting and returns to writing")
                  .transition(pop)
              }
            default:
              RoomControl(title: "End", symbol: AppIcon.end.rawValue, fill: AppPalette.destructive.opacity(0.16), ink: AppPalette.destructive,
                identifier: "voiceEnd", spoken: "End voice") { exit(leave) }
                .accessibilityHint("Stops talking and returns to writing. The interview stays open.")
                // Live, the tip points at End: that's the keyboard route once talking.
                .coachAnchor(.voice)
                .transition(pop)
            }
          }
          .frame(width: 88)
          .padding(.trailing, 16)
        }
        // The free allowance sits under the button, where the decision is made.
        if let allowance {
          Text(allowance)
            .font(.footnote).foregroundStyle(AppPalette.secondary)
            .multilineTextAlignment(.center)
            .accessibilityIdentifier("voiceAllowance")
        }
        #if DEBUG
        if phase == .active, interview.model.fixture, ProcessInfo.processInfo.arguments.contains("--fixture-voice") {
          Button("Simulate speech") { Task { await voice.fixtureSpeech() } }.font(.footnote).accessibilityIdentifier("voiceFixtureSpeech")
        }
        #endif
      case .ending:
        LoadingStatus("Saving the conversation…", centered: true)
      case .unavailable:
        HStack(spacing: 12) {
          Button {
            Task { if voice.blocksText { await voice.retrySync() } else { await voice.start() } }
          } label: { Label("Try again", systemImage: AppIcon.retry.rawValue) }
            .buttonStyle(PracticeButtonStyle())
            .accessibilityIdentifier("voiceRetry")
          KeyboardControl { exit(text) }
        }
      }
    }
    .frame(maxWidth: 560)
    // The taller top gives the soft edge effect more room to fade the words; the controls sit a touch into the
    // home-indicator margin so the dock reads lower on the screen.
    .padding(.horizontal, 24).padding(.top, 28).padding(.bottom, -4)
    .frame(maxWidth: .infinity)
    .animation(reduceMotion ? nil : DrillbitMotion.reveal, value: phase)
  }
}

/// The way back to typing, beside the primary action: a small round key, never competing with it.
private struct KeyboardControl: View {
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      Image(systemName: "keyboard")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(AppPalette.primary)
        .frame(width: 48, height: 48)
        .background(AppPalette.elevated, in: Circle())
        .overlay { Circle().strokeBorder(AppPalette.hairline, lineWidth: 0.5) }
        .contentShape(Circle())
    }
    .buttonStyle(DrillbitPressStyle())
    .accessibilityLabel("Type instead")
    .accessibilityHint("Returns to writing")
    .accessibilityIdentifier("voiceBack")
  }
}

/// Bit as the interviewer's presence beside the mic. He drills while the line comes up and hops once it's live, then
/// follows the room: mouthing the interviewer's measured output, all ears while you talk, and thinking only where
/// a reply is actually being worked out, in the beat after you finish or while a delegated answer is in flight.
private struct VoiceBit: View {
  let voice: LiveVoice
  let phase: LiveVoice.Phase
  @State private var gauge = SpeakerGauge()
  @State private var mood: BitMood
  @State private var cheers = 0
  init(voice: LiveVoice, phase: LiveVoice.Phase) {
    self.voice = voice
    self.phase = phase
    _mood = State(initialValue: phase == .connecting ? .drilling : .idle)
  }
  var body: some View {
    BitView(mood: mood, levels: voice.levels, cheers: cheers)
      // Polls the meter rather than re-rendering on every level change; Bit only hears about real mood changes.
      .task(id: phase) {
        while !Task.isCancelled {
          let next = currentMood(at: .now)
          if next != mood { mood = next }
          try? await Task.sleep(for: .milliseconds(100))
        }
      }
      .onChange(of: phase) { _, now in if now == .active { cheers += 1 } }
  }
  private func currentMood(at date: Date) -> BitMood {
    switch phase {
    case .idle, .ending, .unavailable: return .idle
    case .connecting: return .drilling
    case .active:
      let cue = gauge.cue(input: voice.levels.input, output: voice.levels.output, at: date)
      if cue == .interviewer { return .talking }
      if cue == .you { return .listening }
      if voice.thinking || cue == .replyDue { return .thinking }
      return .idle
    }
  }
}

/// Who has the floor, with a short hold so a breath between words doesn't flip Bit back and forth.
@MainActor private final class SpeakerGauge {
  enum Cue { case interviewer, you, replyDue }
  private let hold: TimeInterval = 0.6
  private var interviewerUntil = Date.distantPast
  private var youUntil = Date.distantPast
  private var youSince: Date?
  /// After a real stretch of talking, the interviewer owes a reply; Bit thinks until it starts, or gives up after a few seconds.
  private var replyDueUntil: Date?
  func cue(input: Double, output: Double, at now: Date) -> Cue? {
    // The interviewer taking the floor answers whatever you just said.
    if output > 0.18 { interviewerUntil = now.addingTimeInterval(hold); replyDueUntil = nil; youSince = nil }
    if input > 0.22 {
      if youSince == nil { youSince = now }
      youUntil = now.addingTimeInterval(hold)
    }
    if now < interviewerUntil { return .interviewer }
    if now < youUntil { return .you }
    if let since = youSince {
      youSince = nil
      // A cough or an "mm" isn't a turn; half a second of speech is.
      if youUntil.timeIntervalSince(since) - hold >= 0.5 { replyDueUntil = youUntil.addingTimeInterval(4) }
    }
    if let due = replyDueUntil, now < due { return .replyDue }
    replyDueUntil = nil
    return nil
  }
}

/// The title, then the session clock once connected; it turns to a countdown in the last two minutes.
private struct VoiceRoomClock: View {
  let voice: LiveVoice
  @Binding var warned: Bool
  var body: some View {
    VStack(spacing: 0) {
      Text("Talk it through").font(.subheadline.weight(.semibold))
      if voice.phase == .active, let started = voice.startedAt {
        TimelineView(.periodic(from: started, by: 1)) { context in
          let elapsed = max(0, context.date.timeIntervalSince(started))
          let left = max(0, voice.sessionLimit - elapsed)
          let closing = left <= 120
          Text(closing ? "\(Self.clock(left)) left" : Self.clock(elapsed))
            .font(.caption.monospacedDigit())
            .foregroundStyle(closing ? AppPalette.accent : AppPalette.secondary)
            .onChange(of: closing) { _, now in if now { warned = true } }
        }
        .accessibilityIdentifier("voiceClock")
      }
    }
  }
  static func clock(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded(.down))
    return String(format: "%d:%02d", total / 60, total % 60)
  }
}

/// The microphone: one big circle in the middle of the dock. Filled and glowing while they can hear you, quiet while muted.
private struct MicControl: View {
  enum State: Equatable { case start, connecting, muted, live }
  let state: State
  let action: () -> Void
  @State private var pulse = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private let size: CGFloat = 80
  private var filled: Bool { state == .start || state == .live }
  private var label: String {
    switch state {
    case .start: "Start talking"
    case .connecting: "Connecting…"
    case .muted: "Unmute"
    case .live: "Mute"
    }
  }
  private var symbol: String {
    switch state {
    case .muted: AppIcon.microphoneMuted.rawValue
    default: AppIcon.microphone.rawValue
    }
  }
  var body: some View {
    Button(action: action) {
      VStack(spacing: 10) {
        ZStack {
          if state == .connecting {
            // One quiet ring breathing out from the mic while the line comes up.
            Circle().strokeBorder(AppPalette.action.opacity(0.6), lineWidth: 2)
              .scaleEffect(pulse ? 1.45 : 1)
              .opacity(pulse ? 0 : 0.9)
          }
          Circle()
            .fill(filled ? AppPalette.action : AppPalette.elevated)
            .overlay { Circle().strokeBorder(filled ? AppPalette.action.opacity(0.5) : AppPalette.hairline, lineWidth: 1) }
            .shadow(color: AppPalette.action.opacity(filled ? 0.35 : 0), radius: 18, y: 4)
          Image(systemName: symbol)
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(filled ? AppPalette.actionInk : state == .connecting ? AppPalette.secondary : AppPalette.primary)
            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        Text(label).font(.caption).foregroundStyle(AppPalette.secondary)
          .contentTransition(.identity).transaction { $0.animation = nil }
      }
      .frame(maxWidth: .infinity)
      .contentShape(Rectangle())
      .animation(reduceMotion ? nil : DrillbitMotion.selection, value: state)
    }
    .buttonStyle(DrillbitPressStyle(scale: 0.94))
    .disabled(state == .connecting)
    .accessibilityLabel(spoken)
    .accessibilityValue(state == .muted ? "Muted" : state == .live ? "Microphone on" : "")
    .accessibilityIdentifier(state == .start ? "voiceStart" : state == .connecting ? "voiceConnecting" : "voiceMute")
    .sensoryFeedback(.selection, trigger: state == .muted)
    .task(id: state == .connecting) {
      pulse = false
      guard state == .connecting, !reduceMotion else { return }
      withAnimation(.easeOut(duration: 1.3).repeatForever(autoreverses: false)) { pulse = true }
    }
  }
  private var spoken: String {
    switch state {
    case .start: "Start talking"
    case .connecting: "Connecting to voice"
    case .muted: "Unmute microphone"
    case .live: "Mute microphone"
    }
  }
}

/// A round transport control with its name underneath, like the phone app's call buttons.
private struct RoomControl: View {
  let title: String
  let symbol: String
  let fill: Color
  let ink: Color
  let identifier: String
  var spoken: String? = nil
  let action: () -> Void
  private let size: CGFloat = 56
  var body: some View {
    Button(action: action) {
      VStack(spacing: 10) {
        Image(systemName: symbol)
          .font(.system(size: 20, weight: .semibold))
          .foregroundStyle(ink)
          .frame(width: size, height: size)
          // Tinted fills sit on the page colour, so words scrolling under the dock never show through the button.
          .background { Circle().fill(AppPalette.background).overlay { Circle().fill(fill) } }
          .contentShape(Circle())
        Text(title).font(.caption).foregroundStyle(AppPalette.secondary)
      }
      .frame(maxWidth: .infinity)
      // Centres the smaller circle on the microphone's midline.
      .padding(.top, 12)
      // The gap between circle and caption is part of the button, not a hole in it.
      .contentShape(Rectangle())
    }
    .buttonStyle(DrillbitPressStyle())
    .accessibilityLabel(spoken ?? title)
    .accessibilityIdentifier(identifier)
  }
}


struct InterviewConversation<Header: View>: View {
  enum Style { case transcript, room }
  var state: InterviewState
  var latestOnly = false
  /// `.room` reads like the live interview: spoken lines in body type, the latest line kept a breath above the dock,
  /// following smoothly and with no button; once they scroll up the view is theirs until they come back to the end.
  var style: Style = .transcript
  var latestIdentifier: String? = nil
  @ViewBuilder var header: () -> Header
  @State private var livePosition = ScrollPosition(y: 0)
  @State private var historyPosition = ScrollPosition(y: 0)
  @State private var liveFollowing = true
  /// Unset until they scroll: the room starts on the latest line, a transcript starts at the top.
  @State private var historyFollowing: Bool?
  private var position: Binding<ScrollPosition> { latestOnly ? $livePosition : $historyPosition }
  private var following: Bool { latestOnly ? liveFollowing : historyFollowing ?? (style == .room) }
  private func setFollowing(_ value: Bool) { if latestOnly { liveFollowing = value } else { historyFollowing = value } }
  @State private var scrolling = false
  @State private var observedIdentity: String?
  /// Room only: earlier spoken rows fold to one line once the conversation has moved on; a tap reopens one.
  @State private var opened: Set<String> = []
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private var visibleTurns: [InterviewTurn] {
    let turns = state.turns.filter { turn in
      if ["hint", "example"].contains(turn.kind) { return false }
      return turn.kind != "voice" || (turn.voice ?? []).contains { !$0.text.isEmpty }
    }
    return latestOnly ? Array(turns.filter { $0.kind == "voice" }.suffix(1)) : turns
  }
  private var contentIdentity: String { visibleTurns.map { $0.id + String($0.voice?.count ?? 0) + ($0.result?.text ?? $0.partial ?? "") }.joined() }
  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 24) {
        header()
        ForEach(visibleTurns) { turn in
          VStack(alignment: .leading, spacing: 8) {
            if turn.kind == "voice" {
              let rows = latestOnly ? VoiceTranscript.latestRows(turn.voice ?? []) : VoiceTranscript.rows(turn.voice ?? [])
              // The current exchange (the last line from each side) stays open; everything before it folds.
              let keepOpen = Set([rows.lastIndex { $0.speaker == "user" }, rows.lastIndex { $0.speaker == "assistant" }].compactMap { $0 })
              ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                let latest = index == rows.count - 1 && turn.id == visibleTurns.last?.id && row.speaker == "assistant"
                if style == .room, turn.id == visibleTurns.last?.id {
                  let current = keepOpen.contains(index)
                  InterviewTurnRow(title: row.speaker == "user" ? "You" : "Interviewer", text: row.text,
                                   expanded: current || opened.contains(row.id), identifier: "voiceRowDisclosure-\(row.id)", textIdentifier: latest ? (latestIdentifier ?? "") : "voiceRow-\(row.id)") {
                    withAnimation(reduceMotion ? nil : DrillbitMotion.reveal) { if opened.contains(row.id) { opened.remove(row.id) } else { opened.insert(row.id) } }
                  }
                } else {
                  Text(row.speaker == "user" ? "You" : "Interviewer").font(.caption).foregroundStyle(.secondary)
                  Text(row.text)
                    .font(style == .room ? .body : nil)
                    .accessibilityIdentifier(latest ? (latestIdentifier ?? "") : "")
                }
              }
            } else {
            if turn.kind == "answer" { Text(turn.prompt).font(.headline) }
            Text(turn.kind == "answer" ? "You" : "You · " + turn.kind.capitalized).font(.caption).foregroundStyle(.secondary)
            if !turn.text.isEmpty { Text(turn.text) }
            else { Text(turn.kind == "hint" ? "Give me a nudge" : turn.kind == "example" ? "Show an example" : "Keep going") }
            if let result = turn.result { Text("Interviewer").font(.caption).foregroundStyle(.secondary); Text(result.text) }
            else { Text(turn.status == "failed" ? "Response unavailable" : "Response pending").foregroundStyle(.secondary) }
            }
          }
          Divider()
        }
        Color.clear.frame(height: 1).id("voiceLatest")
      }.frame(maxWidth:.infinity,alignment:.leading).padding(24).textSelection(.enabled)
      // The gap between the newest line and the mic: the words never sit against the dock.
      .padding(.bottom, style == .room ? 56 : 0)
    }
    .scrollPosition(position)
    .onScrollPhaseChange { _, phase in scrolling = phase == .interacting || phase == .decelerating }
    .onScrollGeometryChange(for: Bool.self) { $0.visibleRect.maxY >= $0.contentSize.height - 80 } action: { _, atEnd in
      if scrolling { setFollowing(atEnd) }
    }
    .task(id: contentIdentity) {
      let isUpdate = observedIdentity != nil
      observedIdentity = contentIdentity
      guard isUpdate else { return }
      await Task.yield()
      guard following, !scrolling, !Task.isCancelled else { return }
      withAnimation(reduceMotion ? nil : style == .room ? .smooth(duration: 0.45, extraBounce: 0) : .easeOut(duration: 0.18)) { position.wrappedValue.scrollTo(id: "voiceLatest", anchor: .bottom) }
    }
    .safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
      if !following, style != .room {
        Button { setFollowing(true); position.wrappedValue.scrollTo(id: "voiceLatest", anchor: .bottom) } label: {
          Image(systemName: AppIcon.latest.rawValue).font(.system(size: 20)).frame(width: 44, height: 44)
            .background(AppPalette.background, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityLabel("Latest").accessibilityIdentifier("voiceLatestButton").padding(8)
      }
    }
  }
}
extension InterviewConversation where Header == EmptyView {
  init(state: InterviewState) { self.state = state; self.header = { EmptyView() } }
}
