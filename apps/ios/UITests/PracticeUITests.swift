import XCTest

@MainActor
final class PracticeUITests: XCTestCase {
  func testLiveVoicePreservesDraftAndTranscript() throws { try voiceJourney(extra:[]) }
  func testLiveVoiceAccessibleDark() throws { try voiceJourney(extra:["--dark","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]) }
  func testVoiceRoomCancelDuringConnection() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-voice", "--fixture-voice-connecting"]
    app.launch()
    XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout: 10))
    app.buttons["startPractice"].tap(); app.buttons["previewStart"].tap()
    XCTAssertTrue(app.buttons["liveVoice"].waitForExistence(timeout: 5))
    app.buttons["liveVoice"].tap()
    XCTAssertTrue(app.staticTexts["Connecting…"].waitForExistence(timeout: 2))
    capture("Voice room connecting", app)
    app.buttons["voiceEnd"].tap()
    XCTAssertTrue(app.buttons["liveVoice"].waitForExistence(timeout: 2))
    // Allow the suspended startup to resume; it must not resurrect audio/a room.
    XCTAssertFalse(app.buttons["voiceMute"].waitForExistence(timeout: 4))
    XCTAssertTrue(app.buttons["liveVoice"].isEnabled)
  }
  func testUnavailableVoicePreservesReply() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-voice-unavailable"]
    app.launch()
    XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout: 10))
    app.buttons["startPractice"].tap(); app.buttons["previewStart"].tap()
    let editor = app.textViews["answerEditor"]
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    editor.tap(); editor.typeText("Keep this reply")
    app.buttons["liveVoice"].tap()
    XCTAssertTrue(app.alerts["Voice"].waitForExistence(timeout: 3))
    XCTAssertFalse(app.buttons["voiceMute"].exists)
    app.alerts.buttons["Done"].tap()
    XCTAssertEqual(editor.value as? String, "Keep this reply")
    XCTAssertTrue(app.buttons["shareAnswer"].isEnabled)
  }
  private func voiceJourney(extra:[String]) throws {
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-voice"] + extra
    app.launch()
    XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout:10))
    app.buttons["startPractice"].tap(); app.buttons["previewStart"].tap()
    let editor = app.descendants(matching:.any).matching(identifier:"answerEditor").firstMatch
    XCTAssertTrue(editor.waitForExistence(timeout:5))
    editor.tap(); editor.typeText("Keep my written draft.")
    app.buttons["liveVoice"].tap()
    XCTAssertTrue(app.buttons["voiceMute"].waitForExistence(timeout:5))
    app.buttons["voiceMute"].tap()
    XCTAssertEqual(app.buttons["voiceMute"].label,"Unmute microphone")
    app.buttons["voiceMute"].tap()
    XCTAssertFalse(app.otherElements["voiceSessionDivider"].exists, "An empty voice session has no separator")
    capture("Voice room question", app)
    app.buttons["voiceFixtureSpeech"].tap()
    app.buttons["voiceHistory"].tap()
    XCTAssertTrue(app.staticTexts["I'd use a durable queue."].waitForExistence(timeout:5))
    XCTAssertTrue(app.staticTexts["Makes sense. What happens when a worker retries?"].exists)
    if app.buttons["voiceLatestButton"].exists { app.buttons["voiceLatestButton"].tap() }
    XCTAssertTrue(app.staticTexts["Makes sense. What happens when a worker retries?"].isHittable)
    capture("Voice room conversation", app)
    app.buttons["voiceHistory"].tap()
    XCTAssertTrue(app.buttons["voiceMute"].exists)
    app.buttons["voiceHistory"].tap()
    app.buttons["voiceEnd"].tap()
    XCTAssertTrue(app.buttons["liveVoice"].waitForExistence(timeout:5))
    XCTAssertEqual(editor.value as? String,"Keep my written draft.")
    XCTAssertTrue(app.staticTexts["I'd use a durable queue."].exists)
  }

  func testAppearanceAndLearningEvidence() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-dashboard", "--fixture-evidence"]
    app.launch()
    XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
    app.buttons["Settings"].tap()
    let appearance = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Appearance,")).firstMatch
    for _ in 0..<5 where !appearance.isHittable { app.swipeUp() }
    appearance.tap(); app.buttons["Dark"].tap()
    capture("Appearance dark", app)
    app.buttons["Done"].tap()
    app.terminate(); app.launch()
    app.buttons["Settings"].tap()
    for _ in 0..<5 where !appearance.isHittable { app.swipeUp() }
    XCTAssertTrue(appearance.label.contains("Dark"))
    appearance.tap(); app.buttons["System"].tap(); app.buttons["Done"].tap()
    app.tabBars.buttons["Library"].tap()
    app.buttons["Practice evidence"].tap()
    XCTAssertTrue(app.staticTexts["Defined a bounded retry policy."].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Independence not established"].exists)
    capture("Grounded practice evidence", app)
  }

  func testSessionRestorationDoesNotShowSignIn() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-dashboard", "--fixture-cached-home", "--fixture-slow-launch"]
    app.launch()
    XCTAssertTrue(app.otherElements["sessionRestoration"].waitForExistence(timeout: 2))
    XCTAssertFalse(app.buttons["Sign in with Apple"].exists)
    XCTAssertTrue(app.staticTexts["Your practice"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["Sign in with Apple"].exists)
    app.terminate()
    app.launchArguments = ["--fixtures", "--fixture-slow-launch", "--fixture-signed-out"]
    app.launch()
    XCTAssertTrue(app.otherElements["sessionRestoration"].waitForExistence(timeout: 2))
    XCTAssertFalse(app.buttons["Sign in with Apple"].exists)
    XCTAssertTrue(app.buttons["Sign in with Apple"].waitForExistence(timeout: 10))
  }

  func testCachedHomeStatisticsAppearOnFirstHomeFrame() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-dashboard", "--fixture-cached-home"]
    for _ in 0..<2 {
      app.launch()
      XCTAssertTrue(app.staticTexts["Your practice"].waitForExistence(timeout: 10))
      XCTAssertTrue(app.otherElements["Completed, 12"].exists || app.staticTexts["12"].exists)
      XCTAssertTrue(app.otherElements["Last 7 days, 4"].exists || app.staticTexts["4"].exists)
      XCTAssertFalse(app.staticTexts["—"].exists)
      XCTAssertFalse(app.staticTexts["Loading practice…"].exists)
      capture("Cached practice statistics", app)
      app.terminate()
    }
  }

  func testHomeAutomaticallyPreparesAndRegenerates() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-dashboard", "--fixture-auto-question", "--fixture-slow-generation"]
    app.launch()
    XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout: 12))
    XCTAssertTrue(app.staticTexts["Design a reliable job queue"].exists)
    app.buttons["homeQuestionActions"].tap()
    XCTAssertTrue(app.buttons["Choose focus or level"].exists)
    app.buttons["Regenerate"].tap()
    XCTAssertTrue(app.staticTexts["Preparing your question…"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["startPractice"].exists, "Old question remains available during replacement")
  }
  func testLibraryAndSkippedQuestionRecovery() throws { try libraryJourney(extra: []) }
  func testLibraryAccessibleDark() throws { try libraryJourney(extra: ["--dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]) }
  private func libraryJourney(extra: [String]) throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-dashboard"] + extra
    app.launch()
    let library = app.tabBars.buttons["Library"]
    XCTAssertTrue(library.waitForExistence(timeout: 10)); library.tap()
    let question = app.buttons["library-question-library-completed"]
    XCTAssertTrue(question.waitForExistence(timeout: 10))
    app.tabBars.buttons["Home"].tap(); library.tap()
    XCTAssertTrue(question.exists)
    capture("Question library", app)
    question.tap()
    for _ in 0..<10 where !app.buttons["Try again"].isHittable { app.swipeUp() }
    XCTAssertTrue(app.buttons["Try again"].waitForExistence(timeout: 5))
    app.buttons["Try again"].tap()
    XCTAssertTrue(app.navigationBars["Question preview"].waitForExistence(timeout: 5))
    app.buttons["Close"].tap()
    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.buttons["Library menu"].tap()
    app.buttons["Skipped questions"].tap()
    let skipped = app.buttons["library-question-library-skipped"]
    XCTAssertTrue(skipped.waitForExistence(timeout: 5)); skipped.tap()
    for _ in 0..<10 where !app.buttons["Add back to pool"].isHittable { app.swipeUp() }
    XCTAssertTrue(app.buttons["Add back to pool"].waitForExistence(timeout: 5))
    app.buttons["Add back to pool"].tap()
    XCTAssertTrue(app.staticTexts["Available in your question pool"].waitForExistence(timeout: 5))
    capture("Restored skipped question", app)
    for _ in 0..<10 where !app.buttons["Practise now"].isHittable { app.swipeDown() }
    app.buttons["Practise now"].tap()
    app.buttons["Start practice"].tap()
    XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "answerEditor").firstMatch.waitForExistence(timeout: 5))
  }

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
    let editor = app.descendants(matching: .any).matching(identifier: "answerEditor").firstMatch
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
    XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "answerEditor").firstMatch.exists)
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
    XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "answerEditor").firstMatch.waitForExistence(timeout: 5))
  }

  func testTemporaryPreparation() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-dashboard"]
    app.launch()
    XCTAssertTrue(app.buttons["Prepare question"].waitForExistence(timeout: 10))
    app.buttons["Prepare question"].tap()
    app.buttons["prepareArea"].tap()
    app.buttons["Caching"].tap()
    app.buttons["prepareLevel"].tap()
    app.buttons["Senior"].tap()
    XCTAssertTrue(app.textFields["Optional request"].exists || app.textViews["Optional request"].exists)
    capture("Temporary preparation", app)
    app.buttons["Cancel"].tap()
    app.buttons["Prepare question"].tap()
    XCTAssertTrue(app.buttons["prepareArea"].label.contains("Automatic"))
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
    XCTAssertFalse(app.staticTexts["Last session"].exists)
    XCTAssertTrue(app.navigationBars["Home"].exists)
    XCTAssertTrue(app.tabBars.buttons["Home"].exists)
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
    XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Focus,")).firstMatch.exists)
    capture("Settings accessible system design", app)
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
    XCTAssertTrue(app.buttons["exchange-original"].waitForExistence(timeout: 5))
    app.buttons["exchange-original"].tap()
    XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "answerEditor").firstMatch.isHittable)
    XCTAssertFalse(app.buttons["openHelp"].exists)
    XCTAssertTrue(app.buttons["liveVoice"].exists)
    XCTAssertTrue(app.buttons["liveVoice"].isEnabled)
    capture("Accessible editor", app)
    app.descendants(matching: .any).matching(identifier: "answerEditor").firstMatch.tap()
    app.descendants(matching: .any).matching(identifier: "answerEditor").firstMatch.typeText("A plan")
    XCTAssertTrue(app.buttons["shareAnswer"].isHittable)
    XCTAssertTrue(app.buttons["interviewOptions"].isHittable)
    capture("Accessible interview keyboard", app)
    let document = app.scrollViews["interviewDocument"]
    let original = app.buttons["exchange-original"]
    for _ in 0..<12 where !original.isHittable { document.swipeDown() }
    original.tap()
    XCTAssertTrue(original.waitForExistence(timeout: 5))
    XCTAssertTrue(original.isHittable)
    XCTAssertEqual(original.value as? String, "Expanded")
    XCTAssertFalse(app.navigationBars["Original question"].exists)
    capture("Accessible inline question", app)
    original.tap()
    let editor = app.descendants(matching: .any).matching(identifier: "answerEditor").firstMatch
    XCTAssertTrue(editor.isHittable)
    editor.tap()
    editor.typeText("\nWith retries")
    app.buttons["shareAnswer"].tap()
    XCTAssertTrue(app.staticTexts["interviewPrompt"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["interviewOptions"].isHittable)
  }





  func testOriginalQuestionExpandsAndScrollsInline() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-long-question"]
    app.launch()
    XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout: 10))
    app.buttons["startPractice"].tap()
    app.buttons["previewStart"].tap()
    let original = app.buttons["exchange-original"]
    XCTAssertTrue(original.waitForExistence(timeout: 5))
    original.tap()
    let editor = app.descendants(matching: .any).matching(identifier: "answerEditor").firstMatch
    editor.tap()
    editor.typeText("Preserve this draft")
    let document = app.scrollViews["interviewDocument"]
    for _ in 0..<12 where !original.isHittable { document.swipeDown() }
    original.tap()
    XCTAssertTrue(original.isHittable)
    XCTAssertEqual(original.value as? String, "Expanded")
    XCTAssertFalse(app.navigationBars["Original question"].exists)
    for _ in 0..<35 where !editor.isHittable { document.swipeUp() }
    XCTAssertTrue(editor.isHittable, "The entire original question scrolls to the answer")
    XCTAssertEqual(editor.value as? String, "Preserve this draft")
    for _ in 0..<35 where !original.isHittable { document.swipeDown() }
    XCTAssertTrue(original.isHittable)
    XCTAssertEqual(original.value as? String, "Expanded")
    capture("Original question inline", app)
  }

  func testSkipUsesAlertAndPreservesDraftWhenCancelled() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures"]
    app.launch()
    XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout: 10))
    app.buttons["startPractice"].tap()
    app.buttons["previewStart"].tap()
    let editor = app.descendants(matching: .any).matching(identifier: "answerEditor").firstMatch
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    editor.tap(); editor.typeText("Keep my draft")
    app.buttons["interviewOptions"].tap()
    app.buttons["Skip question"].tap()
    let alert = app.alerts["Skip this question?"]
    XCTAssertTrue(alert.waitForExistence(timeout: 5))
    capture("Skip confirmation alert", app)
    alert.buttons["Keep practising"].tap()
    XCTAssertEqual(editor.value as? String, "Keep my draft")
    app.buttons["interviewOptions"].tap()
    app.buttons["Skip question"].tap()
    alert.buttons["Skip question"].tap()
    XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 2))
    XCTAssertFalse(app.buttons["startPractice"].exists)
  }

  func testSendImmediatelyCreatesInterviewerAndStreamsText() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-slow-interview"]
    app.launch()
    XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout: 10))
    app.buttons["startPractice"].tap(); app.buttons["previewStart"].tap()
    let editor = app.descendants(matching: .any).matching(identifier: "answerEditor").firstMatch
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    editor.tap(); editor.typeText("Use a durable queue. Persist each job before acknowledging it, and give workers a lease. Retry failed work with an idempotency key so processing the same job twice does not duplicate its effects.")
    app.buttons["shareAnswer"].tap()
    let sent = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "answer-")).firstMatch
    XCTAssertTrue(sent.waitForExistence(timeout: 2))
    XCTAssertEqual(sent.value as? String, "Collapsed")
    let interviewer = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier != %@", "exchange-", "exchange-original")).firstMatch
    XCTAssertTrue(app.staticTexts["Interviewer"].exists)
    XCTAssertFalse(interviewer.exists) // No disclosure for the empty streaming response.
    capture("Immediately after Send", app)
    let response = app.staticTexts["interviewPrompt"]
    let full = "What happens if a worker stops after completing the operation but before acknowledging it?"
    expectation(for: NSPredicate(format: "exists == true AND label.length > 0 AND label != %@", full), evaluatedWith: response)
    waitForExpectations(timeout: 12)
    capture("Partial interviewer response", app)
    expectation(for: NSPredicate(format: "label == %@", full), evaluatedWith: response)
    waitForExpectations(timeout: 5)
    XCTAssertFalse(app.staticTexts["Ready to wrap up?"].exists)
    XCTAssertEqual(sent.value as? String, "Collapsed")
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    sent.tap()
    XCTAssertEqual(sent.value as? String, "Expanded")
    let submittedText = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "sentAnswer-")).firstMatch
    XCTAssertTrue(submittedText.label.contains("does not duplicate its effects"))
    sent.tap()
    XCTAssertEqual(sent.value as? String, "Collapsed")
    capture("Settled response and next answer", app)
  }

  func testInterviewJourney() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures"]
    app.launch()
    XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout:10))
    app.buttons["startPractice"].tap()
    app.buttons["previewStart"].tap()
    let editor = app.descendants(matching: .any).matching(identifier: "answerEditor").firstMatch
    XCTAssertTrue(editor.waitForExistence(timeout:5))
    XCTAssertFalse(app.buttons["practiceMode"].exists)
    XCTAssertTrue(app.buttons["liveVoice"].isEnabled)
    XCTAssertTrue(app.otherElements["answerDivider"].exists)
    editor.tap(); editor.typeText("Use a durable queue and retry failed work.")
    capture("Interview writing", app)
    app.buttons["shareAnswer"].tap()
    XCTAssertTrue(app.staticTexts["What happens if a worker stops after completing the operation but before acknowledging it?"].waitForExistence(timeout:5))
    XCTAssertTrue(["", "Talk through your approach, or ask a question…"].contains(editor.value as? String ?? ""))
    capture("Interviewer follow-up", app)
    XCTAssertEqual(app.buttons["exchange-original"].value as? String, "Collapsed")
    let answerRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "answer-")).firstMatch
    XCTAssertEqual(answerRow.value as? String, "Collapsed")
    XCTAssertTrue(answerRow.isHittable)
    answerRow.tap()
    let sent = app.staticTexts["Use a durable queue and retry failed work."]
    XCTAssertTrue(sent.isHittable, "The complete sent answer expands beside its response")
    let followUp = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier != %@", "exchange-", "exchange-original")).firstMatch
    followUp.tap()
    XCTAssertTrue(sent.isHittable, "Folding a question never hides the sent answer")
    followUp.tap()
    capture("Inline interview history", app)
    editor.tap(); editor.typeText("I need to handle duplicate effects.")
    app.buttons["interviewOptions"].tap()
    app.buttons["Give me a nudge"].tap()
    XCTAssertTrue(app.staticTexts["Consider what a retry can know about an operation that already happened."].waitForExistence(timeout:5))
    XCTAssertFalse(app.navigationBars["Ask interviewer"].exists)
    capture("Inline interviewer help", app)
    XCTAssertEqual(editor.value as? String, "I need to handle duplicate effects.")
    app.buttons["shareAnswer"].tap()
    XCTAssertTrue(editor.waitForExistence(timeout: 8))
    XCTAssertFalse(app.staticTexts["Ready to wrap up?"].exists)
    capture("Interview wrap-up", app)
    app.buttons["interviewOptions"].tap()
    app.buttons["Finish interview"].tap()
    app.alerts.buttons["Keep writing"].tap()
    XCTAssertFalse(app.staticTexts["Practice complete"].exists)
    app.buttons["interviewOptions"].tap()
    app.buttons["Finish interview"].tap()
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
    XCTAssertTrue(deep.waitForExistence(timeout:5)); XCTAssertFalse(deep.isEnabled)
    capture("Interview styles", app)
    app.navigationBars.buttons.element(boundBy:0).tap()
    app.buttons["submitPreparation"].tap()
    XCTAssertTrue(app.buttons["previewStart"].waitForExistence(timeout:8))
    XCTAssertFalse(app.staticTexts["Interview style · In-depth"].exists)
    app.buttons["previewStart"].tap()
    XCTAssertTrue(app.buttons["interviewOptions"].waitForExistence(timeout:5))
    app.buttons["interviewOptions"].tap()
    app.buttons["Interview style"].tap()
    let quick = app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@", "Quick")).firstMatch
    XCTAssertTrue(quick.waitForExistence(timeout:5)); XCTAssertFalse(quick.isEnabled)
    capture("Change active interview style", app)
    app.buttons["Done"].tap()
    let editor = app.descendants(matching: .any).matching(identifier: "answerEditor").firstMatch
    editor.tap(); editor.typeText("Keep a durable queue.")
    XCTAssertEqual(app.buttons["exchange-original"].value as? String, "Expanded")
    capture("Question stays open while typing", app)
    XCTAssertFalse(app.staticTexts["Saved on this device"].exists)
    app.buttons["interviewOptions"].tap()
    app.buttons["Interview style"].tap()
    XCTAssertFalse(quick.isEnabled)
    let standard = app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@", "Standard")).firstMatch
    XCTAssertTrue(standard.isSelected)
  }

  func testInterviewDarkKeyboard() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--dark", "--fixture-long-question"]
    app.launch()
    XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout:10))
    app.buttons["startPractice"].tap(); app.buttons["previewStart"].tap()
    let editor = app.descendants(matching: .any).matching(identifier: "answerEditor").firstMatch
    XCTAssertTrue(editor.waitForExistence(timeout:5))
    capture("Dark interview question", app)
    editor.tap(); editor.typeText("Start with a durable queue.")
    XCTAssertTrue(app.buttons["shareAnswer"].isHittable)
    XCTAssertTrue(app.buttons["interviewOptions"].isHittable)
    capture("Dark interview keyboard", app)
  }

  func testSingleLineTurnsHaveNoDisclosure() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-interview-history", "--fixture-short-turn"]
    app.launch()
    XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout: 10))
    app.buttons["startPractice"].tap()
    XCTAssertTrue(app.buttons["exchange-original"].waitForExistence(timeout: 5))
    app.buttons["exchange-original"].tap()
    XCTAssertTrue(app.staticTexts["sentAnswer-history-1"].exists)
    XCTAssertFalse(app.buttons["answer-history-1"].exists)
    XCTAssertFalse(app.buttons["exchange-history-1"].exists)
    capture("Single-line turns without disclosure", app)
  }

  func testOriginalQuestionExpansionKeepsHistoryBelow() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-interview-history", "--fixture-follow-up"]
    app.launch()
    XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout: 10))
    app.buttons["startPractice"].tap()
    let original = app.buttons["exchange-original"]
    XCTAssertTrue(original.waitForExistence(timeout: 5))
    for _ in 0..<2 {
      original.tap()
      XCTAssertEqual(original.value as? String, "Collapsed")
      original.tap()
      XCTAssertEqual(original.value as? String, "Expanded")
      let body = app.staticTexts["earlierPrompt-original"]
      let answer = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "sentAnswer-")).firstMatch
      XCTAssertGreaterThanOrEqual(answer.frame.minY, body.frame.maxY)
    }
    capture("Expanded original above history", app)
  }

  func testDisclosureHeadersKeepTheirPosition() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-interview-history", "--fixture-follow-up"]
    app.launch()
    XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout: 10))
    app.buttons["startPractice"].tap()
    let original = app.buttons["exchange-original"]
    XCTAssertTrue(original.waitForExistence(timeout: 5))
    let originalY = original.frame.minY
    original.tap()
    XCTAssertEqual(original.frame.minY, originalY, accuracy: 0.5)
    let response = app.buttons["exchange-history-1"]
    XCTAssertTrue(response.waitForExistence(timeout: 5))
    let headerY = response.frame.minY
    for _ in 0..<4 {
      response.tap()
      XCTAssertEqual(response.frame.minY, headerY, accuracy: 0.5)
    }
    capture("Stable disclosure headers", app)
  }

  func testDocumentHistoryRestorationAndLateResponse() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-interview-history", "--fixture-slow-interview", "--fixture-follow-up"]
    app.launch()
    XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout: 10))
    app.buttons["startPractice"].tap()
    let original = app.buttons["exchange-original"]
    XCTAssertTrue(original.waitForExistence(timeout: 5))
    original.tap()
    XCTAssertEqual(original.value as? String, "Collapsed")
    capture("Folded interview document", app)
    XCTAssertFalse(app.buttons["returnToAnswer"].exists)
    let editor = app.descendants(matching: .any).matching(identifier: "answerEditor").firstMatch
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    for _ in 0..<8 where !editor.isHittable { app.swipeUp() }
    editor.tap(); editor.typeText("Bound every retry and record the result.")
    app.buttons["Close"].tap()
    app.buttons["startPractice"].tap()
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    XCTAssertEqual(original.value as? String, "Collapsed")
    XCTAssertEqual(editor.value as? String, "Bound every retry and record the result.")
    XCTAssertTrue(editor.isHittable)
    app.buttons["shareAnswer"].tap()
    XCTAssertEqual(app.progressIndicators.count, 0)
    let document = app.scrollViews["interviewDocument"]
    for _ in 0..<3 { document.swipeDown(velocity: .fast) }
    let before = original.frame.minY
    let ready = NSPredicate(format: "label == %@", "What happens if a worker stops after completing the operation but before acknowledging it?")
    expectation(for: ready, evaluatedWith: app.staticTexts["interviewPrompt"])
    waitForExpectations(timeout: 12)
    XCTAssertEqual(original.frame.minY, before, accuracy: 4)
    XCTAssertTrue(app.staticTexts["Bound every retry and record the result."].exists)
    capture("Response preserves history position", app)
    XCTAssertFalse(app.buttons["returnToAnswer"].exists)
    for _ in 0..<8 where !app.staticTexts["interviewPrompt"].isHittable { document.swipeUp() }
    XCTAssertTrue(app.staticTexts["interviewPrompt"].isHittable)
  }

  func testGrowingDocumentEditor() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--dark"]
    app.launch()
    XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout: 10))
    app.buttons["startPractice"].tap(); app.buttons["previewStart"].tap()
    let editor = app.descendants(matching: .any).matching(identifier: "answerEditor").firstMatch
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    let initialHeight = editor.frame.height
    editor.tap()
    let longAnswer = String(repeating: "Use durable records and bounded retries.\n", count: 10)
    editor.typeText(longAnswer)
    XCTAssertEqual(editor.value as? String, longAnswer)
    capture("Long answer before sizing check", app)
    XCTAssertGreaterThan(editor.frame.height, initialHeight)
    XCTAssertTrue(app.buttons["shareAnswer"].isHittable)
    XCTAssertEqual(app.buttons["exchange-original"].value as? String, "Expanded")
    capture("Growing answer with keyboard", app)
  }

  func testAccessibleInterviewDocument() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
    app.launch()
    XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout: 10))
    let start = app.buttons["startPractice"]
    for _ in 0..<5 where !start.isHittable { app.swipeUp() }
    start.tap(); app.buttons["previewStart"].tap()
    let original = app.buttons["exchange-original"]
    XCTAssertTrue(original.waitForExistence(timeout: 5)); original.tap()
    XCTAssertEqual(original.value as? String, "Collapsed")
    capture("Accessible collapsed document", app)
    let editor = app.descendants(matching: .any).matching(identifier: "answerEditor").firstMatch
    editor.tap(); editor.typeText("A durable queue")
    XCTAssertTrue(app.buttons["shareAnswer"].isHittable)
    capture("Accessible document keyboard", app)
  }

  private func capture(_ name: String, _ app: XCUIApplication) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
