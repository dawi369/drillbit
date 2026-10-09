import SwiftUI

/// Presentation only: the interview shell owns the connection and pending receipts.
/// One quiet stage: the question, the interviewer's orb, who's talking and their last line.
struct InterviewVoiceRoom<Question: View>: View {
  let voice: LiveVoice
  let interview: InterviewController
  /// "5 of 6 left today · resets 2 AM", when the account has a daily allowance.
  var allowance: String? = nil
  @ViewBuilder var question: () -> Question
  var leave: () -> Void
  @State private var showingTranscript = false
  @State private var warned = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    ZStack {
      if showingTranscript {
        InterviewConversation(state: interview.displayState, latestOnly: false) { question() }
          .transition(.opacity)
      } else {
        stage.transition(.opacity)
      }
    }
    .animation(reduceMotion ? nil : DrillbitMotion.page, value: showingTranscript)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(AppPalette.background)
    .safeAreaInset(edge: .bottom, spacing: 0) { dock }
    .navigationTitle("Talk it through")
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden()
    .toolbar {
      ToolbarItem(placement: .principal) { VoiceRoomClock(voice: voice, warned: $warned) }
      // The keyboard is always one tap away; it never competes with the voice controls in the dock.
      ToolbarItem(placement: .topBarTrailing) {
        Button("Write", systemImage: "keyboard", action: leave)
          .accessibilityHint(voice.phase == .active ? "Ends voice and returns to writing. The interview stays open." : "Returns to writing")
          .accessibilityIdentifier("voiceBack")
      }
    }
    .sensoryFeedback(.impact(weight: .medium), trigger: voice.phase == .active) { _, live in live }
    .sensoryFeedback(.warning, trigger: warned) { _, now in now }
    .onChange(of: voice.phase) { _, phase in
      switch phase {
      case .connecting: warned = false
      case .active: AccessibilityNotification.Announcement("Connected. Go ahead and talk.").post()
      case .ending: AccessibilityNotification.Announcement("Voice ended.").post()
      default: break
      }
    }
    .onChange(of: warned) { _, now in if now { AccessibilityNotification.Announcement("Two minutes left in this voice session.").post() } }
  }

  // MARK: Stage

  private var stage: some View {
    GeometryReader { proxy in
      ScrollView {
        VStack(spacing: 0) {
          // The whole question, readable on open; the interviewer's reaction sits below it.
          question()
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.horizontal, 24).padding(.top, 8)
          Spacer(minLength: 32)
          VStack(spacing: 12) {
            if !typeSize.isAccessibilitySize {
              VoiceBit(voice: voice).frame(height: 72)
            }
            VoiceTurnLabel(voice: voice)
            caption
              .frame(maxWidth: 520)
              .padding(.horizontal, 32)
          }
          Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
      }
      .scrollBounceBehavior(.basedOnSize)
    }
  }

  /// The interviewer's latest line, in a fixed four-line box so the stage never jumps while they talk.
  @ViewBuilder private var caption: some View {
    if let line = latestInterviewerLine, voice.phase != .idle {
      Text(line)
        .font(.title3.weight(.medium))
        .multilineTextAlignment(.center)
        .lineLimit(4, reservesSpace: true)
        .truncationMode(.head)
        .foregroundStyle(AppPalette.primary)
        .contentTransition(.opacity)
        .animation(reduceMotion ? nil : DrillbitMotion.fast, value: line)
        .accessibilityLabel("Interviewer said: \(line)")
        .accessibilityIdentifier("voiceCaption")
    } else {
      Text(voice.phase == .idle ? "Say it out loud, like the real one.\nThe interviewer talks back." : " ")
        .font(.title3)
        .multilineTextAlignment(.center)
        .lineLimit(4, reservesSpace: true)
        .foregroundStyle(AppPalette.secondary)
    }
  }
  private var latestInterviewerLine: String? {
    guard let turn = interview.displayState.turns.last(where: { $0.kind == "voice" }) else { return nil }
    return VoiceTranscript.rows(turn.voice ?? []).last { $0.speaker == "assistant" && !$0.text.isEmpty }?.text
  }

  // MARK: Dock

  @ViewBuilder private var dock: some View {
    VStack(spacing: 12) {
      if let message = voice.message {
        Text(message).font(.footnote).foregroundStyle(AppPalette.secondary)
          .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
      }
      switch voice.phase {
      case .idle:
        Button { Task { await voice.start() } } label: {
          Label("Start talking", systemImage: AppIcon.microphone.rawValue)
        }
        .buttonStyle(PracticeButtonStyle())
        .accessibilityIdentifier("voiceStart")
        // The cap and today's allowance sit under the button, where the decision is made.
        Text(["Up to \(Int(LiveVoice.sessionLimit / 60)) min", allowance].compactMap { $0 }.joined(separator: " · "))
          .font(.footnote).foregroundStyle(AppPalette.secondary)
          .multilineTextAlignment(.center)
          .accessibilityIdentifier("voiceAllowance")
      case .connecting:
        // The stage already says it's connecting; the dock only offers the way out.
        Button("Cancel", action: leave)
          .buttonStyle(PracticeButtonStyle(secondary: true))
          .accessibilityHint("Stops connecting and returns to writing")
          .accessibilityIdentifier("voiceCancel")
      case .active:
        HStack(alignment: .top, spacing: 0) {
          RoomControl(title: showingTranscript ? "Live" : "Transcript", symbol: showingTranscript ? AppIcon.voice.rawValue : AppIcon.transcript.rawValue, size: 56,
            fill: AppPalette.elevated, ink: AppPalette.primary, identifier: "voiceHistory") { showingTranscript.toggle() }
          RoomControl(title: voice.muted ? "Unmute" : "Mute", symbol: voice.muted ? AppIcon.microphoneMuted.rawValue : AppIcon.microphone.rawValue, size: 72,
            fill: voice.muted ? AppPalette.elevated : AppPalette.action, ink: voice.muted ? AppPalette.destructive : AppPalette.actionInk,
            identifier: "voiceMute", spoken: voice.muted ? "Unmute microphone" : "Mute microphone") { voice.toggleMute() }
            .accessibilityValue(voice.muted ? "Muted" : "Microphone on")
            .sensoryFeedback(.selection, trigger: voice.muted)
          RoomControl(title: "End", symbol: AppIcon.end.rawValue, size: 56,
            fill: AppPalette.destructive.opacity(0.16), ink: AppPalette.destructive, identifier: "voiceEnd", spoken: "End voice", action: leave)
            .accessibilityHint("Stops talking and returns to writing. The interview stays open.")
        }
        .frame(maxWidth: 360)
        #if DEBUG
        if interview.model.fixture, ProcessInfo.processInfo.arguments.contains("--fixture-voice") {
          Button("Simulate speech") { Task { await voice.fixtureSpeech() } }.font(.footnote).accessibilityIdentifier("voiceFixtureSpeech")
        }
        #endif
      case .ending:
        LoadingStatus("Saving the conversation…", centered: true)
      case .unavailable:
        Button {
          Task { if voice.blocksText { await voice.retrySync() } else { await voice.start() } }
        } label: { Label("Try again", systemImage: AppIcon.retry.rawValue) }
          .buttonStyle(PracticeButtonStyle())
          .accessibilityIdentifier("voiceRetry")
      }
    }
    .frame(maxWidth: 560)
    .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 8)
    .frame(maxWidth: .infinity)
    .background(AppPalette.background)
    .animation(reduceMotion ? nil : DrillbitMotion.reveal, value: voice.phase)
  }
}

