import SwiftUI
import AVFAudio
import OSLog
@preconcurrency import WebRTC

private struct VoiceConnection: Decodable { var id: String; var sdp: String; var expiresAt: String; var sessionSeconds: Int? }
private struct VoiceStart: Encodable { var sdp: String; var revision: Int; var guidanceMode: GuidanceMode; var practiceProfile: PracticeProfile? }
private struct VoiceEvents: Codable { var fragments: [VoiceFragment]; var closed: Bool; var finalized: Bool; var usageSeconds: Double? }
private struct VoiceAck: Decodable { var accepted: [String] }
private struct VoiceDelegation: Encodable { var id: String }
private struct VoiceReply: Decodable { var text: String; var step: Int? }
private struct VoiceOutbox: Codable {
  var id: String
  var fragments: [VoiceFragment] = []
  var closed = false
  var finalized = false
  var usageSeconds: Double? = nil
}

@MainActor @Observable final class LiveVoice {
  nonisolated static let log = Logger(subsystem: "dawi.drillbit", category: "voice")
  /// Routes to the loudspeaker unless something external (headphones, Bluetooth, CarPlay) is the output.
  nonisolated static func keepOnSpeaker() {
    let session = AVAudioSession.sharedInstance()
    let external: Set<AVAudioSession.Port> = [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .carAudio, .airPlay, .usbAudio, .HDMI, .lineOut]
    guard !session.currentRoute.outputs.contains(where: { external.contains($0.portType) }) else { return }
    if session.currentRoute.outputs.contains(where: { $0.portType == .builtInReceiver }) {
      try? session.overrideOutputAudioPort(.speaker)
    }
  }
  enum Phase: Equatable { case idle, connecting, active, ending, unavailable }
  /// Server-issued cap for the next session; the plan decides it.
  var sessionLimit: TimeInterval = 10 * 60
  var phase: Phase = .idle
  var muted = false
  var message: String?
  /// When the provider confirmed the session; drives the room's clock.
  var startedAt: Date?
  /// True only while a delegated reasoning request is actually in flight.
  var thinking = false
  /// A session nobody speaks in still bills every open second, so it ends after this long without speech from
  /// either side. Any transcript or an unmute resets the clock.
  static let idleLimit: TimeInterval = 180
  /// The last thirty seconds before a quiet session ends.
  var idleWarning = false
  private var lastActivity = Date()
  private var idleWatch: Task<Void,Never>?
  var isOpen: Bool { phase != .idle }
  var blocksText: Bool { [.connecting,.active,.ending].contains(phase) || outbox != nil }
  let levels = VoiceLevels()
  private var meter: Task<Void, Never>?
  private let interview: InterviewController
  private var transport: NativeVoiceTransport?
  private var prepared: (link: NativeVoiceTransport, offer: Task<String, Error>, date: Date)?
  private var outbox: VoiceOutbox?
  private var syncing = false
  private var acknowledged: Set<String> = []
  private var eventTask: Task<Void,Never>?
  private var deadline: Task<Void,Never>?
  private var closeDeadline: Task<Void,Never>?
  private var generation = UUID()
  private var seen: Set<String> = []
  private var delegations: Set<String> = []
  private var guidanceDeliveries: [String: VoiceGuidanceDelivery] = [:]
  private var interruptedObserver: NSObjectProtocol?
  private var routeObserver: NSObjectProtocol?
  private var key: String { interview.key + ":voice-outbox" }
  init(interview: InterviewController) { self.interview = interview }

