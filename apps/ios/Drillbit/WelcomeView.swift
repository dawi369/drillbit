import ClerkKit
import SwiftUI

struct WelcomeView: View {
  @Bindable var model: AppModel
  @AppStorage("walkthroughVersion") private var walkthroughVersion = 0
  @State private var leftWalkthrough = false
  @State private var invite = ""
  @State private var signingIn = false
  @FocusState private var inviteFocused: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    NavigationStack {
      Group {
        let forced = ProcessInfo.processInfo.arguments.contains("--fixture-walkthrough") && !leftWalkthrough
        // Version 2 is the playable example; people who saw the old walkthrough get it once.
        if !forced && (walkthroughVersion >= 2 || model.fixture) { authentication.transition(.opacity) } else { walkthrough.transition(.opacity) }
      }
      .animation(DrillbitMotion.page, value: walkthroughVersion)
      .background(AppPalette.background)
      .containerBackground(AppPalette.background, for: .navigation)
    }
  }

  private var walkthrough: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 32) {
        VStack(alignment: .leading, spacing: 20) {
          DrillbitLogo(compact: true).signalEntrance(0)
          VStack(alignment: .leading, spacing: 12) {
            SignalEyebrow(text: "System design mock rounds")
            Text("Grills you like\nthe real one.\nWants you to pass.")
              .font(.largeTitle.weight(.semibold)).tracking(-0.8)
              .fixedSize(horizontal: false, vertical: true)
              .accessibilityAddTraits(.isHeader)
            Text("Talk it through or type it out. Get honest notes on what to fix.")
              .font(.subheadline).foregroundStyle(AppPalette.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          .signalEntrance(1)
        }
        RetryExample().signalEntrance(2)
      }
      .frame(maxWidth: 560, alignment: .topLeading)
      .padding(24)
      .frame(maxWidth: .infinity)
    }
    .scrollBounceBehavior(.basedOnSize)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      VStack(spacing: 0) {
        AppPalette.hairline.frame(height: 1)
        Button("Get started") { walkthroughVersion = 2; withAnimation(DrillbitMotion.page) { leftWalkthrough = true } }
          .buttonStyle(PracticeButtonStyle())
          .frame(maxWidth: 560).padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 8)
          .frame(maxWidth: .infinity)
      }
      .background(AppPalette.background)
    }
  }

  private var authentication: some View {
    let inviting = model.bootstrap != nil
    let code = invite.trimmingCharacters(in: .whitespacesAndNewlines)
    return GeometryReader { geometry in
      ScrollView {
        VStack(spacing: 16) {
          DrillbitLogo()
          VStack(spacing: 8) {
            Text(inviting ? "One last step." : "Ready when you are.")
              .font(.title2.weight(.semibold))
            Text(inviting ? "Enter your invite code to begin." : "Sign in to keep your reps and feedback.")
              .font(.subheadline).foregroundStyle(AppPalette.secondary)
          }
          .multilineTextAlignment(.center)
          .id(inviting)
          .transition(.opacity)
        }
        .animation(reduceMotion ? nil : DrillbitMotion.reveal, value: inviteFocused)
        .frame(maxWidth: 400).padding(24).frame(maxWidth: .infinity, minHeight: geometry.size.height)
      }
      .scrollBounceBehavior(.basedOnSize)
    }
    // Pinned like the walkthrough footer, so the field and its action always sit above the keyboard.
    .safeAreaInset(edge: .bottom, spacing: 0) {
      VStack(spacing: 16) {
        if inviting {
          TextField("Invite code", text: $invite)
            .font(.body.monospaced())
            .keyboardType(.asciiCapable)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .submitLabel(.go).focused($inviteFocused)
            .onSubmit { if !code.isEmpty { redeem(code) } }
            .signalInset(padding: 16)
          Button { redeem(code) } label: {
            HStack(spacing: 8) {
              if signingIn { ProgressView().controlSize(.small).tint(AppPalette.actionInk).transition(.iconPop) }
              Text("Start practising")
            }
          }
          .buttonStyle(PracticeButtonStyle()).disabled(code.isEmpty || signingIn)
          .accessibilityLabel(signingIn ? "Checking invite" : "Start practising")
        } else {
          VStack(spacing: 12) {
            Button { authenticate { await model.signIn() } } label: { Label("Sign in with Apple", systemImage: AppIcon.apple.rawValue) }.buttonStyle(PracticeButtonStyle())
            Button("Continue with Google") { authenticate { await model.signIn(provider: .google) } }.buttonStyle(PracticeButtonStyle(secondary: true))
            Button("Continue with GitHub") { authenticate { await model.signIn(provider: .github) } }.buttonStyle(PracticeButtonStyle(secondary: true))
          }
          // Reserve the row so buttons never shift when work starts.
          ProgressView("Signing in…")
            .opacity(signingIn ? 1 : 0)
            .accessibilityHidden(!signingIn)
        }
      }
      .disabled(signingIn)
      .transition(.opacity)
      .animation(DrillbitMotion.page, value: inviting)
      .animation(DrillbitMotion.fast, value: signingIn)
      .frame(maxWidth: 400).padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 16)
      .frame(maxWidth: .infinity)
      .background(AppPalette.background)
    }
    .task(id: inviting) { if inviting { inviteFocused = true } }
  }

  private func redeem(_ code: String) {
    inviteFocused = false
    authenticate { await model.redeem(code) }
  }
  private func authenticate(_ operation: @escaping @MainActor () async -> Void) {
    guard !signingIn else { return }; signingIn = true
    Task { defer { signingIn = false }; await operation() }
  }
}

