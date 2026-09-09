import SwiftUI

struct HelpView: View {
  @Bindable var practice: PracticeController
  @State private var question = ""
  @State private var preview: HelpResult?
  @Environment(\.dismiss) private var dismiss
  private var currentHelp: HelpResult? {
    practice.help.last {
      !($0.body ?? "").isEmpty
        && ($0.capture == nil || practice.companion.matches($0, answer: practice.answer))
    }
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        if let preview {
          previewContent(preview)
        } else {
          modeHeader
          if practice.mode != .solo {
            HStack {
              Button("Let me think") {
                Task {
                  await practice.pauseCompanion(true)
                  dismiss()
                }
              }
              Spacer()
              if practice.companion.suggestion != nil {
                Button("Dismiss hint") {
                  Task {
                    await practice.dismissSuggestion()
                    dismiss()
                  }
                }
              }
            }
          }
          if practice.mode == .guided {
            if let focus = practice.companion.context.selectedFocus {
              Text("Your focus: " + focus).font(.subheadline).foregroundStyle(.secondary)
            }
            if let latest = practice.help.last, let plan = latest.plan, !plan.isEmpty {
              DisclosureGroup("See the plan") {
                ForEach(plan, id: \.self) { decision in
                  Button(decision) {
                    Task {
                      await practice.changeContext(
                        CompanionUpdate(
                          revision: practice.companion.context.revision, operation: "focus",
                          text: decision))
                    }
                  }
                }
              }
            }
          }
          if let latest = currentHelp { result(latest) }
          if let running = practice.running {
            HStack {
              ProgressView("Preparing help")
              Spacer()
              Button("Stop") { Task { await practice.stop() } }
            }
            .accessibilityIdentifier(running.id)
          }
          if practice.help.contains(where: { $0.body != nil }) {
            DisclosureGroup("More help") { actions.padding(.top, 12) }
          } else {
            actions
          }
          let earlier = practice.help.filter {
            !($0.body ?? "").isEmpty && $0.id != currentHelp?.id
          }
          if !earlier.isEmpty {
            DisclosureGroup("Earlier help") {
              VStack(alignment: .leading, spacing: 24) { ForEach(earlier) { result($0) } }.padding(
                .top, 12)
            }
          }
          if let latest = practice.help.last, ["failed", "cancelled"].contains(latest.status) {
            Text(
              latest.status == "cancelled"
                ? "Stopped. Your answer is unchanged."
                : "That request couldn’t finish. Choose an action to try again."
            ).foregroundStyle(.secondary)
          }
          if practice.undoEvent != nil {
            Button("Undo insertion", systemImage: "arrow.uturn.backward") {
              Task { await practice.undo() }
            }.accessibilityIdentifier("undoInsertion")
          }
        }
        if let failure = practice.failure {
          Text(failure).foregroundStyle(.secondary).font(.footnote)
        }
      }.frame(maxWidth: 640, alignment: .leading).padding(24)
    }
    .navigationTitle(preview == nil ? "Help" : "Preview draft").navigationBarTitleDisplayMode(
      .inline
    )
    .toolbar { Button("Done") { dismiss() }.disabled(practice.working || preview != nil) }
    .interactiveDismissDisabled(preview != nil || practice.working)
  }
  private var modeHeader: some View {
    VStack(alignment: .leading, spacing: 12) {
      Picker("Assistance", selection: Binding(get: { practice.mode }, set: { practice.select($0) }))
      {
        ForEach(AssistanceMode.allCases) { Text($0.rawValue).tag($0) }
      }.pickerStyle(.menu)
      if !practice.help.contains(where: { $0.body != nil }) {
        Text(practice.mode.explanation).foregroundStyle(.secondary)
      }
    }
  }
  private var actions: some View {
    VStack(alignment: .leading, spacing: 16) {
      if practice.mode == .solo {
        Button("Ask coach") { practice.select(.coach) }.accessibilityIdentifier("chooseCoach")
        Button("More help with Guided") { practice.select(.guided) }
      } else {
        VStack(alignment: .leading, spacing: 12) {
          action("Give me a hint", kind: "hint")
          action("Check my reasoning", kind: "check", needsAnswer: true)
          if practice.mode == .guided {
            action("Show a starting point", kind: "starting_point")
            action("Explore an alternative", kind: "alternative")
            action("Show an outline", kind: "outline")
            action("Show a full example", kind: "example")
            action("Suggest a draft", kind: "draft", needsAnswer: true)
          } else {
            Button("More help with Guided") { practice.select(.guided) }
          }
        }
        HStack(alignment: .bottom) {
          TextField("Ask a question", text: $question, axis: .vertical).lineLimit(1...4)
            .textFieldStyle(.roundedBorder)
          Button("Send", systemImage: "arrow.up") {
            let text = question
            Task { await practice.request("question", question: text) }
          }.labelStyle(.iconOnly).disabled(
            question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || practice.working
              || practice.running != nil || practice.locked)
        }
      }
    }
  }
  private func action(_ title: String, kind: String, needsAnswer: Bool = false) -> some View {
    Button(title) { Task { await practice.request(kind) } }
      .disabled(
        practice.working || practice.running != nil || practice.locked
          || (needsAnswer && !practice.nonempty))
  }
  private func result(_ item: HelpResult) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Divider()
      Text(item.title).font(.headline)
      if item.capture != nil && !practice.companion.matches(item, answer: practice.answer) {
        Text("Earlier draft or context").font(.caption).foregroundStyle(.secondary)
      }
      Text(item.body ?? "").textSelection(.enabled)
        .task(id: item.id) { await practice.recordDelivery(item) }
      if item.kind == "example" { Button("Try it in your words") { dismiss() } }
      if let suggestion = item.insertableText {
        if item.kind == "draft" { Text(suggestion).textSelection(.enabled) }
        Button(
          item.kind == "outline"
            ? "Use this outline"
            : item.kind == "example" ? "Use as a starting point" : "Review insertion"
        ) {
          Task { if await practice.preparePreview() { preview = item } }
        }.disabled(practice.working || practice.locked)
      }
    }
  }
  private func previewContent(_ item: HelpResult) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Your answer changes only when you choose an action below.").foregroundStyle(.secondary)
      DisclosureGroup("Current answer") { Text(practice.answer).textSelection(.enabled) }
      Text("Suggested draft").font(.headline)
      Text(item.insertableText ?? "").textSelection(.enabled)
      Button("Append to my answer") {
        Task {
          await practice.insert(item, operation: "append")
          preview = nil
        }
      }
      .buttonStyle(PracticeButtonStyle()).disabled(practice.working || practice.locked)
      Button("Replace my answer") {
        Task {
          await practice.insert(item, operation: "replace")
          preview = nil
        }
      }
      .buttonStyle(PracticeButtonStyle(secondary: true)).disabled(
        practice.working || practice.locked)
      Button("Keep my answer") { preview = nil }.disabled(practice.working)
      Text(
        "You can undo the insertion until you edit again. The source stays in your session history."
      ).font(.footnote).foregroundStyle(.secondary)
    }
  }
}
