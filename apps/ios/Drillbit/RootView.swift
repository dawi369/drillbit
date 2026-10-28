import ClerkKit
import SwiftUI

struct RootView: View {
  @Bindable var model: AppModel
  @State private var settingsOpen = false
  @State private var selectedTab = ProcessInfo.processInfo.arguments.contains("--fixture-recall") ? "recall" : "home"
  @AppStorage("appearance") private var appearance = "dark"
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.colorScheme) private var systemColorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// Device-local progress through the first run: nothing needs an account until the first question.
  @AppStorage("firstRun.stage") private var firstRunStage = FirstRunStage.welcome.rawValue
  @State private var pendingDraft: LearningPlanCoordinator.Draft?
  @State private var showingQuestion = false
  @State private var startedFirstRep: Challenge?
  @State private var applyingDraft = false
  enum FirstRunStage: String { case welcome, setup, signIn, done }
  private enum Stage { case restoring, consent, welcome, setup, signIn, app }
  private var signedIn: Bool { model.bootstrap?.account.status == "active" }
  private var stage: Stage {
    if model.restoringSession || model.launchError != nil { return .restoring }
    // Signed in without the AI consent (an update or a surviving Keychain session): ask before anything else runs.
    if signedIn && !AIConsent.shared.granted { return .consent }
    if signedIn && model.settings.onboardingComplete { return .app }
    // Fixtures that start at onboarding skip Welcome; everything else follows the device's stage.
    let fixtureSetup = model.fixture && ProcessInfo.processInfo.arguments.contains("--fixture-onboarding")
    switch FirstRunStage(rawValue: firstRunStage) ?? .welcome {
    case .welcome: return fixtureSetup ? .setup : signedIn ? .setup : .welcome
    case .setup: return .setup
    case .signIn, .done: return signedIn ? .setup : .signIn
    }
  }
  /// Signing out mid-flow (or a full reset) starts the first run over.
  private func resetFirstRunIfSignedOut() { if !signedIn, FirstRunStage(rawValue: firstRunStage) == .done { firstRunStage = FirstRunStage.welcome.rawValue } }
  private func finishSetup(_ draft: LearningPlanCoordinator.Draft) {
    pendingDraft = draft
    if signedIn { Task { await openFirstQuestionIfPending() } }
    else { withAnimation(DrillbitMotion.page) { firstRunStage = FirstRunStage.signIn.rawValue } }
  }
  private func openFirstQuestionIfPending() async {
    guard !applyingDraft, signedIn, AIConsent.shared.granted, !model.settings.onboardingComplete else { return }
    let draft = pendingDraft ?? UserDefaults.standard.data(forKey: SetupView.draftKey).flatMap { try? JSONDecoder().decode(LearningPlanCoordinator.Draft.self, from: $0) }
    guard let draft, draft.page >= SetupView.pageCount - 1 else { return }
    applyingDraft = true
    defer { applyingDraft = false }
    await model.perform { try await SetupView.apply(draft, to: model) }
    guard model.error == nil else { return }
    pendingDraft = nil
    firstRunStage = FirstRunStage.done.rawValue
    showingQuestion = true
  }
  var body: some View {
    Group {
      if model.restoringSession || model.launchError != nil {
        LaunchSurface(message: model.launchError) { Task { await model.launch() } }
          .transition(.opacity)
      } else if stage == .consent {
        NavigationStack { AIConsentGate() }
          .transition(.opacity)
      } else if stage == .welcome {
        WelcomeView(model: model) { withAnimation(DrillbitMotion.page) { firstRunStage = FirstRunStage.setup.rawValue } }
          .transition(.opacity)
      } else if stage == .setup {
        NavigationStack { SetupView(model: model, onFinish: finishSetup) }
          .transition(.opacity)
          // The first question rises over setup and the interview replaces it; Home appears once the rep is done.
          .sheet(isPresented: $showingQuestion, onDismiss: {
            guard let started = startedFirstRep else { return }
            startedFirstRep = nil
            model.presented = started
          }) {
            QuestionFlow(model: model, initial: model.bootstrap?.challenge.flatMap { $0.lifecycle == "in_progress" ? $0 : nil }) { startedFirstRep = $0 }
          }
      } else if stage == .signIn {
        NavigationStack { SignInView(model: model) }
          .transition(.opacity)
      } else if let account = model.bootstrap?.account, account.status == "active" {
        if !model.settings.onboardingComplete {
          NavigationStack { SetupView(model: model, onFinish: finishSetup) }
            .transition(.opacity)
        } else {
          TabView(selection: $selectedTab) {
            Tab("Home", systemImage: AppIcon.home.rawValue, value: "home") {
              NavigationStack {
                HomeView(model: model, openSettings: { settingsOpen = true })
              }
            }
            Tab("Recall", systemImage: AppIcon.recall.rawValue, value: "recall") {
              NavigationStack {
                RecallView(model: model).drillbitTabClearance()
              }
            }
            Tab("Library", systemImage: AppIcon.library.rawValue, value: "library") {
              NavigationStack {
                MemoryView(model: model).drillbitTabClearance().toolbar {
                  Button("Settings", systemImage: AppIcon.settings.rawValue) { settingsOpen = true }
                }
              }
            }
            if model.bootstrap?.capabilities?.developerTools == true {
              // Coming: talk through where you are and where you want to be next.
              Tab("Bit", image: "BitTab", value: "bit") {
                NavigationStack {
                  Color.clear.navigationTitle("Bit")
                    .containerBackground(AppPalette.background, for: .navigation)
                    .accessibilityIdentifier("bitTab")
                }
              }
            }
          }
          .transition(.opacity)
        }
      } else {
        NavigationStack { SignInView(model: model) }
          .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
      }
    }
    .animation(DrillbitMotion.page, value: stage)
    // Signing in after setup: apply the saved draft and open the first question without another tap.
    .onChange(of: signedIn) { _, now in if now { Task { await openFirstQuestionIfPending() } } else { resetFirstRunIfSignedOut() } }
    .onChange(of: AIConsent.shared.granted) { _, now in if now, signedIn { Task { await openFirstQuestionIfPending() } } }
    .task(id: signedIn) { if signedIn { await openFirstQuestionIfPending() } }
    .preferredColorScheme(model.fixture && ProcessInfo.processInfo.arguments.contains("--dark") ? .dark : appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
    .background(WindowFloorColor().allowsHitTesting(false))
    .onReceive(NotificationCenter.default.publisher(for: .init("OpenPractice"))) { _ in
      selectedTab = "home"
      Task { await model.refresh() }
    }
    .onReceive(NotificationCenter.default.publisher(for: .init("OpenRecall"))) { _ in
      selectedTab = "recall"
      Task { await model.loadRecall() }
    }
    .task {
      await model.launch()
      #if DEBUG
        if model.fixture && ProcessInfo.processInfo.arguments.contains("--fixture-settings") {
          settingsOpen = true
        }
      #endif
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        Task { await model.refresh(); await model.ensureHomeQuestion() }
      } else if phase == .background {
        if !model.fixture { BackgroundRefresh.schedule() }
        Task { await model.sync() }
      }
    }
    .sheet(isPresented: $settingsOpen) {
      NavigationStack { SettingsView(model: model) }
        .presentationBackground(AppPalette.background)
        .environment(\.colorScheme, appearance == "dark" ? .dark : appearance == "light" ? .light : systemColorScheme)
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
        .interactiveDismissDisabled()
    }
    .fullScreenCover(item: $model.presented) { challenge in
      NavigationStack { InterviewView(model: model, challenge: challenge) }
        .presentationBackground(AppPalette.background)
    }
    .sheet(item: $model.conflict) { challenge in
      NavigationStack {
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            Text("The answer changed on another device. Your local draft is still stored.")
            Text("Cloud answer").font(.headline)
            Text(challenge.session?.answer ?? "No answer").textSelection(.enabled)
            Button("Use cloud answer") { Task { await model.resolveConflict(keepLocal: false) } }
              .buttonStyle(PracticeButtonStyle())
            if challenge.isActive {
              Button("Keep my local answer") {
                Task { await model.resolveConflict(keepLocal: true) }
              }
            } else {
              Text("This session is already complete. Copy your local draft before replacing it.")
                .foregroundStyle(.secondary)
            }
            LocalRecoveryView(model: model, challenge: challenge)
          }.padding(24)
        }.navigationTitle("Review draft")
      }.interactiveDismissDisabled()
    }
    .alert(
      "Drillbit",
      isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })
    ) {
      Button("OK") { model.error = nil }
    } message: {
      Text(model.error ?? "")
    }
    .onOpenURL { url in
      if url.scheme == "dawi.drillbit" && url.host == "callback" { return }
      selectedTab = "home"
      Task { await model.refresh() }
    }
    .environment(\.formatsQuestions, model.settings.formatsQuestions)
  }
}

