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
  private enum Stage { case restoring, welcome, setup, app }
  private var stage: Stage {
    if model.restoringSession || model.launchError != nil { return .restoring }
    guard model.bootstrap?.account.status == "active" else { return .welcome }
    return model.settings.onboardingComplete ? .app : .setup
  }
  var body: some View {
    Group {
      if model.restoringSession || model.launchError != nil {
        LaunchSurface(message: model.launchError) { Task { await model.launch() } }
          .transition(.opacity)
      } else if let account = model.bootstrap?.account, account.status == "active" {
        if !model.settings.onboardingComplete {
          NavigationStack { SetupView(model: model) }
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
          }
          .allowsHitTesting(model.firstUse.tourTab == nil)
          .accessibilityHidden(model.firstUse.tourTab != nil)
          .overlay(alignment: .bottom) {
            if model.firstUse.tourTab != nil && model.presented == nil {
              FirstUseTourTip(model: model).padding(.bottom, 80)
                .transition(.opacity)
            }
          }
          .animation(DrillbitMotion.page, value: model.firstUse.stage)
          .transition(.opacity)
        }
      } else {
        WelcomeView(model: model)
          .transition(.opacity)
      }
    }
    .animation(DrillbitMotion.page, value: stage)
    .preferredColorScheme(model.fixture && ProcessInfo.processInfo.arguments.contains("--dark") ? .dark : appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
    .background(WindowFloorColor().allowsHitTesting(false))
    .onChange(of: model.firstUse.stage) { _, stage in
      if let tab = model.firstUse.tourTab { selectedTab = tab }
      if stage == .chooseMode { selectedTab = "home" }
    }
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
      if let tab = model.firstUse.tourTab { selectedTab = tab }
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

/// Neutral surface while Clerk and the account cache restore. Progress appears
/// only if restoration is slow, so fast launches never flash a spinner.
private struct LaunchSurface: View {
  var message: String?
  var retry: () -> Void
  @State private var slow = false
  var body: some View {
    VStack(spacing: 32) {
      DrillbitMark(size: 68).alignmentGuide(.launchMark) { $0[VerticalAlignment.center] }
      if let message {
        Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
        Button("Try again", action: retry)
      } else {
        ProgressView().controlSize(.small).opacity(slow ? 1 : 0)
          .accessibilityLabel("Restoring your session")
      }
    }
    .animation(DrillbitMotion.fast, value: slow)
    .padding(.horizontal, 24)
    // Mirrors the system launch screen (LaunchMark on LaunchBackground): the drill at the exact screen centre.
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Alignment(horizontal: .center, vertical: .launchMark))
    .ignoresSafeArea()
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
