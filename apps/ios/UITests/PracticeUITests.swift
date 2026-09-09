import XCTest

@MainActor
final class PracticeUITests: XCTestCase {
  func testBackgroundPreviewDoesNotReturn() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-dashboard"]
    app.launch()
    XCTAssertTrue(app.buttons["Prepare question"].waitForExistence(timeout: 10))
    app.buttons["Prepare question"].tap()
    app.buttons["submitPreparation"].tap()
    XCTAssertTrue(app.navigationBars["Question preview"].waitForExistence(timeout: 5))
    XCUIDevice.shared.press(.home)
    app.activate()
    XCTAssertTrue(app.staticTexts["Your practice"].waitForExistence(timeout: 8))
    XCTAssertFalse(app.navigationBars["Question preview"].exists)
  }

  func testGenerationPreviewAndResume() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-dashboard"]
    app.launch()
    XCTAssertTrue(app.buttons["Prepare question"].waitForExistence(timeout: 10))
    app.buttons["Prepare question"].tap()
    app.buttons["submitPreparation"].tap()
    XCTAssertTrue(app.staticTexts["Design a reliable job queue"].waitForExistence(timeout: 8))
    XCTAssertTrue(app.navigationBars["Question preview"].exists)
    app.buttons["previewStart"].tap()
    let editor = app.textViews["answerEditor"]
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    editor.tap()
    editor.typeText("Keep retries bounded.")
    app.buttons["Close"].tap()
    XCTAssertTrue(app.staticTexts["Your practice"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["startPractice"].label == "Resume")
    app.buttons["startPractice"].tap()
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    XCTAssertTrue((editor.value as? String ?? "").contains("Keep retries bounded."))
  }

  func testLongPreviewLayout() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-long-question", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
    app.launch()
    XCTAssertTrue(app.staticTexts["Your practice"].waitForExistence(timeout: 10))
    let preview = app.buttons["startPractice"]
    for _ in 0..<8 where !preview.isHittable { app.swipeUp() }
    XCTAssertTrue(preview.isHittable)
    capture("Small phone accessible Today", app)
    preview.tap()
    XCTAssertTrue(app.buttons["previewStart"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["previewStart"].isHittable)
    capture("Small phone accessible preview", app)
    app.swipeUp()
    XCTAssertTrue(app.buttons["previewStart"].isHittable)
    app.buttons["Close"].tap()
    XCTAssertTrue(app.tabBars.buttons["Memory"].isHittable)
  }

  func testPreviewFailures() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-generation-failure", "--fixture-start-failure"]
    app.launch()
    XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout: 10))
    app.buttons["startPractice"].tap()
    app.buttons["previewStart"].tap()
    XCTAssertTrue(app.staticTexts["Could not start. Try again."].waitForExistence(timeout: 5))
    XCTAssertTrue(app.navigationBars["Question preview"].exists)
    XCTAssertFalse(app.textViews["answerEditor"].exists)
    app.buttons["Choose another question"].tap()
    app.buttons["Prepare question"].tap()
    XCTAssertTrue(app.buttons["Back to preparation"].waitForExistence(timeout: 8))
    capture("Failed replacement", app)
    app.buttons["Close"].tap()
    XCTAssertTrue(app.staticTexts["Your practice"].exists)
    XCTAssertTrue(app.staticTexts["Design a feature-flag control plane"].exists)
  }

  func testTodayPreviewLifecycle() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures"]
    app.launch()
    XCTAssertTrue(app.staticTexts["Your practice"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["startPractice"].exists)
    capture("Persistent Today", app)
    app.buttons["startPractice"].tap()
    XCTAssertTrue(app.buttons["previewStart"].waitForExistence(timeout: 5))
    capture("Question preview", app)
    app.buttons["Close"].tap()
    XCTAssertTrue(app.staticTexts["Your practice"].waitForExistence(timeout: 5))
    app.buttons["startPractice"].tap()
    app.buttons["Choose another question"].tap()
    app.buttons["Prepare question"].tap()
    XCTAssertTrue(app.navigationBars["Question preview"].waitForExistence(timeout: 5))
    app.buttons["Close"].tap()
    XCTAssertTrue(app.staticTexts["Your practice"].waitForExistence(timeout: 5))
    sleep(3)
    XCTAssertFalse(app.navigationBars["Question preview"].exists)
    app.buttons["startPractice"].tap()
    XCTAssertTrue(app.staticTexts["Design a reliable job queue"].waitForExistence(timeout: 5))
    app.buttons["previewStart"].tap()
    XCTAssertTrue(app.textViews["answerEditor"].waitForExistence(timeout: 5))
  }

  func testTemporaryPreparation() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-dashboard"]
    app.launch()
    XCTAssertTrue(app.buttons["Prepare question"].waitForExistence(timeout: 10))
    app.buttons["Prepare question"].tap()
    app.buttons["prepareTopic"].tap()
    app.buttons["Backend"].tap()
    app.buttons["prepareLevel"].tap()
    app.buttons["Senior"].tap()
    XCTAssertTrue(app.textFields["Optional request"].exists || app.textViews["Optional request"].exists)
    capture("Temporary preparation", app)
    app.buttons["Cancel"].tap()
    app.buttons["Prepare question"].tap()
    XCTAssertTrue(app.buttons["prepareTopic"].label.contains("System design"))
    XCTAssertTrue(app.buttons["prepareLevel"].label.contains("Mid-level"))
    capture("Preparation defaults", app)
    app.buttons["Cancel"].tap()
    app.buttons["Settings"].tap()
    XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Engineering level, Mid-level")).firstMatch.exists)
  }

  func testPracticeDashboard() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-dashboard"]
    app.launch()
    XCTAssertTrue(app.staticTexts["Your practice"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["12"].exists)
    XCTAssertTrue(app.staticTexts["4"].exists)
    XCTAssertTrue(app.staticTexts["Last session"].exists)
    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Junior · Finished ")).firstMatch.exists)
    XCTAssertTrue(app.buttons["Prepare question"].exists)
    capture("Practice dashboard", app)
    app.buttons["Prepare question"].tap()
    XCTAssertTrue(app.navigationBars["New question"].waitForExistence(timeout: 5))
  }

  func testSettingsAccessibleAndOnboarding() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-long-focus", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
    app.launch()
    XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
    app.buttons["Settings"].tap()
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    let focus = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Focus,")).firstMatch
    XCTAssertTrue(focus.label.contains("safe cross-team migrations"))
    capture("Settings accessible long focus", app)
    focus.tap()
    XCTAssertTrue(app.navigationBars["Focus"].waitForExistence(timeout: 5))
    for _ in 0..<6 where !app.textViews["Practice focus"].exists { app.swipeUp() }
    XCTAssertTrue(app.textViews["Practice focus"].exists)
    capture("Focus accessible", app)
    app.terminate()
    app.launchArguments = ["--fixtures", "--fixture-onboarding"]
    app.launch()
    XCTAssertTrue(app.navigationBars["Make it your practice"].waitForExistence(timeout: 10))
    capture("Onboarding levels", app)
    app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Engineering level")).firstMatch.tap()
    for level in ["Intern", "Junior", "Mid-level", "Senior", "Staff", "Principal"] { XCTAssertTrue(app.buttons[level].exists) }
    capture("All engineering levels", app)
  }

  func testSettingsSelections() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures"]
    app.launch()
    XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
    app.buttons["Settings"].tap()
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    capture("Settings light", app)
    app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Engineering level")).firstMatch.tap()
    app.buttons["Principal"].tap()
    XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Principal")).firstMatch.exists)
    app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Time zone")).firstMatch.tap()
    XCTAssertTrue(app.navigationBars["Time zone"].waitForExistence(timeout: 5))
    app.searchFields.firstMatch.tap()
    app.searchFields.firstMatch.typeText("Kolkata")
    app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Kolkata")).firstMatch.tap()
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    capture("Settings selected", app)
    app.buttons["LLM provider"].tap()
    XCTAssertTrue(app.navigationBars["LLM provider"].waitForExistence(timeout: 5))
    capture("LLM provider", app)
  }

  func testAccessibilityTextEditor() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "--fixtures", "-UIPreferredContentSizeCategoryName",
      "UICTContentSizeCategoryAccessibilityXXXL",
    ]
    app.launch()
    let start = app.buttons["startPractice"]
    XCTAssertTrue(start.waitForExistence(timeout: 10))
    for _ in 0..<8 where !start.isHittable { app.swipeUp() }
    start.tap()
    app.buttons["previewStart"].tap()
    XCTAssertTrue(app.buttons["Read question"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.textViews["answerEditor"].isHittable)
    XCTAssertFalse(app.buttons["openHelp"].exists)
    app.buttons["practiceMode"].tap()
    app.buttons["Coach"].tap()
    XCTAssertTrue(app.buttons["openHelp"].waitForExistence(timeout: 5))
    capture("Accessible editor", app)
    app.buttons["Read question"].tap()
    XCTAssertTrue(app.navigationBars["Question"].waitForExistence(timeout: 5))
    capture("Accessible question", app)
    app.buttons["Done"].tap()
    XCTAssertTrue(app.textViews["answerEditor"].isHittable)
  }

  func testPracticeAndReview() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures"]
    app.launch()
    XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout: 10))
    capture("Today", app)
    app.buttons["startPractice"].tap()
    app.buttons["previewStart"].tap()
    let editor = app.textViews["answerEditor"]
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    editor.tap()
    editor.typeText(
      "Keep evaluation local using a cached configuration. Publish versioned updates and retain the last known good version for rollback."
    )
    capture("Practice with keyboard", app)
    app.buttons["practiceMode"].tap()
    app.buttons["Coach"].tap()
    app.buttons["openHelp"].tap()
    XCTAssertFalse(
      app.staticTexts["What happens to evaluation when a client cannot reach the control plane?"]
        .exists)
    app.buttons["Give me a hint"].tap()
    XCTAssertTrue(
      app.staticTexts["What happens to evaluation when a client cannot reach the control plane?"]
        .waitForExistence(timeout: 5))
    capture("Coach", app)
    app.buttons["Done"].tap()
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    XCTAssertTrue((editor.value as? String ?? "").contains("Keep evaluation local"))
    let draftBeforeFinish = editor.value as? String
    app.buttons["Finish"].tap()
    XCTAssertTrue(app.alerts["Finish practice?"].waitForExistence(timeout: 5))
    capture("Finish confirmation", app)
    app.alerts.buttons["Keep writing"].tap()
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    XCTAssertEqual(editor.value as? String, draftBeforeFinish)
    XCTAssertFalse(app.staticTexts["Practice complete"].exists)
    app.buttons["Finish"].tap()
    app.alerts.buttons["Finish practice"].tap()
    XCTAssertTrue(app.staticTexts["Practice complete"].waitForExistence(timeout: 5))
    capture("Reflection", app)
    let followUp = app.buttons["Practise this next"]
    for _ in 0..<5 where !followUp.isHittable { app.swipeUp() }
    followUp.tap()
    XCTAssertTrue(app.navigationBars["New question"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Building on your last session"].exists)
    capture("Follow-up preparation", app)
    app.buttons["Remove"].tap()
    XCTAssertFalse(app.staticTexts["Building on your last session"].exists)
    app.buttons["Cancel"].tap()
    app.buttons["Done"].tap()
    app.tabBars.buttons["Memory"].tap()
    XCTAssertTrue(
      app.staticTexts["Design a feature-flag control plane"].waitForExistence(timeout: 5))
    capture("Memory", app)
    app.staticTexts["Design a feature-flag control plane"].tap()
    XCTAssertTrue(app.staticTexts["Your answer"].waitForExistence(timeout: 5))
    capture("Session", app)
    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.buttons["Settings"].tap()
    XCTAssertTrue(app.buttons["LLM provider"].waitForExistence(timeout: 5))
    capture("Settings", app)
    app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Focus,")).firstMatch.tap()
    XCTAssertTrue(app.buttons["Algorithms"].waitForExistence(timeout: 5))
    capture("Focus", app)
  }

  func testGuidedPreviewUndoAndDisabledSpeak() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures"]
    app.launch()
    XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout: 10))
    app.buttons["startPractice"].tap()
    app.buttons["previewStart"].tap()
    let editor = app.textViews["answerEditor"]
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    editor.tap()
    editor.typeText("My own reasoning.")
    app.buttons["Practice options"].tap()
    XCTAssertTrue(app.buttons["Speak — In development"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["Speak — In development"].isEnabled)
    capture("Practice options", app)
    app.buttons["Done"].tap()
    app.buttons["practiceMode"].tap()
    app.buttons["Guided"].tap()
    app.buttons["openHelp"].tap()
    if app.buttons["More help"].exists { app.buttons["More help"].tap() }
    app.buttons["Suggest a draft"].tap()
    let review = app.buttons["Review insertion"]
    XCTAssertTrue(review.waitForExistence(timeout: 5))
    for _ in 0..<6 where !review.isHittable { app.swipeUp() }
    review.tap()
    XCTAssertTrue(app.buttons["Replace my answer"].waitForExistence(timeout: 5))
    capture("Draft preview", app)
    app.buttons["Replace my answer"].tap()
    let undo = app.buttons["undoInsertion"]
    XCTAssertTrue(undo.waitForExistence(timeout: 5))
    for _ in 0..<6 where !undo.isHittable { app.swipeUp() }
    undo.tap()
    app.buttons["Done"].tap()
    XCTAssertEqual(editor.value as? String, "My own reasoning.")
  }

  func testCoachBlankPausePreservesEditor() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures"]
    app.launch()
    XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout: 10))
    app.buttons["startPractice"].tap()
    app.buttons["previewStart"].tap()
    XCTAssertFalse(app.buttons["openHelp"].exists)
    app.buttons["practiceMode"].tap()
    app.buttons["Coach"].tap()
    let editor = app.textViews["answerEditor"]
    editor.tap()
    let frame = editor.frame
    let hint = app.staticTexts[
      "What happens to evaluation when a client cannot reach the control plane?"]
    XCTAssertTrue(hint.waitForExistence(timeout: 38))
    XCTAssertEqual(editor.frame, frame)
    XCTAssertTrue(app.keyboards.firstMatch.exists)
    capture("Coach hint with keyboard", app)
    editor.typeText("My reasoning")
    XCTAssertEqual(editor.value as? String, "My reasoning")
    capture("Companion above keyboard", app)
  }

  func testMeaningfulEditDarkReducedEffects() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--dark", "--reduce-effects"]
    app.launch()
    XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout: 10))
    app.buttons["startPractice"].tap()
    app.buttons["previewStart"].tap()
    app.buttons["practiceMode"].tap()
    app.buttons["Coach"].tap()
    let editor = app.textViews["answerEditor"]
    editor.tap()
    editor.typeText(
      "Evaluate flags locally using a versioned cache. Keep the last known good configuration when the control plane is unavailable. Publish a new generation to roll back safely."
    )
    let frame = editor.frame
    XCTAssertTrue(
      app.staticTexts["What happens to evaluation when a client cannot reach the control plane?"]
        .waitForExistence(timeout: 10))
    XCTAssertEqual(editor.frame, frame)
    capture("Dark reduced effects hint", app)
    app.buttons["openHelp"].tap()
    app.buttons["Let me think"].tap()
    XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 5))
    capture("Coach paused", app)
  }

  private func capture(_ name: String, _ app: XCUIApplication) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