  func restore() async {
    if let data = try? await interview.model.disk.cached(key:key),
       var pending = try? JSONDecoder().decode(VoiceOutbox.self,from:data) {
      pending.closed = true // No microphone or paid session automatically restarts.
      outbox = pending
      present(pending.fragments, id:pending.id)
      await sync()
      if outbox != nil { phase = .unavailable }
    }
  }
  // Prepare ICE locally only; opening an interview must never create a billed session.
  func prepareIfAllowed() {
    guard !interview.model.fixture, phase == .idle, !blocksText, prepared == nil,
          interview.currentAccount, interview.acceptsVoiceInput,
          AVAudioApplication.shared.recordPermission == .granted,
          let capability = interview.model.bootstrap?.capabilities?.voice,
          capability.available, capability.isFresh() else { return }
    if let warm = interview.model.takeVoiceWarmup() { prepared = warm; return }
    let link = NativeVoiceTransport()
    prepared = (link, Task { try await link.offer() }, Date())
  }
  func discardPreparation() {
    prepared?.offer.cancel()
    prepared?.link.close()
    prepared = nil
  }
  func start() async {
    guard !blocksText, !interview.locked, interview.currentAccount, interview.acceptsVoiceInput else { return }
    let epoch = UUID(); generation = epoch
    phase = .connecting; message = nil; muted = true; startedAt = nil; thinking = false; seen = []; delegations = []; guidanceDeliveries = [:]; acknowledged = []
    do {
      #if DEBUG
      if interview.model.fixture, ProcessInfo.processInfo.arguments.contains("--fixture-voice-connecting") {
        try await Task.sleep(for: .seconds(3))
        guard generation == epoch else { return }
      }
      #endif
      try await interview.flush()
      let draft = try await interview.model.disk.load(account:interview.account,challenge:interview.challenge)
      guard interview.model.fixture || (draft.kind.isEmpty && !draft.conflict) else {
        throw APIError(code:"draft_pending",message:"Voice couldn’t start yet. Try again shortly.",status:0)
      }
      guard generation == epoch, interview.currentAccount, interview.acceptsVoiceInput else { return }
      if !interview.model.fixture {
        guard AVAudioApplication.shared.recordPermission == .granted else {
          throw APIError(code:"microphone_denied",message:"Microphone access is required for live voice.",status:0)
        }
      }
      let id = UUID().uuidString
      outbox = VoiceOutbox(id:id)
      try await persist()
      guard generation == epoch, interview.currentAccount, interview.acceptsVoiceInput else { return }
      if interview.model.fixture {
        if let seconds = interview.model.bootstrap?.capabilities?.voice?.sessionSeconds { sessionLimit = TimeInterval(seconds) }
        phase = .active
        startedAt = .now
        present([],id:id)
        #if DEBUG
        startFixtureMeter(epoch: epoch)
        #endif
        return
      }
      interruptedObserver = NotificationCenter.default.addObserver(forName:AVAudioSession.interruptionNotification,object:nil,queue:.main) { [weak self] _ in
        Task { @MainActor in self?.interrupt("Voice paused by an audio interruption. You can start it again.") }
      }
      routeObserver = NotificationCenter.default.addObserver(forName:AVAudioSession.routeChangeNotification,object:nil,queue:.main) { [weak self] note in
        let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
        if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
          Task { @MainActor in self?.interrupt("Your audio device disconnected. Voice has stopped.") }
        }
        // WebRTC reapplies its own session settings when its audio unit starts; that can put the call back on the
        // earpiece. With nothing external attached, the interview belongs on the loudspeaker.
        Self.keepOnSpeaker()
      }
      let audio = AVAudioSession.sharedInstance()
      try audio.setCategory(.playAndRecord,mode:.voiceChat,options:[.defaultToSpeaker,.allowBluetoothHFP])
      try audio.setActive(true)
      Self.keepOnSpeaker()
      if let prepared, Date().timeIntervalSince(prepared.date) > 60 { discardPreparation() }
      let preparation = prepared
      prepared = nil
      var link = preparation?.link ?? NativeVoiceTransport()
      transport = link
      let offer: String
      if let preparation {
        do { offer = try await preparation.offer.value }
        catch {
          guard generation == epoch else { link.close(); return }
          // A speculative local preparation must not make explicit Start fail.
          link.close()
          link = NativeVoiceTransport()
          transport = link
          offer = try await link.offer()
        }
      } else { offer = try await link.offer() }
      guard generation == epoch else { link.close(); return }
      link.onEvent = { [weak self] data in self?.enqueue(data,epoch:epoch) }
      link.onFailure = { [weak self] in self?.interrupt("Voice disconnected. Your transcript is preserved.") }
      let result: VoiceConnection = try await interview.model.api.send("challenges/\(interview.challenge.id)/voice",method:"POST",body:VoiceStart(sdp:offer,revision:draft.revision,guidanceMode:interview.mode,practiceProfile:interview.model.settings.practiceProfile),command:id)
      guard generation == epoch else { link.close(); abandon(id); return }
      if let seconds = result.sessionSeconds { sessionLimit = TimeInterval(seconds) }
      try await link.answer(result.sdp)
      guard generation == epoch, phase == .connecting || phase == .active else { link.close(); return }
      link.startAudio()
      // The room opens muted; you unmute when you're ready to talk.
      link.mute(true)
      startMeter(epoch: epoch)
      Task { [weak self] in
        try? await Task.sleep(for:.seconds(10))
        guard let self, self.generation == epoch, self.phase == .connecting else { return }
        self.interrupt("Voice could not finish connecting. Try again.")
      }
      present([],id:id)
      let limit = sessionLimit
      deadline = Task { [weak self] in
        try? await Task.sleep(for:.seconds(limit))
        guard !Task.isCancelled else { return }
        await self?.end()
      }

    } catch {
      guard generation == epoch else { return }
      // Release audio before disk/network recovery, which may be slow or offline.
      cleanup()
      // Startup may have created a server reservation even when its answer was lost.
      if outbox != nil { outbox?.closed = true; try? await persist(); await sync() }
      phase = .unavailable; message = error.localizedDescription
    }
  }
  func toggleMute() {
    guard phase == .active else { return }
    muted.toggle()
    markActivity()
    transport?.mute(muted)
    transport?.send(["type": muted ? "session.input_audio.mute" : "session.input_audio.unmute", "event_id":UUID().uuidString])
  }
  func stopAudioImmediately() {
    discardPreparation()
    // Cancel startup synchronously, before the exit's asynchronous finalization.
    if phase == .connecting { generation = UUID() }
    stopMeter()
    transport?.stopAudio()
  }
  private func startMeter(epoch: UUID) {
    meter?.cancel()
    meter = Task { [weak self] in
      while let self, self.generation == epoch, self.phase == .connecting || self.phase == .active, let transport = self.transport {
        let sample = await transport.audioLevels()
        guard !Task.isCancelled, self.generation == epoch else { break }
        self.levels.input = self.muted ? 0 : Self.perceptual(sample.input)
        self.levels.output = Self.perceptual(sample.output)
        try? await Task.sleep(for: .milliseconds(80))
      }
      self?.levels.reset()
    }
  }
  private func stopMeter() {
    meter?.cancel()
    meter = nil
    levels.reset()
  }
  /// WebRTC reports linear amplitude; speech sits roughly between -50 and -10 dBFS.
  private static func perceptual(_ level: Double) -> Double {
    guard level > 0.0005 else { return 0 }
    return min(1, max(0, (20 * log10(level) + 50) / 40))
  }
  func end() async {
    guard isOpen, phase != .ending else { return }
    idleWatch?.cancel(); idleWarning = false
    let wasConnecting = phase == .connecting
    phase = .ending
    if wasConnecting { generation = UUID() }
    transport?.stopAudio()
    // Cancelled before the line was ever open: nothing was said, so there is no transcript to keep or sync.
    if wasConnecting, transport == nil, outbox?.fragments.isEmpty != false {
      closeDeadline?.cancel(); deadline?.cancel()
      outbox = nil; try? await persist()
      cleanup()
      phase = .idle
      return
    }
    if interview.model.fixture || transport == nil {
      await finalize(confirmed:interview.model.fixture); return
    }
    transport?.send(["type":"session.close","event_id":UUID().uuidString])
    // The line never went live, so no goodbye is coming; waiting for one would only hold the keyboard hostage.
    if wasConnecting, startedAt == nil { await finalize(confirmed:false); return }
    closeDeadline = Task { [weak self] in
      try? await Task.sleep(for:.seconds(5))
      guard !Task.isCancelled else { return }
      await self?.finalize(confirmed:false)
    }
  }
  private func markActivity() { lastActivity = .now; idleWarning = false }
  private func watchIdle(epoch: UUID) {
    idleWatch?.cancel()
    markActivity()
    idleWatch = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(5))
        guard let self, self.generation == epoch, self.phase == .active else { return }
        let quiet = Date().timeIntervalSince(self.lastActivity)
        if quiet >= Self.idleLimit {
          await self.end()
          self.message = "Voice ended after three quiet minutes. Your transcript is saved."
          return
        }
        self.idleWarning = quiet >= Self.idleLimit - 30
      }
    }
  }
  func interrupt(_ reason: String) {
    guard phase == .active || phase == .connecting else { return }
    stopAudioImmediately()
    Task { await end(); message = reason }
  }
  func dismiss() { if !blocksText { phase = .idle; message = nil } }
  /// Startup was cancelled while the server was opening the line. Its outbox may already be gone, so close the
  /// reservation directly; otherwise the next Talk is refused until it expires.
  private func abandon(_ id: String) {
    let api = interview.model.api, path = "challenges/\(interview.challenge.id)/voice/\(id)/events"
    Task { let _: VoiceAck? = try? await api.send(path,method:"POST",body:VoiceEvents(fragments:[],closed:true,finalized:false)) }
  }
  func retrySync() async { await sync(); if outbox == nil { phase = .idle; message = nil } }
  private func enqueue(_ data: Data, epoch: UUID) {
    let prior = eventTask
    eventTask = Task { [weak self] in
      await prior?.value
      guard let self, self.generation == epoch, self.interview.currentAccount else { return }
      await self.receive(data)
    }
  }
  private func receive(_ data: Data) async {
    guard let event = try? JSONSerialization.jsonObject(with:data) as? [String:Any],let type=event["type"] as? String else { return }
    if type == "session.started" {
      if phase == .connecting { phase = .active; startedAt = .now; watchIdle(epoch: generation) }
      if muted { transport?.send(["type": "session.input_audio.mute", "event_id": UUID().uuidString]) }
      return
    }
    if type == "session.closed" { if let usage=event["usage"] as? [String:Any] { outbox?.usageSeconds = usage["seconds"] as? Double }; await finalize(confirmed:true); return }
    if type == "error" {
      // Most provider errors are about one event (a rejected append, a bad field, a turn that was rate-limited)
      // and the session goes on. Only session-level failures end the call.
      let detail = event["error"] as? [String:Any]
      let code = (detail?["code"] as? String) ?? (detail?["type"] as? String) ?? "unknown"
      Self.log.error("live error \(code, privacy: .public): \((detail?["message"] as? String) ?? "", privacy: .public)")
      let fatal = ["session_expired", "session_not_found", "invalid_session", "insufficient_quota", "server_error", "connection_error"]
      if fatal.contains(code) { interrupt("Voice hit a connection problem. Your words are saved; you can start it again.") }
      return
    }
    if type == "session.usage.updated",let usage=event["usage"] as? [String:Any] { outbox?.usageSeconds = usage["seconds"] as? Double; return }
    if ["session.input_transcript.delta","session.output_transcript.delta"].contains(type),
       let id=event["event_id"] as? String, let delta=event["delta"] as? String,
       let start=event["start_ms"] as? Int,let end=event["end_ms"] as? Int, !seen.contains(id), outbox != nil {
      // The provider marks breaths, clicks and laughs in the transcript; they are noise on the page.
      let text = Self.stripNonVerbal(delta)
      let f = VoiceFragment(id:id,sequence:(outbox?.fragments.last?.sequence ?? -1)+1,speaker:type == "session.input_transcript.delta" ? "user":"assistant",text:text,startMs:start,endMs:end)
      outbox?.fragments.append(f); seen.insert(id)
      markActivity()
      do {
        try await persist()
        if let outbox { present(outbox.fragments,id:outbox.id) }
        Task { await sync() }
      } catch { interrupt("Couldn’t save the transcript. Voice has stopped to protect your work.") }
    }
    if type == "session.delegation.created", let d=event["delegation"] as? [String:Any],let id=d["id"] as? String,!delegations.contains(id) {
      delegations.insert(id)
      let epoch=generation
      // One deadline covers transcript synchronization AND reasoning. A slow
      // network task may finish later, but cannot speak after this fallback.
      let deadline = ContinuousClock.now.advanced(by: .seconds(15))
      guidanceDeliveries[id] = VoiceGuidanceDelivery(deadline: deadline)
      thinking = true
      let timeout = Task {
        do { try await Task.sleep(until: deadline, clock: .continuous) } catch { return }
        deliverGuidance(Self.guidanceMissing, id: id, epoch: epoch)
      }
      Task {
        defer { timeout.cancel() }
        do {
          while syncing {
            guard generation == epoch, phase == .active else { return }
            if ContinuousClock.now >= deadline { deliverGuidance(Self.guidanceMissing, id: id, epoch: epoch); return }
            try await Task.sleep(for: .milliseconds(20))
          }
          await sync()
          guard generation == epoch, phase == .active, guidanceDeliveries[id]?.resolved == false else { return }
          // The backend reasons over what it has stored. A sync still catching up gets one more try before giving up on this one.
          if let pending = outbox, !pending.fragments.allSatisfy({ acknowledged.contains($0.id) }) {
            try await Task.sleep(for: .milliseconds(600)); await sync()
          }
          guard generation == epoch, phase == .active, guidanceDeliveries[id]?.resolved == false else { return }
          guard let pending = outbox, pending.fragments.allSatisfy({ acknowledged.contains($0.id) }) else {
            deliverGuidance(Self.guidanceMissing, id: id, epoch: epoch); return
          }
          let reply: VoiceReply = try await interview.model.api.send("challenges/\(interview.challenge.id)/voice/\(pending.id)/delegate", method: "POST", body: VoiceDelegation(id: id))
          if let step = reply.step { interview.noteGuidedStep(step) }
          deliverGuidance(reply.text, id: id, epoch: epoch)
        } catch {
          deliverGuidance(Self.guidanceMissing, id: id, epoch: epoch)
        }
      }
    }
  }
  /// Removes bracketed or parenthesised stage directions such as "[breath]", "(tongue click)" or "*laughs*".
  nonisolated static func stripNonVerbal(_ text: String) -> String {
    let pattern = #"\s*(\[[^\]]{1,40}\]|\([^)]{1,40}\)|\*[^*]{1,40}\*)"#
    let cleaned = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    return cleaned.replacingOccurrences(of: "  ", with: " ")
  }
  /// Whatever reaches the live model here is spoken in its own words, so a fallback is a line the interviewer could
  /// say, never an instruction about what to say. Steering ("say briefly", "offer to continue in text") was being read out.
  static let guidanceMissing = "Let's keep going from where you are."
  private func deliverGuidance(_ text: String, id: String, epoch: UUID) {
    guard generation == epoch, phase == .active, interview.currentAccount,
          guidanceDeliveries[id]?.resolved == false else { return }
    guard let outcome = guidanceDeliveries[id]?.resolve(at: .now) else { return }
    thinking = guidanceDeliveries.values.contains { !$0.resolved }
    let content = outcome == .response ? text : Self.guidanceMissing
    transport?.send(["type":"session.commentary.append", "event_id":UUID().uuidString, "delegation_id":id, "content":content])
  }
  private func present(_ fragments:[VoiceFragment],id:String) {
    if let index=interview.state.turns.firstIndex(where:{$0.id==id}) { interview.state.turns[index].voice = fragments }
    else { interview.state.turns.append(InterviewTurn(id:id,ordinal:(interview.state.turns.last?.ordinal ?? -1)+1,kind:"voice",prompt:interview.state.prompt,text:"",createdAt:Date().ISO8601Format(),jobId:id,status:"completed",voice:fragments)) }
  }
  private func persist() async throws { try await interview.model.disk.cache(key:key,data:JSONEncoder().encode(outbox)) }
  private func sync() async {
    guard !syncing,interview.currentAccount,let captured=outbox else { return }
    syncing = true
    defer { syncing = false }
    do {
      if !interview.model.fixture {
        let pending = captured.fragments.filter { !acknowledged.contains($0.id) }
        for start in stride(from:0,to:pending.count,by:100) {
          guard interview.currentAccount else { throw CancellationError() }
          let batch=Array(pending[start..<min(start+100,pending.count)])
          let ack:VoiceAck = try await interview.model.api.send("challenges/\(interview.challenge.id)/voice/\(captured.id)/events",method:"POST",body:VoiceEvents(fragments:batch,closed:false,finalized:false))
          acknowledged.formUnion(ack.accepted)
        }
        if captured.closed {
          let _:VoiceAck = try await interview.model.api.send("challenges/\(interview.challenge.id)/voice/\(captured.id)/events",method:"POST",body:VoiceEvents(fragments:[],closed:true,finalized:captured.finalized,usageSeconds:captured.usageSeconds))
        }
      }
      guard interview.currentAccount else { return }
      if captured.closed, outbox?.fragments == captured.fragments {
        outbox = nil; try await persist()
        try await interview.model.disk.cache(key:interview.key+":state",data:JSONEncoder().encode(interview.state))
      }
    } catch let error as APIError where error.status == 404 && captured.fragments.isEmpty {
      outbox = nil; try? await persist()
    } catch { message = nil }
  }
  private func finalize(confirmed:Bool) async {
    guard phase != .idle else { return }
    generation = UUID()
    closeDeadline?.cancel(); deadline?.cancel()
    outbox?.closed = true; outbox?.finalized = confirmed
    try? await persist()
    cleanup()
    await sync()
    if syncing { while syncing { try? await Task.sleep(for:.milliseconds(20)) }; await sync() }
    phase = outbox == nil ? .idle : .unavailable
    if outbox == nil { await interview.refresh() }
  }
  private func cleanup() {
    stopMeter()
    transport?.close(); transport = nil
    if let interruptedObserver { NotificationCenter.default.removeObserver(interruptedObserver) }; interruptedObserver = nil
    if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }; routeObserver = nil
    try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
  }
  #if DEBUG
  /// Fixture sessions have no audio; alternate a synthetic speaker envelope.
  private func startFixtureMeter(epoch: UUID) {
    meter?.cancel()
    meter = Task { [weak self] in
      var time = 0.0
      while let self, self.generation == epoch, self.phase == .active {
        let candidateSpeaking = Int(time / 3) % 2 == 0
        let envelope = max(0, 0.5 * sin(time * 7.3) + 0.5 * sin(time * 3.1))
        self.levels.input = candidateSpeaking && !self.muted ? envelope * 0.8 : 0
        self.levels.output = candidateSpeaking ? 0 : envelope * 0.7
        try? await Task.sleep(for: .milliseconds(80))
        if Task.isCancelled { break }
        time += 0.08
      }
      self?.levels.reset()
    }
  }
  func fixtureSpeech() async {
    let events:[[String:Any]] = [
      ["type":"session.input_transcript.delta","event_id":UUID().uuidString,"delta":"I'd use a durable queue.","start_ms":0,"end_ms":1000],
      ["type":"session.output_transcript.delta","event_id":UUID().uuidString,"delta":"Makes sense. What happens when a worker retries?","start_ms":1400,"end_ms":3000]
    ]
    for event in events { await receive(try! JSONSerialization.data(withJSONObject:event)) }
  }
  #endif
}

