import MetricKit
import OSLog

/// Local diagnostics contain counts only, never payloads, stacks or practice text.
final class AppDiagnostics: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
  static let shared = AppDiagnostics()
  private let logger = Logger(subsystem: "dawi.drillbit", category: "reliability")
  func start() { MXMetricManager.shared.add(self) }
  func didReceive(_ payloads: [MXDiagnosticPayload]) {
    for payload in payloads {
      logger.notice("diagnostics crashes=\(payload.crashDiagnostics?.count ?? 0, privacy: .public) hangs=\(payload.hangDiagnostics?.count ?? 0, privacy: .public)")
    }
  }
}
