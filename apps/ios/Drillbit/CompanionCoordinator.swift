import CryptoKit
import Foundation
import Observation

/// Finalized input is shared by keyboard and future voice adapters. Provisional speech never enters here.
enum CompanionEvent {
  case answerCommitted(String)
  case discussionCommitted, inputActivity, userYield
  case modeChanged, visibilityChanged, assistanceDelivered
}
struct InterventionPolicy {
  var settledDelay: TimeInterval = 4
  var pauseDelay: TimeInterval = 30
  var cooldown: TimeInterval = 45
  var budget = 6
  static func normalize(_ text: String) -> String {
    text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }
  static func digest(_ text: String) -> String {
    SHA256.hash(data: Data(normalize(text).utf8)).map { String(format: "%02x", $0) }.joined()
  }
  static func substantial(_ before: String, _ after: String) -> Bool {
    let a = normalize(before)
    let b = normalize(after)
    guard a != b else { return false }
    // Differences count removals and replacements, not just growth. Bound character work for long drafts.
    if b.split(separator: " ").difference(from: a.split(separator: " ")).count >= 20 { return true }
    return Array(b.prefix(10000)).difference(from: Array(a.prefix(10000))).count >= 100
      || abs(a.count - b.count) >= 100
  }
  func trigger(
    now: Date, activity: Date, lastRequest: Date?, count: Int, consumed: Bool,
    allowed: Bool, before: String, answer: String
  ) -> String? {
    guard allowed, !consumed, count < budget, now.timeIntervalSince(activity) >= settledDelay,
      lastRequest.map({ now.timeIntervalSince($0) >= cooldown }) ?? true
    else { return nil }
    if Self.substantial(before, answer) { return "change" }
    if now.timeIntervalSince(activity) >= pauseDelay { return "pause" }
    return nil
  }
}

@MainActor @Observable final class CompanionCoordinator {
  struct Recovery: Codable {
    var consumed: Set<String> = []
    var checkedAnswer = ""
    var lastRequest: Date?
    var automaticCount = 0
    var suppressed: Set<String> = []
    var guidedCycles: Set<String> = []
  }
  var recovery = Recovery()
  var context = CompanionContext()
  var replacing = false
  var suggestion: HelpResult?
  var unavailable: String?
  var showProgress = false
  var requestingSince: Date?
  var foreground = true
  var modal = false
  var completing = false
  var generation = 0
  var lastActivity: Date
  var pendingGuided = false
  var policy = InterventionPolicy()
  private let clock: () -> Date
  init(clock: @escaping () -> Date = Date.init) {
    self.clock = clock
    lastActivity = clock()
  }
  var now: Date { clock() }
  var settled: Bool { now.timeIntervalSince(lastActivity) >= policy.settledDelay }
  func event(_ event: CompanionEvent) {
    switch event {
    case .answerCommitted:
      generation += 1
      lastActivity = now
      suggestion = nil
      unavailable = nil
    case .discussionCommitted:
      lastActivity = now
      unavailable = nil
    case .inputActivity, .visibilityChanged, .modeChanged: lastActivity = now
    case .userYield: lastActivity = now.addingTimeInterval(-policy.pauseDelay)
    case .assistanceDelivered: break
    }
  }
  func eligible(answer: String, enabled: Bool, blocked: Bool) -> String? {
    policy.trigger(
      now: now, activity: lastActivity, lastRequest: recovery.lastRequest,
      count: max(recovery.automaticCount, context.automaticCount),
      consumed: context.cycleConsumed == true || recovery.consumed.contains(context.cycle),
      allowed: enabled && !blocked && foreground && !modal && !completing && !context.paused
        && context.mode != "solo" && unavailable == nil,
      before: recovery.checkedAnswer, answer: answer)
  }
  func capture(trigger: String) -> CompanionCapture {
    CompanionCapture(
      contextRevision: context.revision, modeEpoch: context.modeEpoch,
      cycle: context.cycle, digest: context.digest, trigger: trigger)
  }
  func consume(answer: String, trigger: String) {
    if ["pause", "change"].contains(trigger) {
      recovery.consumed.insert(context.cycle)
      recovery.checkedAnswer = answer
      recovery.lastRequest = now
      recovery.automaticCount += 1
    }
    if trigger == "guided_entry" {
      recovery.guidedCycles.insert(context.cycle)
      recovery.consumed.insert(context.cycle)
    }
    requestingSince = now
  }
  func matches(_ result: HelpResult, answer: String) -> Bool {
    guard let capture = result.capture else { return false }
    return capture.contextRevision == context.revision && capture.modeEpoch == context.modeEpoch
      && capture.digest == InterventionPolicy.digest(answer) && capture.cycle == context.cycle
  }
}
