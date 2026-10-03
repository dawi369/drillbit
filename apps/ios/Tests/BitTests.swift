import Foundation
import Testing

#if canImport(DrillbitCore)
  @testable import DrillbitCore
#else
  @testable import Drillbit
#endif

struct BitTests {
  private func finite(_ points: [CGPoint]) -> Bool { points.allSatisfy { $0.x.isFinite && $0.y.isFinite } }

  @Test func outlineIsFiniteAndStaysInsideTheBody() {
    for phase in stride(from: 0.0, to: 2 * .pi, by: 0.37) {
      var pose = BitPose()
      pose.phase = phase
      let outline = BitGeometry(pose: pose).outline()
      #expect(outline.count > 150)
      #expect(finite(outline))
      #expect(outline.allSatisfy { abs($0.x - BitShape.centerX) <= BitShape.maxRadius + 0.001 })
      #expect(abs(outline[0].x - BitShape.centerX) < 0.001)
    }
  }

  @Test func notchesStayBelowTheFluteStartAndWithinTheirDepth() {
    var pose = BitPose()
    pose.phase = 2.45
    let geometry = BitGeometry(pose: pose)
    for t in stride(from: 0.0, through: BitShape.length, by: 0.5) {
      for side in [Double.pi / 2, -Double.pi / 2] {
        let indent = geometry.indent(t, side: side)
        #expect(indent >= 0)
        #expect(indent <= BitShape.notchDepth + 0.001)
        if t < BitShape.fluteStart { #expect(indent == 0) }
      }
    }
  }

  @Test func notchesAreContinuousAcrossTheSpinWrap() {
    var before = BitPose(), after = BitPose()
    before.phase = 2 * .pi - 1e-7
    after.phase = 1e-7
    let a = BitGeometry(pose: before), b = BitGeometry(pose: after)
    for t in stride(from: BitShape.fluteStart, through: BitShape.length, by: 0.25) {
      #expect(abs(a.indent(t, side: .pi / 2) - b.indent(t, side: .pi / 2)) < 0.01)
    }
  }

  @Test func runOutClosesIntoAPoint() {
    var pose = BitPose()
    pose.phase = 2.3
    let flutes = BitGeometry(pose: pose).flutes()
    #expect(!flutes.isEmpty)
    let closed = flutes.filter { flute in
      guard let upper = flute.upper.last, let lower = flute.lower.last else { return false }
      return hypot(upper.x - lower.x, upper.y - lower.y) < 0.001
    }
    #expect(!closed.isEmpty)
    for flute in flutes {
      #expect(flute.upper.count == flute.lower.count)
      #expect(zip(flute.upper, flute.lower).allSatisfy { $0.y <= $1.y + 0.001 })
    }
  }

  @Test func restPosesCarryEachExpression() {
    #expect(BitPose.rest(.happy).left.bottom < 0)
    #expect(BitPose.rest(.drilling).left.top < BitPose.rest(.drilling).left.bottom)
    #expect(BitPose.rest(.thinking).right.top < BitPose.rest(.thinking).left.top)
    #expect(BitPose.rest(.talking).mouth > 0)
    #expect(BitPose.rest(.idle).mouth == 0)
    #expect(BitPose.rest(.thinking).dots == 1)
    #expect(BitPose.rest(.content).left.bottom < 0)
    #expect(BitPose.rest(.content).mouth == 0)
    #expect(BitPose.rest(.concerned).lookY > 0)
  }

  @MainActor @Test func moodsSettleThroughSprings() {
    let dynamics = BitDynamics(seed: 7)
    var pose = BitPose()
    for _ in 0..<120 { pose = dynamics.step(1.0 / 60, mood: .drilling) }
    #expect(pose.spin > 10)
    #expect(!pose.particles.isEmpty)
    #expect(abs(pose.left.top - 4) < 0.5)
    for _ in 0..<240 { pose = dynamics.step(1.0 / 60, mood: .idle) }
    #expect(pose.spin < 1)
    #expect(abs(pose.left.top - 9) < 0.5)
    #expect(pose.particles.isEmpty)
  }

  @MainActor @Test func boopIsHappyForAMomentThenReturns() {
    let dynamics = BitDynamics(seed: 3)
    _ = dynamics.step(1.0 / 60, mood: .idle)
    dynamics.boop()
    var pose = BitPose()
    for _ in 0..<30 { pose = dynamics.step(1.0 / 60, mood: .idle) }
    #expect(pose.left.bottom < 0)
    for _ in 0..<180 { pose = dynamics.step(1.0 / 60, mood: .idle) }
    #expect(pose.left.bottom > 0)
  }

  @MainActor @Test func longFramesStayStable() {
    let dynamics = BitDynamics(seed: 11)
    var pose = BitPose()
    for _ in 0..<50 { pose = dynamics.step(0.1, mood: .happy) }
    for value in [pose.squash, pose.lift, pose.headX, pose.mouth, pose.eyeWidth] {
      #expect(value.isFinite)
      #expect(abs(value) < 100)
    }
    #expect(finite(BitGeometry(pose: pose).outline()))
  }

  @MainActor @Test func talkingFollowsMeasuredAudio() {
    let dynamics = BitDynamics(seed: 5)
    var pose = BitPose()
    for _ in 0..<60 { pose = dynamics.step(1.0 / 60, mood: .talking, level: 0) }
    #expect(pose.mouth < 0.05)
    for _ in 0..<60 { pose = dynamics.step(1.0 / 60, mood: .talking, level: 0.5) }
    #expect(pose.mouth > 0.6)
  }
}
