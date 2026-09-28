import ClerkKit
import SwiftUI

struct WelcomeView: View {
  @Bindable var model: AppModel
  @AppStorage("walkthroughVersion") private var walkthroughVersion = 0
  @State private var page = 0
  @State private var movingForward = true
  @State private var hasMoved = false
  @State private var demoReply = ""
  @State private var invite = ""
  @State private var signingIn = false
  @FocusState private var inviteFocused: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    NavigationStack {
      Group {
        let forced = ProcessInfo.processInfo.arguments.contains("--fixture-walkthrough")
        if !forced && (walkthroughVersion >= 1 || model.fixture) { authentication.transition(.opacity) } else { walkthrough.transition(.opacity) }
      }
      .animation(DrillbitMotion.page, value: walkthroughVersion)
      .background(AppPalette.background)
      .containerBackground(AppPalette.background, for: .navigation)
    }
  }

  private var walkthrough: some View {
    GeometryReader { geometry in
      ScrollView {
        Group {
          switch page {
          case 0: practiceProof
          case 1: feedbackProof
          case 2: recallProof
          default: localTry
          }
        }
        .id(page)
        .transition(reduceMotion ? .identity : .asymmetric(
          insertion: .offset(x: movingForward ? geometry.size.width : -geometry.size.width),
          removal: .offset(x: movingForward ? -geometry.size.width : geometry.size.width)))
        .frame(maxWidth: 560, alignment: .topLeading)
        .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 24)
        .frame(maxWidth: .infinity)
      }
      .scrollBounceBehavior(.basedOnSize)
      .scrollDismissesKeyboard(.interactively)
    }
    .clipped()
    .safeAreaInset(edge: .top, spacing: 0) {
      SignalStepProgress(step: page + 1, total: 4)
        .frame(maxWidth: 560).padding(.horizontal, 24).padding(.top, 16)
        .frame(maxWidth: .infinity)
        .background(AppPalette.background)
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      VStack(spacing: 0) {
        AppPalette.hairline.frame(height: 1)
        HStack(spacing: 12) {
          if page > 0 {
            Button("Back") { move(to: page - 1) }
              .buttonStyle(PracticeButtonStyle(secondary: true))
              .frame(width: 88)
              .transition(.opacity.combined(with: .offset(x: -12)))
          }
          Button(page == 3 ? "Continue to sign in" : "Continue") {
            if page == 3 { finishWalkthrough() } else { move(to: page + 1) }
          }
          .buttonStyle(PracticeButtonStyle())
          .contentTransition(.opacity)
        }
        .frame(maxWidth: 560).padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : DrillbitMotion.page, value: page > 0)
      }
      .background(AppPalette.background)
    }
  }

  private var practiceProof: some View {
    VStack(alignment: .leading, spacing: 20) {
      DrillbitLogo(compact: true).signalEntrance(0, active: !hasMoved)
      SignalPresence(density: 720)
        .frame(height: 260)
        .signalEntrance(1, active: !hasMoved)
      VStack(alignment: .leading, spacing: 20) {
        SignalEyebrow(text: "System design mock rounds")
        Text("Grills you like\nthe real one.\nWants you to pass.")
          .font(.largeTitle.weight(.semibold)).tracking(-0.8)
          .fixedSize(horizontal: false, vertical: true)
        Text("One question, a few minutes, honest notes on what to fix.")
          .font(.subheadline).foregroundStyle(AppPalette.secondary)
      }
      .signalEntrance(2, active: !hasMoved)
    }
  }

  private var feedbackProof: some View {
    VStack(alignment: .leading, spacing: 20) {
      SignalEyebrow(text: "How a round goes")
      Text("It pokes holes.\nYou patch them.")
        .font(.largeTitle.weight(.semibold)).tracking(-0.8)
        .fixedSize(horizontal: false, vertical: true)
      VStack(alignment: .leading, spacing: 12) {
        turn("You", "If the push fails, I’d just retry it.").signalEntrance(1)
        VStack(alignment: .leading, spacing: 12) {
          Divider()
          turn("Interviewer", "Okay. What if the first one actually went through?")
        }.signalEntrance(2)
      }
      VStack(alignment: .leading, spacing: 8) {
        SignalRule().padding(.bottom, 12)
        SignalEyebrow(text: "What you missed")
        Text("Give each push an idempotency key.")
          .font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
        Text("Then a retry after a timeout can’t notify someone twice.")
          .foregroundStyle(AppPalette.secondary).fixedSize(horizontal: false, vertical: true)
      }.signalEntrance(3)
    }
  }

  private var recallProof: some View {
    VStack(alignment: .leading, spacing: 20) {
      SignalEyebrow(text: "Recall")
      Text("One useful idea\nat a time.")
        .font(.largeTitle.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
      Text("A focused retry tests the same decision. Recall brings the evidence back when it is useful.")
        .foregroundStyle(AppPalette.secondary)
      VStack(alignment: .leading, spacing: 0) {
        stage("01", "Speak through a decision").signalEntrance(1)
        Divider()
        stage("02", "See the missing guard").signalEntrance(2)
        Divider()
        stage("03", "Practise it again").signalEntrance(3)
      }
    }
  }

  private var localTry: some View {
    VStack(alignment: .leading, spacing: 20) {
      SignalEyebrow(text: "Try the input")
      Text("Before designing a notification service, what would you clarify first?").font(.title2.weight(.semibold))
      VStack(alignment: .leading, spacing: 10) {
        Text("You").font(.subheadline).foregroundStyle(.secondary)
        TextField("Type or use keyboard dictation…", text: $demoReply, axis: .vertical).lineLimit(3...6).textFieldStyle(.plain)
          .submitLabel(.done)
        if !demoReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { Divider(); Text(demoReply).fixedSize(horizontal: false, vertical: true) }
      }.signalInset(padding: 20)
      Text("This local preview is not saved or scored. Personalized follow-up begins after sign-in.").font(.footnote).foregroundStyle(.secondary)
    }
  }

  private func turn(_ speaker: String, _ text: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      InterviewRowLabel(text: speaker)
      Text(text).fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityElement(children: .combine)
  }
  private func stage(_ number: String, _ title: String) -> some View {
    HStack(spacing: 20) {
      Text(number).font(.caption.monospaced()).foregroundStyle(AppPalette.accent)
      Text(title).font(.body.weight(.medium))
    }.frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
  }

  private var authentication: some View {
    let inviting = model.bootstrap != nil
    let code = invite.trimmingCharacters(in: .whitespacesAndNewlines)
    return GeometryReader { geometry in
      ScrollView {
        VStack(spacing: 16) {
          DrillbitLogo()
          // Gives the form room above the keyboard while typing.
          SignalPresence(density: 600).frame(height: inviteFocused ? 128 : 190)
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
  private func finishWalkthrough() { demoReply = ""; walkthroughVersion = 1 }
  private func move(to value: Int) {
    movingForward = value > page
    hasMoved = true
    withAnimation(reduceMotion ? nil : DrillbitMotion.page) { page = value }
  }
  private func authenticate(_ operation: @escaping @MainActor () async -> Void) {
    guard !signingIn else { return }; signingIn = true
    Task { defer { signingIn = false }; await operation() }
  }
}
