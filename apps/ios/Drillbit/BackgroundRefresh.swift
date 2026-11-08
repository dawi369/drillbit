import BackgroundTasks

/// What refresh needs from a `BGTask`, so a test can play the system's part.
protocol RefreshTask: AnyObject {
  var expirationHandler: (() -> Void)? { get set }
  func setTaskCompleted(success: Bool)
}
extension BGTask: RefreshTask {}

/// The registration call, so a test can see which queue the launch handler is given.
protocol RefreshScheduler {
  func register(
    forTaskWithIdentifier identifier: String, using queue: DispatchQueue?,
    launchHandler: @escaping (BGTask) -> Void) -> Bool
}
extension BGTaskScheduler: RefreshScheduler {}

@MainActor enum BackgroundRefresh {
  static let identifier = "dawi.drillbit.refresh"

  /// BackgroundTasks calls the launch handler on `queue`. The handler is formed on the main actor, so Swift 6 checks
  /// it runs on the main queue; `nil` picks a background queue and trapped on entry (Sentry DRILLBIT-IOS-5).
  static func register(
    with scheduler: some RefreshScheduler = BGTaskScheduler.shared,
    refresh: @escaping @MainActor () async -> Void
  ) {
    _ = scheduler.register(forTaskWithIdentifier: identifier, using: .main) { task in
      run(task, refresh: refresh)
    }
  }

  /// The system calls the expiration handler on a queue of its choosing, so that closure stays nonisolated.
  @discardableResult static func run(
    _ task: some RefreshTask, reschedule: @escaping @MainActor () -> Void = { schedule() },
    refresh: @escaping @MainActor () async -> Void
  ) -> Task<Void, Never> {
    let work = Task { @MainActor in
      await refresh()
      reschedule()
      task.setTaskCompleted(success: !Task.isCancelled)
    }
    task.expirationHandler = { @Sendable in work.cancel() }
    return work
  }

  static func schedule() {
    let request = BGAppRefreshTaskRequest(identifier: identifier)
    request.earliestBeginDate = Date().addingTimeInterval(3600)
    try? BGTaskScheduler.shared.submit(request)
  }
}
