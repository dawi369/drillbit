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