/// Neutral surface while Clerk and the account cache restore. Bit sits exactly where the launch screen drew him,
/// then drills only if restoration is slow, so fast launches never show a loading state.
private struct LaunchSurface: View {
  var message: String?
  var retry: () -> Void
  @State private var slow = false
  var body: some View {
    VStack(spacing: 32) {
      BitView(mood: message != nil ? .concerned : slow ? .drilling : .idle)
        .frame(width: BitLaunch.size.width, height: BitLaunch.size.height)
        .alignmentGuide(.launchMark) { $0[VerticalAlignment.center] }
      if let message {
        Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
        Button("Try again", action: retry)
      } else {
        Text("Picking up where you left off…").font(.subheadline).foregroundStyle(.secondary)
          .opacity(slow ? 1 : 0)
          .accessibilityHidden(!slow)
      }
    }
    .animation(DrillbitMotion.fast, value: slow)
    .padding(.horizontal, 24)
    // Mirrors the system launch screen (LaunchBit on LaunchBackground): Bit at the exact screen centre.
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Alignment(horizontal: .center, vertical: .launchMark))
    .ignoresSafeArea()
    .overlay(alignment: .bottom) {
      // Who built this, in the wordmark face it wears on t23.dev; only here, like Instagram's "from Meta".
      VStack(spacing: 1) {
        Text("by").font(.caption2.weight(.medium)).foregroundStyle(AppPalette.secondary)
        Text("t23.dev")
          .font(.custom("Literata", size: 19, relativeTo: .title3).weight(.medium))
          .tracking(-0.4)
          .foregroundStyle(AppPalette.primary)
      }
      .padding(.bottom, 12)
      .accessibilityElement(children: .combine)
      .accessibilityLabel("Made by t23.dev")
    }
    .background(AppPalette.background)
    .environment(\.colorScheme, .dark)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("sessionRestoration")
    .task {
      try? await Task.sleep(for: .seconds(1.2))
      slow = true
    }
  }
}

