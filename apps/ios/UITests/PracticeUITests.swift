import StoreKitTest
import XCTest

@MainActor
final class PracticeUITests: XCTestCase {
  func testRecallTemporaryDeck() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures"]
    app.launch()
    XCTAssertTrue(app.tabBars.buttons["Recall"].waitForExistence(timeout: 10))
    app.tabBars.buttons["Recall"].tap()
    XCTAssertTrue(app.navigationBars["Recall"].waitForExistence(timeout: 3))
    XCTAssertFalse(app.staticTexts["Loading Recall…"].exists)
    XCTAssertFalse(app.buttons["recallAreaPicker"].exists)
    XCTAssertFalse(app.buttons["recallDepthPicker"].exists)
    XCTAssertTrue(app.staticTexts["Your first idea starts with a practice."].exists)
    app.buttons["Map"].tap()
    XCTAssertTrue(app.staticTexts["Your system design map"].waitForExistence(timeout: 2))
    app.buttons["Paths"].tap()
    XCTAssertTrue(app.staticTexts["Choose a path"].waitForExistence(timeout: 2))
    app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "System design essentials")).firstMatch.tap()
    XCTAssertTrue(app.buttons["recallReveal"].waitForExistence(timeout: 2))
    XCTAssertTrue(app.buttons["recallLeavePath"].exists)
    app.buttons["recallReveal"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["recallAnswer"].waitForExistence(timeout: 2))
    capture("Recall path answer", app)
  }

  func testHomeTicketResumesAndOffersActions() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-home-rich", "--fixture-interview-history"]
    app.launch()
    let ticket = app.buttons["startPractice"]
    XCTAssertTrue(ticket.waitForExistence(timeout: 10))
    XCTAssertTrue(ticket.label.contains("Where you left off"), ticket.label)
    XCTAssertTrue(ticket.label.contains("Follow-up 3"), "Resume quotes the interviewer's latest question")
    ticket.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).press(forDuration: 1)
    XCTAssertTrue(app.buttons["Choose another question"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["Skip question"].exists)
    capture("Home ticket actions", app)
  }
  func testTicketSettlesStraightAfterClosingPreview() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures"]
    app.launch()
    let ticket = app.buttons["startPractice"]
    XCTAssertTrue(ticket.waitForExistence(timeout: 10))
    Thread.sleep(forTimeInterval: 1)
    capture("Ticket at rest", app)
    ticket.tap()
    XCTAssertTrue(app.buttons["previewStart"].waitForExistence(timeout: 5))
    app.navigationBars.buttons["Close"].tap()
    // Frames across the return, to catch the ticket resettling after the sheet has gone.
    for index in 0..<10 {
      let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
      attachment.name = "Ticket return \(index)"
      attachment.lifetime = .keepAlways
      add(attachment)
    }
    XCTAssertTrue(ticket.isHittable)
  }
  func testSettingsSaveOfflineAndThemeImmediately() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-settings-offline"]
    app.launch()
    XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
    app.buttons["Settings"].tap()
    app.buttons["appearancePicker"].tap(); app.buttons["Light"].tap()
    capture("Settings immediate light", app)
    app.buttons["appearancePicker"].tap(); app.buttons["Dark"].tap()
    XCTAssertTrue(app.buttons["appearancePicker"].label.contains("Dark"))
    capture("Settings immediate dark", app)
    app.navigationBars["Settings"].buttons["Done"].tap()
    XCTAssertTrue(app.buttons["homeSettings"].waitForExistence(timeout: 3))
    app.buttons["Settings"].tap()
    XCTAssertTrue(app.buttons["appearancePicker"].label.contains("Dark"))
    XCTAssertFalse(app.buttons["Retry sync"].exists)
    capture("Settings retained offline", app)
  }
  func testPracticeProfileEditingAndReset() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures"]
    app.launch()
    XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
    // The profile lives under Developer, below the fold since Settings gained Plan.
    let about = app.buttons["About your practice"]
    let openAbout = { app.buttons["Settings"].tap(); for _ in 0..<6 where !about.exists || !about.isHittable { app.swipeUp() }; about.tap() }
    openAbout()
    let goals = app.descendants(matching: .any).matching(identifier: "practiceGoals").firstMatch
    XCTAssertTrue(goals.waitForExistence(timeout: 5))
    goals.tap(); goals.typeText("Senior interviews")
    app.navigationBars.buttons.firstMatch.tap()
    app.buttons["Done"].tap()
    openAbout()
    XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "practiceGoals").firstMatch.value as? String, "Senior interviews")
    for _ in 0..<4 where !app.buttons["Reset personalization"].isHittable { app.swipeUp() }
    capture("Practice personalization", app)
    app.buttons["Reset personalization"].tap()
    app.swipeDown(); app.swipeDown()
    XCTAssertNotEqual(app.descendants(matching: .any).matching(identifier: "practiceGoals").firstMatch.value as? String, "Senior interviews")
  }
  func testRichHome() throws { try richHome(extra: ["-appearance", "light"]) }
  func testRichHomeAccessibleDark() throws { try richHome(extra: ["--dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]) }
  private func richHome(extra: [String]) throws {
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-home-rich"] + extra
    app.launch()
    XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout: 10))
    capture("Home next session", app)
    app.buttons["startPractice"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).press(forDuration: 1)
    XCTAssertTrue(app.buttons["Choose focus or level"].waitForExistence(timeout: 3))
    app.buttons["Choose focus or level"].tap()
    XCTAssertTrue(app.navigationBars["New question"].waitForExistence(timeout: 5))
    for _ in 0..<5 where !app.buttons["submitPreparation"].isHittable { app.swipeUp() }
    XCTAssertTrue(app.buttons["submitPreparation"].isHittable)
    capture("Home topic preparation", app)
  }
  func testLiveVoicePreservesDraftAndTranscript() throws { try voiceJourney(extra:[]) }
  func testTalkFromPreviewOpensStraightIntoVoice() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-voice", "--fixture-talk"]
    app.launch()
    XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout: 10))
    app.buttons["startPractice"].tap()
    XCTAssertTrue(app.buttons["previewStart"].waitForExistence(timeout: 5))
    // One Start, no mode switch: the interview opens out loud.
    XCTAssertEqual(app.buttons["previewStart"].label, "Start")
    XCTAssertFalse(app.buttons["Talk it through"].exists)
    capture("Preview", app)
    app.buttons["previewStart"].tap()
    XCTAssertTrue(app.buttons["voiceMute"].waitForExistence(timeout: 8), "Start opens the room already connected")
    XCTAssertTrue(app.descendants(matching: .any)["voiceQuestion"].exists, "The whole question is readable in the room")
    XCTAssertTrue(app.buttons["voiceEnd"].exists, "End is the one way back to writing")
    capture("Voice from preview", app)
    app.buttons["voiceEnd"].tap()
    XCTAssertTrue(app.buttons["liveVoice"].waitForExistence(timeout: 5))
  }
  func testCoachmarksPointAtTheComposerThenTheTools() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-coach"]
    app.launch()
    XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout: 10))
    app.buttons["startPractice"].tap(); app.buttons["previewStart"].tap()
    let composerTip = app.descendants(matching: .any)["coach-composer"]
    XCTAssertTrue(composerTip.waitForExistence(timeout: 10))
    capture("Coachmark your turn", app)
    // The screen takes no touches while a tip is up; Got it is the way on.
    let editor = app.descendants(matching: .any).matching(identifier: "answerEditor").firstMatch
    editor.tap()
    XCTAssertTrue(composerTip.exists, "A tap under the tip does nothing")
    app.buttons["coachDone"].tap()
    XCTAssertTrue(composerTip.waitForNonExistence(timeout: 2))
    // The header tip follows straight on, and shields the screen too, before any typing.
    let toolsTip = app.descendants(matching: .any)["coach-tools"]
    XCTAssertTrue(toolsTip.waitForExistence(timeout: 10))
    capture("Coachmark stuck", app)
    app.buttons["coachDone"].tap()
    XCTAssertTrue(toolsTip.waitForNonExistence(timeout: 2))
    editor.tap(); editor.typeText("Workers lease jobs and record every attempt.")
    app.buttons["shareAnswer"].tap()
    XCTAssertTrue(app.staticTexts["What happens if a worker stops after completing the operation but before acknowledging it?"].waitForExistence(timeout: 10))
    // The tip pointed at the menu; the menu has what it promised.
    app.buttons["interviewOptions"].tap()
    XCTAssertTrue(app.buttons["Need a nudge?"].waitForExistence(timeout: 2))
    XCTAssertTrue(app.buttons["Show an example"].exists)
    XCTAssertTrue(app.buttons["Finish interview"].exists)
  }
  func testFirstRunTipsStayInsideTheInterview() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-onboarding", "--fixture-coach"]
    app.launch()
    XCTAssertTrue(app.staticTexts["Quick one. No wrong answers."].waitForExistence(timeout: 10))
    app.buttons["The database"].tap()
    for _ in 0..<6 { app.buttons["Continue"].tap() }
    app.buttons["Show me my first question"].tap()
    XCTAssertTrue(app.buttons["previewStart"].waitForExistence(timeout: 10))
    app.buttons["previewStart"].tap()
    // The composer tip comes first; skipping the first question still ends onboarding.
    XCTAssertTrue(app.descendants(matching: .any)["coach-composer"].waitForExistence(timeout: 12))
    app.buttons["coachDone"].tap()
    // Guided: the roadmap tip's Show me opens the steps.
    let pathTip = app.descendants(matching: .any)["coach-path"]
    XCTAssertTrue(pathTip.waitForExistence(timeout: 5))
    let bar = app.descendants(matching: .any)["guidedPath"].frame, tipFrame = pathTip.frame
    XCTAssertEqual(tipFrame.minY, bar.maxY + 12, accuracy: 20, "tip \(tipFrame) should hang just under the bar \(bar)")
    XCTAssertTrue(bar.minX < tipFrame.midX && tipFrame.midX < bar.maxX)
    capture("Coachmark roadmap", app)
    app.buttons["coachDone"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["guidedPathSteps"].waitForExistence(timeout: 3))
    XCTAssertFalse(app.descendants(matching: .any)["coach-tools"].waitForExistence(timeout: 1), "No second tip while the steps are open")
    app.otherElements["PopoverDismissRegion"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["coach-tools"].waitForExistence(timeout: 5))
    app.buttons["coachDone"].tap()
    app.buttons["interviewOptions"].tap()
    app.buttons["Skip question"].tap()
    let alert = app.alerts["Skip this question?"]
    XCTAssertTrue(alert.waitForExistence(timeout: 5))
    alert.buttons["Skip question"].tap()
    // Tips live inside the interview only: Home and every tab stay clear after the first rep.
    XCTAssertTrue(app.buttons["homeSettings"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.descendants(matching: .any)["coachDone"].waitForExistence(timeout: 2), "Home offers no tip")
    for tab in ["Recall", "Library", "Home"] {
      app.tabBars.buttons[tab].tap()
      XCTAssertFalse(app.descendants(matching: .any)["coachDone"].waitForExistence(timeout: 2), "\(tab) offers no tip")
    }
  }
  func testLiveVoiceAccessibleDark() throws { try voiceJourney(extra:["--dark","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]) }
  func testVoiceRoomCancelDuringConnection() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-voice", "--fixture-voice-connecting"]
    app.launch()
    XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout: 10))
    app.buttons["startPractice"].tap(); app.buttons["previewStart"].tap()
    XCTAssertTrue(app.buttons["liveVoice"].waitForExistence(timeout: 5))
    app.buttons["liveVoice"].tap()
    // Talk connects on its own; the mic says so and can't be pressed while it does.
    XCTAssertTrue(app.buttons["voiceConnecting"].waitForExistence(timeout: 2))
    XCTAssertFalse(app.buttons["voiceConnecting"].isEnabled)
    capture("Voice room connecting", app)
    app.buttons["voiceCancel"].tap()
    XCTAssertTrue(app.buttons["liveVoice"].waitForExistence(timeout: 2))
    // Allow the suspended startup to resume; it must not resurrect audio/a room.
    XCTAssertFalse(app.buttons["voiceMute"].waitForExistence(timeout: 4))
    XCTAssertTrue(app.buttons["liveVoice"].isEnabled)
  }
  func testVoiceLiveHidesEarlierExample() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-voice", "--fixture-voice-example"]
    app.launch()
    XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout: 10))
    app.buttons["startPractice"].tap()
    XCTAssertTrue(app.buttons["liveVoice"].waitForExistence(timeout: 5))
    app.buttons["liveVoice"].tap()
    XCTAssertTrue(app.buttons["voiceMute"].waitForExistence(timeout: 5))
    capture("Voice live without earlier example", app)
    XCTAssertFalse(app.staticTexts["You · Example"].exists)
    XCTAssertFalse(app.staticTexts["For example, give each logical operation a stable key and store its result in the same transaction as the state change."].exists)
    XCTAssertFalse(app.staticTexts["You · Example"].exists)
    app.buttons["voiceEnd"].tap()
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
    let voiceFrame = app.buttons["liveVoice"].frame
    let sendFrame = app.buttons["shareAnswer"].frame
    XCTAssertGreaterThanOrEqual(voiceFrame.height, 44)
    XCTAssertEqual(voiceFrame.height, sendFrame.height, accuracy: 1)
    capture("Native interview actions", app)
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
    // Talk connects straight away; the free allowance sits under the live mic.
    XCTAssertTrue(app.buttons["voiceMute"].waitForExistence(timeout:5))
    XCTAssertFalse(app.buttons["voiceStart"].exists)
    XCTAssertEqual(app.descendants(matching: .any)["voiceAllowance"].label, "2 of 3 free voice sessions left.")
    // Live: Transcript, Mute and End sit in one dock; the keyboard waits in the toolbar.
    XCTAssertTrue(app.buttons["voiceEnd"].exists)
    XCTAssertFalse(app.buttons["voiceBack"].exists, "Live, End is the only way back; the keyboard key sits beside Start")
    XCTAssertFalse(app.buttons["voiceCancel"].exists)
    XCTAssertTrue(app.descendants(matching: .any)["voiceClock"].exists)
    XCTAssertFalse(app.buttons["voiceUseText"].exists)
    XCTAssertFalse(app.buttons["voiceEndControl"].exists)
    // The room opens muted; one tap on the mic opens the line.
    XCTAssertEqual(app.buttons["voiceMute"].label,"Unmute microphone")
    XCTAssertEqual(app.buttons["voiceMute"].value as? String, "Muted")
    capture("Voice microphone muted", app)
    app.buttons["voiceMute"].tap()
    XCTAssertEqual(app.buttons["voiceMute"].label,"Mute microphone")
    XCTAssertFalse(app.otherElements["voiceSessionDivider"].exists, "An empty voice session has no separator")
    XCTAssertFalse(app.staticTexts["Microphone on"].exists)
    capture("Voice room question", app)
    app.buttons["voiceFixtureSpeech"].tap()
    // The interviewer's latest line stays on stage without opening the transcript.
    XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "voiceCaption").firstMatch.waitForExistence(timeout: 3))
    XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "voiceCaption").firstMatch.label.contains("What happens when a worker retries?"))
    capture("Voice room live caption", app)
    // End lands in the editor with the transcript in the document.
    app.buttons["voiceEnd"].tap()
    XCTAssertTrue(app.buttons["liveVoice"].waitForExistence(timeout:5))
    XCTAssertEqual(editor.value as? String,"Keep my written draft.")
    XCTAssertTrue(app.staticTexts["I'd use a durable queue."].waitForExistence(timeout:5))
    XCTAssertTrue(app.staticTexts["Makes sense. What happens when a worker retries?"].exists)
    capture("Voice room conversation", app)
    app.buttons["liveVoice"].tap()
    XCTAssertTrue(app.buttons["voiceMute"].waitForExistence(timeout: 5), "Talk reconnects without a Start step")
    app.buttons["voiceEnd"].tap()
    XCTAssertTrue(app.buttons["liveVoice"].waitForExistence(timeout: 5))
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
    // Leave the shared preference on the app's default, dark.
    appearance.tap(); app.buttons["Dark"].tap(); app.buttons["Done"].tap()
    app.tabBars.buttons["Library"].tap()
    app.buttons["Practice evidence"].tap()
    XCTAssertTrue(app.staticTexts["Defined a bounded retry policy."].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Independence not established"].exists)
    capture("Grounded practice evidence", app)
  }

  func testAIConsentReadsAtLargestTypeInLight() throws {
    let app = XCUIApplication()
    // Straight to the sign-in stage: the argument domain overrides the stage a signed-out launch clears.
    app.launchArguments = ["--fixtures", "--fixture-signed-out", "-firstRun.stage", "signIn", "-appearance", "light",
                           "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
    app.launch()
    let agree = app.buttons["aiConsentAgree"]
    XCTAssertTrue(agree.waitForExistence(timeout: 10))
    XCTAssertTrue(agree.isHittable, "Agreeing stays reachable above the fold")
    // The whole disclosure scrolls into view at the largest size, policy link included.
    let policy = app.links["aiConsentPrivacy"].exists ? app.links["aiConsentPrivacy"] : app.buttons["aiConsentPrivacy"]
    let body = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "never sell it")).firstMatch
    for _ in 0..<8 where !(body.exists && body.isHittable) { app.swipeUp() }
    XCTAssertTrue(body.isHittable)
    if policy.exists { for _ in 0..<4 where !policy.isHittable { app.swipeUp() }; XCTAssertTrue(policy.isHittable) }
    capture("AI consent at largest type", app)
    agree.tap()
    XCTAssertTrue(app.buttons["Sign in with Apple"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.descendants(matching: .any)["aiDisclosure"].exists)
  }

  func testSignedInWithoutConsentIsAskedBeforeAnythingElse() throws {
    let app = XCUIApplication()
    // An update, or a Keychain session that outlived a reinstall: signed in, but never agreed.
    app.launchArguments = ["--fixtures", "--fixture-dashboard", "--fixture-no-ai-consent"]
    app.launch()
    let agree = app.buttons["aiConsentAgree"]
    XCTAssertTrue(agree.waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["One quick thing."].exists)
    XCTAssertTrue(app.descendants(matching: .any)["aiDisclosure"].exists)
    XCTAssertFalse(app.tabBars.firstMatch.exists, "Nothing behind the gate is reachable")
    XCTAssertFalse(app.buttons["homeSettings"].exists)
    capture("AI consent for a signed-in account", app)
    agree.tap()
    XCTAssertTrue(app.buttons["homeSettings"].waitForExistence(timeout: 5))
    XCTAssertFalse(agree.exists)
  }

  func testSessionRestorationDoesNotShowSignIn() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-dashboard", "--fixture-cached-home", "--fixture-slow-launch"]
    app.launch()
    XCTAssertTrue(app.otherElements["sessionRestoration"].waitForExistence(timeout: 2))
    XCTAssertFalse(app.buttons["Sign in with Apple"].exists)
    XCTAssertTrue(app.buttons["homeSettings"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["Sign in with Apple"].exists)
    app.terminate()
    app.launchArguments = ["--fixtures", "--fixture-slow-launch", "--fixture-signed-out"]
    app.launch()
    XCTAssertTrue(app.otherElements["sessionRestoration"].waitForExistence(timeout: 2))
    XCTAssertFalse(app.buttons["Sign in with Apple"].exists)
    // Signed out is a first run: Welcome, with sign-in (and the AI consent before it) waiting until after setup.
    XCTAssertTrue(app.descendants(matching: .any)["separatorHeadline"].waitForExistence(timeout: 15))
    XCTAssertFalse(app.buttons["Sign in with Apple"].exists)
    XCTAssertFalse(app.buttons["aiConsentAgree"].exists)
  }

  func testCachedHomeAppearsOnFirstFrame() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-dashboard", "--fixture-cached-home"]
    for _ in 0..<2 {
      app.launch()
      XCTAssertTrue(app.buttons["homeSettings"].waitForExistence(timeout: 10))
      XCTAssertTrue(app.buttons["prepareQuestion"].exists)
      XCTAssertTrue(app.buttons["prepareQuestion"].label.contains("No. 013"), app.buttons["prepareQuestion"].label)
      XCTAssertFalse(app.staticTexts["Loading practice…"].exists)
      capture("Cached Home", app)
      app.terminate()
    }
  }

  func testHomeAutomaticallyPreparesAndRegenerates() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-dashboard", "--fixture-auto-question", "--fixture-slow-generation"]
    app.launch()
    let ticket = app.buttons["startPractice"]
    XCTAssertTrue(ticket.waitForExistence(timeout: 12))
    XCTAssertTrue(ticket.label.contains("Design a reliable job queue"), ticket.label)
    ticket.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).press(forDuration: 1)
    XCTAssertTrue(app.buttons["Choose focus or level"].waitForExistence(timeout: 3))
    app.buttons["Regenerate"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["todayPreparing"].waitForExistence(timeout: 3))
    XCTAssertTrue(ticket.waitForExistence(timeout: 15), "The replacement lands on the same ticket")
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
    XCTAssertTrue(app.buttons["prepareQuestion"].waitForExistence(timeout: 10))
    app.buttons["prepareQuestion"].tap()
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
    XCTAssertTrue(app.buttons["prepareQuestion"].waitForExistence(timeout: 10))
    app.buttons["prepareQuestion"].tap()
    app.buttons["submitPreparation"].tap()
    XCTAssertTrue(app.navigationBars["Question preview"].waitForExistence(timeout: 5))
    XCUIDevice.shared.press(.home)
    app.activate()
    XCTAssertTrue(app.buttons["homeSettings"].waitForExistence(timeout: 8))
    XCTAssertFalse(app.navigationBars["Question preview"].exists)
  }

  func testGenerationPreviewAndResume() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-dashboard"]
    app.launch()
    XCTAssertTrue(app.buttons["prepareQuestion"].waitForExistence(timeout: 10))
    app.buttons["prepareQuestion"].tap()
    app.buttons["submitPreparation"].tap()
    XCTAssertTrue(app.staticTexts["Design a reliable job queue"].waitForExistence(timeout: 8))
    XCTAssertTrue(app.navigationBars["Question preview"].exists)
    capture("Question streaming in", app)
    XCTAssertTrue(app.buttons["previewStart"].waitForExistence(timeout: 8))
    app.buttons["previewStart"].tap()
    let editor = app.descendants(matching: .any).matching(identifier: "answerEditor").firstMatch
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    editor.tap()
    editor.typeText("Keep retries bounded.")
    app.buttons["Close"].tap()
    XCTAssertTrue(app.buttons["homeSettings"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["startPractice"].label.contains("Where you left off"))
    app.buttons["startPractice"].tap()
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    XCTAssertTrue((editor.value as? String ?? "").contains("Keep retries bounded."))
  }

  func testLongPreviewLayout() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-long-question", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
    app.launch()
    XCTAssertTrue(app.buttons["homeSettings"].waitForExistence(timeout: 10))
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
    XCTAssertTrue(app.tabBars.buttons["Library"].isHittable)
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
    XCTAssertTrue(app.buttons["submitPreparation"].waitForExistence(timeout: 3))
    app.buttons["submitPreparation"].tap()
    XCTAssertTrue(app.buttons["Back to preparation"].waitForExistence(timeout: 8))
    capture("Failed replacement", app)
    app.buttons["Close"].tap()
    XCTAssertTrue(app.buttons["homeSettings"].exists)
    XCTAssertTrue(app.buttons["startPractice"].label.contains("Design a reliable job queue"))
  }

  func testTodayPreviewLifecycle() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures"]
    app.launch()
    XCTAssertTrue(app.buttons["homeSettings"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["startPractice"].exists)
    capture("Persistent Today", app)
    app.buttons["startPractice"].tap()
    XCTAssertTrue(app.buttons["previewStart"].waitForExistence(timeout: 5))
    capture("Question preview", app)
    app.buttons["Close"].tap()
    XCTAssertTrue(app.buttons["homeSettings"].waitForExistence(timeout: 5))
    app.buttons["startPractice"].tap()
    app.buttons["Choose another question"].tap()
    XCTAssertTrue(app.buttons["submitPreparation"].waitForExistence(timeout: 3))
    app.buttons["submitPreparation"].tap()
    XCTAssertTrue(app.navigationBars["Question preview"].waitForExistence(timeout: 5))
    app.buttons["Close"].tap()
    XCTAssertTrue(app.buttons["homeSettings"].waitForExistence(timeout: 5))
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
    XCTAssertTrue(app.buttons["prepareQuestion"].waitForExistence(timeout: 10))
    app.buttons["prepareQuestion"].tap()
    app.buttons["prepareArea"].tap()
    app.buttons["Scale & performance"].tap()
    app.buttons["Caching"].tap()
    app.buttons["prepareLevel"].tap()
    app.buttons["Senior"].tap()
    // Style and custom instructions aren't offered here for now: nothing in Settings backs them.
    XCTAssertFalse(app.buttons["interviewStyle"].exists)
    XCTAssertFalse(app.textFields["Optional request"].exists || app.textViews["Optional request"].exists)
    capture("Temporary preparation", app)
    app.buttons["Cancel"].tap()
    app.buttons["prepareQuestion"].tap()
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
    XCTAssertTrue(app.buttons["homeSettings"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.staticTexts["Last session"].exists)
    XCTAssertTrue(app.buttons["homeSettings"].exists)
    XCTAssertTrue(app.tabBars.buttons["Home"].exists)
    XCTAssertTrue(app.buttons["prepareQuestion"].exists)
    capture("Practice dashboard", app)
    app.buttons["prepareQuestion"].tap()
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
    XCTAssertTrue(app.staticTexts["Quick one. No wrong answers."].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["Back"].exists)
    XCTAssertFalse(app.buttons["Continue"].isEnabled, "The taste wants an answer before moving on")
    capture("Onboarding taste", app)
    app.buttons["Honestly, no idea yet"].tap()
    let taste = app.descendants(matching: .any).matching(identifier: "tasteReaction").firstMatch
    XCTAssertTrue(taste.waitForExistence(timeout: 3))
    XCTAssertTrue(taste.label.contains("database"), taste.label)
    app.buttons["Continue"].tap()
    XCTAssertTrue(app.staticTexts["Where are you right now?"].waitForExistence(timeout: 5))
    app.buttons["Interviews are happening"].tap()
    app.buttons["Continue"].tap()
    XCTAssertTrue(app.staticTexts["When someone says ‘system design’, what happens?"].waitForExistence(timeout: 5))
    for level in ["I freeze", "I know the words", "I can wing it", "I’ve done real ones"] { XCTAssertTrue(app.buttons[level].exists) }
    app.buttons["I freeze"].tap()
    XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "levelPromise").firstMatch.label.contains("so small you can’t freeze"))
    app.buttons["Continue"].tap()
    XCTAssertTrue(app.staticTexts["Four weeks from now, what’s the win?"].waitForExistence(timeout: 5))
    app.buttons["Not panic in an interview"].tap()
    let knowsDate = app.switches["I know the date"]
    XCTAssertTrue(knowsDate.waitForExistence(timeout: 3))
    knowsDate.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
    XCTAssertTrue(app.staticTexts["That’s today. One quick rep to warm up."].waitForExistence(timeout: 3))
    capture("Onboarding interview date", app)
    app.buttons["Back"].tap()
    XCTAssertTrue(app.staticTexts["When someone says ‘system design’, what happens?"].waitForExistence(timeout: 5))
    app.buttons["Continue"].tap()
    XCTAssertTrue(app.staticTexts["Four weeks from now, what’s the win?"].waitForExistence(timeout: 5))
    capture("Onboarding win", app)
  }

  func testDeveloperResetReturnsToOnboarding() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures"]
    app.launch()

    XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
    app.buttons["Settings"].tap()
    let reset = app.buttons["Reset Drillbit"]
    for _ in 0..<5 where !reset.exists { app.swipeUp() }
    XCTAssertTrue(reset.waitForExistence(timeout: 3))
    reset.tap()
    // Anchored to its button, the dialog comes up as a popover: no Cancel, so wait for its message instead.
    let confirmReset = app.buttons.matching(NSPredicate(format: "label == %@", "Reset Drillbit"))
    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Removes your practice")).firstMatch.waitForExistence(timeout: 3))
    confirmReset.allElementsBoundByIndex.last?.tap()
    // The full reset signs out and forgets the first run: the next screen is Welcome.
    XCTAssertTrue(app.descendants(matching: .any)["separatorBit"].waitForExistence(timeout: 25))
    app.buttons["welcomeNext"].tap()
    XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 35), "Get started arrives once the example has played")
    app.terminate()

    // Replay onboarding keeps the sign-in and lands on the setup questions.
    app.launch()
    XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
    app.buttons["Settings"].tap()
    let replay = app.buttons["Replay onboarding questions"]
    for _ in 0..<5 where !replay.exists { app.swipeUp() }
    XCTAssertTrue(replay.waitForExistence(timeout: 3))
    replay.tap()
    XCTAssertTrue(app.buttons["Replay onboarding"].waitForExistence(timeout: 3))
    app.buttons["Replay onboarding"].tap()
    XCTAssertTrue(app.staticTexts["Quick one. No wrong answers."].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Continue"].exists)
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
    // Time zone and the provider are parked under Developer, below the fold.
    let timeZone = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Time zone")).firstMatch
    for _ in 0..<6 where !timeZone.exists || !timeZone.isHittable { app.swipeUp() }
    timeZone.tap()
    XCTAssertTrue(app.navigationBars["Time zone"].waitForExistence(timeout: 5))
    app.searchFields.firstMatch.tap()
    app.searchFields.firstMatch.typeText("Kolkata")
    app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Kolkata")).firstMatch.tap()
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    capture("Settings selected", app)
    let provider = app.buttons["LLM provider"]
    for _ in 0..<6 where !provider.exists || !provider.isHittable { app.swipeUp() }
    provider.tap()
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
    let editor = app.descendants(matching: .any).matching(identifier: "answerEditor").firstMatch
    // At accessibility sizes the document intentionally scrolls, even with the question collapsed.
    for _ in 0..<8 where !editor.isHittable { app.swipeUp() }
    XCTAssertTrue(editor.isHittable)
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
    // Swiping down anywhere near the footer at this size can land on the inline nudge; dismiss it if so.
    for _ in 0..<12 where original.frame.minY < document.frame.minY || !original.isHittable {
      document.swipeDown()
      if app.otherElements["assistancePopup"].waitForExistence(timeout: 0.5) {
        app.buttons["Got it"].tap()
        XCTAssertTrue(app.otherElements["assistancePopup"].waitForNonExistence(timeout: 2))
      }
    }
    // The keyboard's interactive dismissal is still settling the layout after the last swipe.
    Thread.sleep(forTimeInterval: 0.6)
    original.tap()
    XCTAssertTrue(original.waitForExistence(timeout: 5))
    XCTAssertTrue(original.isHittable)
    XCTAssertEqual(original.value as? String, "Expanded")
    XCTAssertFalse(app.navigationBars["Original question"].exists)
    capture("Accessible inline question", app)
    original.tap()
    // XCUITest calls the editor hittable while it still sits under the footer; scroll until its top clears the Send row.
    for _ in 0..<8 where !editor.isHittable || editor.frame.minY > app.buttons["shareAnswer"].frame.minY - 80 { document.swipeUp() }
    XCTAssertTrue(editor.isHittable)
    editor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
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
    // Collapsing eighteen paragraphs moves the editor a long way; tap it once it has arrived.
    Thread.sleep(forTimeInterval: 0.5)
    XCTAssertTrue(editor.isHittable)
    editor.tap()
    editor.typeText("Preserve this draft")
    let document = app.scrollViews["interviewDocument"]
    for _ in 0..<12 where !original.isHittable { document.swipeDown() }
    Thread.sleep(forTimeInterval: 0.5)
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
    XCTAssertTrue(app.buttons["homeSettings"].waitForExistence(timeout: 2))
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
    app.launchArguments = ["--fixtures", "--fixture-slow-assistance"]
    app.launch()
    XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout:10))
    app.buttons["startPractice"].tap()
    app.buttons["previewStart"].tap()
    let editor = app.descendants(matching: .any).matching(identifier: "answerEditor").firstMatch
    XCTAssertTrue(editor.waitForExistence(timeout:5))
    XCTAssertFalse(app.buttons["practiceMode"].exists)
    XCTAssertTrue(app.buttons["liveVoice"].isEnabled)
    XCTAssertTrue(app.otherElements["answerDivider"].exists)
    // Long enough to wrap on every iPhone width, so the answer always gets a disclosure.
    let answer = "Use a durable queue, retry failed work with backoff, and record each attempt so duplicates stay safe."
    editor.tap(); editor.typeText(answer)
    capture("Interview writing", app)
    app.buttons["shareAnswer"].tap()
    XCTAssertTrue(app.staticTexts["What happens if a worker stops after completing the operation but before acknowledging it?"].waitForExistence(timeout:5))
    XCTAssertTrue(["", "Answer or ask a question…"].contains(editor.value as? String ?? ""))
    capture("Interviewer follow-up", app)
    XCTAssertEqual(app.buttons["exchange-original"].value as? String, "Collapsed")
    let answerRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "answer-")).firstMatch
    XCTAssertEqual(answerRow.value as? String, "Collapsed")
    XCTAssertTrue(answerRow.isHittable)
    answerRow.tap()
    let sent = app.staticTexts[answer]
    XCTAssertTrue(sent.isHittable, "The complete sent answer expands beside its response")
    let followUp = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier != %@", "exchange-", "exchange-original")).firstMatch
    followUp.tap()
    XCTAssertTrue(sent.exists, "Folding a question never removes the sent answer")
    followUp.tap()
    capture("Inline interview history", app)
    editor.tap(); editor.typeText("I need to handle duplicate effects.")
    app.buttons["interviewOptions"].tap()
    let menuNudge = app.buttons["Need a nudge?"]
    XCTAssertTrue(menuNudge.exists)
    menuNudge.tap()
    XCTAssertTrue(app.otherElements["assistancePopup"].waitForExistence(timeout: 1))
    // The fixture nudge can land before the loading state is sampled; the slow-assistance test covers loading.
    let nudge = "Consider what a retry can know about an operation that already happened."
    XCTAssertTrue(app.descendants(matching: .any)["assistanceLoading"].exists || app.buttons["Got it"].exists)
    capture("Assistance loading", app)
    XCTAssertTrue(app.staticTexts[nudge].waitForExistence(timeout: 5))
    app.buttons["Got it"].tap()
    XCTAssertFalse(app.staticTexts[nudge].exists)
    XCTAssertFalse(app.navigationBars["Ask interviewer"].exists)
    capture("Inline interviewer help", app)
    XCTAssertEqual(editor.value as? String, "I need to handle duplicate effects.")
    app.buttons["interviewOptions"].tap()
    app.buttons["Show an example"].tap()
    XCTAssertTrue(app.otherElements["assistancePopup"].waitForExistence(timeout: 1))
    XCTAssertTrue(app.descendants(matching: .any)["assistanceLoading"].exists)
    let example = "For example, give each logical operation a stable key and store its result in the same transaction as the state change."
    XCTAssertTrue(app.staticTexts[example].waitForExistence(timeout: 5))
    app.buttons["Got it"].tap()
    XCTAssertFalse(app.staticTexts[example].exists)
    XCTAssertEqual(editor.value as? String, "I need to handle duplicate effects.")
    app.buttons["shareAnswer"].tap()
    XCTAssertTrue(editor.waitForExistence(timeout: 8))
    XCTAssertFalse(app.staticTexts["Ready to wrap up?"].exists)
    capture("Interview wrap-up", app)
    app.buttons["interviewOptions"].tap()
    app.buttons["Finish interview"].tap()
    app.alerts.buttons["Keep writing"].tap()
    XCTAssertFalse(app.staticTexts["That’s one in the bag."].exists)
    app.buttons["interviewOptions"].tap()
    app.buttons["Finish interview"].tap()
    app.alerts.buttons["Finish interview"].tap()
    XCTAssertTrue(app.staticTexts["That’s one in the bag."].waitForExistence(timeout:5))
    capture("Practice completion", app)
    app.buttons["Done for today"].firstMatch.tap()
    let done = app.buttons["todayDone"]
    XCTAssertTrue(done.waitForExistence(timeout: 5))
    XCTAssertTrue(done.label.contains("Make retries safe before making them automatic."), done.label)
    XCTAssertTrue(app.buttons["oneMore"].exists)
    XCTAssertFalse(app.alerts["Drillbit"].exists)
    capture("Home after practice", app)
  }

  func testCancellingAssistanceUnlocksImmediately() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-slow-assistance"]
    app.launch()
    XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout:10))
    app.buttons["startPractice"].tap()
    app.buttons["previewStart"].tap()
    XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "answerEditor").firstMatch.waitForExistence(timeout: 5))
    app.buttons["interviewOptions"].tap()
    app.buttons["Need a nudge?"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["assistanceLoading"].waitForExistence(timeout: 1))
    app.buttons["Cancel"].tap()
    XCTAssertTrue(app.otherElements["assistancePopup"].waitForNonExistence(timeout: 1))
    // The slow nudge would still be running; the next request is available at once.
    app.buttons["interviewOptions"].tap()
    XCTAssertTrue(app.buttons["Show an example"].isEnabled)
    app.buttons["Show an example"].tap()
    let example = "For example, give each logical operation a stable key and store its result in the same transaction as the state change."
    XCTAssertTrue(app.staticTexts[example].waitForExistence(timeout: 6))
    app.buttons["Got it"].tap()
    XCTAssertFalse(app.staticTexts["Consider what a retry can know about an operation that already happened."].exists,
                   "A cancelled nudge never lands in the interview")
  }

  func testPracticeModeLargestLight() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-dashboard", "-appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
    app.launch()
    XCTAssertTrue(app.buttons["prepareQuestion"].waitForExistence(timeout: 10))
    app.buttons["prepareQuestion"].tap()
    let submit = app.buttons["submitPreparation"]
    for _ in 0..<3 where !submit.isHittable { app.swipeUp() }
    submit.tap()
    XCTAssertTrue(app.buttons["previewStart"].waitForExistence(timeout: 10))
    app.buttons["previewStart"].tap()
    XCTAssertTrue(app.buttons["interviewOptions"].waitForExistence(timeout: 5))
    app.buttons["interviewOptions"].tap()
    app.buttons["Session style"].tap()
    XCTAssertTrue(app.navigationBars["Session style"].waitForExistence(timeout: 5))
    for title in ["Guided", "Practice", "Mock interview"] {
      let option = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
      // The list is lazy at this size: rows below the fold only exist once scrolled to.
      for _ in 0..<4 where !(option.exists && option.isHittable) { app.swipeUp() }
      XCTAssertTrue(option.isHittable)
    }
    capture("Largest practice modes light", app)
  }

  func testMockInterviewRunsOnTheClockAndFinishes() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-dashboard"]
    app.launch()
    XCTAssertTrue(app.buttons["prepareQuestion"].waitForExistence(timeout: 10))
    app.buttons["prepareQuestion"].tap()
    app.buttons["submitPreparation"].tap()
    XCTAssertTrue(app.buttons["previewStart"].waitForExistence(timeout: 10))
    app.buttons["previewStart"].tap()
    // The round is chosen inside the interview; the new-question form doesn't offer styles for now.
    XCTAssertTrue(app.buttons["interviewOptions"].waitForExistence(timeout: 5))
    app.buttons["interviewOptions"].tap()
    app.buttons["Session style"].tap()
    let mock = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Mock interview")).firstMatch
    XCTAssertTrue(mock.waitForExistence(timeout: 5)); mock.tap()
    let clock = app.descendants(matching: .any)["roundClock"]
    XCTAssertTrue(clock.waitForExistence(timeout: 5))
    XCTAssertTrue(clock.label.hasSuffix("minutes left"), clock.label)
    capture("Mock interview clock", app)
    // A real round: no nudge or example on tap, only Finish.
    app.buttons["interviewOptions"].tap()
    XCTAssertTrue(app.buttons["Finish interview"].waitForExistence(timeout: 3))
    XCTAssertFalse(app.buttons["Show an example"].exists)
    XCTAssertFalse(app.buttons["Need a nudge?"].exists)
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.6)).tap()
    let editor = app.descendants(matching: .any).matching(identifier: "answerEditor").firstMatch
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    editor.tap(); editor.typeText("Workers lease jobs and record every attempt durably.")
    app.buttons["shareAnswer"].tap()
    XCTAssertTrue(app.staticTexts["What happens if a worker stops after completing the operation but before acknowledging it?"].waitForExistence(timeout: 8))
    app.buttons["interviewOptions"].tap()
    app.buttons["Finish interview"].tap()
    app.alerts.buttons["Finish interview"].tap()
    // Generated feedback is parked for MVP (`ReflectionView.showsFeedback`): the round ends on the plain finish.
    XCTAssertTrue(app.staticTexts["That’s one in the bag."].waitForExistence(timeout: 8))
    XCTAssertFalse(app.staticTexts["INTERVIEW DEBRIEF"].exists)
    XCTAssertFalse(clock.exists, "The clock stops once the round is over")
    capture("Mock interview finished", app)
  }

  func testInterviewStyle() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-dashboard"]
    app.launch()
    XCTAssertTrue(app.buttons["prepareQuestion"].waitForExistence(timeout:10))
    app.buttons["prepareQuestion"].tap()
    app.buttons["submitPreparation"].tap()
    XCTAssertTrue(app.buttons["previewStart"].waitForExistence(timeout:8))
    XCTAssertFalse(app.staticTexts["Interview style · In-depth"].exists)
    app.buttons["previewStart"].tap()
    XCTAssertTrue(app.buttons["interviewOptions"].waitForExistence(timeout:5))
    app.buttons["interviewOptions"].tap()
    app.buttons["Session style"].tap()
    let quick = app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@", "Mock interview")).firstMatch
    XCTAssertTrue(quick.waitForExistence(timeout:5)); XCTAssertTrue(quick.isEnabled)
    XCTAssertTrue(app.buttons["Back"].exists)
    quick.tap()
    capture("Change active practice mode", app)
    let editor = app.descendants(matching: .any).matching(identifier: "answerEditor").firstMatch
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    editor.tap(); editor.typeText("Keep a durable queue.")
    XCTAssertEqual(app.buttons["exchange-original"].value as? String, "Expanded")
    capture("Question stays open while typing", app)
    XCTAssertFalse(app.staticTexts["Saved on this device"].exists)
    app.buttons["interviewOptions"].tap()
    app.buttons["Session style"].tap()
    XCTAssertTrue(quick.isEnabled)
    let standard = app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@", "Practice")).firstMatch
    XCTAssertTrue(quick.isSelected)
    standard.tap()
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    app.buttons["interviewOptions"].tap()
    app.buttons["Session style"].tap()
    XCTAssertTrue(standard.isSelected)
    app.buttons["Back"].tap()
    XCTAssertTrue(editor.exists)
  }

  func testInterviewDarkKeyboard() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--dark", "--fixture-long-question"]
    app.launch()
    XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout:10))
    app.buttons["startPractice"].tap(); app.buttons["previewStart"].tap()
    let editor = app.descendants(matching: .any).matching(identifier: "answerEditor").firstMatch
    XCTAssertTrue(editor.waitForExistence(timeout:5))
    XCTAssertFalse(app.otherElements["interviewParameters"].exists)
    capture("Dark interview question", app)
    editor.tap(); editor.typeText("Start with a durable queue.")
    XCTAssertTrue(app.buttons["shareAnswer"].isHittable)
    XCTAssertTrue(app.buttons["interviewOptions"].isHittable)
    // Xcode may attach a hardware keyboard; the capture name says which one this run saw.
    capture(app.keyboards.count > 0 ? "Dark interview keyboard" : "Dark interview hardware keyboard", app)
    XCTAssertEqual(editor.value(forKey: "hasKeyboardFocus") as? Bool, true)
    // Tapping the document outside the reply puts the keyboard away.
    app.otherElements["answerDivider"].tap()
    let released = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == false"), object: editor)
    XCTAssertEqual(XCTWaiter.wait(for: [released], timeout: 3), .completed)
    XCTAssertFalse(app.buttons["hideKeyboard"].exists)
  }

  func testQuestionUsesSameComposerWithoutAdvancingPrompt() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures"]
    app.launch()
    XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout: 10))
    app.buttons["startPractice"].tap(); app.buttons["previewStart"].tap()
    let editor = app.descendants(matching: .any).matching(identifier: "answerEditor").firstMatch
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    editor.tap(); editor.typeText("What scale?")
    app.buttons["shareAnswer"].tap()
    XCTAssertTrue(app.staticTexts["Consider what a retry can know about an operation that already happened."].waitForExistence(timeout: 8))
    let clarification = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "clarification-")).firstMatch
    XCTAssertTrue(clarification.exists)
    let original = app.buttons["exchange-original"]
    original.tap()
    XCTAssertFalse(clarification.exists)
    original.tap()
    XCTAssertTrue(clarification.exists)
    XCTAssertTrue(["", "Answer or ask a question…"].contains(editor.value as? String ?? ""))
    XCTAssertFalse(app.buttons["Ask interviewer"].exists)
  }

  func testOnboardingStartsWithGuidedFirstQuestion() throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-onboarding"]
    app.launch()
    XCTAssertTrue(app.staticTexts["Quick one. No wrong answers."].waitForExistence(timeout: 10))
    app.buttons["The database"].tap()
    app.buttons["Continue"].tap()
    XCTAssertTrue(app.staticTexts["Where are you right now?"].waitForExistence(timeout: 5))
    app.buttons["Continue"].tap()
    XCTAssertTrue(app.staticTexts["When someone says ‘system design’, what happens?"].waitForExistence(timeout: 5))
    capture("Onboarding level", app)
    app.buttons["Continue"].tap()
    XCTAssertTrue(app.staticTexts["Four weeks from now, what’s the win?"].waitForExistence(timeout: 5))
    app.buttons["Continue"].tap()
    XCTAssertTrue(app.staticTexts["How do you think best?"].waitForExistence(timeout: 5))
    app.buttons["Typing, at my own pace"].tap()
    app.buttons["Continue"].tap()
    XCTAssertTrue(app.staticTexts["Be honest. How much time?"].waitForExistence(timeout: 5))
    app.buttons["Continue"].tap()
    XCTAssertTrue(app.staticTexts["Here’s where we start."].waitForExistence(timeout: 5))
    XCTAssertTrue(app.descendants(matching: .any)["planTicket"].exists)
    capture("Onboarding plan", app)
    app.buttons["Show me my first question"].tap()
    // The first question rises over setup: it counts, there's no Close, and one swap is included.
    XCTAssertTrue(app.buttons["previewStart"].waitForExistence(timeout: 10))
    XCTAssertEqual(app.buttons["previewStart"].label, "Start")
    XCTAssertFalse(app.buttons["Close"].exists)
    capture("First question preview", app)
    app.buttons["Choose another question"].tap()
    XCTAssertFalse(app.buttons["previewStart"].waitForExistence(timeout: 1), "Actions wait until the next question is fully written")
    XCTAssertTrue(app.buttons["previewStart"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["Choose another question"].exists, "The first rep includes one swap")
    app.buttons["previewStart"].tap()
    // No guide: the interviewer's opener types itself in and every control works straight away.
    let editor = app.descendants(matching: .any).matching(identifier: "answerEditor").firstMatch
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    XCTAssertTrue(app.descendants(matching: .any)["interviewOpener"].waitForExistence(timeout: 6))
    XCTAssertTrue(app.buttons["interviewOptions"].isEnabled)
    Thread.sleep(forTimeInterval: 2)
    capture("First rep opener", app)
    app.buttons["interviewOptions"].tap()
    app.buttons["Need a nudge?"].tap()
    XCTAssertTrue(app.otherElements["assistancePopup"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["Got it"].waitForExistence(timeout: 8))
    app.buttons["Got it"].tap()
    editor.tap(); editor.typeText("Start with one table of saved links keyed by user.")
    app.buttons["shareAnswer"].tap()
    XCTAssertTrue(app.staticTexts["What happens if a worker stops after completing the operation but before acknowledging it?"].waitForExistence(timeout: 8))
    // Guided holds your hand: a visible path, and answers you can tap instead of facing an empty box.
    let path = app.descendants(matching: .any)["guidedPath"]
    XCTAssertTrue(path.exists)
    XCTAssertTrue(path.label.hasPrefix("Step 1 of 4"), path.label)
    let choice = app.buttons["guidedChoice-1"]
    XCTAssertTrue(choice.waitForExistence(timeout: 3))
    capture("Guided path and choices", app)
    path.tap()
    XCTAssertTrue(app.descendants(matching: .any)["guidedPathSteps"].waitForExistence(timeout: 3))
    capture("Guided path steps", app)
    app.otherElements["PopoverDismissRegion"].tap()
    XCTAssertFalse(app.descendants(matching: .any)["guidedPathSteps"].waitForExistence(timeout: 1))
    choice.tap()
    XCTAssertTrue(app.buttons["guidedChoice-1"].waitForExistence(timeout: 8))
    XCTAssertTrue(path.label.hasPrefix("Step 2 of 4"), path.label)
    app.buttons["interviewOptions"].tap()
    app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Finish interview'")).firstMatch.tap()
    app.alerts.buttons["Finish interview"].tap()
    // Feedback leads with what worked and what to fix, then offers the reminder once.
    XCTAssertTrue(app.descendants(matching: .any)["feedbackLead"].waitForExistence(timeout: 8))
    XCTAssertTrue(app.descendants(matching: .any)["reminderOffer"].exists)
    // MVP: generated feedback is parked; the completion is plain, and the rep still counts on Home.
    XCTAssertFalse(app.buttons["Review in Recall"].exists)
    capture("First rep feedback", app)
    let noThanks = app.buttons["No thanks"]
    for _ in 0..<4 where !noThanks.isHittable { app.swipeUp() }
    noThanks.tap()
    XCTAssertFalse(app.descendants(matching: .any)["reminderOffer"].waitForExistence(timeout: 2))
    let done = app.buttons["Done for today"].firstMatch
    for _ in 0..<4 where !done.isHittable { app.swipeUp() }
    done.tap()
    // Onboarding ends on Home with the rep already counted; no tab tour.
    XCTAssertTrue(app.buttons["todayDone"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["firstUseTourNext"].exists)
    capture("Home after first rep", app)
  }

  func testSpentFreeRepWaitsOnHome() throws {
    // The local products from Config/Drillbit.storekit, so the paywall shows real plan options.
    let store = try SKTestSession(configurationFileNamed: "Drillbit")
    store.resetToDefaultState(); store.disableDialogs = true; store.clearTransactions()
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-dashboard", "--fixture-gate"]
    app.launch()
    let waiting = app.descendants(matching: .any)["freeRepWaiting"]
    XCTAssertTrue(waiting.waitForExistence(timeout: 10))
    XCTAssertTrue(waiting.label.contains("That’s today’s free reps"), waiting.label)
    XCTAssertFalse(app.buttons["prepareQuestion"].exists)
    capture("Free reps spent on Home", app)
    // The gate opens the paywall; a purchase lands back on Home with practice open again.
    XCTAssertTrue(app.buttons["seePro"].exists)
    app.buttons["seePro"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["paywall"].waitForExistence(timeout: 5))
    // Every figure comes from the products: 39.99 a year against 52 × 6.99 saves 88%, and the weekly intro shows.
    let option = { (text: String) in app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch }
    XCTAssertTrue(option("Save 88%").waitForExistence(timeout: 10))
    XCTAssertTrue(option("$3.33 a month").exists)
    XCTAssertTrue(option("Try a week for $0.99, then $6.99 a week").exists)
    // What App Review checks on a subscription paywall: terms, renewal terms, restore and a way out.
    XCTAssertTrue(option("Terms of Service").exists)
    XCTAssertTrue(option("auto-renews").exists)
    XCTAssertTrue(option("Restore").exists)
    XCTAssertTrue(app.buttons["paywallDismiss"].isHittable)
    capture("Paywall from the rep gate", app)
    app.buttons["paywallDismiss"].tap()
    XCTAssertTrue(waiting.waitForExistence(timeout: 5))
    app.buttons["seePro"].tap()
    XCTAssertTrue(app.buttons["paywallFixturePurchase"].waitForExistence(timeout: 5))
    app.buttons["paywallFixturePurchase"].tap()
    XCTAssertTrue(app.buttons["prepareQuestion"].waitForExistence(timeout: 5), "Pro reopens practice without a relaunch")
    XCTAssertFalse(waiting.exists)
    app.buttons["Settings"].tap()
    let plan = app.descendants(matching: .any)["planRow"]
    for _ in 0..<4 where !plan.exists { app.swipeUp() }
    XCTAssertTrue(plan.waitForExistence(timeout: 5))
    XCTAssertTrue(plan.label.contains("Pro"), plan.label)
    capture("Settings on Pro", app)
  }

  func testDeveloperCanActAsFreeAndMeetThePaywall() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-dashboard"]
    app.launch()
    XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
    app.buttons["Settings"].tap()
    let picker = app.buttons["developerPlan"]
    for _ in 0..<8 where !picker.isHittable { app.swipeUp() }
    picker.tap()
    app.buttons["Free"].tap()
    capture("Developer acting as Free", app)
    app.buttons["Done"].tap()
    // Free with today's reps spent: Home waits, and See Pro opens the paywall.
    XCTAssertTrue(app.descendants(matching: .any)["freeRepWaiting"].waitForExistence(timeout: 5))
    app.buttons["seePro"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["paywall"].waitForExistence(timeout: 5))
    app.buttons["paywallDismiss"].tap()
    app.buttons["Settings"].tap()
    for _ in 0..<8 where !picker.isHittable { app.swipeUp() }
    picker.tap()
    app.buttons["Pro"].tap()
    app.buttons["Done"].tap()
    XCTAssertTrue(app.buttons["prepareQuestion"].waitForExistence(timeout: 5), "Pro opens practice again")
  }

  func testFreePlanShowsRepsLeftAndVoiceIntroInSettings() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-free-reps"]
    app.launch()
    XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
    app.buttons["Settings"].tap()
    let plan = app.descendants(matching: .any)["planRow"]
    for _ in 0..<4 where !plan.exists { app.swipeUp() }
    XCTAssertTrue(plan.waitForExistence(timeout: 5))
    XCTAssertTrue(plan.label.contains("Free"), plan.label)
    XCTAssertTrue(app.staticTexts["2 of 3 free reps left today"].exists)
    XCTAssertTrue(app.buttons["settingsSeePro"].exists)
    // See Pro works from inside the Settings sheet too, and Not now lands back in Settings.
    app.buttons["settingsSeePro"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["paywall"].waitForExistence(timeout: 5))
    app.buttons["paywallDismiss"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["paywall"].waitForNonExistence(timeout: 5))
    XCTAssertTrue(plan.exists, "Still in Settings")
    // A swipe down dismisses it the same way, and it opens again afterwards.
    app.buttons["settingsSeePro"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["paywall"].waitForExistence(timeout: 5))
    app.descendants(matching: .any)["paywall"].swipeDown(velocity: .fast)
    XCTAssertTrue(app.descendants(matching: .any)["paywall"].waitForNonExistence(timeout: 5))
    app.buttons["settingsSeePro"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["paywall"].waitForExistence(timeout: 5))
    app.buttons["paywallDismiss"].tap()
    let restore = app.buttons["Restore purchases"]
    for _ in 0..<2 where !restore.exists { app.swipeUp() }
    XCTAssertTrue(restore.waitForExistence(timeout: 3))
    // Subscription apps must reach their terms from inside the app.
    let terms = app.descendants(matching: .any)["settingsTerms"]
    for _ in 0..<8 where !terms.exists { app.swipeUp() }
    XCTAssertTrue(terms.waitForExistence(timeout: 3))
    // The third-party AI disclosure stays findable after the one-time consent.
    let disclosure = app.descendants(matching: .any)["settingsAIDisclosure"]
    for _ in 0..<2 where !disclosure.exists { app.swipeUp() }
    XCTAssertTrue(disclosure.waitForExistence(timeout: 3))
    XCTAssertTrue(disclosure.label.contains("OpenRouter") && disclosure.label.contains("OpenAI"), disclosure.label)
    capture("Settings on Free", app)
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
    // The collapse animates and the editor can still sit below the fold at this size.
    Thread.sleep(forTimeInterval: 0.5)
    for _ in 0..<8 where !editor.isHittable { app.swipeUp() }
    editor.tap(); editor.typeText("A durable queue")
    XCTAssertTrue(app.buttons["shareAnswer"].isHittable)
    capture("Accessible document keyboard", app)
  }

  func testLocalWalkthroughShowsTheLearningLoopBeforeSignIn() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--fixtures", "--fixture-signed-out", "--fixture-walkthrough"]
    app.launch()
    // Page one: why this round matters, then Next.
    XCTAssertTrue(app.descendants(matching: .any)["separatorHeadline"].waitForExistence(timeout: 8))
    XCTAssertFalse(app.buttons["Get started"].exists)
    // Bit arrives with the pitch once the loop has lit; the arrow at the foot turns the page.
    XCTAssertTrue(app.descendants(matching: .any)["separatorBit"].waitForExistence(timeout: 20))
    Thread.sleep(forTimeInterval: 2)
    capture("Welcome separator", app)
    app.buttons["welcomeNext"].tap()
    // Page two: the promise and an example that plays itself, no buttons to press.
    XCTAssertTrue(app.descendants(matching: .any)["welcomeHeadline"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["Continue"].exists)
    capture("Welcome", app)
    XCTAssertTrue(app.descendants(matching: .any)["exampleTurn-2"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.descendants(matching: .any)["exampleTurn-2"].label.contains("buzzed twice"))
    capture("Welcome example doubled", app)
    XCTAssertTrue(app.descendants(matching: .any)["exampleTurn-4"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.descendants(matching: .any)["exampleTurn-4"].label.contains("idempotency key"))
    XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 8), "The way in waits for the example to finish")
    capture("Welcome example fixed", app)
    // Get started goes to the setup cards; sign-in waits until the first question.
    app.buttons["Get started"].tap()
    XCTAssertTrue(app.staticTexts["Quick one. No wrong answers."].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["Sign in with Apple"].exists)
    app.buttons["The database"].tap()
    for _ in 0..<6 { app.buttons["Continue"].tap() }
    XCTAssertTrue(app.buttons["Show me my first question"].waitForExistence(timeout: 5))
    app.buttons["Show me my first question"].tap()
    XCTAssertTrue(app.staticTexts["Your question’s ready."].waitForExistence(timeout: 5))
    // Third-party AI is disclosed and agreed to before any sign-in, so nothing reaches a model without permission.
    XCTAssertTrue(app.descendants(matching: .any)["aiDisclosure"].exists)
    XCTAssertTrue(app.staticTexts["Before we start: Bit runs on outside AI."].exists)
    XCTAssertFalse(app.buttons["Sign in with Apple"].exists)
    capture("AI consent before sign in", app)
    app.buttons["aiConsentAgree"].tap()
    XCTAssertTrue(app.buttons["Sign in with Apple"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.descendants(matching: .any)["aiDisclosure"].exists)
    capture("Sign in after setup", app)
  }

  private func capture(_ name: String, _ app: XCUIApplication) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
