import XCTest

/// Screenshots of the Bit tab and the practice sheet it opens, for design review. Fixtures only; it runs when asked
/// (`TEST_RUNNER_DRILLBIT_DESIGN_SHOTS=1`). Screenshots are the output: export them from the result bundle.
@MainActor
final class DesignShots: XCTestCase {
  private var app: XCUIApplication!
  private var step = 0

  override func setUpWithError() throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["DRILLBIT_DESIGN_SHOTS"] == "1", "Design shots run only when asked.")
    continueAfterFailure = true
  }

  private func shot(_ name: String) {
    step += 1
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = String(format: "%02d-%@", step, name)
    attachment.lifetime = .keepAlways
    add(attachment)
  }
  private func any(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }
  private func reveal(_ element: XCUIElement) {
    for _ in 0..<6 where !(element.exists && element.isHittable) { app.swipeUp(); Thread.sleep(forTimeInterval: 0.4) }
  }

  func testBitAndPracticeSheet() throws {
    app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-dashboard", "--fixture-map", "--fixture-pro", "--fixture-bit"]
    app.launch()
    XCTAssertTrue(any("knowledgeMap").waitForExistence(timeout: 15))
    Thread.sleep(forTimeInterval: 2)
    shot("bit-top")
    app.swipeUp(); Thread.sleep(forTimeInterval: 0.8)
    shot("bit-level")
    app.swipeUp(); Thread.sleep(forTimeInterval: 0.8)
    shot("bit-next")
    app.swipeUp(); Thread.sleep(forTimeInterval: 0.8)
    shot("bit-bottom")

    // A concept on the map, then "Practise this": the sheet opens on that concept, its area and every area behind it.
    for _ in 0..<6 { app.swipeDown() }
    let node = app.buttons["mapNode-consistency"]
    XCTAssertTrue(node.waitForExistence(timeout: 5))
    node.tap()
    Thread.sleep(forTimeInterval: 0.8)
    let practise = app.buttons["mapPractise"]
    reveal(practise)
    shot("bit-detail")
    practise.tap()
    Thread.sleep(forTimeInterval: 1.5)
    shot("sheet-topic")
    let back = app.navigationBars.buttons.element(boundBy: 0)
    if back.waitForExistence(timeout: 3) { back.tap() }
    Thread.sleep(forTimeInterval: 1)
    shot("sheet-area")
    if back.waitForExistence(timeout: 3) { back.tap() }
    Thread.sleep(forTimeInterval: 1)
    shot("sheet-areas")
    app.swipeUp(); Thread.sleep(forTimeInterval: 0.6)
    shot("sheet-areas-scrolled")
    // Typing your own topic: the card scrolls up above the keyboard.
    let custom = app.textFields["customTopic"]
    if custom.waitForExistence(timeout: 3) {
      custom.tap(); Thread.sleep(forTimeInterval: 1.2)
      custom.typeText("search ranking"); Thread.sleep(forTimeInterval: 0.6)
      shot("sheet-custom-typing")
      app.swipeDown(); Thread.sleep(forTimeInterval: 0.6)
    }
    for _ in 0..<3 { app.swipeDown() }
    Thread.sleep(forTimeInterval: 0.6)

    // Bit's pick from the top of the sheet, then search.
    if app.buttons["browse-pick"].waitForExistence(timeout: 3) {
      app.buttons["browse-pick"].tap(); Thread.sleep(forTimeInterval: 1.2); shot("sheet-pick")
      if back.waitForExistence(timeout: 3) { back.tap() }
      Thread.sleep(forTimeInterval: 1)
    }
    let search = app.searchFields.firstMatch
    if search.waitForExistence(timeout: 3) {
      search.tap(); search.typeText("cach"); Thread.sleep(forTimeInterval: 1); shot("sheet-search")
    }
  }
}
