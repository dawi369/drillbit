import Foundation
import Sentry
import StoreKit

/// Crash and error reports to Sentry (t23/drillbit-ios, EU), for what nobody expected: crashes, freezes, server
/// errors and responses the app can't read. Strict by design: no account or install identifier, no screenshots,
/// view hierarchy or replays, no request bodies, no practice text. Only builds with a DSN report (Release); fixtures
/// and tests never start it. Expected answers (free reps used, offline, a 4xx) are never sent.
enum CrashReporting {
  static func start() {
    guard let dsn = Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String, dsn.hasPrefix("https://") else { return }
    let info = Bundle.main.infoDictionary
    SentrySDK.start { options in
      options.dsn = dsn
      options.releaseName = "dawi.drillbit@\(info?["CFBundleShortVersionString"] as? String ?? "?")+\(info?["CFBundleVersion"] as? String ?? "?")"
      #if DEBUG
      options.environment = "development"
      #else
      options.environment = "production"
      #endif
      options.sendDefaultPii = false
      options.attachScreenshot = false
      options.attachViewHierarchy = false
      options.sessionReplay.sessionSampleRate = 0
      options.sessionReplay.onErrorSampleRate = 0
      // Sessions carry a per-install id; without them no device identifier leaves the phone.
      options.enableAutoSessionTracking = false
      options.tracesSampleRate = 0
      options.enableCaptureFailedRequests = false
      options.enableMetricKit = true
      options.maxBreadcrumbs = 40
      options.beforeBreadcrumb = scrub
      options.beforeSend = { event in
        event.user = nil
        event.extra = nil
        // Crashes recorded by builds up to 20 still carry the hash in their saved scope.
        event.context = withoutInstallHash(event.context)
        quietSystemHang(event, app: info?["CFBundleExecutable"] as? String ?? "Drillbit")
        // Without this, Sentry geolocates the connection's IP (city and country) before discarding the address.
        var sdk = event.sdk ?? [:]
        sdk["settings"] = ["infer_ip": "never"]
        event.sdk = sdk
        return event
      }
    }
    SentrySDK.configureScope { scope in
      // An empty user stops the SDK filling in its per-install id on reports that skip beforeSend (bug reports).
      scope.setUser(User())
      // The scope also feeds bug reports and the crash report written at the moment of a crash.
      let contexts = (scope.serialize()["context"] as? [String: [String: Any]])
      if let app = withoutInstallHash(contexts)?["app"] { scope.setContext(value: app, key: "app") }
    }
  }

  /// The SDK's `device_app_hash` is SHA-1 of identifierForVendor, model and bundle id: a stable per-install id.
  static func withoutInstallHash(_ contexts: [String: [String: Any]]?) -> [String: [String: Any]]? {
    guard var contexts, var app = contexts["app"] else { return contexts }
    app.removeValue(forKey: "device_app_hash")
    contexts["app"] = app
    return contexts
  }

  /// A hang whose only app frame is the `main` entry point was all system work (a cold Metal shader compile after an
  /// install or iOS update, or the main thread sitting idle in its run loop as the app resumes from a long suspension).
  /// Both MetricKit's and the SDK's own watchdog (`AppHang`) report these. It stays in Sentry as a warning tagged
  /// `hang: system`, so it counts without paging as a high-priority error. Hangs that pass through Drillbit code stay errors.
  static func quietSystemHang(_ event: Event, app: String) {
    guard let exception = event.exceptions?.first, ["mx_hang_diagnostic", "AppHang"].contains(exception.mechanism?.type ?? ""),
      let frames = exception.stacktrace?.frames, !frames.isEmpty
    else { return }
    // Outermost first: dyld, then main, then the run loop. Frames without a binary are kernel addresses. MetricKit
    // names the binary; the SDK's watchdog gives its full path.
    let binary = { (frame: Frame) in frame.package.map { ($0 as NSString).lastPathComponent } }
    let afterEntry = frames.drop { binary($0) == nil || binary($0) == "dyld" || binary($0) == app }
    guard !afterEntry.contains(where: { binary($0) == app }) else { return }
    event.level = .warning
    event.tags = (event.tags ?? [:]).merging(["hang": "system"]) { _, new in new }
  }

