import Foundation
import SwiftData
import Testing
#if canImport(DrillbitCore)
@testable import DrillbitCore
#else
@testable import Drillbit
#endif
struct InterviewTests {
  @Test func commandAndDraftSurviveStoreRecreation() async throws {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".store")
    defer { for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
    let config = ModelConfiguration(url: url)
    let command = PendingInterviewCommand(command: UUID().uuidString, input: InterviewInput(promptId: "turn-one", kind: "answer", revision: 7, text: "A stable key per notification"))
    let challenge = Challenge(id:"question",lifecycle:"in_progress",title:"Queue",prompt:"How?",topic:"Backend",session:SessionDraft(answer:"",revision:7))
    do {
      let container = try ModelContainer(for: Schema(StoreV1.models), configurations: config)
      let disk = DiskStore(modelContainer: container)
      _ = try await disk.load(account:"a",challenge:challenge)
      try await disk.save(account:"a",id:challenge.id,answer:command.input.text)
      try await disk.cache(key:"interview:a:question:pending",data:JSONEncoder().encode(command))
    }
    let container = try ModelContainer(for: Schema(StoreV1.models), configurations: config)
    let disk = DiskStore(modelContainer: container)
    let data = try #require(await disk.cached(key:"interview:a:question:pending"))
    let restored = try JSONDecoder().decode(PendingInterviewCommand.self,from:data)
    #expect(restored.command == command.command)
    #expect(restored.input.promptId == "turn-one")
    #expect(try await disk.load(account:"a",challenge:challenge).answer == command.input.text)
    #expect(try await disk.cached(key:"interview:b:question:pending") == nil)
  }
  @Test func lateDetailCannotRollBackAcknowledgedDraft() async throws {
    let container = try ModelContainer(for: Schema(StoreV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let disk = DiskStore(modelContainer: container)
    let old = Challenge(id:"q",lifecycle:"in_progress",title:"Queue",prompt:"How?",topic:"Backend",session:SessionDraft(answer:"old",revision:1))
    _ = try await disk.load(account:"a",challenge:old)
    try await disk.save(account:"a",id:"q",answer:"new answer")
    let sent = try #require(await disk.pending(account:"a").first)
    try await disk.acknowledge(account:"a",sent:sent,revision:2)
    let restored = try await disk.load(account:"a",challenge:old)
    #expect(restored.answer == "new answer")
    #expect(restored.revision == 2)
  }
  @Test func stylesRemainIndependentOfLevelAndOldPreparationDecodes() throws {
    let old = Data(#"{"focus":"Backend","kind":"design","difficulty":"hard","instruction":""}"#.utf8)
    #expect(try JSONDecoder().decode(PreparationInput.self,from:old).interviewStyle == nil)
    for style in InterviewStyle.allCases {
      let input = PreparationInput(interviewStyle:style,focus:"Backend",kind:"design",difficulty:"hard",engineeringLevel:"senior")
      let restored = try JSONDecoder().decode(PreparationInput.self,from:JSONEncoder().encode(input))
      #expect(restored.interviewStyle == style)
      #expect(restored.engineeringLevel == "senior")
    }
  }
}
