import AVFoundation
import SwiftUI

/// GPT-Live's English voices. Each ships a clip recorded from the live model itself
/// (`scripts/record-voice-previews.ts`), so a preview sounds like a real mock.
struct InterviewerVoice: Identifiable, Hashable {
  let id: String
  let accent: String?
  var name: String { id.prefix(1).uppercased() + id.dropFirst() }

  static let byDefault = "marin"
  static let groups: [(title: String, voices: [InterviewerVoice])] = [
    ("Most natural", [.init(id: "marin", accent: nil), .init(id: "cedar", accent: nil)]),
    ("Classic", ["alloy", "ash", "ballad", "coral", "echo", "sage", "shimmer", "verse"].map { .init(id: $0, accent: nil) }),
    ("Accents", [
      .init(id: "gleam", accent: "North American"), .init(id: "meridian", accent: "North American"),
      .init(id: "delta", accent: "Southern US"), .init(id: "cinder", accent: "Southern US"),
      .init(id: "vesper", accent: "British"), .init(id: "willow", accent: "Irish"), .init(id: "stone", accent: "Irish"),
      .init(id: "quartz", accent: "Australian"), .init(id: "ripple", accent: "Australian"), .init(id: "beacon", accent: "Filipino"),
    ]),
  ]
  static func name(_ id: String?) -> String {
    groups.flatMap(\.voices).first { $0.id == (id ?? byDefault) }?.name ?? "Marin"
  }
}

struct InterviewerVoiceView: View {
  @Binding var selection: String?
  @State private var player = VoicePreviewPlayer()

  var body: some View {
    SignalList {
      ForEach(InterviewerVoice.groups, id: \.title) { group in
        Section(group.title) {
          ForEach(group.voices) { voice in row(voice) }
        }
      }
      Section {} footer: {
        Text("Tap one to hear it. Your next voice rep talks like that.")
      }
    }
    .navigationTitle("Interviewer voice")
    .onDisappear { player.stop() }
  }

  private func row(_ voice: InterviewerVoice) -> some View {
    let chosen = (selection ?? InterviewerVoice.byDefault) == voice.id
    let playing = player.playing == voice.id
    return Button {
      selection = voice.id
      player.toggle(voice.id)
    } label: {
      HStack(spacing: 12) {
        Image(systemName: playing ? "speaker.wave.2.fill" : "play.circle")
          .symbolEffect(.variableColor.iterative, isActive: playing)
          .foregroundStyle(AppPalette.primary)
          .frame(width: 28)
        VStack(alignment: .leading, spacing: 2) {
          Text(voice.name).foregroundStyle(.primary)
          if let accent = voice.accent {
            Text(accent).font(.footnote).foregroundStyle(.secondary)
          }
        }
        Spacer()
        if chosen {
          Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(AppPalette.primary)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(voice.accent.map { "\(voice.name), \($0)" } ?? voice.name)
    .accessibilityValue(chosen ? "Selected" : "")
    .accessibilityHint(playing ? "Stops the sample" : "Picks this voice and plays a sample")
    .accessibilityAddTraits(chosen ? .isSelected : [])
    .accessibilityIdentifier("voice-\(voice.id)")
  }
}

@MainActor @Observable final class VoicePreviewPlayer: NSObject, AVAudioPlayerDelegate {
  private(set) var playing: String?
  private var player: AVAudioPlayer?

  func toggle(_ voice: String) {
    if playing == voice { stop(); return }
    stop()
    guard let url = Bundle.main.url(forResource: "voice-\(voice)", withExtension: "m4a"),
          let next = try? AVAudioPlayer(contentsOf: url) else { return }
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
    try? AVAudioSession.sharedInstance().setActive(true)
    next.delegate = self
    next.play()
    player = next
    playing = voice
  }

  func stop() {
    player?.stop()
    player = nil
    if playing != nil { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    playing = nil
  }

  nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    let finished = ObjectIdentifier(player)
    Task { @MainActor in if self.player.map(ObjectIdentifier.init) == finished { self.stop() } }
  }
}
