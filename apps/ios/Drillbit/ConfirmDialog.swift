import SwiftUI

/// One choice in a `DrillbitConfirm`. `.primary` is the one we want tapped (gold capsule), `.secondary` the way out
/// (white text), `.destructive` an irreversible step (red text).
struct ConfirmAction {
  enum Style { case primary, secondary, destructive }
  let title: String
  var style: Style = .secondary
  let action: () -> Void
  init(_ title: String, style: Style = .secondary, action: @escaping () -> Void = {}) {
    self.title = title; self.style = style; self.action = action
  }
}

extension View {
  /// A confirmation in Drillbit's own colours. System alerts tint every button the same, so they can't say which
  /// choice is the one we want. The first `.secondary` action doubles as the escape gesture.
  func drillbitConfirm(_ title: String, isPresented: Binding<Bool>, message: String? = nil, actions: [ConfirmAction]) -> some View {
    modifier(DrillbitConfirmModifier(title: title, message: message, isPresented: isPresented, actions: actions))
  }
}

private struct DrillbitConfirmModifier: ViewModifier {
  let title: String
  let message: String?
  @Binding var isPresented: Bool
  let actions: [ConfirmAction]
  @State private var shown = false

  func body(content: Content) -> some View {
    content
      .onChange(of: isPresented, initial: true) { _, now in
        // The cover appears without its slide; the dialog fades and settles itself, like an alert.
        var quiet = Transaction(); quiet.disablesAnimations = true
        withTransaction(quiet) { shown = now }
      }
      .fullScreenCover(isPresented: $shown, onDismiss: { isPresented = false }) {
        ConfirmDialog(title: title, message: message, actions: actions) { chosen in
          var quiet = Transaction(); quiet.disablesAnimations = true
          withTransaction(quiet) { shown = false }
          // The action first: some read the state that `isPresented` is bound to.
          chosen?.action()
          isPresented = false
        }
        .presentationBackground(.clear)
      }
  }
}

private struct ConfirmDialog: View {
  let title: String
  let message: String?
  let actions: [ConfirmAction]
  let close: (ConfirmAction?) -> Void
  @State private var visible = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      Color.black.opacity(visible ? 0.4 : 0).ignoresSafeArea().accessibilityHidden(true)
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(AppPalette.primary)
              .accessibilityAddTraits(.isHeader)
            if let message {
              Text(message).font(.subheadline).foregroundStyle(AppPalette.secondary)
            }
          }
          .fixedSize(horizontal: false, vertical: true)
          VStack(spacing: 8) {
            ForEach(actions.indices, id: \.self) { index in button(actions[index]) }
          }
        }
        .padding(24)
        .frame(maxWidth: 360)
        .background(AppPalette.elevated, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(AppPalette.hairline, lineWidth: 0.5) }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 0)
        .containerRelativeFrame(.vertical, alignment: .center) { length, _ in length }
      }
      .scrollBounceBehavior(.basedOnSize)
      .scaleEffect(visible || reduceMotion ? 1 : 1.06)
      .opacity(visible ? 1 : 0)
    }
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(.isModal)
    .accessibilityIdentifier("confirmDialog")
    .accessibilityAction(.escape) { if let way = actions.first(where: { $0.style == .secondary }) { dismiss(way) } }
    .onAppear { withAnimation(reduceMotion ? .easeOut(duration: 0.15) : DrillbitMotion.fast) { visible = true } }
  }

  @ViewBuilder private func button(_ choice: ConfirmAction) -> some View {
    switch choice.style {
    case .primary:
      Button(choice.title) { dismiss(choice) }.buttonStyle(PracticeButtonStyle())
    case .secondary, .destructive:
      Button { dismiss(choice) } label: {
        Text(choice.title).font(.body.weight(.semibold))
          .foregroundStyle(choice.style == .destructive ? AppPalette.destructive : AppPalette.primary)
          .frame(maxWidth: .infinity, minHeight: 48)
          .contentShape(Rectangle())
      }
      .buttonStyle(DrillbitPressStyle())
    }
  }

  private func dismiss(_ choice: ConfirmAction) {
    withAnimation(reduceMotion ? nil : DrillbitMotion.fast) { visible = false }
    Task {
      if !reduceMotion { try? await Task.sleep(for: .milliseconds(150)) }
      close(choice)
    }
  }
}
