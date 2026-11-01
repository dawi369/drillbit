import SwiftUI

/// Settings → Feedback → Report a bug: a short typed report to Sentry's user feedback (t23/drillbit-ios). It isn't
/// tied to any error, carries no screenshot, and Sentry adds only the app version, device model and iOS version.
struct BugReportView: View {
  var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var what = ""
  @State private var doing = ""
  @State private var sent = false
  @State private var failure: String?
  @FocusState private var focused: Bool
  private var ready: Bool { !what.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

  var body: some View {
    NavigationStack {
      Group {
        if sent {
          VStack(spacing: 16) {
            BitView(mood: .happy, greets: true).frame(height: 88)
            Text("Got it. Thank you.").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Text("I read every report. If it’s a bug, it’s on my list now.")
              .font(.subheadline).foregroundStyle(AppPalette.secondary).multilineTextAlignment(.center)
          }
          .padding(24)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .transition(.opacity)
        } else {
          Form {
            Section {
              TextField("The send button did nothing after I…", text: $what, axis: .vertical)
                .lineLimit(4...10)
                .focused($focused)
                .accessibilityLabel("What went wrong")
                .accessibilityIdentifier("bugReportWhat")
                .listRowBackground(AppPalette.inset)
            } header: { Text("What went wrong?") }
            Section {
              TextField("Mid-interview, in voice, on Wi-Fi…", text: $doing, axis: .vertical)
                .lineLimit(2...6)
                .accessibilityLabel("What you were doing, optional")
                .accessibilityIdentifier("bugReportDoing")
                .listRowBackground(AppPalette.inset)
            } header: { Text("What were you doing? (optional)") } footer: {
              Text("This goes to Sentry, the service that tells me when the app breaks, with the app version, device model and iOS version. Leave out anything personal.")
            }
            if let failure {
              Section { Text(failure).foregroundStyle(AppPalette.destructive) }
            }
          }
          .scrollContentBackground(.hidden)
        }
      }
      .background(AppPalette.background)
      .navigationTitle(sent ? "" : "Report a bug")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button(sent ? "Close" : "Cancel") { dismiss() } }
        if !sent {
          ToolbarItem(placement: .confirmationAction) {
            Button("Send") { send() }.disabled(!ready).accessibilityIdentifier("bugReportSend")
          }
        }
      }
    }
    .accessibilityIdentifier("bugReport")
    // Focus once the sheet has settled; asking while it slides up is ignored.
    .task { try? await Task.sleep(for: .milliseconds(450)); focused = true }
  }

  private func send() {
    let report = what.trimmingCharacters(in: .whitespacesAndNewlines)
    let context = doing.trimmingCharacters(in: .whitespacesAndNewlines)
    // Fixtures never start Sentry; they act as if it went through.
    guard model.fixture || CrashReporting.sendBugReport(report, doing: context) else {
      failure = "Bug reports go through in App Store and TestFlight builds. This build can’t send them."
      return
    }
    focused = false
    withAnimation(reduceMotion ? nil : DrillbitMotion.reveal) { sent = true }
  }
}