/// Audio uses native WebRTC media tracks; the data channel carries provider events only.
@MainActor final class NativeVoiceTransport: NSObject, RTCPeerConnectionDelegate, RTCDataChannelDelegate {
  var onEvent: ((Data)->Void)?
  var onFailure: (()->Void)?
  private let factory = RTCPeerConnectionFactory()
  private var peer: RTCPeerConnection?
  private var channel: RTCDataChannel?
  private var track: RTCAudioTrack?
  private var stopped = false
  private var ownsAudio = false
  private var recovery: Task<Void, Never>?
  override init() {
    super.init()
    RTCAudioSession.sharedInstance().useManualAudio = true
    RTCAudioSession.sharedInstance().isAudioEnabled = false
  }
  func startAudio() {
    guard !stopped, peer != nil else { return }
    ownsAudio = true
    track?.isEnabled = true
    // Hand WebRTC the configuration we already set, so enabling its audio unit doesn't swap in its own.
    let session = RTCAudioSession.sharedInstance()
    let configuration = RTCAudioSessionConfiguration.webRTC()
    configuration.category = AVAudioSession.Category.playAndRecord.rawValue
    configuration.mode = AVAudioSession.Mode.voiceChat.rawValue
    configuration.categoryOptions = [.defaultToSpeaker, .allowBluetoothHFP]
    session.lockForConfiguration()
    try? session.setConfiguration(configuration)
    session.unlockForConfiguration()
    session.isAudioEnabled = true
    LiveVoice.keepOnSpeaker()
  }
  func offer() async throws -> String {
    guard !stopped else { throw CancellationError() }
    let config=RTCConfiguration();config.sdpSemantics = .unifiedPlan
    let constraints=RTCMediaConstraints(mandatoryConstraints:nil,optionalConstraints:nil)
    guard let pc=factory.peerConnection(with:config,constraints:constraints,delegate:self) else { throw NSError(domain:"Voice",code:1) }
    peer=pc
    let audio=factory.audioTrack(with:factory.audioSource(with:constraints),trackId:"microphone")
    audio.isEnabled = false
    track=audio;pc.add(audio,streamIds:["drillbit-voice"])
    channel=pc.dataChannel(forLabel:"oai-events",configuration:RTCDataChannelConfiguration());channel?.delegate=self
    let offer:RTCSessionDescription = try await withCheckedThrowingContinuation { c in pc.offer(for:RTCMediaConstraints(mandatoryConstraints:["OfferToReceiveAudio":"true"],optionalConstraints:nil)) { s,e in if let s { c.resume(returning:s) } else { c.resume(throwing:e ?? NSError(domain:"Voice",code:2)) } } }
    try await withCheckedThrowingContinuation { (c:CheckedContinuation<Void,Error>) in pc.setLocalDescription(offer) { e in if let e { c.resume(throwing:e) } else { c.resume() } } }
    for _ in 0..<100 { if pc.iceGatheringState == .complete { break }; try await Task.sleep(for:.milliseconds(50)) }
    guard pc.iceGatheringState == .complete,let sdp=pc.localDescription?.sdp else { throw NSError(domain:"Voice",code:3,userInfo:[NSLocalizedDescriptionKey:"Couldn’t establish an audio connection."]) }
    return sdp
  }
  func answer(_ sdp:String) async throws {
    guard let peer else { return }
    try await withCheckedThrowingContinuation { (c:CheckedContinuation<Void,Error>) in peer.setRemoteDescription(RTCSessionDescription(type:.answer,sdp:sdp)) { e in if let e { c.resume(throwing:e) } else { c.resume() } } }
  }
  func stopAudio() {
    stopped = true
    track?.isEnabled = false
    for receiver in peer?.receivers ?? [] { receiver.track?.isEnabled = false }
    if ownsAudio {
      RTCAudioSession.sharedInstance().isAudioEnabled = false
      ownsAudio = false
    }
  }
  func mute(_ muted:Bool) { guard !stopped else { return }; track?.isEnabled = !muted }
  /// Reads WebRTC's own audio-level statistics; never touches the audio unit.
  func audioLevels() async -> (input: Double, output: Double) {
    guard let peer, !stopped else { return (0, 0) }
    return await withCheckedContinuation { continuation in
      peer.statistics { report in
        var input = 0.0, output = 0.0
        for stat in report.statistics.values where (stat.values["kind"] as? String) == "audio" {
          guard let level = (stat.values["audioLevel"] as? NSNumber)?.doubleValue else { continue }
          if stat.type == "media-source" { input = max(input, level) }
          else if stat.type == "inbound-rtp" { output = max(output, level) }
        }
        continuation.resume(returning: (input, output))
      }
    }
  }
  func send(_ event:[String:Any]) { if let data=try? JSONSerialization.data(withJSONObject:event) { channel?.sendData(RTCDataBuffer(data:data,isBinary:false)) } }
  func close() { recovery?.cancel();recovery=nil;stopAudio();channel?.delegate=nil;channel?.close();peer?.delegate=nil;peer?.close();peer=nil;channel=nil;track=nil }
  nonisolated func dataChannelDidChangeState(_ dataChannel:RTCDataChannel) {}
  nonisolated func dataChannel(_ dataChannel:RTCDataChannel,didReceiveMessageWith buffer:RTCDataBuffer) { let data=buffer.data; Task { @MainActor [weak self] in self?.onEvent?(data) } }
  nonisolated func peerConnection(_ peerConnection:RTCPeerConnection,didChange stateChanged:RTCSignalingState) {}
  nonisolated func peerConnection(_ peerConnection:RTCPeerConnection,didAdd stream:RTCMediaStream) {}
  nonisolated func peerConnection(_ peerConnection:RTCPeerConnection,didRemove stream:RTCMediaStream) {}
  nonisolated func peerConnectionShouldNegotiate(_ peerConnection:RTCPeerConnection) {}
  // ICE goes `disconnected` for a moment on a route or network change and usually recovers; only `failed` is final.
  // A disconnect that lasts is given a few seconds to come back before the call is declared lost.
  nonisolated func peerConnection(_ peerConnection:RTCPeerConnection,didChange newState:RTCIceConnectionState) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      switch newState {
      case .failed: self.onFailure?()
      case .disconnected:
        self.recovery?.cancel()
        self.recovery = Task { [weak self] in
          try? await Task.sleep(for: .seconds(8))
          guard let self, !Task.isCancelled, self.peer?.iceConnectionState == .disconnected else { return }
          self.onFailure?()
        }
      case .connected, .completed: self.recovery?.cancel(); self.recovery = nil
      default: break
      }
    }
  }
  nonisolated func peerConnection(_ peerConnection:RTCPeerConnection,didChange newState:RTCIceGatheringState) {}
  nonisolated func peerConnection(_ peerConnection:RTCPeerConnection,didGenerate candidate:RTCIceCandidate) {}
  nonisolated func peerConnection(_ peerConnection:RTCPeerConnection,didRemove candidates:[RTCIceCandidate]) {}
  nonisolated func peerConnection(_ peerConnection:RTCPeerConnection,didOpen dataChannel:RTCDataChannel) { Task { @MainActor [weak self] in self?.channel=dataChannel; self?.channel?.delegate=self } }
}
