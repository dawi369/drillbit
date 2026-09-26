import SwiftUI

struct CompanionPanel: View {
  var practice: PracticeController
  var expand: () -> Void
  @Environment(\.dynamicTypeSize) private var size
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
          }
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
      }.buttonStyle(.plain).accessibilityIdentifier("openHelp")
      if companion.context.paused {
        Button("Resume") { Task { await practice.pauseCompanion(false) } }.font(.subheadline)
      } else if companion.showProgress {
        ProgressView().controlSize(.small).accessibilityLabel("Preparing help")
      }
    }
    .padding(.horizontal, 24).padding(.vertical, 12)
    .frame(minHeight: 100)
    .overlay(alignment: .top) {
      (companion.requestingSince != nil || companion.suggestion != nil
       ? AppPalette.accent : AppPalette.hairline).frame(height: 1)
    }
    .task(id: companion.requestingSince) {
      companion.showProgress = false
      guard companion.requestingSince != nil else { return }
      try? await Task.sleep(for: .seconds(1))
      guard !Task.isCancelled, companion.requestingSince != nil else { return }
      companion.showProgress = true
    }
  }
}
