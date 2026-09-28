import SwiftUI

/// The original prompt is one persistent text view. Only its allocated height
/// changes, so neither its first line nor its preview is replaced mid-animation.
struct InterviewDisclosureText: View {
  let text: String
  let expanded: Bool
  let identifier: String
  var previewLines = 3
  var dimsPreview = true
  /// Renders question markup; interviewer text stays plain.
  var markup = false
  var onOverflowChange: (Bool) -> Void = { _ in }
  @State private var fullHeight: CGFloat?
  @State private var previewHeight: CGFloat?
  var body: some View {
    content(lineLimit: !expanded && previewHeight == nil ? previewLines : nil)
      .font(.body)
      .foregroundStyle(expanded || !dimsPreview ? Color.primary : Color.secondary)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
      .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
      .overlay(alignment: .topLeading) {
        content(lineLimit: previewLines).font(.body)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
          .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { previewHeight = $0 }
          .hidden().accessibilityHidden(true)
      }
      .frame(height: expanded ? fullHeight : previewHeight, alignment: .top)
      .clipped()
      .textSelection(.enabled)
      .accessibilityIdentifier(identifier)
      .onChange(of: fullHeight) { _, _ in reportOverflow() }
      .onChange(of: previewHeight) { _, _ in reportOverflow() }
  }
  private func reportOverflow() {
    guard let fullHeight, let previewHeight else { return }
    onOverflowChange(fullHeight > previewHeight + 0.5)
  }
  @ViewBuilder private func content(lineLimit: Int?) -> some View {
    if markup { QuestionBody(markup: text, lineLimit: lineLimit) } else { Text(text).lineLimit(lineLimit) }
  }
}

/// Disclosure feedback belongs to the chevron, not a fade of the reading content.
struct InterviewDisclosureButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
  }
}

/// Labels stay opaque but inherit document placement animation with their rows.
struct InterviewRowLabel: View {
  let text: String
  var body: some View {
    Text(text)
      .font(.subheadline.weight(.medium))
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .transition(.identity)
  }
}

/// One chevron that turns with its disclosure, carried by the disclosure's own transaction.
struct DisclosureChevron: View {
  let expanded: Bool
  var body: some View {
    Image(systemName: AppIcon.collapsed.rawValue)
      .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
      .rotationEffect(.degrees(expanded ? 90 : 0))
      .accessibilityHidden(true)
  }
}

/// Measure the actual SwiftUI text at the current width and Dynamic Type size.
/// Short turns remain plain text; a longer turn gets a 44-point disclosure target.
struct InterviewTurnRow: View {
  let title: String
  let text: String
  let expanded: Bool
  let identifier: String
  let textIdentifier: String
  let toggle: () -> Void
  @State private var overflows = false
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      InterviewRowLabel(text: title)
      InterviewDisclosureText(text: text, expanded: expanded,
        identifier: textIdentifier, previewLines: 1, dimsPreview: false,
        onOverflowChange: { overflows = $0 })
    }
    .padding(.trailing, 36)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(alignment: .topTrailing) {
      if overflows {
        Button(action: toggle) {
          DisclosureChevron(expanded: expanded)
            .frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain)
          .accessibilityLabel(title + ". " + text)
          .accessibilityValue(expanded ? "Expanded" : "Collapsed")
          .accessibilityIdentifier(identifier)
      }
    }
  }
}
