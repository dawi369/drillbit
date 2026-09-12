import SwiftUI

enum AppPalette {
  static let background = Color(uiColor: .systemBackground)
  static let surface = Color(uiColor: .secondarySystemBackground)
  static let primary = Color.primary
  static let secondary = Color.secondary
  static let destructive = Color(uiColor: .systemRed)
  static let success = Color(uiColor: .systemGreen)
}

struct PracticeButtonStyle: ButtonStyle {
  var secondary = false
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.body.weight(.semibold))
      .multilineTextAlignment(.center)
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity, minHeight: 48)
      .foregroundStyle(secondary ? AppPalette.primary : AppPalette.background)
      .background(
        secondary ? AppPalette.surface : AppPalette.primary,
        in: RoundedRectangle(cornerRadius: 12)
      )
      .contentShape(RoundedRectangle(cornerRadius: 12))
      .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.5)
      .hoverEffect(.highlight)
  }
}

struct LoadingStatus: View {
  let message: String
  init(_ message: String) { self.message = message }
  var body: some View {
    VStack(spacing: 12) {
      ProgressView().accessibilityHidden(true)
      Text(message).font(.subheadline).foregroundStyle(.secondary)
        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
    }.frame(maxWidth: .infinity).padding(24)
      .accessibilityElement(children: .combine)
  }
}

/// Native symbol catalog shared by navigation and actions throughout the app.
enum AppIcon: String, CaseIterable {
  case settings = "gearshape"
  case send = "arrow.up"
  case latest = "arrow.down"
  case undo = "arrow.uturn.backward"
  case checkmark = "checkmark"
  case skip = "forward"
  case hint = "lightbulb"
  case preferences = "slider.horizontal.3"
  case text = "text.alignleft"
  case more = "ellipsis"
  case voice = "waveform"
  case books = "books.vertical"
  case completed = "checkmark.circle"
  case filter = "line.3.horizontal.decrease"
  case delete = "trash"
  case assistance = "sparkle"
  case retry = "arrow.clockwise"
  case regenerate = "arrow.triangle.2.circlepath"
  case library = "book.closed"
  case home = "house"
  case apple = "apple.logo"
  case start = "play.fill"
  case microphone = "mic.fill"
  case microphoneMuted = "mic.slash.fill"
  case history = "clock.arrow.circlepath"
  case collapsed = "chevron.right"
  case expanded = "chevron.down"
}
