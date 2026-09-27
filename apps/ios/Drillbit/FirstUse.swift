import SwiftUI

/// A short authored rehearsal. No interview controller, inference, outbox,
/// completion, or Recall write is reachable from this surface.
struct FirstPracticeView: View {
  @Bindable var model: AppModel
  @State private var draft = ""
  @State private var expanded = true
  @State private var saving = false
  @State private var failure: String?
  @State private var voiceInfo = false
  @FocusState private var focused: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var phase
  private var step: FirstUseProgress.Step { model.firstUse.step }

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          SignalEyebrow(text: "Quick walkthrough · not counted")
          DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 16) {
              Text(FirstUseProgress.challenge.prompt).padding(.top, 8)
              if !model.firstUse.question.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                  Text("Clarification").font(.caption).foregroundStyle(AppPalette.secondary)
                  Text(model.firstUse.question).font(.subheadline.weight(.medium))
                  Text("For this walkthrough: start with 1,000 people, each saving a few links a day.").font(.subheadline)
                }.padding(.leading, 16).padding(.vertical, 8)
                  .overlay(alignment: .leading) { AppPalette.hairline.frame(width: 1) }
                  .accessibilityIdentifier("walkthroughClarification")
              }
            }
          } label: {
            Text(FirstUseProgress.challenge.title).font(.title2.weight(.semibold))
              .foregroundStyle(AppPalette.primary)
          }.accessibilityIdentifier("walkthroughQuestion")
          if step == .collapse {
            FirstUseTip(number: "02", title: "Keep the useful detail.", message: "Your clarification lives with the question. Tap the heading above to fold them away.", pointsUp: true)
          } else if step == .finished {
            VStack(alignment: .leading, spacing: 16) {
              DrillbitMark(size: 52, arrives: true)
              Text("You’ve got the idea.").font(.largeTitle.weight(.semibold))
              Text("We stop here on purpose. This walkthrough doesn’t count toward your practice.")
                .foregroundStyle(AppPalette.secondary)
              if !model.firstUse.answer.isEmpty {
                Text(model.firstUse.answer).font(.subheadline).padding(.leading, 16)
                  .overlay(alignment: .leading) { AppPalette.hairline.frame(width: 1) }
              }
            }.accessibilityIdentifier("walkthroughComplete")
          } else {
            FirstUseTip(number: step == .ask ? "01" : "03",
              title: step == .ask ? "Ask before you design." : "Now make one choice.",
              message: step == .ask ? "Use the reply box below for answers and questions. Try this sample clarification, then tap Send." : "Write a design choice in the same box. Send moves the interview forward.")
            Button(step == .ask ? "Try: How many people will use it?" : "Try: Start with one database for saved links.") {
              draft = step == .ask ? "How many people will use it?" : "Start with one database for saved links."
              focused = true
              withAnimation(reduceMotion ? nil : DrillbitMotion.reveal) { proxy.scrollTo("tutorialReply", anchor: .bottom) }
            }.font(.subheadline.weight(.medium)).frame(minHeight: 44, alignment: .leading)
              .accessibilityIdentifier("walkthroughExample")
            VStack(alignment: .leading, spacing: 12) {
              Divider()
              Text("Your reply").font(.subheadline).foregroundStyle(AppPalette.secondary)
              TextField("Write your reply…", text: $draft, axis: .vertical)
                .lineLimit(3...6).focused($focused)
                .accessibilityIdentifier("walkthroughEditor")
            }.id("tutorialReply")
          }
          if let failure { Text(failure).font(.footnote).foregroundStyle(AppPalette.destructive) }
        }.padding(24).frame(maxWidth: 600, alignment: .leading).frame(maxWidth: .infinity)
          .animation(reduceMotion ? nil : DrillbitMotion.reveal, value: step)
      }.scrollDismissesKeyboard(.interactively)
    }
    .background(AppPalette.background.ignoresSafeArea())
    .navigationTitle("A quick warm-up").navigationBarTitleDisplayMode(.inline)
    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Home") { Task { await leave() } }.disabled(saving) } }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      Group {
        if step == .finished {
          Button("Show me around") { Task { await finish() } }
            .buttonStyle(PracticeButtonStyle()).accessibilityIdentifier("walkthroughTour")
        } else if step != .collapse {
          HStack(spacing: 16) {
            Button { voiceInfo = true } label: { Image(systemName: AppIcon.voice.rawValue).frame(width: 24, height: 24) }
              .buttonStyle(DrillbitIconButtonStyle()).accessibilityLabel("About voice practice")
            Spacer()
            if focused {
              Button { focused = false } label: { Image(systemName: "keyboard.chevron.compact.down").frame(width: 24, height: 24) }
                .buttonStyle(DrillbitIconButtonStyle()).accessibilityLabel("Hide keyboard")
            }
            Button { Task { await send() } } label: { Image(systemName: "arrow.up").frame(width: 24, height: 24) }
              .buttonStyle(DrillbitIconButtonStyle(prominent: true)).accessibilityLabel("Send")
              .accessibilityIdentifier("walkthroughSend")
              .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        }
      }.disabled(saving).padding(16).background(AppPalette.background)
    }
    .alert("Speak or type", isPresented: $voiceInfo) { Button("Got it", role: .cancel) {} } message: {
      Text("Real sessions support live voice. You can switch between speaking and typing without starting over.")
    }
    .sensoryFeedback(.success, trigger: step == .finished) { _, finished in finished }
    .onAppear { draft = model.firstUse.draft; expanded = step == .ask || step == .collapse }
    .onChange(of: expanded) { _, value in
      if !value && step == .collapse { Task { var next = model.firstUse; next.step = .answer; await store(next) } }
    }
    .onChange(of: phase) { _, value in if value == .background { Task { await saveDraft() } } }
  }
  private func store(_ next: FirstUseProgress) async {
    saving = true; defer { saving = false }
    do { try await model.setFirstUse(next); failure = nil } catch { failure = "Couldn’t save your place. Try again." }
  }
  private func send() async {
    guard !saving else { return }
    focused = false
    var next = model.firstUse
    if step == .ask { next.question = draft; next.step = .collapse; expanded = true }
    else { next.answer = draft; next.step = .finished }
    next.draft = ""
    await store(next)
    if failure == nil { draft = "" }
  }
  private func saveDraft() async { var next = model.firstUse; next.draft = draft; await store(next) }
  private func leave() async { await saveDraft(); if failure == nil { model.presented = nil } }
  private func finish() async {
    var next = model.firstUse; next.stage = .tourHome
    await store(next)
    if failure == nil { model.presented = nil }
  }
}

