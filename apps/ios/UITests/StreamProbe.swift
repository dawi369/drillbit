import XCTest

/// Diagnostic, not a gate: records a streaming question frame by frame so stalls are measured rather than guessed.
/// The bursty fixture reproduces the live provider's shape (big chunks, quiet gaps, text done before the job).
final class StreamProbe: XCTestCase {
  /// The first question of onboarding, in the preview.
  func testProbePreviewStream() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-onboarding", "--fixture-bursty-stream"]
    app.launch()
    XCTAssertTrue(app.staticTexts["Quick one. No wrong answers."].waitForExistence(timeout: 10))
    app.buttons["The database"].tap()
    for _ in 0..<6 { app.buttons["Continue"].tap() }
    let start = Date()
    app.buttons["Show me my first question"].tap()
    record(app, from: start, until: app.buttons["previewStart"])
  }
  /// Home's ticket writing today's question.
  func testProbeHomeTicket() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-dashboard", "--fixture-auto-question", "--fixture-bursty-stream"]
    let start = Date()
    app.launch()
    record(app, from: start, until: app.buttons["startPractice"])
  }

  private func record(_ app: XCUIApplication, from start: Date, until doneMarker: XCUIElement) {
    var frames = 0
    var doneAt: TimeInterval?
    while Date().timeIntervalSince(start) < 40 {
      let attachment = XCTAttachment(screenshot: app.screenshot())
      attachment.name = String(format: "frame-%06d", Int(Date().timeIntervalSince(start) * 1000))
      attachment.lifetime = .keepAlways
      add(attachment)
      frames += 1
      if doneAt == nil, doneMarker.exists { doneAt = Date().timeIntervalSince(start) }
      if let seen = doneAt, Date().timeIntervalSince(start) - seen > 1.2 { break }
      Thread.sleep(forTimeInterval: 0.06)
    }
    NSLog("STREAMPROBE frames=\(frames) doneAt=\(doneAt.map { String(format: "%.2f", $0) } ?? "never")")
    XCTAssertNotNil(doneAt)
  }
}
