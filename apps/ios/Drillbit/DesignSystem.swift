import SwiftUI

/// Drillbit stays close to iOS: quiet semantic reading surfaces and monochrome actions.
enum AppPalette {
  static let background = Color(uiColor: .systemBackground)
  static let groupedBackground = Color(uiColor: .systemGroupedBackground)
  static let surface = Color(uiColor: .secondarySystemBackground)
  static let elevated = Color(uiColor: .tertiarySystemBackground)
  static let primary = Color.primary
  static let secondary = Color.secondary
  static let accent = Color.primary
  static let accentSoft = Color(uiColor: .secondarySystemBackground)
  static let hairline = Color(uiColor: .separator).opacity(0.55)
  static let destructive = Color(uiColor: .systemRed)
  static let success = Color(uiColor: .systemGreen)
}

enum DrillbitMotion {
  static let fast = Animation.easeOut(duration: 0.14)
  static let disclosure = Animation.easeInOut(duration: 0.22)
}

/// Three repeated cuts converge on one point: a small visual mnemonic for
/// deliberate practice. This geometry is shared with the app icon.
struct DrillbitMark: View {
  var size: CGFloat = 52
  var foreground: Color = .white

  var body: some View {
    Canvas { context, canvas in
      let scale = min(canvas.width, canvas.height) / 64
      func capsule(_ rect: CGRect, angle: Angle) {
        var resolved = context
        resolved.translateBy(x: canvas.width / 2, y: canvas.height / 2)
        resolved.rotate(by: angle)
        resolved.translateBy(x: -canvas.width / 2, y: -canvas.height / 2)
        resolved.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2), with: .color(foreground))
      }
      capsule(CGRect(x: 15 * scale, y: 13 * scale, width: 34 * scale, height: 12 * scale), angle: .zero)
      capsule(CGRect(x: 14 * scale, y: 31 * scale, width: 28 * scale, height: 12 * scale), angle: .degrees(55))
      capsule(CGRect(x: 22 * scale, y: 31 * scale, width: 28 * scale, height: 12 * scale), angle: .degrees(-55))
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}

struct DrillbitLogo: View {
  var compact = false
  var body: some View {
    HStack(spacing: compact ? 8 : 12) {
      DrillbitMark(size: compact ? 28 : 44, foreground: AppPalette.background)
        .padding(compact ? 4 : 8)
        .background(AppPalette.primary, in: RoundedRectangle(cornerRadius: compact ? 9 : 12))
      Text("drillbit")
        .font(.system(compact ? .headline : .largeTitle, design: .rounded, weight: .bold))
        .tracking(-0.6)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Drillbit")
  }
}

struct DrillbitSurface: ViewModifier {
  var padding: CGFloat = 20
  var elevated = false
  func body(content: Content) -> some View {
    content
      .padding(padding)
      .background(elevated ? AppPalette.elevated : AppPalette.surface, in: RoundedRectangle(cornerRadius: 12))
      .overlay { RoundedRectangle(cornerRadius: 12).stroke(AppPalette.hairline, lineWidth: 0.5) }
  }
}

extension View {
  func drillbitSurface(padding: CGFloat = 20, elevated: Bool = false) -> some View {
    modifier(DrillbitSurface(padding: padding, elevated: elevated))
  }

  func drillbitHeroSurface(padding: CGFloat = 20) -> some View {
    self
      .padding(padding)
      .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 12))
      .overlay { RoundedRectangle(cornerRadius: 12).stroke(AppPalette.hairline, lineWidth: 0.5) }
  }
}

struct DrillbitMetadata: View {
  let text: String
  @Environment(\.dynamicTypeSize) private var typeSize
  var body: some View {
    Group {
      if typeSize.isAccessibilitySize {
        Text(text).font(.caption)
      } else {
        Text(text).font(.caption.weight(.medium)).monospaced()
      }
    }
    .foregroundStyle(AppPalette.secondary)
  }
}

struct DrillbitSectionHeader: View {
  let title: String
  var eyebrow: String? = nil
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      if let eyebrow {
        Text(eyebrow.uppercased())
          .font(.caption2.weight(.semibold)).tracking(0.8)
          .foregroundStyle(AppPalette.secondary)
      }
      Text(title).font(.title3.weight(.semibold))
    }
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
  }
}

struct PracticeButtonStyle: ButtonStyle {
  var secondary = false
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.body.weight(.semibold))
      .multilineTextAlignment(.center)
      .padding(.horizontal, 16).padding(.vertical, 12)
      .frame(maxWidth: .infinity, minHeight: 48)
      .foregroundStyle(secondary ? AppPalette.primary : AppPalette.background)
      .background(secondary ? AppPalette.elevated : AppPalette.primary, in: RoundedRectangle(cornerRadius: 12))
      .overlay {
        if secondary { RoundedRectangle(cornerRadius: 12).stroke(AppPalette.hairline, lineWidth: 0.5) }
      }
      .contentShape(RoundedRectangle(cornerRadius: 12))
      .scaleEffect(configuration.isPressed && isEnabled ? 0.96 : 1)
      .opacity(isEnabled ? 1 : 0.45)
      .animation(reduceMotion ? nil : DrillbitMotion.fast, value: configuration.isPressed)
      .hoverEffect(.highlight)
  }
}

struct DrillbitIconButtonStyle: ButtonStyle {
  var prominent = false
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .frame(width: 48, height: 48)
      .foregroundStyle(prominent ? AppPalette.background : AppPalette.primary)
      .background(prominent ? AppPalette.primary : AppPalette.elevated, in: Circle())
      .overlay { Circle().stroke(prominent ? .clear : AppPalette.hairline, lineWidth: 0.5) }
      .scaleEffect(configuration.isPressed && isEnabled ? 0.96 : 1)
      .opacity(isEnabled ? 1 : 0.42)
      .animation(reduceMotion ? nil : DrillbitMotion.fast, value: configuration.isPressed)
      .contentShape(Circle())
  }
}

struct LoadingStatus: View {
  let message: String
  var centered: Bool
  init(_ message: String, centered: Bool = false) {
    self.message = message
    self.centered = centered
  }
  var body: some View {
    if centered {
      VStack(spacing: 12) {
        ProgressView().controlSize(.small).accessibilityHidden(true)
        Text(message).font(.subheadline).foregroundStyle(.secondary)
          .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity)
      .accessibilityElement(children: .combine)
    } else {
      HStack(spacing: 12) {
        ProgressView().controlSize(.small).accessibilityHidden(true)
        Text(message).font(.subheadline).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(16)
      .background(AppPalette.accentSoft, in: RoundedRectangle(cornerRadius: 12))
      .accessibilityElement(children: .combine)
    }
  }
}

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
