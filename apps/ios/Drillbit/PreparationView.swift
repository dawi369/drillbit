import SwiftUI

struct PreparationView: View {
  var model: AppModel
  var source: Challenge? = nil
  var initialCustomTopic: String? = nil
  var onSubmitted: () -> Void = {}
  var submit: ((PreparationInput) -> Void)? = nil
  var recovery: PreparationInput? = nil
  @State private var focus = "System design"
  @State private var practiceArea = ""
  @State private var customTopic = ""
  @State private var engineeringLevel = "mid"
  @State private var includeSource = true
  @State private var initialized = false
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    SignalList {
      Section {
        NavigationLink { PracticeAreaPicker(model: model, selection: $practiceArea, customTopic: $customTopic) } label: {
          LabeledContent("Practice area", value: customTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (model.taxonomy.first { $0.id == practiceArea }?.label ?? "Automatic") : customTopic)
        }.accessibilityIdentifier("prepareArea")
        Picker("Target level", selection: $engineeringLevel) {
          ForEach(EngineeringLevel.choices, id: \.0) { Text($0.1).tag($0.0) }
        }.accessibilityIdentifier("prepareLevel")

      }
      if includeSource, let source, let reflection = source.reflection {
        Section("Building on your last session") {
          Text(reflection.improve).font(.subheadline)
          NavigationLink(source.title) { SessionDetailView(model: model, initial: source) }
          Button("Remove") { includeSource = false }
        }
      }
      Section {
        Button("Prepare question") {
          let requestedTopic = customTopic.trimmingCharacters(in: .whitespacesAndNewlines)
          // Session style isn't picked here for now: a retry keeps the one it failed with, otherwise it follows
          // the last real session, like the daily question. The interview's own menu still changes it.
          let mode = recovery?.guidanceMode ?? model.memory.sessions.first { !$0.isWarmUp }?.guidanceMode
          let input = PreparationInput(
            primaryConceptId: practiceArea.isEmpty ? nil : practiceArea, guidanceMode: mode, interviewStyle: .standard, focus: "System design", kind: "design", difficulty: model.settings.difficulty,
            engineeringLevel: engineeringLevel,
            replaceId: model.bootstrap?.challenge?.lifecycle == "ready" ? model.bootstrap?.challenge?.id : nil,
            instruction: requestedTopic.isEmpty ? "" : "Use this product or system domain: \(requestedTopic).",
            followUpId: includeSource && source?.reflection != nil ? source?.id : nil)
          if let submit { submit(input) }
          else {
            dismiss()
            onSubmitted()
            Task { await model.generate(input) }
          }
        }.buttonStyle(PracticeButtonStyle())
          .accessibilityIdentifier("submitPreparation")
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
          .listRowSeparator(.hidden)
          .disabled(focus.isEmpty || model.busy || model.bootstrap?.challenge?.lifecycle == "in_progress")
      } footer: {
        if model.bootstrap?.challenge?.lifecycle == "in_progress" {
          Text("Finish or skip your current interview before preparing another. Your choices here won’t change it.")
        } else if model.bootstrap?.challenge?.lifecycle == "ready" {
          Text("Your current question stays until the new one is ready.")
        }
      }
    }.task { await model.loadTaxonomy() }.navigationTitle("New question").navigationBarTitleDisplayMode(.inline).toolbar {
      Button("Cancel") { dismiss() }
    }
    .onAppear {
      guard !initialized else { return }
      initialized = true
      focus = "System design"
      engineeringLevel = model.settings.selectedLevel
      customTopic = initialCustomTopic ?? ""
      if let recovery {
        practiceArea = recovery.primaryConceptId ?? ""
        engineeringLevel = recovery.engineeringLevel ?? EngineeringLevel.legacy(recovery.difficulty)
        includeSource = recovery.followUpId != nil
        if customTopic.isEmpty, let topic = recovery.instruction.firstMatch(of: /^Use this product or system domain: (.+?)\.(?: |$)/)?.1 {
          customTopic = String(topic)
        }
      }
    }
  }
}
struct PracticeAreaPicker: View {
  var model: AppModel
  @Binding var selection: String
  @Binding var customTopic: String
  @State private var search = ""
  @State private var expandedAreas: Set<String> = []
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    SignalList {
      Button { selection = ""; customTopic = ""; dismiss() } label: {
        HStack { Text("Automatic"); Spacer(); if selection.isEmpty { Image(systemName: AppIcon.checkmark.rawValue) } }
      }.foregroundStyle(.primary)
      ForEach(PracticeAreaGroup.all) { area in
        let matches = model.taxonomy.filter { area.concepts.contains($0.id) && (search.isEmpty || $0.label.localizedCaseInsensitiveContains(search) || area.title.localizedCaseInsensitiveContains(search)) }
        if !matches.isEmpty {
          DisclosureGroup(isExpanded: Binding(get: { !search.isEmpty || expandedAreas.contains(area.id) }, set: { if $0 { expandedAreas.insert(area.id) } else { expandedAreas.remove(area.id) } })) {
            ForEach(matches) { concept in
              Button { selection = concept.id; customTopic = ""; dismiss() } label: {
                HStack { Text(concept.label); Spacer(); if selection == concept.id { Image(systemName: AppIcon.checkmark.rawValue) } }
              }.foregroundStyle(.primary).accessibilityAddTraits(selection == concept.id ? .isSelected : [])
            }
          } label: { Text(area.title).foregroundStyle(AppPalette.primary) }
        }
      }
      Section("Your own topic") {
        TextField("For example, collaborative editing", text: $customTopic)
          .textInputAutocapitalization(.sentences)
          .onChange(of: customTopic) { if !customTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { selection = "" } }
        Button("Use this topic") { dismiss() }
          .disabled(customTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }.navigationTitle("Practice area").searchable(text: $search).task {
      await model.loadTaxonomy()
      if let area = PracticeAreaGroup.all.first(where: { $0.concepts.contains(selection) }) { expandedAreas.insert(area.id) }
    }
  }
}
