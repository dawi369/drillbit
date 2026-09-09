import SwiftUI

struct CompanionPanel: View {
  var practice: PracticeController
  var expand: () -> Void
  @Environment(\.dynamicTypeSize) private var size
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
  private var reduceMotion: Bool {
    systemReduceMotion
      || (practice.model.fixture && ProcessInfo.processInfo.arguments.contains("--reduce-effects"))
  }
  private var reduceTransparency: Bool {
    systemReduceTransparency
      || (practice.model.fixture && ProcessInfo.processInfo.arguments.contains("--reduce-effects"))
  }
  private var companion: CompanionCoordinator { practice.companion }
  var body: some View {
    HStack(spacing: 12) {
      Button(action: expand) {
        VStack(alignment: .leading, spacing: 4) {
          if !size.isAccessibilitySize {
            Text(
              companion.context.paused ? "\(practice.mode.rawValue) paused" : practice.mode.rawValue
            )
            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
          }
          if size.isAccessibilitySize {
            Text(
              companion.suggestion == nil
                ? "\(practice.mode.rawValue) help" : "\(practice.mode.rawValue) suggestion"
            )
            .font(.caption).lineLimit(2)
            .accessibilityLabel(
              companion.suggestion == nil
                ? "Open help" : "\(practice.mode.rawValue) has a suggestion")
          } else {
            Text(
              companion.unavailable ?? companion.suggestion?.body
                ?? (companion.context.paused ? "Take your time." : "Here when you need a hand.")
            )
            .font(.subheadline).lineLimit(3)
            .id(companion.suggestion?.id ?? "quiet")
            .transition(
              .opacity.combined(with: .offset(y: reduceMotion || companion.replacing ? 0 : 4)))
          }
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
      }.buttonStyle(.plain).accessibilityIdentifier("openHelp")
      if companion.context.paused {
        Button("Resume") { Task { await practice.pauseCompanion(false) } }.font(.subheadline)
      } else if companion.showProgress {
        ProgressView().controlSize(.small).accessibilityLabel("Preparing help")
      }
    }
    .padding(12)
    .frame(height: size.isAccessibilitySize ? 80 : 100)
    .background {
      if reduceTransparency {
        RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground))
      } else {
        RoundedRectangle(cornerRadius: 12).fill(.regularMaterial)
      }
    }
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .stroke(
          LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing),
          lineWidth: 1
        )
        .opacity(companion.requestingSince != nil || companion.suggestion != nil ? 0.35 : 0)
        .animation(
          reduceMotion ? nil : .easeOut(duration: 0.6), value: companion.requestingSince != nil
        )
        .allowsHitTesting(false)
    }
    .animation(
      reduceMotion ? nil : .easeInOut(duration: companion.replacing ? 0.2 : 0.35),
      value: companion.suggestion?.id
    )
    .padding(.horizontal, 24)
    .task(id: companion.requestingSince) {
      companion.showProgress = false
      guard companion.requestingSince != nil else { return }
      try? await Task.sleep(for: .seconds(1))
      guard !Task.isCancelled, companion.requestingSince != nil else { return }
      companion.showProgress = true
    }
  }
}
