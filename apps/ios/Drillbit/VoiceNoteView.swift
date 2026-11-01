import AVFoundation
import SwiftUI

/// Settings → Feedback: a voice note straight to the developer. Voice only, two minutes at most; listen back, then send.
/// The recording is stored with the account on Drillbit's server and never goes to an AI provider.
struct VoiceNoteView: View {
  var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var recorder = VoiceNoteRecorder()
  @State private var sending = false
  @State private var sent = false
  @State private var failure: String?
  /// One recording, one command: a retried send can't arrive twice. Redo starts a new one.
  @State private var command = UUID().uuidString

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 24) {
          BitView(mood: sent ? .happy : recorder.phase == .recording ? .listening : .idle, greets: true)
            .frame(height: 88)
            .padding(.top, 24)
          VStack(spacing: 8) {
            Text(copy.title).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Text(copy.detail).font(.subheadline).foregroundStyle(AppPalette.secondary)
          }
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
          if [.recording, .recorded].contains(recorder.phase), !sent {
            Text("\(Self.clock(recorder.phase == .recording ? recorder.elapsed : recorder.duration)) / \(Self.clock(VoiceNoteRecorder.limit))")
              .font(.body.monospacedDigit())
              .foregroundStyle(AppPalette.secondary)
              .contentTransition(.numericText())
              .accessibilityLabel("\(Int(recorder.phase == .recording ? recorder.elapsed : recorder.duration)) seconds of two minutes")
          }
          if let failure {
            Text(failure).font(.subheadline).foregroundStyle(AppPalette.destructive).multilineTextAlignment(.center)
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
      }
      .safeAreaInset(edge: .bottom) { controls.padding(24).background(AppPalette.background) }
      .background(AppPalette.background)
      .animation(reduceMotion ? nil : DrillbitMotion.reveal, value: recorder.phase)
      .animation(reduceMotion ? nil : DrillbitMotion.reveal, value: sent)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(sent ? "Close" : "Cancel") { dismiss() }.disabled(sending)
        }
      }
    }
    .accessibilityIdentifier("voiceNote")
    .onAppear { recorder.simulated = model.fixture }
    .onDisappear { recorder.discard() }
    // Recording stops when the app leaves the foreground; what was said so far is kept.
    .onChange(of: scenePhase) { _, phase in if phase != .active, recorder.phase == .recording { finish() } }
    .onChange(of: recorder.reachedLimit) { _, reached in if reached { finish() } }
  }

  private var copy: (title: String, detail: String) {
    if sent { return ("Thank you.", "It’s on its way to me. Notes like this are how the app gets better.") }
    switch recorder.phase {
    case .denied: return ("I need your mic for this.", "Turn on the microphone for Drillbit in Settings, then come back.")
    case .recording: return ("Listening…", "Tap stop when you’re done. Two minutes at most.")
    case .recorded: return ("Got it down.", "Listen back if you like, then send it.")
    case .idle: return ("Tell me what to fix.", "Voice only, up to two minutes. What’s broken, what’s missing, what you’d love. I listen to every one.")
    }
  }

  @ViewBuilder private var controls: some View {
    if sent {
      Button("Done") { dismiss() }.buttonStyle(PracticeButtonStyle()).accessibilityIdentifier("voiceNoteDone")
    } else {
      switch recorder.phase {
      case .denied:
        Button("Open Settings") {
          if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        }.buttonStyle(PracticeButtonStyle())
      case .idle, .recording:
        RecordButton(recording: recorder.phase == .recording, level: recorder.level) {
          if recorder.phase == .recording { finish() } else { Task { failure = nil; await recorder.start() } }
        }
        .frame(maxWidth: .infinity)
      case .recorded:
        VStack(spacing: 12) {
          HStack(spacing: 12) {
            Button(recorder.playing ? "Pause" : "Listen back", systemImage: recorder.playing ? "pause.fill" : "play.fill") { recorder.togglePlayback() }
              .buttonStyle(PracticeButtonStyle(secondary: true))
              .accessibilityIdentifier("voiceNotePlay")
            Button("Redo", systemImage: "arrow.counterclockwise") { failure = nil; command = UUID().uuidString; recorder.discard() }
              .buttonStyle(PracticeButtonStyle(secondary: true))
              .disabled(sending)
          }
          Button(sending ? "Sending…" : "Send it") { Task { await send() } }
            .buttonStyle(PracticeButtonStyle())
            .disabled(sending)
            .accessibilityIdentifier("voiceNoteSend")
        }
      }
    }
  }

  private func finish() {
    recorder.stop()
    if recorder.duration < 1.5 {
      recorder.discard()
      failure = "That was quick. Try a few seconds more."
    }
  }

  private func send() async {
    sending = true
    failure = nil
    defer { sending = false }
    do {
      if model.fixture {
        try await Task.sleep(for: .milliseconds(600))
      } else {
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String).map { "\($0) (\(info?["CFBundleVersion"] as? String ?? "?"))" }
        let input = VoiceNoteInput(audio: try recorder.audio().base64EncodedString(), durationSeconds: recorder.duration, appVersion: version)
        let _: VoiceNoteReceipt = try await model.api.send("feedback/voice", method: "POST", body: input, command: command)
      }
      recorder.discard(keepPhase: true)
      withAnimation(reduceMotion ? nil : DrillbitMotion.celebrate) { sent = true }
    } catch {
      failure = "Couldn’t send it. Your recording’s still here, so try again in a moment."
    }
  }

  static func clock(_ seconds: TimeInterval) -> String {
    let whole = Int(seconds.rounded(.down))
    return String(format: "%d:%02d", whole / 60, whole % 60)
  }
}

