#if !canImport(DrillbitCore)
  import BackgroundTasks
  import Foundation
  import Testing
  @testable import Drillbit

  /// Plays the system: BackgroundTasks completes and expires tasks from its own queues.
  private final class SystemTask: RefreshTask, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (() -> Void)?
    private var result: Bool?
    var expirationHandler: (() -> Void)? {
      get { lock.withLock { handler } }
      set { lock.withLock { handler = newValue } }
    }
    var success: Bool? { lock.withLock { result } }
    func setTaskCompleted(success: Bool) { lock.withLock { result = success } }
  }

  private final class Scheduler: RefreshScheduler {
    var identifier: String?
    var queue: DispatchQueue?
    func register(
      forTaskWithIdentifier identifier: String, using queue: DispatchQueue?,
      launchHandler: @escaping (BGTask) -> Void
    ) -> Bool {
      self.identifier = identifier
      self.queue = queue
      return true
    }
  }

  @MainActor private final class Flag { var raised = false }

  @MainActor struct BackgroundRefreshTests {
    @Test func launchHandlerRunsOnTheMainQueue() {
      // The handler is main-actor isolated: any other queue traps on entry (Sentry DRILLBIT-IOS-5).
      let scheduler = Scheduler()
      BackgroundRefresh.register(with: scheduler) {}
      #expect(scheduler.identifier == "dawi.drillbit.refresh")
      #expect(scheduler.queue === DispatchQueue.main)
    }

    @Test func expiryFromABackgroundQueueCancelsTheRefresh() async {
      let task = SystemTask()
      let rescheduled = Flag()
      let work = BackgroundRefresh.run(task, reschedule: { rescheduled.raised = true }) {
        try? await Task.sleep(for: .seconds(30))
      }
      nonisolated(unsafe) let expire = task.expirationHandler
      await withCheckedContinuation { done in
        DispatchQueue.global().async {
          expire?()
          done.resume()
        }
      }
      await work.value
      #expect(task.success == false)
      #expect(rescheduled.raised)
    }

    @Test func finishedRefreshCompletesAndReschedules() async {
      let task = SystemTask()
      let rescheduled = Flag()
      await BackgroundRefresh.run(task, reschedule: { rescheduled.raised = true }) {}.value
      #expect(task.success == true)
      #expect(rescheduled.raised)
    }
  }
#endif
