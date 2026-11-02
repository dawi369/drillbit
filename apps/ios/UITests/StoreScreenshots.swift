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

  /// Frames 1, 3, 4, 5 and 6 of the listing. Frame 2, live voice, comes from a real phone.
  /// Home, Recall and Library are captured as spares.
  func testStoreScreenshots() throws {
    var app = launch(["--fixtures", "--fixture-signed-out", "--fixture-walkthrough"])
    XCTAssertTrue(app.descendants(matching: .any)["separatorBit"].waitForExistence(timeout: 25))
    XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Next'")).firstMatch.exists)
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
    // Sending drops the keyboard, so the follow-up gets the whole screen.
    app.buttons["shareAnswer"].tap()
    XCTAssertTrue(app.staticTexts["What happens if a worker stops after completing the operation but before acknowledging it?"].waitForExistence(timeout: 8))
    XCTAssertTrue(waitForNoKeyboard(app))
    Thread.sleep(forTimeInterval: 1)
    shot("03-pushback", app)
    app.buttons["interviewOptions"].tap()
    app.buttons["Show an example"].tap()
    XCTAssertTrue(app.buttons["Got it"].waitForExistence(timeout: 8))
    XCTAssertTrue(waitForNoKeyboard(app))
    XCTAssertTrue(app.buttons["Got it"].isHittable, "The whole example sheet is in view")
    Thread.sleep(forTimeInterval: 0.8)
    shot("04-example", app)
    app.buttons["Got it"].tap()
    app.buttons["interviewOptions"].tap()
    app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Finish interview'")).firstMatch.tap()
    app.descendants(matching: .any)["confirmDialog"].buttons["Finish interview"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["feedbackLead"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '“'")).firstMatch.exists, "Quotes their own words")
    Thread.sleep(forTimeInterval: 1.5)
    shot("05-feedback", app)
    app.terminate()

    app = launch(["--fixtures", "--fixture-dashboard", "--fixture-map", "--fixture-pro"])
    XCTAssertTrue(app.tabBars.buttons["Bit"].waitForExistence(timeout: 10))
    app.tabBars.buttons["Bit"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["knowledgeMap"].waitForExistence(timeout: 5))
    Thread.sleep(forTimeInterval: 1.5)
    shot("06-knowledge-map", app)
    app.terminate()

    app = launch(["--fixtures", "--fixture-dashboard", "--fixture-evidence", "--fixture-recall-due"])
    XCTAssertTrue(app.tabBars.buttons["Recall"].waitForExistence(timeout: 10))
    Thread.sleep(forTimeInterval: 1)
    shot("spare-home", app)
    app.tabBars.buttons["Recall"].tap()
    XCTAssertTrue(app.buttons["recallReveal"].waitForExistence(timeout: 5))
    app.buttons["recallReveal"].tap()
    Thread.sleep(forTimeInterval: 0.8)
    shot("spare-recall", app)
    app.tabBars.buttons["Library"].tap()
    XCTAssertTrue(app.buttons["worthTryAgain"].waitForExistence(timeout: 10))
    Thread.sleep(forTimeInterval: 0.8)
    shot("spare-library", app)
  }

  private func waitForNoKeyboard(_ app: XCUIApplication) -> Bool {
    for _ in 0..<20 {
      if app.keyboards.count == 0 { return true }
      Thread.sleep(forTimeInterval: 0.25)
    }
    return false
  }

  /// For App Review (5.1.2(i)): where the third-party AI permission is asked, and where it can be read again.
  func testAIConsentReviewScreenshots() throws {
    // A new account: setup, then the first question is about to be written. Nothing has gone to a model yet.
    var app = launch(["--fixtures", "--fixture-onboarding", "--fixture-no-ai-consent"])
    XCTAssertTrue(app.staticTexts["Quick one. No wrong answers."].waitForExistence(timeout: 10))
    app.buttons["The database"].tap()
    for _ in 0..<6 { app.buttons["Continue"].tap() }
    XCTAssertTrue(app.buttons["Show me my first question"].waitForExistence(timeout: 5))
    app.buttons["Show me my first question"].tap()
    XCTAssertTrue(app.buttons["aiConsentAgree"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Bit runs on outside AI."].exists)
    Thread.sleep(forTimeInterval: 1.2)
    shot("review-ai-consent-first-question", app)
    app.buttons["aiConsentAgree"].tap()
    XCTAssertTrue(app.buttons["previewStart"].waitForExistence(timeout: 15), "Agreeing lets the first question be written")
    app.terminate()

    // Signed in without it (an update): Home is open; starting a question asks first.
    app = launch(["--fixtures", "--fixture-home-rich", "--fixture-no-ai-consent"])
    XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout: 10))
    app.buttons["startPractice"].tap()
    XCTAssertTrue(app.buttons["previewStart"].waitForExistence(timeout: 5))
    app.buttons["previewStart"].tap()
    XCTAssertTrue(app.buttons["aiConsentAgree"].waitForExistence(timeout: 5))
    Thread.sleep(forTimeInterval: 1.2)
    shot("review-ai-consent-returning", app)
    app.terminate()

    // Settings → AI and your data: the same words, any time.
    app = launch(["--fixtures", "--fixture-settings"])
    let row = app.buttons["settingsAIData"]
    for _ in 0..<8 where !row.exists || !row.isHittable { app.swipeUp() }
    Thread.sleep(forTimeInterval: 0.6)
    shot("review-ai-data-settings-row", app)
    row.tap()
    XCTAssertTrue(app.descendants(matching: .any)["aiDisclosure"].waitForExistence(timeout: 5))
    Thread.sleep(forTimeInterval: 0.8)
    shot("review-ai-data-settings", app)
  }

  /// The subscription review screenshot App Store Connect asks for: the paywall with real plan options.
  func testPaywallReviewScreenshot() throws {
    let store = try SKTestSession(configurationFileNamed: "Drillbit")
    store.resetToDefaultState(); store.disableDialogs = true; store.clearTransactions()
    // Production's model: both lifetime free reps used.
    let app = launch(["--fixtures", "--fixture-dashboard", "--fixture-lifetime-spent"])
    XCTAssertTrue(app.buttons["seePro"].waitForExistence(timeout: 10))
    app.buttons["seePro"].tap()
    // A freshly booted simulator's StoreKit test session can miss the first request; retry as a person would.
    for _ in 0..<4 where !app.buttons["paywallSubscribe"].waitForExistence(timeout: 5) {
      if app.buttons["Try again"].exists { app.buttons["Try again"].tap() }
    }
    XCTAssertTrue(app.buttons["paywallSubscribe"].exists)
    XCTAssertFalse(app.buttons["paywallFixturePurchase"].exists, "No debug controls in the review screenshot")
    XCTAssertTrue(app.staticTexts["Keep the reps coming."].exists)
    Thread.sleep(forTimeInterval: 1.5)
    shot("review-paywall", app)
  }
}
