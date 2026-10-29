import StoreKitTest
import XCTest

/// A real, signed-in run against the development backend: real questions, real AI, every screen and menu. It only
/// runs when asked (`TEST_RUNNER_DRILLBIT_LIVE=1`), on a signed simulator build whose account is already signed in,
/// because it spends real reps and leaves real attempts behind. Screenshots are the output; read them afterwards.
@MainActor
final class LiveWalkthrough: XCTestCase {
  private var app: XCUIApplication!
  private var step = 0

  override func setUpWithError() throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["DRILLBIT_LIVE"] == "1", "Live walkthrough runs only when asked.")
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
  private func tapIfPresent(_ element: XCUIElement, timeout: TimeInterval = 2) -> Bool {
    guard element.waitForExistence(timeout: timeout), element.isHittable else { return false }
    element.tap(); return true
  }
  private var editor: XCUIElement { app.descendants(matching: .any).matching(identifier: "answerEditor").firstMatch }
  private var dialog: XCUIElement { any("confirmDialog") }

  /// Waits for the interviewer to finish replying: the composer is usable again.
  private func waitForReply(_ timeout: TimeInterval = 60) {
    let deadline = Date().addingTimeInterval(timeout)
    Thread.sleep(forTimeInterval: 3)
    while Date() < deadline {
      if editor.exists, editor.isHittable, app.buttons["interviewOptions"].isEnabled { break }
      Thread.sleep(forTimeInterval: 1)
    }
    Thread.sleep(forTimeInterval: 1.5)
  }
  private func answer(_ text: String, name: String) {
    guard editor.waitForExistence(timeout: 20) else { return }
    clearTips(name)
    for _ in 0..<6 where !editor.isHittable { app.swipeUp() }
    // Tips arrive on their own timers; a late one swallows the tap, so clear it and try again.
    for _ in 0..<5 {
      if app.buttons["coachDone"].exists { app.buttons["coachDone"].tap(); Thread.sleep(forTimeInterval: 1) }
      editor.tap()
      if (editor.value(forKey: "hasKeyboardFocus") as? Bool) == true { break }
      Thread.sleep(forTimeInterval: 1.5)
    }
    guard (editor.value(forKey: "hasKeyboardFocus") as? Bool) == true else { shot(name + "-no-focus"); return }
    editor.typeText(text)
    shot(name + "-typed")
    if tapIfPresent(app.buttons["shareAnswer"]) { waitForReply(); shot(name + "-reply") }
  }

  /// First-run tips lock the screen until answered; a later one can arrive a few seconds after the last.
  private func clearTips(_ name: String) {
    for index in 0..<4 {
      guard app.buttons["coachDone"].waitForExistence(timeout: index == 0 ? 6 : 4) else { return }
      shot("\(name)-tip\(index)"); app.buttons["coachDone"].tap(); Thread.sleep(forTimeInterval: 1)
    }
  }
  /// Interviews open in voice for "Talking it out"; look at the room, then go to typing.
  private func leaveVoiceIfOpen(_ name: String) {
    Thread.sleep(forTimeInterval: 6)
    app.tap()
    guard app.buttons["voiceMute"].exists || app.buttons["voiceEnd"].exists || app.buttons["voiceBack"].exists || app.buttons["Show me"].exists else { return }
    shot(name)
    if tapIfPresent(app.buttons["Show me"], timeout: 1) { Thread.sleep(forTimeInterval: 3); return }
    _ = tapIfPresent(app.buttons["voiceEnd"], timeout: 2) || tapIfPresent(app.buttons["voiceBack"], timeout: 2)
    Thread.sleep(forTimeInterval: 4)
  }

  func testLiveWalkthrough() throws {
    let store = try SKTestSession(configurationFileNamed: "Drillbit")
    store.resetToDefaultState(); store.disableDialogs = true; store.clearTransactions()
    app = XCUIApplication()
    // System prompts (Apple Account verification, microphone) shouldn't stall the walk.
    addUIInterruptionMonitor(withDescription: "System alerts") { alert in
      for title in ["Allow", "Not Now", "OK"] where alert.buttons[title].exists { alert.buttons[title].tap(); return true }
      return false
    }
    app.launch()
    Thread.sleep(forTimeInterval: 4)
    shot("launch")

    // Consent, if this device hasn't agreed yet.
    if tapIfPresent(app.buttons["aiConsentAgree"], timeout: 6) { shot("after-consent") }

    // Setup, if onboarding isn't finished: answer the cards and ask for the first question.
    if app.staticTexts["Quick one. No wrong answers."].waitForExistence(timeout: 6) {
      shot("setup-taste")
      _ = tapIfPresent(app.buttons["The database"])
      for page in 0..<6 {
        guard tapIfPresent(app.buttons["Continue"], timeout: 4) else { break }
        Thread.sleep(forTimeInterval: 0.8)
        shot("setup-\(page)")
      }
      if tapIfPresent(app.buttons["Show me my first question"], timeout: 5) { shot("first-question-requested") }
    }

    // Came back mid-rep: the interview reopens by itself (in voice, for "Talking it out").
    let resumed = app.buttons["interviewOptions"].waitForExistence(timeout: 10) || app.buttons["voiceEnd"].exists || app.buttons["voiceMute"].exists
    if resumed { shot("resumed-interview"); leaveVoiceIfOpen("resumed-in-voice") }
    // Home, or the first question's preview rising over setup.
    if !resumed, !app.buttons["previewStart"].waitForExistence(timeout: 45) {
      shot("home")
      if tapIfPresent(app.buttons["startPractice"], timeout: 10) || tapIfPresent(app.buttons["prepareQuestion"], timeout: 2) {
        leaveVoiceIfOpen("voice-on-resume")
        if tapIfPresent(app.buttons["submitPreparation"], timeout: 5) { shot("preparation-submitted") }
      }
    }
    if !resumed, app.buttons["previewStart"].waitForExistence(timeout: 60) {
      Thread.sleep(forTimeInterval: 2)
      shot("question-preview")
      app.buttons["previewStart"].tap()
    }
    leaveVoiceIfOpen("voice-first-open")

    // Rep one: a real interview, every tool and menu.
    if editor.waitForExistence(timeout: 30) {
      waitForReply(40)
      shot("interview-opener")
      clearTips("opener")
      answer("I'd start by pinning down the requirements: who calls this, how large the payloads are, and what happens when a client retries.", name: "turn1")
      answer("Clients upload to object storage with a presigned URL, and the API only records metadata and an idempotency key, so a retry never stores the file twice.", name: "turn2")
      clearTips("tools")
      if tapIfPresent(app.buttons["interviewOptions"]) {
        shot("interview-menu")
        if tapIfPresent(app.buttons["Need a nudge?"]) {
          Thread.sleep(forTimeInterval: 12); shot("nudge")
          _ = tapIfPresent(app.buttons["Got it"], timeout: 20) || tapIfPresent(app.buttons["Cancel"])
        }
      }
      if tapIfPresent(app.buttons["interviewOptions"]), tapIfPresent(app.buttons["Show an example"]) {
        Thread.sleep(forTimeInterval: 12); shot("example")
        _ = tapIfPresent(app.buttons["Got it"], timeout: 20) || tapIfPresent(app.buttons["Cancel"])
      }
      if tapIfPresent(app.buttons["interviewOptions"]), tapIfPresent(app.buttons["Session style"]) {
        Thread.sleep(forTimeInterval: 0.8); shot("session-style")
        _ = tapIfPresent(app.navigationBars["Session style"].buttons["Back"])
        Thread.sleep(forTimeInterval: 1)
      }
      if tapIfPresent(app.buttons["exchange-original"]) { Thread.sleep(forTimeInterval: 0.8); shot("original-expanded"); app.buttons["exchange-original"].tap() }
      if tapIfPresent(any("guidedPath")) { Thread.sleep(forTimeInterval: 0.8); shot("roadmap"); app.otherElements["PopoverDismissRegion"].firstMatch.tap() }
      // Voice: open, look around, leave without speaking (waived, so it costs no free session).
      if tapIfPresent(app.buttons["liveVoice"]) {
        Thread.sleep(forTimeInterval: 8); shot("voice-room")
        Thread.sleep(forTimeInterval: 4); shot("voice-room-later")
        _ = tapIfPresent(app.buttons["voiceEnd"], timeout: 4) || tapIfPresent(app.buttons["voiceBack"], timeout: 2)
        Thread.sleep(forTimeInterval: 4); shot("after-voice")
        _ = tapIfPresent(dialog.buttons.firstMatch, timeout: 1)
      }
      answer("For load, the API stays stateless behind a load balancer; storage absorbs the bytes, and a queue handles post-processing so slow scans never block uploads.", name: "turn3")
      if tapIfPresent(app.buttons["interviewOptions"]) {
        if tapIfPresent(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Finish interview'")).firstMatch) {
          if dialog.waitForExistence(timeout: 3) { shot("finish-dialog"); dialog.buttons["Finish interview"].tap() }
        }
      }
      Thread.sleep(forTimeInterval: 6)
      shot("after-finish")
      if app.staticTexts["That’s one in the bag."].exists || app.buttons["completionDone"].exists {
        app.swipeUp(); shot("completion-scrolled")
        _ = tapIfPresent(app.buttons["reminderOfferAccept"].exists ? app.buttons["No thanks"] : app.buttons["completionDone"], timeout: 2)
        _ = tapIfPresent(app.buttons["completionDone"], timeout: 2) || tapIfPresent(app.buttons["Done for today"], timeout: 2)
      }
    }

    // Home after the rep, and the one-time reminder question.
    Thread.sleep(forTimeInterval: 3)
    shot("home-after-rep")
    if dialog.waitForExistence(timeout: 4) { shot("reminder-popup"); _ = tapIfPresent(dialog.buttons["No thanks"]) }

    // Settings, every section and sub-page, and Pro from there.
    if tapIfPresent(app.buttons["homeSettings"], timeout: 5) || tapIfPresent(app.buttons["Settings"], timeout: 2) {
      Thread.sleep(forTimeInterval: 1); shot("settings-top")
      for page in ["Learning plan", "About your practice", "Time zone", "Export practice data"] {
        let button = app.buttons[page]
        for _ in 0..<6 where !(button.exists && button.isHittable) { app.swipeUp() }
        if tapIfPresent(button) { Thread.sleep(forTimeInterval: 1); shot("settings-" + page.replacingOccurrences(of: " ", with: "-")); app.navigationBars.buttons.element(boundBy: 0).tap() }
      }
      for index in 0..<3 { app.swipeUp(); Thread.sleep(forTimeInterval: 0.5); shot("settings-scroll-\(index)") }
      for _ in 0..<8 { app.swipeDown() }
      if tapIfPresent(app.buttons["settingsSeePro"], timeout: 3) {
        for _ in 0..<4 where !app.buttons["paywallSubscribe"].waitForExistence(timeout: 4) { _ = tapIfPresent(app.buttons["Try again"]) }
        shot("paywall-yearly")
        if tapIfPresent(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Weekly")).firstMatch) { shot("paywall-weekly") }
        _ = tapIfPresent(app.buttons["paywallDismiss"])
      }
      _ = tapIfPresent(app.buttons["Done"], timeout: 3)
    }

    // Library: the glance, an area, Try again's preview, a rep and its delete question (cancelled).
    if tapIfPresent(app.tabBars.buttons["Library"], timeout: 5) {
      Thread.sleep(forTimeInterval: 2); shot("library")
      if tapIfPresent(app.buttons["Library menu"]) { shot("library-menu"); app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap() }
      let chip = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'libraryArea-' AND NOT identifier == 'libraryArea-All'")).firstMatch
      if tapIfPresent(chip) { Thread.sleep(forTimeInterval: 0.8); shot("library-area"); chip.tap() }
      if tapIfPresent(app.buttons["worthTryAgain"]) {
        Thread.sleep(forTimeInterval: 1.5); shot("library-try-again")
        _ = tapIfPresent(app.buttons["Close"])
      }
      let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library-rep-'")).firstMatch
      for _ in 0..<4 where first.exists && !first.isHittable { app.swipeUp() }
      if tapIfPresent(first, timeout: 5) {
        Thread.sleep(forTimeInterval: 1.5); shot("attempt")
        app.swipeUp(); shot("attempt-scrolled")
        if tapIfPresent(app.buttons["deleteAttempt"]) { shot("delete-dialog"); _ = tapIfPresent(dialog.buttons["Cancel"]) }
      }
    }

    // Recall and its sections.
    if tapIfPresent(app.tabBars.buttons["Recall"], timeout: 5) {
      Thread.sleep(forTimeInterval: 2); shot("recall")
      if tapIfPresent(app.buttons["recallReveal"]) { Thread.sleep(forTimeInterval: 1); shot("recall-revealed") }
      for section in ["Map", "Paths"] where tapIfPresent(app.buttons[section]) { Thread.sleep(forTimeInterval: 1); shot("recall-" + section.lowercased()) }
    }

    // Rep two from Home's ticket.
    if tapIfPresent(app.tabBars.buttons["Home"], timeout: 5) {
      Thread.sleep(forTimeInterval: 2); shot("home-again")
      if tapIfPresent(app.buttons["oneMore"], timeout: 3) || tapIfPresent(app.buttons["startPractice"], timeout: 2) || tapIfPresent(app.buttons["prepareQuestion"], timeout: 2) {
        Thread.sleep(forTimeInterval: 1.5); shot("question-flow")
        if tapIfPresent(app.buttons["submitPreparation"], timeout: 5) { shot("preparing") }
        if app.buttons["previewStart"].waitForExistence(timeout: 60) {
          Thread.sleep(forTimeInterval: 2); shot("preview-2"); app.buttons["previewStart"].tap()
          leaveVoiceIfOpen("voice-second-open")
          waitForReply(40); shot("interview-2-opener")
          answer("I'd want to clarify the read-to-write ratio first, since it decides whether caching or partitioning matters more here.", name: "rep2-turn1")
          if tapIfPresent(app.buttons["interviewOptions"]),
             tapIfPresent(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Finish interview'")).firstMatch),
             dialog.waitForExistence(timeout: 3) { dialog.buttons["Finish interview"].tap() }
          Thread.sleep(forTimeInterval: 6); shot("after-finish-2")
          _ = tapIfPresent(app.buttons["completionDone"], timeout: 3) || tapIfPresent(app.buttons["Done for today"], timeout: 2)
          Thread.sleep(forTimeInterval: 3); shot("home-final")
        }
      }
    }
  }
}