/// Welcome's playable example: a timed-out push, a retry that sends it twice, then the fix.
/// Scripted and local; no model call, no score. Bit reacts to what happened to the push, not to the person.
struct RetryExample: View {
  enum Step: Equatable { case asking, checked, doubled, fixed }
  @State private var step = Step.asking
  @State private var cheers = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private struct Receipt: Identifiable, Equatable {
    var id: String
    var request: String
    var status: String
    var symbol: String
    var tone: Tone
    enum Tone { case waiting, delivered, duplicate, skipped }
  }
  private var line: String {
    switch step {
    case .asking: "Your push to their phone timed out. Now what?"
    case .checked: "Smart. But the server never answered, so you can’t tell if it went out."
    case .doubled: "Oops. It went out the first time. Their phone buzzed twice."
    case .fixed: "Same request, same result. That’s an idempotency key."
    }
  }
  private var mood: BitMood {
    switch step {
    case .asking: .idle
    case .checked: .thinking
    case .doubled: .concerned
    case .fixed: .content
    }
  }
  private var receipts: [Receipt] {
    switch step {
    case .asking: [Receipt(id: "first", request: "7f3a", status: "Timed out", symbol: "clock", tone: .waiting)]
    case .checked: [Receipt(id: "first", request: "7f3a", status: "No answer", symbol: "questionmark.circle", tone: .waiting)]
    case .doubled: [
      Receipt(id: "first", request: "7f3a", status: "Delivered", symbol: "checkmark.circle.fill", tone: .delivered),
      Receipt(id: "second", request: "b21c", status: "Delivered again", symbol: "exclamationmark.circle.fill", tone: .duplicate)]
    case .fixed: [
      Receipt(id: "first", request: "7f3a", status: "Delivered", symbol: "checkmark.circle.fill", tone: .delivered),
      Receipt(id: "second", request: "7f3a", status: "Duplicate skipped", symbol: "arrow.uturn.backward.circle", tone: .skipped)]
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      SignalEyebrow(text: "Try one · 20 seconds")
      BitAsks(question: line, cheers: cheers, mood: mood, font: .headline, isHeader: false)
        .animation(reduceMotion ? nil : DrillbitMotion.fast, value: line)
        .accessibilityIdentifier("exampleLine")
      VStack(spacing: 8) {
        ForEach(receipts) { receipt in
          receiptRow(receipt)
            .transition(reduceMotion ? .opacity : .asymmetric(
              insertion: .opacity.combined(with: .offset(y: -8)).combined(with: .scale(scale: 0.96, anchor: .top)),
              removal: .opacity))
        }
      }
      actions
    }
    .sensoryFeedback(trigger: step) { _, new in
      switch new {
      case .doubled: .warning
      case .fixed: .success
      default: nil
      }
    }
  }

  @ViewBuilder private var actions: some View {
    switch step {
    case .asking:
      HStack(spacing: 12) {
        choice("Retry it", primary: true) { go(.doubled) }
          .accessibilityIdentifier("exampleRetry")
        choice("Check first", primary: false) { go(.checked) }
          .accessibilityIdentifier("exampleCheck")
      }
    case .checked, .doubled:
      choice("Retry with the same request ID", primary: true) { go(.fixed) }
        .accessibilityIdentifier("exampleFix")
    case .fixed:
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text("That’s the kind of hole Drillbit pokes. Then it tells you how to patch it.")
          .font(.subheadline).foregroundStyle(AppPalette.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
        Button("Again") { go(.asking) }
          .font(.subheadline.weight(.semibold))
          .frame(minHeight: 44)
          .accessibilityLabel("Play the example again")
      }
    }
  }

  private func go(_ next: Step) {
    withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0)) { step = next }
    if next == .fixed { cheers += 1 }
  }

  private func choice(_ title: String, primary: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .font(.subheadline.weight(.semibold))
        .multilineTextAlignment(.center)
        .foregroundStyle(primary ? AppPalette.actionInk : AppPalette.primary)
        .padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 44)
        .background(primary ? AppPalette.action : AppPalette.elevated, in: Capsule())
        .contentShape(Capsule())
    }
    .buttonStyle(DrillbitPressStyle())
  }

  private func receiptRow(_ receipt: Receipt) -> some View {
    let tint: Color = switch receipt.tone {
    case .waiting, .skipped: AppPalette.secondary
    case .delivered: AppPalette.success
    case .duplicate: AppPalette.destructive
    }
    return HStack(spacing: 12) {
      Image(systemName: receipt.symbol)
        .font(.body.weight(.semibold)).foregroundStyle(tint)
        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
        .frame(width: 24)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text("Push notification").font(.subheadline.weight(.semibold))
        Text("request \(receipt.request)").font(.caption.monospaced()).foregroundStyle(AppPalette.secondary)
          .contentTransition(.numericText())
      }
      Spacer(minLength: 8)
      Text(receipt.status)
        .font(.subheadline.weight(.medium)).foregroundStyle(tint)
        .multilineTextAlignment(.trailing)
        .contentTransition(.opacity)
    }
    .padding(.horizontal, 16).padding(.vertical, 12)
    .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 12))
    .overlay { RoundedRectangle(cornerRadius: 12).stroke(receipt.tone == .duplicate ? AppPalette.destructive.opacity(0.5) : AppPalette.hairline.opacity(0.6), lineWidth: 1) }
    .opacity(receipt.tone == .skipped ? 0.7 : 1)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("exampleReceipt-" + receipt.id)
  }
}
