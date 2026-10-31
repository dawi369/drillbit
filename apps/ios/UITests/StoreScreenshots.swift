import StoreKitTest
import XCTest

/// App Store screenshots: run on a 6.9" iPhone simulator with a 9:41 status bar, then export the attachments.
/// `--fixture-customer` hides developer-only UI so every frame matches what a subscriber sees.
///
///   xcrun simctl status_bar <udid> override --time 9:41 --batteryState charged --batteryLevel 100
///   xcodebuild test ... -only-testing:DrillbitUITests/StoreScreenshots
@MainActor
final class StoreScreenshots: XCTestCase {
  override func setUp() { continueAfterFailure = false }

  private func launch(_ arguments: [String]) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = arguments + ["--fixture-customer", "-appearance", "dark"]
    app.launch()
    return app
  }

  private func shot(_ name: String, _ app: XCUIApplication) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func editor(_ app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: "answerEditor").firstMatch
  }

  func testStoreScreenshots() throws {
    var app = launch(["--fixtures", "--fixture-signed-out", "--fixture-walkthrough"])
    XCTAssertTrue(app.descendants(matching: .any)["separatorBit"].waitForExistence(timeout: 25))
    Thread.sleep(forTimeInterval: 1.5)
    shot("01-welcome", app)
    app.terminate()

    app = launch(["--fixtures", "--fixture-home-rich"])
    XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.tabBars.buttons["Bit"].exists, "Everyone sees the Bit tab; it's Pro behind the tap")
    app.buttons["startPractice"].tap()
    XCTAssertTrue(app.buttons["previewStart"].waitForExistence(timeout: 5))
    app.buttons["previewStart"].tap()
    XCTAssertTrue(editor(app).waitForExistence(timeout: 5))
    editor(app).tap()
    editor(app).typeText("Use a durable queue, retry failed work with backoff, and record each attempt so duplicates stay safe.")
    app.buttons["shareAnswer"].tap()
    XCTAssertTrue(app.staticTexts["What happens if a worker stops after completing the operation but before acknowledging it?"].waitForExistence(timeout: 8))
    editor(app).tap()
    editor(app).typeText("The worker writes the result and an idempotency key in one transaction, so a redelivered job sees the key and")
    Thread.sleep(forTimeInterval: 1)
    shot("02-interview", app)
    app.buttons["interviewOptions"].tap()
    app.buttons["Show an example"].tap()
    XCTAssertTrue(app.buttons["Got it"].waitForExistence(timeout: 8))
    Thread.sleep(forTimeInterval: 0.6)
    shot("03-example", app)
    app.terminate()

    app = launch(["--fixtures", "--fixture-dashboard", "--fixture-evidence", "--fixture-recall-due"])
    XCTAssertTrue(app.tabBars.buttons["Recall"].waitForExistence(timeout: 10))
    Thread.sleep(forTimeInterval: 1)
    shot("04-home", app)
    app.tabBars.buttons["Recall"].tap()
    XCTAssertTrue(app.buttons["recallReveal"].waitForExistence(timeout: 5))
    app.buttons["recallReveal"].tap()
    Thread.sleep(forTimeInterval: 0.8)
    shot("05-recall", app)
    app.tabBars.buttons["Library"].tap()
    XCTAssertTrue(app.buttons["worthTryAgain"].waitForExistence(timeout: 10))
    Thread.sleep(forTimeInterval: 0.8)
    shot("06-library", app)
  }

  /// The subscription review screenshot App Store Connect asks for: the paywall with real plan options.
  func testPaywallReviewScreenshot() throws {
    let store = try SKTestSession(configurationFileNamed: "Drillbit")
    store.resetToDefaultState(); store.disableDialogs = true; store.clearTransactions()
    let app = launch(["--fixtures", "--fixture-dashboard", "--fixture-gate"])
    XCTAssertTrue(app.buttons["seePro"].waitForExistence(timeout: 10))
    app.buttons["seePro"].tap()
    // A freshly booted simulator's StoreKit test session can miss the first request; retry as a person would.
    for _ in 0..<4 where !app.buttons["paywallSubscribe"].waitForExistence(timeout: 5) {
      if app.buttons["Try again"].exists { app.buttons["Try again"].tap() }
    }
    XCTAssertTrue(app.buttons["paywallSubscribe"].exists)
    XCTAssertFalse(app.buttons["paywallFixturePurchase"].exists, "No debug controls in the review screenshot")
    Thread.sleep(forTimeInterval: 1.5)
    shot("review-paywall", app)
  }
}
