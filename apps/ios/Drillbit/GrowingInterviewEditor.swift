import SwiftUI
import UIKit

/// UITextView supplies selection/caret geometry; vertical scrolling belongs exclusively to the document.
struct GrowingInterviewEditor: UIViewRepresentable {
  @Binding var text: String
  @Binding var focused: Bool
  var accessibilityLabel: String
  var enabled: Bool
  var revealCaret: (CGRect) -> Void
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeUIView(context: Context) -> UITextView {
    let view = UITextView()
    view.delegate = context.coordinator
    view.isScrollEnabled = false
    view.backgroundColor = .clear
    view.textColor = .label
    view.font = .preferredFont(forTextStyle: .body)
    view.adjustsFontForContentSizeCategory = true
    view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
    view.textContainer.lineFragmentPadding = 0
    view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    view.accessibilityLabel = accessibilityLabel
    view.accessibilityIdentifier = "answerEditor"
    return view
  }
  func updateUIView(_ view: UITextView, context: Context) {
    context.coordinator.parent = self
    view.accessibilityLabel = accessibilityLabel
    if view.text != text { view.text = text; view.invalidateIntrinsicContentSize() }
    context.coordinator.reconcileInteraction(view)
  }
  func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
    guard let width = proposal.width, width > 0 else { return nil }
    let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    return CGSize(width: width, height: max((uiView.font?.lineHeight ?? 22) * 6 + 16, size.height))
  }
  @MainActor final class Coordinator: NSObject, UITextViewDelegate {
    var parent: GrowingInterviewEditor
    private var interactionUpdateQueued = false
    init(_ parent: GrowingInterviewEditor) { self.parent = parent }
    func reconcileInteraction(_ textView: UITextView) {
      guard !interactionUpdateQueued else { return }
      interactionUpdateQueued = true
      // Resigning (including isEditable = false) asks the SwiftUI host for its next
      // responder. Doing that inside updateUIView re-enters the active view graph.
      DispatchQueue.main.async { [weak self, weak textView] in
        guard let self else { return }
        self.interactionUpdateQueued = false
        guard let textView else { return }
        if !self.parent.focused && textView.isFirstResponder { textView.resignFirstResponder() }
        if textView.isEditable != self.parent.enabled { textView.isEditable = self.parent.enabled }
      }
    }
    func textViewDidBeginEditing(_ textView: UITextView) { parent.focused = true; reveal(textView) }
    // Dictation may suspend editing temporarily. Only an explicit parent action
    // clears focus intent; otherwise a SwiftUI update can resign the responder
    // before the system keyboard returns.
    func textViewDidEndEditing(_ textView: UITextView) {}
    func textViewDidChange(_ textView: UITextView) {
      parent.text = textView.text
      textView.invalidateIntrinsicContentSize()
      reveal(textView)
    }
    func textViewDidChangeSelection(_ textView: UITextView) { if textView.isFirstResponder { reveal(textView) } }
    private func reveal(_ textView: UITextView) {
      // Wait for the growing view to be measured before locating the caret in the document.
      DispatchQueue.main.async { [weak self, weak textView] in
        guard let self, let textView, textView.isFirstResponder, let selection = textView.selectedTextRange else { return }
        self.parent.revealCaret(textView.caretRect(for: selection.end))
      }
    }
  }
}
