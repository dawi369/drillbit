import ClerkKit
import SwiftUI

struct WelcomeView: View {
  @Bindable var model: AppModel
  @State private var invite = ""
  @State private var signingIn = false

  var body: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(spacing: 32) {
          VStack(spacing: 12) {
            Text("Drillbit")
              .font(.largeTitle.weight(.semibold))
              .accessibilityAddTraits(.isHeader)
            Text(
              model.bootstrap == nil
                ? "A little interview practice, every day."
                : "Enter your invite to start practicing."
            )
            .font(.body)
            .foregroundStyle(AppPalette.secondary)
            .fixedSize(horizontal: false, vertical: true)
          }

          VStack(spacing: 12) {
            if model.bootstrap != nil {
              TextField("Invite code", text: $invite)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(16)
                .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Invite code")
              Button("Start practicing") {
                authenticate {
                  await model.redeem(invite.trimmingCharacters(in: .whitespacesAndNewlines))
                }
              }
              .buttonStyle(PracticeButtonStyle())
              .disabled(invite.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || signingIn)
            } else {
              Button {
                authenticate { await model.signIn() }
              } label: {
                Label("Sign in with Apple", systemImage: "apple.logo")
              }
              .buttonStyle(PracticeButtonStyle())
              Button("Continue with Google") {
                authenticate { await model.signIn(provider: .google) }
              }
              .buttonStyle(PracticeButtonStyle(secondary: true))
              Button("Continue with GitHub") {
                authenticate { await model.signIn(provider: .github) }
              }
              .buttonStyle(PracticeButtonStyle(secondary: true))
            }
          }
          .disabled(signingIn)

          if signingIn {
            ProgressView(model.bootstrap == nil ? "Signing in…" : "Checking invite…")
          } else {
            Text("Your practice syncs across devices.")
              .font(.footnote)
              .foregroundStyle(AppPalette.secondary)
          }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 400)
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: geometry.size.height)
      }
      .scrollBounceBehavior(.basedOnSize)
      .background(AppPalette.background)
    }
  }

  private func authenticate(_ operation: @escaping @MainActor () async -> Void) {
    guard !signingIn else { return }
    signingIn = true
    Task {
      defer { signingIn = false }
      await operation()
    }
  }
}
