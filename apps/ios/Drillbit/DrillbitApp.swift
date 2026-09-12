import BackgroundTasks
import ClerkKit
import SwiftData
import SwiftUI
import UserNotifications

final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
  ) async {
    await MainActor.run {
      NotificationCenter.default.post(name: .init("OpenPractice"), object: nil)
    }
  }
}
@main struct DrillbitApp: App {
  @State private var model: AppModel?
  private let configurationError: String?
  private let notificationRouter = NotificationRouter()
  init() {
    let key = Bundle.main.object(forInfoDictionaryKey: "ClerkPublishableKey") as? String ?? ""
    let endpoint = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String ?? ""
    var fixture = false
    #if DEBUG
      fixture = ProcessInfo.processInfo.arguments.contains("--fixtures")
    #endif
    guard
      fixture
        || (key.hasPrefix("pk_") && endpoint.hasPrefix("https://")
          && !endpoint.contains("example.invalid"))
    else {
      configurationError =
        "Set API_BASE_URL and CLERK_PUBLISHABLE_KEY in Config/Local.xcconfig, then rebuild. No provider secret belongs in the app."
      return
    }
    do {
      let configuration = ModelConfiguration(isStoredInMemoryOnly: fixture, cloudKitDatabase: .none)
      let container = try ModelContainer(
        for: Schema(StoreV1.models), migrationPlan: StoreMigrations.self,
        configurations: configuration)
      if !fixture { Clerk.configure(publishableKey: key); AppDiagnostics.shared.start() }
      let appModel = AppModel(
        container: container,
        baseURL: URL(string: endpoint) ?? URL(string: "https://example.invalid")!, fixture: fixture)
      _model = State(initialValue: appModel)
      configurationError = nil
      UNUserNotificationCenter.current().delegate = notificationRouter
      BGTaskScheduler.shared.register(forTaskWithIdentifier: "dawi.drillbit.refresh", using: nil) {
        task in
        let work = Task { @MainActor in
          await appModel.refresh()
          BackgroundRefresh.schedule()
          task.setTaskCompleted(success: !Task.isCancelled)
        }
        task.expirationHandler = { work.cancel() }
      }
    } catch {
      configurationError =
        "The local store could not open. Your existing files have not been deleted. \(error.localizedDescription)"
    }
  }
  var body: some Scene {
    WindowGroup {
      if let model {
        RootView(model: model).tint(AppPalette.primary)
      } else {
        ContentUnavailableView(
          "Setup required", systemImage: "gearshape",
          description: Text(configurationError ?? "Configuration is unavailable."))
      }
    }
  }
}

@MainActor enum BackgroundRefresh {
  static func schedule() {
    let request = BGAppRefreshTaskRequest(identifier: "dawi.drillbit.refresh")
    request.earliestBeginDate = Date().addingTimeInterval(3600)
    try? BGTaskScheduler.shared.submit(request)
  }
}