private struct VoiceNoteInput: Encodable {
  let audio: String
  let durationSeconds: Double
  let appVersion: String?
}
private struct VoiceNoteReceipt: Decodable { let id: String }

/// The big round record button. While recording it turns into stop, and a soft ring follows your voice.
private struct RecordButton: View {
  let recording: Bool
  let level: Double
  let action: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    Button(action: action) {
      Image(systemName: recording ? "stop.fill" : "mic.fill")
        .font(.system(size: 30, weight: .semibold))
        .foregroundStyle(AppPalette.actionInk)
        .frame(width: 88, height: 88)
        .background(AppPalette.action, in: Circle())
        .background {
          Circle().fill(AppPalette.action.opacity(0.25))
            .scaleEffect(recording && !reduceMotion ? 1 + 0.35 * level : 1)
            .opacity(recording ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: level)
        }
        .contentTransition(.symbolEffect(.replace))
    }
    .buttonStyle(DrillbitPressStyle())
    .sensoryFeedback(.impact(weight: .light), trigger: recording)
    .accessibilityLabel(recording ? "Stop recording" : "Record a voice note")
    .accessibilityIdentifier("voiceNoteRecord")
  }
}

/// Records one AAC note to a temporary file and plays it back. Simulated (no microphone, no file) for UI fixtures.
@MainActor @Observable final class VoiceNoteRecorder {
  enum Phase: Equatable { case idle, recording, recorded, denied }
  static let limit: TimeInterval = 120
  private(set) var phase = Phase.idle
  private(set) var elapsed: TimeInterval = 0
  private(set) var duration: TimeInterval = 0
  /// 0...1, from the recorder's meter.
  private(set) var level = 0.0
  private(set) var playing = false
  private(set) var reachedLimit = false
  var simulated = false
  private var recorder: AVAudioRecorder?
  private var player: AVAudioPlayer?
  private var ticker: Task<Void, Never>?
  private var started = Date()
  private let url = FileManager.default.temporaryDirectory.appendingPathComponent("drillbit-voice-note.m4a")

  func start() async {
    reachedLimit = false
    if simulated { begin(); return }
    guard await AVAudioApplication.requestRecordPermission() else { phase = .denied; return }
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
      try session.setActive(true)
      try? FileManager.default.removeItem(at: url)
      let next = try AVAudioRecorder(url: url, settings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 22_050, AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 32_000, AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
      ])
      next.isMeteringEnabled = true
      guard next.record(forDuration: Self.limit) else { throw CocoaError(.fileWriteUnknown) }
      recorder = next
      begin()
    } catch {
      deactivate()
      phase = .idle
    }
  }

  private func begin() {
    started = .now
    elapsed = 0
    phase = .recording
    ticker?.cancel()
    ticker = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(50))
        self?.tick()
      }
    }
  }

  private func tick() {
    if phase == .recording {
      if let recorder {
        elapsed = recorder.isRecording ? recorder.currentTime : elapsed
        recorder.updateMeters()
        // -50 dB and below is silence; 0 dB is as loud as it gets.
        level = max(0, min(1, (Double(recorder.averagePower(forChannel: 0)) + 50) / 50))
        if !recorder.isRecording { reachedLimit = true }
      } else {
        elapsed = Date.now.timeIntervalSince(started)
        level = 0.3 + 0.3 * sin(elapsed * 6)
        if elapsed >= Self.limit { reachedLimit = true }
      }
    }
    if playing, player?.isPlaying != true { playing = false }
  }

  func stop() {
    guard phase == .recording else { return }
    recorder?.stop()
    duration = min(elapsed, Self.limit)
    level = 0
    phase = .recorded
  }

  func togglePlayback() {
    if simulated { playing.toggle(); return }
    if playing { player?.pause(); playing = false; return }
    if player == nil { player = try? AVAudioPlayer(contentsOf: url) }
    playing = player?.play() == true
  }

  func audio() throws -> Data { try Data(contentsOf: url) }

  /// Throws the recording away. `keepPhase` leaves the screen as it is (after a send).
  func discard(keepPhase: Bool = false) {
    recorder?.stop(); recorder = nil
    player?.stop(); player = nil
    playing = false
    ticker?.cancel(); ticker = nil
    try? FileManager.default.removeItem(at: url)
    deactivate()
    if !keepPhase { phase = phase == .denied ? .denied : .idle; elapsed = 0; duration = 0; level = 0; reachedLimit = false }
  }

  private func deactivate() {
    guard !simulated else { return }
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
}
