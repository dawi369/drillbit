import SwiftUI

/// Bit, drawn every frame from `BitDynamics`. Decorative: any state it shows is also stated in text nearby.
/// Reduce Motion renders the mood's still pose; background and offscreen views freeze and resume.
struct BitView: View {
  var mood: BitMood = .idle
  var finish: BitFinish = .satin
  /// Measured audio only: the interviewer's output level drives the mouth while talking.
  var levels: VoiceLevels? = nil
  /// One happy hop on first appearance.
  var greets = false
  /// Each change is one happy hop, for a result that just arrived. No haptic: only taps play one.
  var cheers = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var visible = false
  @State private var dynamics = BitDynamics()
  @State private var taps = 0
  @State private var hops = 0
  @State private var lively = false

  var body: some View {
    let style = finish.style
    let paused = reduceMotion || !visible || scenePhase == .background
    TimelineView(.animation(minimumInterval: interval, paused: paused)) { timeline in
      let pose = reduceMotion ? BitPose.rest(mood)
        : paused ? dynamics.current : dynamics.advance(to: timeline.date, mood: mood, level: levels?.output)
      Canvas { context, size in
        BitRenderer.draw(pose, style: style, in: &context, size: size)
      }
    }
    .aspectRatio(BitShape.viewBox.width / BitShape.viewBox.height, contentMode: .fit)
    .contentShape(Rectangle())
    .onTapGesture {
      guard !reduceMotion else { return }
      taps += 1
      hop()
    }
    .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: taps)
    .onChange(of: cheers) { hop() }
    .task(id: hops) {
      guard hops > 0 else { return }
      lively = true
      do { try await Task.sleep(for: .seconds(1.6)) } catch { return }
      lively = false
    }
    .onAppear {
      visible = true
      if greets { hop() }
    }
    .onDisappear { visible = false }
    .accessibilityHidden(true)
  }

  private func hop() {
    guard !reduceMotion else { return }
    dynamics.boop()
    hops += 1
  }

  /// Calm moods run at 30 fps; hops, spins and speech get 60. Low Power Mode caps everything at 20.
  private var interval: Double {
    if ProcessInfo.processInfo.isLowPowerModeEnabled { return 1.0 / 20 }
    return lively || [.talking, .happy, .drilling].contains(mood) ? 1.0 / 60 : 1.0 / 30
  }
}

#Preview("Bit") {
  ScrollView {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 16) {
      ForEach(BitMood.allCases, id: \.self) { mood in BitView(mood: mood).frame(height: 140) }
      ForEach(BitFinish.allCases, id: \.self) { finish in BitView(finish: finish).frame(height: 140) }
    }
    .padding()
  }
  .background(AppPalette.background)
}
