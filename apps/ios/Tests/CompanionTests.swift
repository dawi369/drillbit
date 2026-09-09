import Foundation
import Testing

#if canImport(DrillbitCore)
  @testable import DrillbitCore
#else
  @testable import Drillbit
#endif

struct CompanionTests {
  @Test func rewritesDeletionsAndCosmeticChanges() {
    let before = (0..<30).map { "word\($0)" }.joined(separator: " ")
    let after = (0..<30).map { "other\($0)" }.joined(separator: " ")
    #expect(InterventionPolicy.substantial(before, after))
    #expect(InterventionPolicy.substantial(before, ""))
    #expect(!InterventionPolicy.substantial("one two", " one\n two "))
    #expect(!InterventionPolicy.substantial("one two", "one three"))
  }
  @Test func pauseWithoutChangesAndSharedControls() {
    let p = InterventionPolicy()
    let now = Date(timeIntervalSince1970: 100)
    func trigger(
      _ age: Double, consumed: Bool = false, count: Int = 0, allowed: Bool = true, last: Date? = nil
    ) -> String? {
      p.trigger(
        now: now, activity: now.addingTimeInterval(-age), lastRequest: last, count: count,
        consumed: consumed, allowed: allowed, before: "", answer: "")
    }
    #expect(trigger(29) == nil)
    #expect(trigger(30) == "pause")
    #expect(trigger(90, consumed: true) == nil)
    #expect(trigger(90, count: 6) == nil)
    #expect(trigger(90, allowed: false) == nil)
    #expect(trigger(90, last: now.addingTimeInterval(-44)) == nil)
    #expect(trigger(90, last: now.addingTimeInterval(-45)) == "pause")
  }
  @Test func changesWaitForSettledInput() {
    let p = InterventionPolicy()
    let now = Date()
    let answer = String(repeating: "changed reasoning ", count: 15)
    #expect(
      p.trigger(
        now: now, activity: now.addingTimeInterval(-3), lastRequest: nil, count: 0, consumed: false,
        allowed: true, before: "", answer: answer) == nil)
    #expect(
      p.trigger(
        now: now, activity: now.addingTimeInterval(-4), lastRequest: nil, count: 0, consumed: false,
        allowed: true, before: "", answer: answer) == "change")
  }
  @MainActor @Test func restorationAndForegroundReset() throws {
    let now = Date(timeIntervalSince1970: 100)
    let c = CompanionCoordinator(clock: { now })
    c.context.mode = "coach"
    c.context.cycle = "cycle"
    c.lastActivity = now.addingTimeInterval(-40)
    #expect(c.eligible(answer: "", enabled: true, blocked: false) == "pause")
    c.event(.visibilityChanged)
    #expect(c.eligible(answer: "", enabled: true, blocked: false) == nil)
    c.consume(answer: "", trigger: "pause")
    let restored = CompanionCoordinator(clock: { now.addingTimeInterval(90) })
    restored.recovery = try JSONDecoder().decode(
      CompanionCoordinator.Recovery.self, from: JSONEncoder().encode(c.recovery))
    restored.context = c.context
    restored.lastActivity = now
    #expect(restored.eligible(answer: "", enabled: true, blocked: false) == nil)
  }
  @MainActor @Test func freshnessIncludesModeContextAndNormalizedAnswer() {
    let c = CompanionCoordinator()
    c.context = CompanionContext(
      revision: 2, mode: "coach", modeEpoch: 3, digest: InterventionPolicy.digest("answer"),
      cycle: "cycle")
    let result = HelpResult(
      id: "help", status: "completed", kind: "nudge", revision: 1, body: "A hint",
      capture: c.capture(trigger: "pause"))
    #expect(c.matches(result, answer: "answer"))
    #expect(!c.matches(result, answer: "new answer"))
    c.context.modeEpoch += 1
    #expect(!c.matches(result, answer: "answer"))
  }
}
