import SwiftUI

/// Signal uses one graphite and yellow identity, with a warm light companion.
/// Meaning stays in the content; yellow marks active state and primary action.
enum AppPalette {
  private static func adaptive(_ dark: UInt32, _ light: UInt32) -> Color {
    Color(uiColor: UIColor { traits in
      let hex = traits.userInterfaceStyle == .dark ? dark : light
      return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                     green: CGFloat((hex >> 8) & 0xFF) / 255,
                     blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    })
  }
  static let background = adaptive(0x1F2430, 0xF6F4EE)
  static let groupedBackground = background
  static let surface = adaptive(0x232834, 0xFFFFFF)
  static let elevated = adaptive(0x2A303E, 0xECE9E0)
  static let inset = adaptive(0x191E28, 0xEAE7DE)
  static let primary = adaptive(0xF3F4F6, 0x202632)
  static let secondary = adaptive(0xADB4C0, 0x566171)
  static let accent = adaptive(0xFFCC65, 0x8A5310)
  static let action = Color(red: 1, green: 204 / 255, blue: 101 / 255)
  static let actionInk = Color(red: 31 / 255, green: 36 / 255, blue: 48 / 255)
  static let accentSoft = adaptive(0x3D3730, 0xF7E7C6)
  static let hairline = adaptive(0x414C5D, 0xCBD0D5)
  static let grain = adaptive(0xD8D6CF, 0x6D717A)
  static let destructive = adaptive(0xF0817B, 0xAD3333)
  static let success = adaptive(0x97CFB0, 0x286A50)
}

enum DrillbitMotion {
  static let fast = Animation.easeOut(duration: 0.14)
  static let disclosure = Animation.easeInOut(duration: 0.22)
}

/// Three small points identify Signal without introducing a second agent shape.
struct DrillbitMark: View {
  var size: CGFloat = 52
  var foreground: Color = AppPalette.action

  var body: some View {
    Canvas { context, canvas in
      let scale = min(canvas.width, canvas.height) / 32
      let dots: [(CGFloat, CGFloat, CGFloat, Color)] = [
        (12.0, 13.0, 5.0, foreground),
        (19.0, 10.0, 2.8, foreground.opacity(0.9)),
        (20.0, 18.0, 1.9, AppPalette.primary.opacity(0.85)),
      ]
      for (x, y, radius, color) in dots {
        let rect = CGRect(x: (x - radius) * scale, y: (y - radius) * scale,
                          width: 2 * radius * scale, height: 2 * radius * scale)
        context.fill(Path(ellipseIn: rect), with: .color(color))
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}

struct DrillbitLogo: View {
  var compact = false
  var body: some View {
    HStack(spacing: compact ? 8 : 12) {
      DrillbitMark(size: compact ? 28 : 40)
      Text("drillbit").font(compact ? .headline : .title2.weight(.semibold)).tracking(-0.5)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Drillbit")
  }
}

/// A brief acknowledgement for completed learning actions. It has no idle
/// animation, so motion always communicates a real state change.
struct DrillbitFeedbackMark: View {
  var trigger: Int
  var body: some View {
    ZStack {
      Circle().fill(AppPalette.elevated).frame(width: 48, height: 48)
      DrillbitMark(size: 24)
    }
    .accessibilityHidden(true)
  }
}

/// A still, deterministic texture. Audio-driven particles belong to a later
/// motion pass; this view never starts a renderer or reads the microphone.
struct SignalParticleField: View {
  var density = 520
  var body: some View {
    Canvas { context, size in
      var seed: UInt64 = 0x5349474E414C
      func unit() -> Double {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double(seed >> 11) / Double(1 << 53)
      }
      for _ in 0..<density {
        let angle = unit() * .pi * 2
        let radius = min(1.18, (unit() + unit() + unit()) / 3 * 1.42)
        let x = Double(size.width) / 2 + cos(angle) * Double(size.width) * 0.45 * radius
        let y = Double(size.height) / 2 + sin(angle) * Double(size.height) * 0.45 * radius
        let dot = 0.45 + unit() * 0.75
        let warm = radius < 0.46 || (radius < 0.82 && unit() < 0.14)
        let color = warm ? AppPalette.action : AppPalette.grain
        context.fill(Path(ellipseIn: CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(dot), height: CGFloat(dot))),
                     with: .color(color.opacity(radius > 0.95 ? 0.18 : 0.32 + (1 - radius) * 0.36)))
      }
    }
    .accessibilityHidden(true)
  }
}

struct SignalWaveform: View {
  var body: some View {
    HStack(alignment: .center, spacing: 2) {
      ForEach(0..<33, id: \.self) { index in
        Capsule().fill(AppPalette.action.opacity(0.92))
          .frame(width: 2, height: CGFloat(4 + 18 * abs(sin(Double(index) * 0.35))))
      }
    }
    .frame(height: 28)
    .accessibilityHidden(true)
  }
}

struct SignalEyebrow: View {
  let text: String
  var body: some View {
    Text(text.uppercased())
      .font(.caption2.weight(.semibold).monospaced())
      .tracking(1.2)
      .foregroundStyle(AppPalette.accent)
  }
}

/// Use only for editable fields or a selected control, never to group content.
struct SignalInset: ViewModifier {
  var padding: CGFloat = 20
  func body(content: Content) -> some View {
    content
      .padding(padding)
      .background(AppPalette.inset, in: RoundedRectangle(cornerRadius: 12))
  }
}

/// Rows stay on the page floor. Only a row's control may opt into an inset.
struct SignalList<Content: View>: View {
  @ViewBuilder var content: () -> Content

  var body: some View {
    List {
      Group { content() }
        .listRowBackground(AppPalette.background)
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .background(AppPalette.background)
  }
}

extension View {
  func signalInset(padding: CGFloat = 20) -> some View {
    modifier(SignalInset(padding: padding))
  }
}

struct SignalChoiceRow: View {
  let title: String
  let selected: Bool
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 16) {
        Text(title).foregroundStyle(AppPalette.primary)
        Spacer(minLength: 8)
        if selected { Image(systemName: "checkmark").foregroundStyle(AppPalette.accent) }
      }
      .padding(.horizontal, 16)
      .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
      .background(selected ? AppPalette.inset : .clear,
                  in: RoundedRectangle(cornerRadius: 12))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? .isSelected : [])
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
      .foregroundStyle(secondary ? AppPalette.accent : AppPalette.actionInk)
      .background(secondary ? .clear : AppPalette.action, in: Capsule())
      .contentShape(Capsule())
      .opacity(isEnabled ? 1 : 0.45)
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
      .foregroundStyle(prominent ? AppPalette.actionInk : AppPalette.primary)
      .background(prominent ? AppPalette.action : AppPalette.elevated, in: Circle())
      .overlay { Circle().stroke(prominent ? .clear : AppPalette.hairline, lineWidth: 0.5) }
      .opacity(isEnabled ? 1 : 0.42)
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
      .padding(.vertical, 12)
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
  case recall = "rectangle.stack"
  case home = "house"
  case apple = "apple.logo"
  case start = "play.fill"
  case microphone = "mic.fill"
  case microphoneMuted = "mic.slash.fill"
  case history = "clock.arrow.circlepath"
  case collapsed = "chevron.right"
  case expanded = "chevron.down"
}

extension View {
  func drillbitTabClearance() -> some View {
    safeAreaInset(edge: .bottom, spacing: 0) {
      Color.clear.frame(height: 72).allowsHitTesting(false).accessibilityHidden(true)
    }
  }
}
