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
        if !forced && (walkthroughVersion >= 1 || model.fixture) { authentication.transition(.opacity) } else { walkthrough.transition(.opacity) }
      }
      .animation(DrillbitMotion.page, value: walkthroughVersion)
      .background(AppPalette.background)
      .containerBackground(AppPalette.background, for: .navigation)
    }
  }

  private var walkthrough: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 32) {
        practiceProof
        feedbackProof.signalEntrance(3)
      }
      .frame(maxWidth: 560, alignment: .topLeading)
      .padding(24)
      .frame(maxWidth: .infinity)
    }
    .scrollBounceBehavior(.basedOnSize)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      VStack(spacing: 0) {
        AppPalette.hairline.frame(height: 1)
        Button("Get started") { walkthroughVersion = 1; withAnimation(DrillbitMotion.page) { leftWalkthrough = true } }
          .buttonStyle(PracticeButtonStyle())
          .frame(maxWidth: 560).padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 8)
          .frame(maxWidth: .infinity)
      }
      .background(AppPalette.background)
    }
  }

  private var practiceProof: some View {
    VStack(alignment: .leading, spacing: 20) {
      DrillbitLogo(compact: true).signalEntrance(0)
      BitView(greets: true)
        .frame(height: 180)
        .frame(maxWidth: .infinity)
        // The app icon's glow: one static gradient, never animated. Sized past Bit's frame so it fades out instead of ending in an edge.
        .background {
          RadialGradient(colors: [AppPalette.accent.opacity(0.22), AppPalette.accent.opacity(0)], center: .center, startRadius: 8, endRadius: 150)
            .frame(width: 300, height: 300)
            .accessibilityHidden(true)
        }
        .signalEntrance(1)
      VStack(alignment: .leading, spacing: 20) {
        SignalEyebrow(text: "System design mock rounds")
        Text("Grills you like\nthe real one.\nWants you to pass.")
          .font(.largeTitle.weight(.semibold)).tracking(-0.8)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityAddTraits(.isHeader)
        Text("One question, a few minutes, honest notes on what to fix.")
          .font(.subheadline).foregroundStyle(AppPalette.secondary)
      }
      .signalEntrance(2)
    }
  }

  private var feedbackProof: some View {
    VStack(alignment: .leading, spacing: 16) {
      SignalEyebrow(text: "It pokes holes. You patch them.")
      VStack(alignment: .leading, spacing: 12) {
        turn("You", "If the push fails, I’d just retry it.")
        Divider()
        turn("Interviewer", "Okay. What if the first one actually went through?")
      }
      VStack(alignment: .leading, spacing: 8) {
        SignalRule().padding(.bottom, 12)
        SignalEyebrow(text: "What you missed")
        Text("Give each push an idempotency key.")
          .font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
        Text("Then a retry after a timeout can’t notify someone twice.")
          .foregroundStyle(AppPalette.secondary).fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func turn(_ speaker: String, _ text: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      InterviewRowLabel(text: speaker)
      Text(text).fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityElement(children: .combine)
  }

  private var authentication: some View {
    let inviting = model.bootstrap != nil
    let code = invite.trimmingCharacters(in: .whitespacesAndNewlines)
    return GeometryReader { geometry in
      ScrollView {
        VStack(spacing: 16) {
          DrillbitLogo()
          // Gives the form room above the keyboard while typing; Bit listens while you type.
          BitView(mood: inviteFocused ? .listening : .idle).frame(height: inviteFocused ? 96 : 140)
          VStack(spacing: 8) {
            Text(inviting ? "One last step." : "Ready when you are.")
              .font(.title2.weight(.semibold))
            Text(inviting ? "Enter your invite code to begin." : "Sign in to save your practice and feedback.")
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