private extension VerticalAlignment {
  enum LaunchMark: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat { context[VerticalAlignment.center] }
  }
  static let launchMark = VerticalAlignment(LaunchMark.self)
}

/// The keyboard's rounded corners reveal the host window, outside SwiftUI's
/// keyboard-safe area. Keep that window on the same adaptive app floor.
private struct WindowFloorColor: UIViewRepresentable {
  func makeUIView(context: Context) -> FloorView { FloorView() }
  func updateUIView(_ view: FloorView, context: Context) { view.window?.backgroundColor = AppPalette.backgroundUIColor }

  final class FloorView: UIView {
    override func didMoveToWindow() {
      super.didMoveToWindow()
      window?.backgroundColor = AppPalette.backgroundUIColor
      if let window { KeyboardDismissal.install(on: window) }
    }
  }
}

/// Tapping anywhere outside a text input puts the keyboard away, on every screen, sheet and cover.
/// The tap still reaches controls; taps inside text inputs keep editing.
@MainActor private final class KeyboardDismissal: NSObject, UIGestureRecognizerDelegate {
  private static let shared = KeyboardDismissal()
  static func install(on window: UIWindow) {
    guard !(window.gestureRecognizers ?? []).contains(where: { $0.delegate === shared }) else { return }
    let tap = UITapGestureRecognizer(target: shared, action: #selector(dismiss(_:)))
    tap.cancelsTouchesInView = false
    tap.delaysTouchesEnded = false
    tap.delegate = shared
    window.addGestureRecognizer(tap)
  }
  // Deferred so the tapped control's action runs before focus (and any search state) changes.
  @objc private func dismiss(_ tap: UITapGestureRecognizer) {
    DispatchQueue.main.async { [weak window = tap.view] in window?.endEditing(true) }
  }
  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    var view = touch.view
    while let current = view {
      if current is UITextField || current is UITextView || current is UISearchBar { return false }
      view = current.superview
    }
    return true
  }
  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
struct LocalRecoveryView: View {
  var model: AppModel
  var challenge: Challenge
  @State private var local = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Local answer").font(.headline)
      Text(local).textSelection(.enabled)
      ShareLink("Export local answer", item: local)
    }.task { local = await model.localAnswer(challenge) }
  }
}