struct FirstUseTip: View {
  let number: String
  let title: String
  let message: String
  var pointsUp = false
  var symbol: String? = nil
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Text(number).font(.caption.monospaced()).foregroundStyle(AppPalette.accent)
        Text(title).font(.headline)
        Spacer(minLength: 0)
        Image(systemName: symbol ?? (pointsUp ? "arrow.up" : "arrow.down")).foregroundStyle(AppPalette.accent).accessibilityHidden(true)
      }
      Text(message).font(.subheadline).foregroundStyle(AppPalette.secondary)
    }.padding(16).background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 12))
      .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(AppPalette.accent.opacity(0.35), lineWidth: 0.5) }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("firstUseTip")
  }
}

struct FirstUseTourTip: View {
  @Bindable var model: AppModel
  private var content: (String, String, String, AppIcon) {
    switch model.firstUse.stage {
    case .tourRecall: ("02", "Recall makes it stick.", "Short reviews grow from your real sessions. Come back here to practise what needs another look.", .recall)
    case .tourLibrary: ("03", "Your work stays in Library.", "Revisit past interviews and feedback. Next, choose how you want your first real session to feel.", .library)
    default: ("01", "Home is your starting point.", "Resume a session or explore a core area. Your next question is always within reach.", .home)
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      FirstUseTip(number: content.0, title: content.1, message: content.2, symbol: content.3.rawValue)
        .id(model.firstUse.stage)
        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity))
      Button(model.firstUse.stage == .tourLibrary ? "Choose my session" : "Next") { Task { await model.advanceFirstUseTour() } }
        .buttonStyle(PracticeButtonStyle()).accessibilityIdentifier("firstUseTourNext")
    }.padding(20).background(AppPalette.background)
      .overlay(alignment: .top) { AppPalette.hairline.frame(height: 0.5) }
      .accessibilityElement(children: .contain)
  }
}

struct PracticeAreaGroupRow: View {
  let area: PracticeAreaGroup
  var body: some View {
    HStack(spacing: 16) {
      Image(systemName: area.symbol).font(.system(size: 20)).foregroundStyle(AppPalette.accent).frame(width: 24)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(area.title).foregroundStyle(AppPalette.primary)
        Text(area.detail).font(.caption).foregroundStyle(AppPalette.secondary)
      }
      Spacer(minLength: 8)
      Image(systemName: "chevron.right").font(.caption).foregroundStyle(AppPalette.secondary).accessibilityHidden(true)
    }.frame(minHeight: 64).contentShape(Rectangle())
  }
}
