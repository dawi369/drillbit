import Foundation
import SwiftData
import Testing
#if canImport(DrillbitCore)
@testable import DrillbitCore
#else
@testable import Drillbit
#endif
struct InterviewTests {
  @Test func voiceFragmentsPreserveSpacesOverlapAndStableRows() {
    let first = VoiceFragment(id:"one",sequence:0,speaker:"user",text:"Use a",startMs:0,endMs:500)
    let overlapping = VoiceFragment(id:"two",sequence:1,speaker:"assistant",text:"Mm-hm.",startMs:300,endMs:600)
    let next = VoiceFragment(id:"three",sequence:2,speaker:"user",text:" queue.",startMs:500,endMs:900)
    let rows = VoiceTranscript.rows([first,overlapping,next])
    #expect(rows.map(\.id) == ["one","two"])
    #expect(rows[0].text == "Use a queue.")
    #expect(rows[1].text == "Mm-hm.")
  }

  @Test func atomicInterviewSubmissionRetainsTextUntilAcknowledged() async throws {
    let container = try ModelContainer(for: Schema(StoreV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let disk = DiskStore(modelContainer: container)
    let challenge = Challenge(id: "q", lifecycle: "in_progress", title: "Queue", prompt: "How?", topic: "System design", session: SessionDraft(answer: "Old", revision: 2))
    _ = try await disk.load(account: "a", challenge: challenge)
    let command = try await disk.prepareInterviewAnswer(account: "a", id: "q", answer: "New", command: "cmd", promptID: "original", style: .standard)
    #expect(command.input.revision == 2 && command.input.saveDraft == true)
    #expect(try await disk.load(account: "a", challenge: challenge).answer == "New")
    #expect(try await disk.cached(key: "interview:a:q:pending") != nil)
    #expect(try await disk.cached(key: "interview:b:q:pending") == nil)
    try await disk.acknowledgeInterviewAnswer(account: "a", id: "q", text: "Different", revision: 3)
    #expect(try await disk.pending(account: "a").first?.answer == "New")
    try await disk.acknowledgeInterviewAnswer(account: "a", id: "q", text: "New", revision: 3)
    #expect(try await disk.pending(account: "a").isEmpty)
    #expect(try await disk.load(account: "a", challenge: challenge).answer == "")
  }
  @Test func skipQueueIsDurableScopedAndKeepsAnswer() async throws {
    let container = try ModelContainer(for: Schema(StoreV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let disk = DiskStore(modelContainer: container)
    let challenge = Challenge(id: "q", lifecycle: "in_progress", title: "Queue", prompt: "How?", topic: "System design", session: SessionDraft(answer: "", revision: 0))
    _ = try await disk.load(account: "a", challenge: challenge)
    try await disk.save(account: "a", id: "q", answer: "Keep this reasoning")
    try await disk.queueSkip(account: "a", id: "q")
    try await disk.queueSkip(account: "a", id: "q")
    let reopened = DiskStore(modelContainer: container)
    #expect(try await reopened.pendingSkips(account: "a") == ["q"])
    #expect(try await reopened.pendingSkips(account: "b").isEmpty)
    #expect(try await reopened.pending(account: "a").first?.answer == "Keep this reasoning")
    try await reopened.acknowledgeSkip(account: "a", id: "q")
    #expect(try await reopened.pendingSkips(account: "a").isEmpty)
    #expect(try await reopened.pending(account: "a").isEmpty)
    #expect(try await reopened.load(account: "a", challenge: challenge).answer == "Keep this reasoning")
  }
  @Test func practiceResetIsAccountScopedAndClearsPendingCommands() async throws {
    let container = try ModelContainer(for: Schema(StoreV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let store = DiskStore(modelContainer: container)
    let question = Challenge(id: "q", lifecycle: "in_progress", title: "Queue", prompt: "How?", topic: "System design", session: SessionDraft(answer: "", revision: 0))
    for account in ["a", "b"] { _ = try await store.load(account: account, challenge: question); try await store.save(account: account, id: "q", answer: "Pending"); try await store.cache(key: "library:" + account, data: Data("cached".utf8)); try await store.cache(key: "interview:" + account + ":q:pending", data: Data("command".utf8)) }
    try await store.clearPractice(account: "a")
    #expect(try await store.pending(account: "a").isEmpty)
    #expect(try await store.cached(key: "interview:a:q:pending") == nil)
    #expect(try await store.pending(account: "b").count == 1)
    #expect(try await store.cached(key: "library:b") != nil)
    #expect(try await store.cached(key: "interview:b:q:pending") != nil)
  }
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
      try await disk.queueSkip(account: "a", id: challenge.id)
    }
    let container = try ModelContainer(for: Schema(StoreV1.models), configurations: config)
    let disk = DiskStore(modelContainer: container)
    let data = try #require(await disk.cached(key:"interview:a:question:pending"))
    let restored = try JSONDecoder().decode(PendingInterviewCommand.self,from:data)
    #expect(try await disk.pendingSkips(account: "a") == [challenge.id])
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

#if !canImport(DrillbitCore)
@MainActor struct InterviewSubmissionTests {
  @Test func liveVoiceKeepsDraftAndRestoresWithoutAnotherRequest() async throws {
    let container = try ModelContainer(for: Schema(StoreV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly:true))
    let challenge = Challenge(id:"live",lifecycle:"in_progress",title:"Queue",prompt:"How?",topic:"System design",session:SessionDraft(answer:"",revision:0))
    let model = AppModel(container:container,baseURL:URL(string:"https://interview.test")!,fixture:true,monitorNetwork:false)
    model.bootstrap = Bootstrap(account:.init(id:"a",status:"active"),settings:PracticeSettings(),challenge:challenge,jobs:[])
    let interview=InterviewController(model:model,challenge:challenge)
    await interview.load(); interview.edit("Keep this draft")
    let voice=LiveVoice(interview:interview); interview.voice=voice
    await voice.start(); #expect(voice.phase == .active)
    await voice.fixtureSpeech()
    #expect(interview.answer == "Keep this draft")
    #expect(!interview.canFinish)
    #expect(try await model.disk.hasPendingVoice(account:"a"))
    #expect(try await !model.disk.hasPendingVoice(account:"b"))
    await voice.end()
    #expect(voice.phase == .idle)
    #expect(interview.state.turns.first?.voice?.count == 2)
    #expect(try await !model.disk.hasPendingVoice(account:"a"))
    let restored=InterviewController(model:model,challenge:challenge)
    await restored.load()
    let restoredVoice=LiveVoice(interview:restored); await restoredVoice.restore()
    #expect(restoredVoice.phase == .idle)
    #expect(restored.state.turns.first?.voice?.count == 2)
    #expect(restored.answer == "Keep this draft")
  }

  @Test func finalizedVoiceAnswersUseTheDurableInterviewTranscript() async throws {
    let container = try ModelContainer(for: Schema(StoreV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let challenge = Challenge(id: "voice-question", lifecycle: "in_progress", title: "Queue", prompt: "How?", topic: "Backend", session: SessionDraft(answer: "", revision: 0))
    let model = AppModel(container: container, baseURL: URL(string: "https://interview.test")!, fixture: true, monitorNetwork: false)
    model.bootstrap = Bootstrap(account: .init(id: "a", status: "active"), settings: PracticeSettings(), challenge: challenge, jobs: [])
    let controller = InterviewController(model: model, challenge: challenge)
    await controller.load()
    let event = FinalizedInterviewAnswer(id: UUID(), account: "a", challengeID: challenge.id, promptID: "original", text: "Use a durable queue")
    var stale = event; stale.account = "other"
    await #expect(throws: APIError.self) { try await controller.receiveFinalizedAnswer(stale) }
    controller.edit("A written draft")
    await #expect(throws: APIError.self) { try await controller.receiveFinalizedAnswer(event) }
    #expect(controller.answer == "A written draft")
    controller.edit("")
    var padded = event; padded.text = "  " + event.text + "\n"
    try await controller.receiveFinalizedAnswer(padded)
    try await controller.receiveFinalizedAnswer(padded)
    try await controller.receiveFinalizedAnswer(event)
    #expect(controller.state.turns.count == 1)
    #expect(controller.state.turns.first?.text == event.text)
    #expect(controller.state.turns.first?.result?.outcome == "follow_up")
    #expect(controller.answer.isEmpty)
    var duplicate = event; duplicate.text = "Different answer"
    await #expect(throws: APIError.self) { try await controller.receiveFinalizedAnswer(duplicate) }
    var oldPrompt = event; oldPrompt.id = UUID()
    await #expect(throws: APIError.self) { try await controller.receiveFinalizedAnswer(oldPrompt) }
    controller.acceptsVoiceInput = false
    await #expect(throws: APIError.self) { try await controller.receiveFinalizedAnswer(event) }
    controller.acceptsVoiceInput = true
    controller.finished = challenge
    await #expect(throws: APIError.self) { try await controller.receiveFinalizedAnswer(event) }
    controller.finished = nil
    let restored = InterviewController(model: model, challenge: controller.challenge)
    await restored.load()
    #expect(restored.state.turns.first?.id == event.id.uuidString)
    #expect(restored.state.turns.first?.text == event.text)
    #expect(restored.state.turns.first?.result != nil)
  }
  @Test(arguments: ["autosave", "offline", "unrelated"]) func shareWaitsForAutosaveAndSubmitsLatestAnswer(scenario: String) async throws {
    let container = try ModelContainer(for: Schema(StoreV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    var remote = Challenge(id:"q",lifecycle:"in_progress",title:"Queue",prompt:"How?",topic:"Backend",session:SessionDraft(answer:"",revision:0))
    var writeStarted = false
    var shares = 0
    var failuresRemaining = scenario == "offline" ? 1 : 0
    let url = URL(string:"https://interview.test")!
    let client = APIClient(baseURL:url,tokenProvider:{ "test" },transport:{ request in
      let path = request.url!.path
      var data: Data
      if path.contains("/other") { throw URLError(.notConnectedToInternet) }
      if path.hasSuffix("/bootstrap") {
        data = try JSONEncoder().encode(Bootstrap(account: .init(id: "a", status: "active"), settings: PracticeSettings(), challenge: remote, jobs: []))
      } else if path.hasSuffix("/draft") {
        if failuresRemaining > 0 { failuresRemaining -= 1; throw URLError(.notConnectedToInternet) }
        writeStarted = true
        try await Task.sleep(for:.milliseconds(150))
        let input = try JSONDecoder().decode(DraftWrite.self,from:request.httpBody!)
        remote.session = SessionDraft(answer:input.answer,revision:input.revision+1)
        data = try JSONEncoder().encode(RevisionResponse(revision:input.revision+1))
      } else if path.hasSuffix("/interview") {
        if failuresRemaining > 0 { failuresRemaining -= 1; throw URLError(.notConnectedToInternet) }
        let input = try JSONDecoder().decode(InterviewInput.self,from:request.httpBody!)
        #expect(input.text == "Latest answer")
        #expect(input.style == .standard)
        #expect(input.revision == remote.session?.revision)
        shares += 1
        remote.session = SessionDraft(answer:"",revision:input.revision+1)
        remote.interview = InterviewState(prompt:"Next question")
        data = try JSONEncoder().encode(remote.interview!)
      } else { data = try JSONEncoder().encode(remote) }
      return (data,HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!)
    })
    let model = AppModel(container:container,baseURL:url,fixture:false,client:client,monitorNetwork:false)
    model.bootstrap = Bootstrap(account:.init(id:"a",status:"active"),settings:PracticeSettings(),challenge:remote,jobs:[])
    let interview = InterviewController(model:model,challenge:remote)
    await interview.load()
    await interview.selectStyle(.quick)
    let restored = InterviewController(model:model,challenge:remote)
    await restored.load()
    #expect(restored.style == .standard)
    var autosave: Task<Void, Never>?
    if scenario == "autosave" {
      try await model.save(remote,answer:"Earlier answer")
      autosave = Task { await model.sync() }
      while !writeStarted { await Task.yield() }
    }
    if scenario == "unrelated" {
      var other = remote; other.id = "other"
      _ = try await model.disk.load(account:"a",challenge:other)
      try await model.save(other,answer:"Unsent work on another question")
    }
    interview.edit("Latest answer")
    await interview.submit("answer")
    await autosave?.value
    if scenario == "offline" {
      #expect(shares == 0)
      #expect(interview.pending?.input.text == "Latest answer")
      #expect(try await model.disk.cached(key: interview.key + ":pending") != nil)
      await interview.retry()
    }
    #expect(shares == 1)
    #expect(interview.failure == nil)
  }
}
#endif

struct InterviewDocumentTests {
  @Test func eachFollowUpAppearsOnceAndHelpStaysWithItsQuestion() throws {
    let help = InterviewTurn(id:"help",ordinal:0,kind:"hint",prompt:"Original",text:"",createdAt:"now",jobId:"help",status:"completed",result:InterviewResponse(outcome:"reply",text:"Consider retries"))
    let answer = InterviewTurn(id:"answer",ordinal:1,kind:"answer",prompt:"Original",text:"Use a queue",createdAt:"now",jobId:"answer",status:"completed",result:InterviewResponse(outcome:"follow_up",text:"What if it fails?"))
    let second = InterviewTurn(id:"second",ordinal:2,kind:"answer",prompt:"What if it fails?",text:"Retry",createdAt:"now",jobId:"second",status:"failed")
    let groups = InterviewExchange.document(original:"Original",state:InterviewState(prompt:"What if it fails?",turns:[second,answer,help]))
    #expect(groups.map(\.id) == ["original","answer","second"])
    #expect(groups.map(\.prompt) == ["Original","What if it fails?",""])
    #expect(groups[0].turns.map(\.id) == ["help","answer"])
    #expect(groups[1].turns.map(\.id) == ["second"])
    #expect(groups[1].hasAnswer)
  }
  @Test func foldingAndReadingPositionSurviveStoreRecreation() async throws {
    let container = try ModelContainer(for: Schema(StoreV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly:true))
    let first = DiskStore(modelContainer:container)
    let saved = InterviewReadingState(collapsed:["original","answer","second"],offset:340)
    try await first.cache(key:"interview:a:q:reading",data:JSONEncoder().encode(saved))
    let reopened = DiskStore(modelContainer:container)
    let data = try #require(await reopened.cached(key:"interview:a:q:reading"))
    let value = try JSONDecoder().decode(InterviewReadingState.self,from:data)
    #expect(value.collapsed == saved.collapsed)
    #expect(value.offset == 340)
    #expect(try await reopened.cached(key:"interview:b:q:reading") == nil)
  }
}