/// Bit as the interviewer's presence in the room: talking from measured output, listening while you speak, thinking while a reply is on its way.
private struct VoiceBit: View {
  let voice: LiveVoice
  @State private var gauge = SpeakerGauge()
  var body: some View {
    TimelineView(.periodic(from: .now, by: 0.2)) { context in
      BitView(mood: mood(at: context.date), levels: voice.levels)
    }
  }
  private func mood(at date: Date) -> BitMood {
    switch voice.phase {
    case .idle, .ending, .unavailable: return .idle
    case .connecting: return .thinking
    case .active:
      if voice.muted { return .idle }
      if voice.thinking { return .thinking }
      switch gauge.speaker(input: voice.levels.input, output: voice.levels.output, at: date) {
      case .interviewer: return .talking
      case .you: return .listening
      case nil: return .idle
      }
    }
  }
}

/// Who has the floor, read from measured audio a few times a second. A short hold keeps it from flickering between words.
private struct VoiceTurnLabel: View {
  let voice: LiveVoice
  @State private var gauge = SpeakerGauge()
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    TimelineView(.periodic(from: .now, by: 0.2)) { context in
      let text = label(at: context.date)
      let muted = voice.muted && voice.phase == .active
      HStack(spacing: 8) {
        // One small dot carries the state's colour; the words carry its meaning.
        Circle().fill(muted ? AppPalette.destructive : voice.phase == .active ? AppPalette.action : AppPalette.secondary)
          .frame(width: 6, height: 6)
          .opacity(voice.phase == .connecting && !reduceMotion ? 0.4 + 0.6 * (0.5 + 0.5 * sin(context.date.timeIntervalSinceReferenceDate * 4)) : 1)
        Text(text)
          .font(.subheadline.weight(.medium))
          .foregroundStyle(muted ? AppPalette.destructive : AppPalette.secondary)
          .contentTransition(.opacity)
      }
      .animation(DrillbitMotion.fast, value: text)
    }
    // Speaker changes stay visual; VoiceOver hears only steady states.
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(steady)
    .accessibilityIdentifier("voiceState")
  }
  private var steady: String {
    switch voice.phase {
    case .idle: "Ready when you are"
    case .connecting: "Connecting"
    case .active: voice.muted ? "Mic off. They can’t hear you." : voice.thinking ? "Working through your answer" : "Voice connected"
    case .ending: "Saving the conversation"
    case .unavailable: "Voice is off"
    }
  }
  private func label(at date: Date) -> String {
    guard voice.phase == .active, !voice.muted, !voice.thinking else { return steady }
    switch gauge.speaker(input: voice.levels.input, output: voice.levels.output, at: date) {
    case .interviewer: return "Interviewer’s talking"
    case .you: return "You’re talking"
    case nil: return "Listening"
    }
  }
}

