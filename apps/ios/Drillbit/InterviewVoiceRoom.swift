import SwiftUI

/// Presentation only: the interview shell owns the connection and pending receipts.
struct InterviewVoiceRoom<Question: View>: View {
  let voice: LiveVoice
  let interview: InterviewController
  @ViewBuilder var question: () -> Question
  var leave: () -> Void
  @State private var showingHistory = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    InterviewConversation(state: interview.displayState, latestOnly: !showingHistory) {
      VStack(alignment: .leading, spacing: 12) {
        question()
        if !showingHistory {
          SignalPresence(mode: presenceMode, density: 720, levels: voice.levels)
            .frame(height: 240)
          SignalEyebrow(text: voiceState)
            .contentTransition(.opacity)
            .frame(maxWidth: .infinity)
            .animation(DrillbitMotion.fast, value: voiceState)
        }
      }
    }
      .background(AppPalette.background)
      .safeAreaInset(edge: .bottom, spacing: 0) { controls }
      .navigationTitle(interview.challenge.scenario?.split(whereSeparator: \.isWhitespace).prefix(2).joined(separator: " ") ?? "Voice interview")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Back", action: leave)
            .accessibilityHint("Ends voice and returns to writing")
            .accessibilityIdentifier("voiceBack")
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button(showingHistory ? "Live" : "History", systemImage: showingHistory ? AppIcon.voice.rawValue : AppIcon.history.rawValue) { showingHistory.toggle() }
            .accessibilityIdentifier("voiceHistory")
        }
      }
  }
  private var status: String? {
    switch voice.phase {
    case .idle: nil
    case .connecting: "Connecting…"
    case .active: nil
    case .ending: "Voice ended · saving conversation"
    case .unavailable: "Voice unavailable"
    }
  }
  private var presenceMode: SignalPresence.Mode {
    switch voice.phase {
    case .idle: .ambient
    case .connecting: .connecting
    case .active: voice.muted ? .muted : .live
    case .ending, .unavailable: .still
    }
  }
  private var voiceState: String {
    switch voice.phase {
    case .idle: "Ready"
    case .connecting: "Connecting"
    case .active: voice.muted ? "Microphone muted" : "Voice connected"
    case .ending: "Saving voice"
    case .unavailable: "Voice unavailable"
    }
  }
  private var controls: some View {
    VStack(spacing: 12) {
      // The live view already names Connecting under the presence field.
      if let status, showingHistory || voice.phase != .connecting { Text(status).font(.subheadline).foregroundStyle(.secondary) }
      if let message = voice.message { Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center) }
      HStack(alignment: .top, spacing: 16) {
        Spacer(minLength: 0)
        if voice.phase == .idle || voice.phase == .connecting || voice.phase == .active {
          Button {
            if voice.phase == .idle { Task { await voice.start() } }
            else { voice.toggleMute() }
          } label: {
            VStack(spacing: 8) {
              Image(systemName: voice.phase == .active ? (voice.muted ? AppIcon.microphoneMuted.rawValue : AppIcon.microphone.rawValue) : AppIcon.start.rawValue)
              .font(.title3.weight(.medium))
              .symbolRenderingMode(.monochrome)
              .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
              .foregroundStyle(voice.muted ? AppPalette.destructive : AppPalette.actionInk)
              .frame(width: 116, height: 56)
              .background(voice.muted ? AppPalette.surface : AppPalette.action, in: Capsule())
              .contentShape(Capsule())
              Text(voice.phase == .active ? (voice.muted ? "Unmute" : "Mute") : "Start")
                .font(.caption).foregroundStyle(AppPalette.secondary)
                .contentTransition(.identity).transaction { $0.animation = nil }
            }
              .opacity(voice.phase == .connecting ? 0.4 : 1)
              .animation(DrillbitMotion.selection, value: voice.muted)
              .animation(DrillbitMotion.selection, value: voice.phase)
          }
          .buttonStyle(DrillbitPressStyle())
          .disabled(voice.phase == .connecting)
          .sensoryFeedback(.impact(weight: .medium), trigger: voice.phase == .active) { _, live in live }
          .sensoryFeedback(.selection, trigger: voice.muted)
          .accessibilityIdentifier(voice.phase == .active ? "voiceMute" : "voiceStart")
          .accessibilityLabel(voice.phase == .active ? (voice.muted ? "Unmute microphone" : "Mute microphone") : "Start voice")
          .accessibilityValue(voice.phase == .active ? (voice.muted ? "Muted" : "Microphone on") : "Microphone off")
        }
        if voice.phase == .unavailable {
          voiceControl("Retry", symbol: AppIcon.retry.rawValue, id: "voiceRetry") { Task {
            if voice.blocksText { await voice.retrySync() } else { await voice.start() }
          } }
        }
        Spacer(minLength: 0)
      }.frame(maxWidth: .infinity)
      #if DEBUG
      if interview.model.fixture, ProcessInfo.processInfo.arguments.contains("--fixture-voice"), voice.phase == .active {
        Button("Simulate speech") { Task { await voice.fixtureSpeech() } }.font(.system(size: 17)).accessibilityIdentifier("voiceFixtureSpeech")
      }
      #endif
    }.padding(24).background(AppPalette.background)
  }
  private func voiceControl(_ title: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      VStack(spacing: 8) {
        Image(systemName: symbol).font(.title3.weight(.medium))
          .frame(width: 76, height: 56).background(AppPalette.elevated, in: Capsule())
        Text(title).font(.caption).multilineTextAlignment(.center).contentTransition(.identity).transaction { $0.animation = nil }
      }.frame(maxWidth: .infinity)
    }.buttonStyle(DrillbitPressStyle()).accessibilityIdentifier(id)
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