  /// System and network breadcrumbs only; taps and console lines can carry on-screen or practice text.
  private static let keptBreadcrumbs: Set<String> = ["http", "app.lifecycle", "ui.lifecycle", "navigation", "device.event", "device.orientation", "system", "sentry.event"]
  private static func scrub(_ crumb: Breadcrumb) -> Breadcrumb? {
    guard keptBreadcrumbs.contains(crumb.category) else { return nil }
    if var data = crumb.data, let url = data["url"] as? String {
      data["url"] = url.components(separatedBy: CharacterSet(charactersIn: "?#"))[0]
      crumb.data = data
    }
    return crumb
  }

  /// Settings → Developer: proves a build reports. False when Sentry is off (no DSN, as in Debug).
  static func sendTest() -> Bool {
    guard SentrySDK.isEnabled else { return false }
    SentrySDK.capture(message: "Test report from Settings → Developer")
    return true
  }

  /// Settings → Feedback → Report a bug. Not tied to any error and no screenshot; false when Sentry is off.
  static func sendBugReport(_ report: String, doing: String) -> Bool {
    guard SentrySDK.isEnabled else { return false }
    let message = doing.isEmpty ? report : "\(report)\n\nWhat I was doing: \(doing)"
    SentrySDK.capture(feedback: SentryFeedback(message: String(message.prefix(4000)), name: nil, email: nil, source: .custom))
    return true
  }

  /// A server error (5xx) or a response the app couldn't decode. The URL is reduced to its path with ids replaced;
  /// the Worker's `X-Request-ID` finds the same request in Worker logs and in drillbit-api.
  static func reportServer(_ error: Error, response: URLResponse?) {
    guard SentrySDK.isEnabled else { return }
    let tags = serverTags(response)
    SentrySDK.capture(error: error) { scope in
      for (key, value) in tags { scope.setTag(value: value, key: key) }
    }
  }

  static func serverTags(_ response: URLResponse?) -> [String: String] {
    let endpoint = (response?.url?.path ?? "?").replacingOccurrences(of: "[0-9A-Fa-f]{8}-[0-9A-Fa-f-]{27}", with: ":id", options: .regularExpression)
    var tags = ["endpoint": endpoint]
    if let id = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-Request-ID"), !id.isEmpty {
      tags["request_id"] = String(id.prefix(64))
    }
    return tags
  }

  /// A StoreKit failure at purchase or restore. Cancelling and being offline are expected; anything else may mean
  /// someone couldn't pay or get back what they paid for.
  static func reportStore(_ error: Error, operation: String) {
    guard SentrySDK.isEnabled, !(error is CancellationError), !(error is URLError) else { return }
    if let store = error as? StoreKitError {
      switch store {
      case .userCancelled, .networkError: return
      default: break
      }
    }
    SentrySDK.capture(error: error) { scope in scope.setTag(value: operation, key: "operation") }
  }

  /// Anything else that went wrong in an operation the user started, unless it's expected: a cancellation, being
  /// offline, or an answer from the server (those are reported at the source if they're server errors).
  static func reportUnexpected(_ error: Error, operation: String) {
    guard SentrySDK.isEnabled, !(error is CancellationError), !(error is URLError), !(error is APIError), !(error is DecodingError) else { return }
    SentrySDK.capture(error: error) { scope in scope.setTag(value: operation, key: "operation") }
  }

  /// Apple's sign-in sheet failing for a reason other than Cancel. Usually the Apple ID or iCloud state on the device,
  /// so a warning to count, not an issue to page on.
  static func reportAppleSignIn(_ error: NSError) {
    guard SentrySDK.isEnabled else { return }
    SentrySDK.capture(error: error) { scope in
      scope.setLevel(.warning)
      scope.setTag(value: "sign_in_apple", key: "operation")
    }
  }
}
