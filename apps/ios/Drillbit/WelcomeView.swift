import ClerkKit
import SwiftUI

struct WelcomeView: View {
  @Bindable var model: AppModel
  @AppStorage("walkthroughVersion") private var walkthroughVersion = 0
  @State private var page = 0
  @State private var demoReply = ""
  @State private var invite = ""
  @State private var signingIn = false

  var body: some View {
    NavigationStack {
      Group {
        let forced = ProcessInfo.processInfo.arguments.contains("--fixture-walkthrough")
        if !forced && (walkthroughVersion >= 1 || model.fixture) { authentication } else { walkthrough }
      }
        .background(AppPalette.background)
    }
  }

  private var walkthrough: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          HStack {
            SignalEyebrow(text: String(format: "%02d / 04", page + 1))
            Spacer()
            Button("Sign in now") { finishWalkthrough() }
              .font(.subheadline.weight(.medium))
          }
          Group {
            switch page {
            case 0: practiceProof
            case 1: feedbackProof
            case 2: recallProof
            default: localTry
            }
          }.id(page)
          Spacer(minLength: 12)
          HStack(spacing: 12) {
            if page > 0 { Button("Back") { move(to: page - 1) }.buttonStyle(PracticeButtonStyle(secondary: true)) }
            Button(page == 3 ? "Continue to sign in" : "Continue") {
              if page == 3 { finishWalkthrough() } else { move(to: page + 1) }
            }.buttonStyle(PracticeButtonStyle())
          }
        }
        .frame(maxWidth: 560, minHeight: geometry.size.height, alignment: .topLeading)
        .padding(24).frame(maxWidth: .infinity)
      }.scrollBounceBehavior(.basedOnSize)
    }
  }

  private var practiceProof: some View {
    VStack(alignment: .leading, spacing: 20) {
      DrillbitLogo(compact: true)
      SignalPresence(density: 720)
        .frame(height: 260)
      SignalEyebrow(text: "System design / out loud")
      Text("A better answer\nstarts in motion.")
        .font(.largeTitle.weight(.semibold)).tracking(-0.8)
        .fixedSize(horizontal: false, vertical: true)
      Text("An AI interviewer for five spare minutes.")
        .font(.subheadline).foregroundStyle(AppPalette.secondary)
    }
  }

  private var feedbackProof: some View {
    VStack(alignment: .leading, spacing: 20) {
      SignalEyebrow(text: "From your answer")
      Text("“I’d retry every failed delivery.”")
        .font(.title.weight(.medium)).fixedSize(horizontal: false, vertical: true)
      Rectangle().fill(AppPalette.action).frame(height: 2)
      SignalEyebrow(text: "The missing guard")
      Text("One request ID.\nOne delivery.")
        .font(.largeTitle.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
      Text("If the first send succeeded, retrying should return its result without sending again.")
        .foregroundStyle(AppPalette.secondary)
      fact("Feedback is grounded in your words")
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
        stage("01", "Speak through a decision")
        Divider()
        stage("02", "See the missing guard")
        Divider()
        stage("03", "Practice it again")
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
        if !demoReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { Divider(); Text(demoReply).fixedSize(horizontal: false, vertical: true) }
      }.signalInset(padding: 20)
      Text("This local preview is not saved or scored. Personalized follow-up begins after sign-in.").font(.footnote).foregroundStyle(.secondary)
    }
  }

  private func fact(_ value: String) -> some View {
    Label(value, systemImage: "checkmark.circle")
      .font(.subheadline.weight(.medium)).foregroundStyle(AppPalette.accent)
  }
  private func stage(_ number: String, _ title: String) -> some View {
    HStack(spacing: 20) {
      Text(number).font(.caption.monospaced()).foregroundStyle(AppPalette.accent)
      Text(title).font(.body.weight(.medium))
    }.frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
  }

  private var authentication: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(spacing: 32) {
          VStack(spacing: 12) {
            DrillbitLogo()
            SignalPresence(density: 480).frame(height: 190)
            Text(model.bootstrap == nil ? "System design. Out loud." : "Enter your invite to begin.")
              .font(.title2.weight(.semibold)).multilineTextAlignment(.center)
          }
          VStack(spacing: 12) {
            if model.bootstrap != nil {
              TextField("Invite code", text: $invite).textInputAutocapitalization(.never).autocorrectionDisabled()
                .signalInset(padding: 16)
              Button("Start practicing") { authenticate { await model.redeem(invite.trimmingCharacters(in: .whitespacesAndNewlines)) } }
                .buttonStyle(PracticeButtonStyle()).disabled(invite.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || signingIn)
            } else {
              Button { authenticate { await model.signIn() } } label: { Label("Sign in with Apple", systemImage: AppIcon.apple.rawValue) }.buttonStyle(PracticeButtonStyle())
              Button("Continue with Google") { authenticate { await model.signIn(provider: .google) } }.buttonStyle(PracticeButtonStyle(secondary: true))
              Button("Continue with GitHub") { authenticate { await model.signIn(provider: .github) } }.buttonStyle(PracticeButtonStyle(secondary: true))
            }
            if signingIn { ProgressView(model.bootstrap == nil ? "Signing in…" : "Checking invite…") }
          }.disabled(signingIn)
        }.frame(maxWidth: 400).padding(24).frame(maxWidth: .infinity, minHeight: geometry.size.height)
      }.scrollBounceBehavior(.basedOnSize)
    }
  }

  private func finishWalkthrough() { demoReply = ""; walkthroughVersion = 1 }
  private func move(to value: Int) { page = value }
  private func authenticate(_ operation: @escaping @MainActor () async -> Void) {
    guard !signingIn else { return }; signingIn = true
    Task { defer { signingIn = false }; await operation() }
  }
}