@MainActor private final class SpeakerGauge {
  enum Speaker { case interviewer, you }
  private var interviewerUntil = Date.distantPast
  private var youUntil = Date.distantPast
  func speaker(input: Double, output: Double, at now: Date) -> Speaker? {
    if output > 0.18 { interviewerUntil = now.addingTimeInterval(0.6) }
    if input > 0.22 { youUntil = now.addingTimeInterval(0.6) }
    if now < interviewerUntil { return .interviewer }
    if now < youUntil { return .you }
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
          let left = max(0, LiveVoice.sessionLimit - elapsed)
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

/// A round transport control with its name underneath, like the phone app's call buttons.
private struct RoomControl: View {
  let title: String
  let symbol: String
  let size: CGFloat
  let fill: Color
  let ink: Color
  let identifier: String
  var spoken: String? = nil
  let action: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    Button(action: action) {
      VStack(spacing: 8) {
        Image(systemName: symbol)
          .font(.system(size: size * 0.36, weight: .semibold))
          .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
          .foregroundStyle(ink)
          .frame(width: size, height: size)
          .background(fill, in: Circle())
          .contentShape(Circle())
        Text(title).font(.caption).foregroundStyle(AppPalette.secondary)
          .contentTransition(.identity).transaction { $0.animation = nil }
      }
      .frame(maxWidth: .infinity)
      .animation(DrillbitMotion.selection, value: symbol)
    }
    .buttonStyle(DrillbitPressStyle())
    .accessibilityLabel(spoken ?? title)
    .accessibilityIdentifier(identifier)
  }
}


struct InterviewConversation<Header: View>: View {
  var state: InterviewState
  var latestOnly = false
  @ViewBuilder var header: () -> Header
  @State private var livePosition = ScrollPosition(y: 0)
  @State private var historyPosition = ScrollPosition(y: 0)
  @State private var liveFollowing = true
  @State private var historyFollowing = false
  private var position: Binding<ScrollPosition> { latestOnly ? $livePosition : $historyPosition }
  private var following: Bool { latestOnly ? liveFollowing : historyFollowing }
  private func setFollowing(_ value: Bool) { if latestOnly { liveFollowing = value } else { historyFollowing = value } }
  @State private var scrolling = false
  @State private var observedIdentity: String?
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
              ForEach(latestOnly ? VoiceTranscript.latestRows(turn.voice ?? []) : VoiceTranscript.rows(turn.voice ?? [])) { row in
                Text(row.speaker == "user" ? "You" : "Interviewer").font(.caption).foregroundStyle(.secondary)
                Text(row.text)
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
      withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { position.wrappedValue.scrollTo(id: "voiceLatest", anchor: .bottom) }
    }
    .safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
      if !following {
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
