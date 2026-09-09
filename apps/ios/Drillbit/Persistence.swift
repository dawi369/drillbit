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
    } else if value.pendingKind.isEmpty, let remote = challenge.session {
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
    if value.answer == answer && !completing { return }
    value.answer = answer
    value.pendingKind = completing ? "complete" : "draft"
    value.command = UUID().uuidString
    try modelContext.save()
  }
  func pending(account: String) throws -> [LocalDraft] {
    try modelContext.fetch(
      FetchDescriptor<StoredDraft>(
        predicate: #Predicate { $0.account == account && $0.pendingKind != "" })
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
