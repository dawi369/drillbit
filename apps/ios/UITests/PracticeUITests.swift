import XCTest

@MainActor
final class PracticeUITests: XCTestCase {
  func testPreviewReachesEnd() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-long-question"]
    app.launch()
    XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout: 10))
    app.buttons["startPractice"].tap()
    let start = app.buttons["previewStart"]
    XCTAssertTrue(start.waitForExistence(timeout: 5))
    let prompt = app.staticTexts["previewPrompt"]
    let scroll = app.scrollViews["questionPreviewScroll"]
    for _ in 0..<16 where prompt.frame.maxY > start.frame.minY {
      scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)))
    }
    XCTAssertLessThanOrEqual(prompt.frame.maxY, start.frame.minY)
    XCTAssertTrue(start.isHittable)
    capture("End of long preview", app)
  }

  func testPreviewLoadingAlignment() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-dashboard", "--fixture-slow-generation"]
    app.launch()
    XCTAssertTrue(app.buttons["Prepare question"].waitForExistence(timeout: 10))
    app.buttons["Prepare question"].tap()
    app.buttons["submitPreparation"].tap()
    XCTAssertTrue(app.navigationBars["Question preview"].waitForExistence(timeout: 5))
    capture("Centered preview loading", app)
    XCTAssertTrue(app.buttons["previewStart"].waitForExistence(timeout: 12))
    capture("Minimal question preview", app)
  }

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
    let prompt = app.staticTexts["previewPrompt"]
    let before = prompt.frame.minY
    let scroll = app.scrollViews["questionPreviewScroll"]
    scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
      .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)))
    capture("Preview after scrolling", app)
    XCTAssertLessThan(prompt.frame.minY, before)
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
    XCTAssertTrue(app.buttons["liveVoice"].exists)
    XCTAssertFalse(app.buttons["liveVoice"].isEnabled)
    capture("Accessible editor", app)
    app.textViews["answerEditor"].tap()
    app.textViews["answerEditor"].typeText("A plan")
    XCTAssertTrue(app.buttons["shareAnswer"].isHittable)
    XCTAssertTrue(app.buttons["interviewOptions"].isHittable)
    capture("Accessible interview keyboard", app)
    app.buttons["Read question"].tap()
    XCTAssertTrue(app.navigationBars["Question"].waitForExistence(timeout: 5))
    capture("Accessible question", app)
    app.buttons["Done"].tap()
    XCTAssertTrue(app.textViews["answerEditor"].isHittable)
  }





  func testInterviewJourney() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures"]
    app.launch()
    XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout:10))
    app.buttons["startPractice"].tap()
    app.buttons["previewStart"].tap()
    let editor = app.textViews["answerEditor"]
    XCTAssertTrue(editor.waitForExistence(timeout:5))
    XCTAssertFalse(app.buttons["practiceMode"].exists)
    XCTAssertFalse(app.buttons["liveVoice"].isEnabled)
    editor.tap(); editor.typeText("Use a durable queue and retry failed work.")
    capture("Interview writing", app)
    app.buttons["shareAnswer"].tap()
    XCTAssertTrue(app.staticTexts["What happens if a worker stops after completing the operation but before acknowledging it?"].waitForExistence(timeout:5))
    XCTAssertEqual(editor.value as? String, "")
    capture("Interviewer follow-up", app)
    app.buttons["interviewOptions"].tap()
    app.buttons["Conversation"].tap()
    XCTAssertTrue(app.staticTexts["Use a durable queue and retry failed work."].exists)
    capture("Interview conversation", app)
    app.buttons["Done"].tap()
    editor.tap(); editor.typeText("I need to handle duplicate effects.")
    app.buttons["interviewOptions"].tap()
    app.buttons["Ask interviewer"].tap()
    app.buttons["Give me a nudge"].tap()
    XCTAssertTrue(app.staticTexts["Consider what a retry can know about an operation that already happened."].waitForExistence(timeout:5))
    capture("Ask interviewer", app)
    app.buttons["Done"].tap()
    XCTAssertEqual(editor.value as? String, "I need to handle duplicate effects.")
    app.buttons["shareAnswer"].tap()
    XCTAssertTrue(app.buttons["Keep going"].waitForExistence(timeout:5))
    capture("Interview wrap-up", app)
    app.buttons["Finish"].tap()
    app.alerts.buttons["Keep writing"].tap()
    XCTAssertFalse(app.staticTexts["Practice complete"].exists)
    app.buttons["Finish"].tap()
    app.alerts.buttons["Finish interview"].tap()
    XCTAssertTrue(app.staticTexts["Practice complete"].waitForExistence(timeout:5))
  }

  func testInterviewStyle() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-dashboard"]
    app.launch()
    XCTAssertTrue(app.buttons["Prepare question"].waitForExistence(timeout:10))
    app.buttons["Prepare question"].tap()
    app.buttons["interviewStyle"].tap()
    let deep = app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@", "In-depth")).firstMatch
    XCTAssertTrue(deep.waitForExistence(timeout:5)); deep.tap()
    capture("Interview styles", app)
    app.navigationBars.buttons.element(boundBy:0).tap()
    app.buttons["submitPreparation"].tap()
    XCTAssertTrue(app.buttons["previewStart"].waitForExistence(timeout:8))
    XCTAssertFalse(app.staticTexts["Interview style · In-depth"].exists)
    app.buttons["previewStart"].tap()
    XCTAssertTrue(app.buttons["interviewOptions"].waitForExistence(timeout:5))
    app.buttons["interviewOptions"].tap()
    XCTAssertTrue(app.buttons["In-depth"].waitForExistence(timeout:5))
    capture("Interview options", app)
  }

  func testInterviewDarkKeyboard() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--dark", "--fixture-long-question"]
    app.launch()
    XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout:10))
    app.buttons["startPractice"].tap(); app.buttons["previewStart"].tap()
    let editor = app.textViews["answerEditor"]
    XCTAssertTrue(editor.waitForExistence(timeout:5))
    capture("Dark interview question", app)
    editor.tap(); editor.typeText("Start with a durable queue.")
    XCTAssertTrue(app.buttons["shareAnswer"].isHittable)
    XCTAssertTrue(app.buttons["interviewOptions"].isHittable)
    capture("Dark interview keyboard", app)
  }

  private func capture(_ name: String, _ app: XCUIApplication) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
