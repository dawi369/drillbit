import Foundation

struct PendingHelp: Codable {
  var command: String
  var input: HelpInput
}
struct PendingContext: Codable {
  var command: String
  var input: CompanionUpdate
}

extension PracticeController {
  func persistCompanion() async {
    do {
      try await model.disk.cache(
        key: key + ":companion", data: JSONEncoder().encode(companion.recovery))
    } catch { companion.unavailable = "Couldn’t save help state. Your answer is unchanged." }
  }
  func changeContext(_ input: CompanionUpdate) async {
    guard !contextBusy else { return }
    contextBusy = true
    defer { contextBusy = false }
    do {
      if model.fixture {
        companion.context.revision += 1
        if let mode = input.mode {
          companion.context.mode = mode
          companion.context.modeEpoch += 1
          companion.context.paused = false
        }
        if let paused = input.paused { companion.context.paused = paused }
        if input.operation == "focus" { companion.context.selectedFocus = input.text }
        if input.operation == "discussion", let text = input.text {
          companion.context.decisions.append(.init(id: UUID().uuidString, text: text))
        }
      } else {
        let stored = try await model.disk.cached(key: key + ":context-command")
        let pending =
          stored.flatMap { try? JSONDecoder().decode(PendingContext.self, from: $0) }
          ?? PendingContext(command: UUID().uuidString, input: input)
        try await model.disk.cache(
          key: key + ":context-command", data: JSONEncoder().encode(pending))
        companion.context = try await model.api.send(
          "challenges/\(challenge.id)/companion", method: "PUT", body: pending.input,
          command: pending.command)
        try await model.disk.cache(key: key + ":context-command", data: Data())
      }
      mode = AssistanceMode(rawValue: companion.context.mode.capitalized) ?? .solo
      companion.unavailable = nil
      companion.event(input.operation == "discussion" ? .discussionCommitted : .modeChanged)
      await persistCompanion()
    } catch let error as APIError where error.status == 409 {
      try? await model.disk.cache(key: key + ":context-command", data: Data())
      companion.unavailable = "Practice changed elsewhere. Reopen help to refresh."
    } catch {
      companion.unavailable = "Connection unavailable. Your choice is saved on this device."
    }
  }
  func pauseCompanion(_ paused: Bool) async {
    companion.suggestion = nil
    await changeContext(
      CompanionUpdate(revision: companion.context.revision, operation: "pause", paused: paused))
  }
  func dismissSuggestion() async {
    guard let suggestion = companion.suggestion else { return }
    companion.recovery.suppressed.insert(suggestion.id)
    companion.suggestion = nil
    await persistCompanion()
    await recordDelivery(suggestion, disposition: "dismissed")
  }
  @discardableResult func recordDelivery(_ result: HelpResult, disposition: String = "shown") async
    -> Bool
  {
    guard model.bootstrap?.account.id == accountID, !companion.completing else { return false }
    if (result.deliveries ?? []).contains(disposition) { return true }
    let receiptKey = key + ":receipts"
    do {
      let receipts = try await model.disk.enqueueReceipt(
        key: receiptKey, receipt: DeliveryReceipt(helpId: result.id, disposition: disposition))
      // The durable local intent precedes UI presentation. Keep the queue through completion for conservative exposure.
      if !model.fixture && disposition != "uncertain" {
        for offset in stride(from: 0, to: receipts.count, by: 100) {
          let batch = Array(receipts[offset..<min(offset + 100, receipts.count)])
          let _: EmptyResponse = try await model.api.send(
            "challenges/\(challenge.id)/deliveries", method: "POST",
            body: DeliveryInput(receipts: batch))
          try await model.disk.acknowledgeReceipts(key: receiptKey, ids: Set(batch.map(\.id)))
        }
      }
    } catch {
      return false
    }
    return true
  }
  func tickCompanion() async {
    guard model.bootstrap?.account.id == accountID, loaded, finished == nil, !companion.completing
    else { return }
    if let suggestion = companion.suggestion, !companion.matches(suggestion, answer: answer) {
      companion.suggestion = nil
    }
    let blocked =
      working || locked || contextBusy || composing || running != nil
      || (!model.fixture && model.hasPendingWrites) || model.conflict != nil
    if model.fixture {
      companion.context.digest = InterventionPolicy.digest(answer)
      companion.context.cycle =
        companion.context.digest + (companion.context.decisions.last?.id ?? "")
    } else if companion.foreground, !companion.modal, !blocked, companion.settled,
      companion.unavailable == nil, mode != .solo,
      companion.context.digest != InterventionPolicy.digest(answer)
    {
      await refreshHelp()
    }
    if running == nil { companion.requestingSince = nil }
    if companion.foreground, !companion.modal, !composing, companion.settled, mode != .solo,
      !contextBusy,
      let latest = help.last(where: {
        $0.status == "completed" && !($0.body ?? "").isEmpty && $0.outcome != "no_intervention"
      }),
      !companion.recovery.suppressed.contains(latest.id), companion.matches(latest, answer: answer),
      localCaptures[latest.id] == companion.generation, companion.suggestion?.id != latest.id
    {
      guard await recordDelivery(latest, disposition: "uncertain") else { return }
      // Recheck after the disk/network suspension: the user may have resumed typing or left the workspace.
      if companion.foreground, !companion.modal, !composing, companion.settled,
        !companion.completing, mode != .solo,
        companion.matches(latest, answer: answer), localCaptures[latest.id] == companion.generation
      {
        companion.replacing = companion.suggestion != nil
        companion.suggestion = latest
        await recordDelivery(latest)
      }
    }
    guard !blocked, companion.foreground, !companion.modal, mode != .solo else { return }
    if companion.pendingGuided {
      companion.pendingGuided = false
      if !companion.recovery.guidedCycles.contains(companion.context.cycle) {
        await request("guide", trigger: "guided_entry")
      }
      return
    }
    if let trigger = companion.eligible(
      answer: answer, enabled: model.fixture || challenge.automaticCompanion == true,
      blocked: blocked)
    {
      await request(mode == .guided ? "guide" : "nudge", trigger: trigger)
    }
  }
}
