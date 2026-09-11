import Foundation
import SwiftData

@Model final class StoredDraft {
  @Attribute(.unique) var key: String
  var account: String
  var challengeID: String
  var answer: String
  var serverAnswer: String
  var revision: Int
  var pendingKind: String
  var command: String
  var conflict: Bool
  init(account: String, challengeID: String, answer: String, revision: Int) {
    key = account + ":" + challengeID
    self.account = account
    self.challengeID = challengeID
    self.answer = answer
    serverAnswer = answer
    self.revision = revision
    pendingKind = ""
    command = UUID().uuidString
    conflict = false
  }
}
@Model final class CachedPayload {
  @Attribute(.unique) var key: String
  var payload: Data
  init(key: String, payload: Data) {
    self.key = key
    self.payload = payload
  }
}
enum StoreV1: VersionedSchema {
  static let versionIdentifier = Schema.Version(1, 0, 0)
  static var models: [any PersistentModel.Type] { [StoredDraft.self, CachedPayload.self] }
}
enum StoreMigrations: SchemaMigrationPlan {
  static var schemas: [any VersionedSchema.Type] { [StoreV1.self] }
  static var stages: [MigrationStage] { [] }
}
struct LocalDraft: Sendable {
  var challengeID: String
  var answer: String
  var serverAnswer: String
  var revision: Int
  var kind: String
  var command: String
  var conflict: Bool
}
@ModelActor actor DiskStore {
  private func row(account: String, id: String) throws -> StoredDraft? {
    let key = account + ":" + id
    return try modelContext.fetch(
      FetchDescriptor<StoredDraft>(predicate: #Predicate { $0.key == key })
    ).first
  }
  func load(account: String, challenge: Challenge) throws -> LocalDraft {
    let existing = try row(account: account, id: challenge.id)
    let value =
      existing
      ?? StoredDraft(
        account: account, challengeID: challenge.id, answer: challenge.session?.answer ?? "",
        revision: challenge.session?.revision ?? 0)
    if existing == nil {
      modelContext.insert(value)
    } else if value.pendingKind.isEmpty, let remote = challenge.session, remote.revision >= value.revision {
      value.answer = remote.answer
      value.serverAnswer = remote.answer
      value.revision = remote.revision
    }
    try modelContext.save()
    return snapshot(value)
  }
  func save(account: String, id: String, answer: String, completing: Bool = false) throws {
    guard let value = try row(account: account, id: id) else {
      throw APIError(
        code: "draft_missing", message: "Reopen this session before editing.", status: 0)
    }
    if value.pendingKind == "skipped" { return }
    if value.answer == answer && !completing { return }
    value.answer = answer
    value.pendingKind = completing ? "complete" : "draft"
    value.command = UUID().uuidString
    try modelContext.save()
  }
  func pending(account: String) throws -> [LocalDraft] {
    try modelContext.fetch(
      FetchDescriptor<StoredDraft>(
        predicate: #Predicate { $0.account == account && $0.pendingKind != "" && $0.pendingKind != "skipped" })
    ).map(snapshot)
  }
  func acknowledge(account: String, sent: LocalDraft, revision: Int) throws {
    guard let value = try row(account: account, id: sent.challengeID) else { return }
    value.revision = revision
    value.serverAnswer = sent.answer
    if value.command == sent.command { value.pendingKind = "" }
    try modelContext.save()
  }
  func markConflict(account: String, id: String) throws {
    guard let value = try row(account: account, id: id) else { return }
    value.conflict = true
    try modelContext.save()
  }
  func resolve(account: String, challenge: Challenge, keepLocal: Bool) throws {
    guard let value = try row(account: account, id: challenge.id) else { return }
    value.serverAnswer = challenge.session?.answer ?? ""
    value.revision = challenge.session?.revision ?? 0
    value.conflict = false
    if !keepLocal {
      value.answer = value.serverAnswer
      value.pendingKind = ""
    } else {
      value.pendingKind = "draft"
      value.command = UUID().uuidString
    }
    try modelContext.save()
  }
  func cache(key: String, data: Data) throws {
    if let value = try modelContext.fetch(
      FetchDescriptor<CachedPayload>(predicate: #Predicate { $0.key == key })
    ).first {
      value.payload = data
    } else {
      modelContext.insert(CachedPayload(key: key, payload: data))
    }
    try modelContext.save()
  }
  func cached(key: String) throws -> Data? {
    try modelContext.fetch(FetchDescriptor<CachedPayload>(predicate: #Predicate { $0.key == key }))
      .first?.payload
  }
  func enqueueReceipt(key: String, receipt: DeliveryReceipt) throws -> [DeliveryReceipt] {
    var receipts =
      try cached(key: key).flatMap { try JSONDecoder().decode([DeliveryReceipt].self, from: $0) }
      ?? []
    if !receipts.contains(where: {
      $0.helpId == receipt.helpId && $0.disposition == receipt.disposition
    }) {
      receipts.append(receipt)
      try cache(key: key, data: JSONEncoder().encode(receipts))
    }
    return receipts
  }
  func acknowledgeReceipts(key: String, ids: Set<String>) throws {
    let receipts =
      try cached(key: key).flatMap { try JSONDecoder().decode([DeliveryReceipt].self, from: $0) }
      ?? []
    try cache(key: key, data: JSONEncoder().encode(receipts.filter { !ids.contains($0.id) }))
  }
  func prepareInterviewAnswer(account: String, id: String, answer: String, command: String, promptID: String, style: InterviewStyle) throws -> PendingInterviewCommand {
    guard let draft = try row(account: account, id: id), !draft.conflict, !["complete", "skipped"].contains(draft.pendingKind) else {
      throw APIError(code: "sync_pending", message: "Review the current draft before sending.", status: 409)
    }
    draft.answer = answer
    draft.pendingKind = "draft"
    draft.command = command
    let pending = PendingInterviewCommand(command: command, input: InterviewInput(promptId: promptID, kind: "answer", revision: draft.revision, text: answer, style: style, saveDraft: true))
    try cache(key: "interview:" + account + ":" + id + ":pending", data: JSONEncoder().encode(pending))
    return pending
  }
  func acknowledgeInterviewAnswer(account: String, id: String, text: String, revision: Int) throws {
    guard let draft = try row(account: account, id: id), draft.pendingKind == "draft", draft.answer == text, !draft.conflict else { return }
    draft.answer = ""; draft.serverAnswer = ""; draft.revision = revision; draft.pendingKind = ""
    try modelContext.save()
  }
  func pendingSkips(account: String) throws -> [String] {
    try cached(key: "skips:" + account).flatMap { try JSONDecoder().decode([String].self, from: $0) } ?? []
  }
  func queueSkip(account: String, id: String, answer: String? = nil) throws {
    if let answer, let draft = try row(account: account, id: id) { draft.answer = answer }
    var ids = try pendingSkips(account: account)
    if !ids.contains(id) { ids.append(id) }
    try cache(key: "skips:" + account, data: JSONEncoder().encode(ids))
  }
  func acknowledgeSkip(account: String, id: String) throws {
    // Retain the answer locally, but stop trying to upload edits to a retired attempt.
    if let draft = try row(account: account, id: id) { draft.pendingKind = "skipped"; draft.conflict = false }
    let ids = try pendingSkips(account: account).filter { $0 != id }
    try cache(key: "skips:" + account, data: JSONEncoder().encode(ids))
  }
  func enqueueEligibility(account: String, command: EligibilityCommand) throws {
    let key = "eligibility:" + account
    var values = try cached(key: key).flatMap { try JSONDecoder().decode([EligibilityCommand].self, from: $0) } ?? []
    if !values.contains(where: { $0.questionId == command.questionId }) { values.append(command) }
    try cache(key: key, data: JSONEncoder().encode(values))
  }
  func acknowledgeEligibility(account: String, command: String) throws {
    let key = "eligibility:" + account
    let values = try cached(key: key).flatMap { try JSONDecoder().decode([EligibilityCommand].self, from: $0) } ?? []
    try cache(key: key, data: JSONEncoder().encode(values.filter { $0.id != command }))
  }
  func clearPractice(account: String) throws {
    for value in try modelContext.fetch(FetchDescriptor<StoredDraft>(predicate: #Predicate { $0.account == account })) { modelContext.delete(value) }
    for value in try modelContext.fetch(FetchDescriptor<CachedPayload>()) where value.key.contains(":" + account + ":") || value.key.hasSuffix(":" + account) || value.key.hasPrefix(account + ":") { modelContext.delete(value) }
    try modelContext.save()
  }
  func clear() throws {
    try modelContext.delete(model: StoredDraft.self)
    try modelContext.delete(model: CachedPayload.self)
    try modelContext.save()
  }
  private func snapshot(_ row: StoredDraft) -> LocalDraft {
    LocalDraft(
      challengeID: row.challengeID, answer: row.answer, serverAnswer: row.serverAnswer,
      revision: row.revision, kind: row.pendingKind, command: row.command, conflict: row.conflict)
  }
}
