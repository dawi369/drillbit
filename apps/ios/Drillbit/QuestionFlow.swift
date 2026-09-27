import SwiftUI

struct QuestionFlowEntry: Identifiable {
  let id = UUID()
  var challenge: Challenge? = nil
  var recovery: PreparationInput? = nil
  var source: Challenge? = nil
  var browseTopics = false
  var area: PracticeAreaGroup? = nil
}
struct QuestionFlow: View {
  @Bindable var model: AppModel
  var initial: Challenge? = nil
  var isStarter = false
  var source: Challenge? = nil
  var recovery: PreparationInput? = nil
  var browseTopics = false
  var area: PracticeAreaGroup? = nil
  var onStart: (Challenge) -> Void
  @State private var selectedTopic: PracticeConcept?
  @State private var selectedArea: PracticeAreaGroup?
  @State private var topicSearch = ""
  @State private var customTopic = ""
  @State private var selectedCustomTopic: String?
  @State private var showingPreview = false
  @State private var question: Challenge?
  @State private var loading = false
  @State private var generated = false
  @State private var starting = false
  @State private var failure: String?
  @State private var retryInput: PreparationInput?
  @State private var account: String?
  @State private var visible = true
  @State private var initialized = false
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  var body: some View {
    NavigationStack {
      if browseTopics && selectedTopic == nil && selectedCustomTopic == nil && model.firstUse.stage != .walkthrough {
        SignalList {
          Section("Core areas") {
            if let selectedArea {
              ForEach(model.taxonomy.filter { selectedArea.concepts.contains($0.id) && (topicSearch.isEmpty || $0.label.localizedCaseInsensitiveContains(topicSearch)) }) { concept in
              Button {
                selectedTopic = concept
                retryInput = PreparationInput(primaryConceptId: concept.id, focus: "System design", kind: "design", difficulty: model.settings.difficulty, engineeringLevel: model.settings.selectedLevel, replaceId: model.bootstrap?.challenge?.lifecycle == "ready" ? model.bootstrap?.challenge?.id : nil)
              } label: {
                HomeTopicRow(concept: concept, coverage: model.libraryCoverage.first(where: { $0.conceptId == concept.id }), loaded: model.libraryCoverageLoaded)
              }.buttonStyle(DrillbitRowButtonStyle())
              }
            } else {
              ForEach(PracticeAreaGroup.all.filter { topicSearch.isEmpty || $0.title.localizedCaseInsensitiveContains(topicSearch) || $0.detail.localizedCaseInsensitiveContains(topicSearch) }) { area in
                Button { selectedArea = area } label: { PracticeAreaGroupRow(area: area) }.buttonStyle(DrillbitRowButtonStyle())
                  .accessibilityIdentifier("browse-area-" + area.id)
              }
            }
          }
          Section("Your own topic") {
            TextField("For example, search ranking", text: $customTopic)
            Button("Continue") { selectedCustomTopic = customTopic.trimmingCharacters(in: .whitespacesAndNewlines) }
              .disabled(customTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        }.searchable(text: $topicSearch, prompt: "Find a core area")
          .navigationTitle(selectedArea?.title ?? "System design").navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              if selectedArea != nil { Button("Back") { selectedArea = nil; topicSearch = "" } }
              else { Button("Close") { dismiss() } }
            }
          }.task { await model.loadTaxonomy() }
      } else if showingPreview {
        Group {
          if loading {
            LoadingStatus("Preparing your question…", centered: true)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .transition(.opacity)
          } else {
            ScrollView {
              VStack(alignment: .leading, spacing: 16) {
                if let question {
                  VStack(alignment: .leading, spacing: 16) {
                    SignalEyebrow(text: "The scenario")
                    Text(question.title).font(.largeTitle.weight(.semibold)).tracking(-0.8)
                      .fixedSize(horizontal: false, vertical: true)
                  }.signalEntrance(0, active: generated)
                  VStack(alignment: .leading, spacing: 16) {
                    if question.guidanceMode == .learnTogether {
                      Text(question.id == FirstUseProgress.challengeID ? "A short, guided warm-up. It won’t count toward your practice." : "Guided practice helps you structure the approach.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text(question.displayPrompt)
                      .fixedSize(horizontal: false, vertical: true)
                      .frame(maxWidth: .infinity, alignment: .leading)
                      .textSelection(.enabled).accessibilityIdentifier("previewPrompt")
                  }.signalEntrance(1, active: generated)
                }
                if let failure {
                  Text(failure).foregroundStyle(.secondary)
                  Button("Back to preparation") { showingPreview = false }
                }
              }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
              .accessibilityIdentifier("questionPreviewScroll")
          }
        }.safeAreaInset(edge: .bottom) {
          if let question, !loading {
            VStack(spacing: 12) {
              Button {
                starting = true
                Task {
                  do {
                    let opened = try await model.openForPreview(question)
                    if visible, scenePhase == .active, account == model.bootstrap?.account.id { onStart(opened); dismiss() }
                  } catch { failure = error.localizedDescription }
                  starting = false
                }
              } label: {
                HStack(spacing: 8) {
                  if starting { ProgressView().controlSize(.small).tint(AppPalette.actionInk).transition(.iconPop) }
                  Text(question.lifecycle == "in_progress" ? "Resume" : isStarter ? "Start practice" : "Start interview")
                }
                .animation(DrillbitMotion.fast, value: starting)
              }.buttonStyle(PracticeButtonStyle()).disabled(starting)
                .accessibilityLabel(question.lifecycle == "in_progress" ? "Resume" : isStarter ? "Start practice" : "Start interview")
                .accessibilityIdentifier("previewStart")
              if question.lifecycle == "ready" && question.id != FirstUseProgress.challengeID {
                Button("Choose another question") { showingPreview = false; failure = nil }.disabled(starting)
              }
            }.padding(16).background(AppPalette.background)
          }
        }.navigationTitle("Question preview").navigationBarTitleDisplayMode(.inline)
          .toolbar { Button("Close") { dismiss() } }
      } else {
        PreparationView(model: model, source: source, initialCustomTopic: selectedCustomTopic, submit: { input in
          showingPreview = true
          loading = true
          question = nil
          failure = nil
          let capturedAccount = model.bootstrap?.account.id
          Task {
            do {
              let result = try await model.generateForPreview(input)
              guard capturedAccount == model.bootstrap?.account.id else { return }
              generated = true
              question = result
            } catch {
              guard capturedAccount == model.bootstrap?.account.id else { return }
              failure = error.localizedDescription
              model.preparationFailure = error.localizedDescription
              model.failedPreparation = input
              model.failedPreparationSource = source
              retryInput = input
            }
            withAnimation(DrillbitMotion.fast) { loading = false }
          }
        }, recovery: retryInput ?? recovery)
      }
    }.background(AppPalette.background).onAppear {
      visible = true
      guard !initialized else { return }
      initialized = true
      account = model.bootstrap?.account.id
      selectedArea = area
      if model.firstUse.stage == .walkthrough { question = FirstUseProgress.challenge; showingPreview = true }
      else if let initial { question = initial; showingPreview = true }
    }
    .onDisappear { visible = false }
    .onChange(of: scenePhase) { _, phase in if phase == .background { visible = false; dismiss() } }
    .onChange(of: model.bootstrap?.account.id) { _, value in if value != account { dismiss() } }
  }
}
