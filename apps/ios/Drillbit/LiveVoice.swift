import SwiftUI
import AVFAudio
@preconcurrency import WebRTC

private struct VoiceConnection: Decodable { var id: String; var sdp: String; var expiresAt: String }
private struct VoiceStart: Encodable { var sdp: String; var revision: Int }
private struct VoiceEvents: Codable { var fragments: [VoiceFragment]; var closed: Bool; var finalized: Bool; var usageSeconds: Double? }
private struct VoiceAck: Decodable { var accepted: [String] }
private struct VoiceDelegation: Encodable { var id: String }
private struct VoiceReply: Decodable { var text: String }
private struct VoiceOutbox: Codable {
  var id: String
  var fragments: [VoiceFragment] = []
  var closed = false
  var finalized = false
  var usageSeconds: Double? = nil
}

@MainActor @Observable final class LiveVoice {
  enum Phase: Equatable { case idle, connecting, active, ending, unavailable }
  var phase: Phase = .idle
  var muted = false
  var message: String?
  var isOpen: Bool { phase != .idle }
  var blocksText: Bool { [.connecting,.active,.ending].contains(phase) || outbox != nil }
  private let interview: InterviewController
  private var transport: NativeVoiceTransport?
  private var outbox: VoiceOutbox?
  private var syncing = false
  private var acknowledged: Set<String> = []
  private var eventTask: Task<Void,Never>?
  private var deadline: Task<Void,Never>?
  private var closeDeadline: Task<Void,Never>?
  private var generation = UUID()
  private var seen: Set<String> = []
  private var delegations: Set<String> = []
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
  func start() async {
    guard !blocksText, !interview.locked, interview.currentAccount, interview.acceptsVoiceInput else { return }
    let epoch = UUID(); generation = epoch
    phase = .connecting; message = nil; muted = false; seen = []; delegations = []; acknowledged = []
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
        throw APIError(code:"sync_pending",message:"Sync your draft before starting voice.",status:0)
      }
      guard generation == epoch, interview.currentAccount, interview.acceptsVoiceInput else { return }
      if !interview.model.fixture {
        let allowed = await AVAudioApplication.requestRecordPermission()
        guard generation == epoch else { return }
        guard allowed else { throw APIError(code:"microphone_denied",message:"Allow microphone access in iPhone Settings to use voice.",status:0) }
      }
      let id = UUID().uuidString
      outbox = VoiceOutbox(id:id)
      try await persist()
      guard generation == epoch, interview.currentAccount, interview.acceptsVoiceInput else { return }
      if interview.model.fixture {
        phase = .active
        present([],id:id)
        return
      }
      let audio = AVAudioSession.sharedInstance()
      try audio.setCategory(.playAndRecord,mode:.voiceChat,options:[.defaultToSpeaker,.allowBluetoothHFP])
      try audio.setActive(true)
      let link = NativeVoiceTransport()
      transport = link
      link.onEvent = { [weak self] data in self?.enqueue(data,epoch:epoch) }
      link.onFailure = { [weak self] in self?.interrupt("Voice disconnected. Your transcript is preserved.") }
      let offer = try await link.offer()
      guard generation == epoch else { link.close(); return }
      let result: VoiceConnection = try await interview.model.api.send("challenges/\(interview.challenge.id)/voice",method:"POST",body:VoiceStart(sdp:offer,revision:draft.revision),command:id)
      guard generation == epoch else { link.close(); return }
      try await link.answer(result.sdp)
      Task { [weak self] in
        try? await Task.sleep(for:.seconds(10))
        guard let self, self.generation == epoch, self.phase == .connecting else { return }
        self.interrupt("Voice could not finish connecting. Try again.")
      }
      present([],id:id)
      deadline = Task { [weak self] in
        try? await Task.sleep(for:.seconds(10*60))
        guard !Task.isCancelled else { return }
        await self?.end()
      }
      interruptedObserver = NotificationCenter.default.addObserver(forName:AVAudioSession.interruptionNotification,object:nil,queue:.main) { [weak self] _ in
        Task { @MainActor in self?.interrupt("Voice paused by an audio interruption. You can start it again.") }
      }
      routeObserver = NotificationCenter.default.addObserver(forName:AVAudioSession.routeChangeNotification,object:nil,queue:.main) { [weak self] note in
        let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
        if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
          Task { @MainActor in self?.interrupt("Your audio device disconnected. Voice has stopped.") }
        }
      }
    } catch {
      guard generation == epoch else { return }
      // Startup may have created a server reservation even when its answer was lost.
      if outbox != nil { outbox?.closed = true; try? await persist(); await sync() }
      cleanup(); phase = .unavailable; message = error.localizedDescription
    }
  }
  func toggleMute() {
    guard phase == .active else { return }
    muted.toggle()
    transport?.mute(muted)
    transport?.send(["type": muted ? "session.input_audio.mute" : "session.input_audio.unmute", "event_id":UUID().uuidString])
  }
  func stopAudioImmediately() { transport?.stopAudio() }
  func end() async {
    guard isOpen, phase != .ending else { return }
    let wasConnecting = phase == .connecting
    phase = .ending
    if wasConnecting { generation = UUID() }
    transport?.stopAudio()
    if interview.model.fixture || transport == nil {
      await finalize(confirmed:interview.model.fixture); return
    }
    transport?.send(["type":"session.close","event_id":UUID().uuidString])
    closeDeadline = Task { [weak self] in
      try? await Task.sleep(for:.seconds(5))
      guard !Task.isCancelled else { return }
      await self?.finalize(confirmed:false)
    }
  }
  func interrupt(_ reason: String) {
    guard phase == .active || phase == .connecting else { return }
    transport?.mute(true)
    Task { await end(); message = reason }
  }
  func dismiss() { if !blocksText { phase = .idle; message = nil } }
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
    if type == "session.started" { if phase == .connecting { phase = .active }; return }
    if type == "session.closed" { if let usage=event["usage"] as? [String:Any] { outbox?.usageSeconds = usage["seconds"] as? Double }; await finalize(confirmed:true); return }
    if type == "error" { interrupt("Voice encountered a connection error. Your writing is safe."); return }
    if type == "session.usage.updated",let usage=event["usage"] as? [String:Any] { outbox?.usageSeconds = usage["seconds"] as? Double; return }
    if ["session.input_transcript.delta","session.output_transcript.delta"].contains(type),
       let id=event["event_id"] as? String, let delta=event["delta"] as? String,
       let start=event["start_ms"] as? Int,let end=event["end_ms"] as? Int, !seen.contains(id), outbox != nil {
      let f = VoiceFragment(id:id,sequence:(outbox?.fragments.last?.sequence ?? -1)+1,speaker:type == "session.input_transcript.delta" ? "user":"assistant",text:delta,startMs:start,endMs:end)
      outbox?.fragments.append(f); seen.insert(id)
      do {
        try await persist()
        if let outbox { present(outbox.fragments,id:outbox.id) }
        Task { await sync() }
      } catch { interrupt("Couldn’t save the transcript. Voice has stopped to protect your work.") }
    }
    if type == "session.delegation.created", let d=event["delegation"] as? [String:Any],let id=d["id"] as? String,!delegations.contains(id) {
      delegations.insert(id)
      let epoch=generation
      Task {
        while syncing { try? await Task.sleep(for:.milliseconds(20)) }
        await sync()
        guard let pending = outbox, pending.fragments.allSatisfy({ acknowledged.contains($0.id) }), generation == epoch, phase == .active else { return }
        do {
          let reply:VoiceReply = try await interview.model.api.send("challenges/\(interview.challenge.id)/voice/\(outbox!.id)/delegate",method:"POST",body:VoiceDelegation(id:id))
          guard generation == epoch,phase == .active else { return }
          transport?.send(["type":"session.commentary.append","event_id":UUID().uuidString,"delegation_id":id,"content":reply.text])
        } catch {
          guard generation == epoch,phase == .active else { return }
          transport?.send(["type":"session.commentary.append","event_id":UUID().uuidString,"delegation_id":id,"content":"Technical guidance is unavailable. Say so briefly; don't invent a result."])
        }
      }
    }
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
    } catch { message = "Transcript saved on this device. Reconnect to sync before continuing." }
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
    transport?.close(); transport = nil
    if let interruptedObserver { NotificationCenter.default.removeObserver(interruptedObserver) }; interruptedObserver = nil
    if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }; routeObserver = nil
    try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
  }
  #if DEBUG
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
  func offer() async throws -> String {
    let config=RTCConfiguration();config.sdpSemantics = .unifiedPlan
    let constraints=RTCMediaConstraints(mandatoryConstraints:nil,optionalConstraints:nil)
    guard let pc=factory.peerConnection(with:config,constraints:constraints,delegate:self) else { throw NSError(domain:"Voice",code:1) }
    peer=pc
    let audio=factory.audioTrack(with:factory.audioSource(with:constraints),trackId:"microphone")
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
  func stopAudio() { track?.isEnabled=false; for receiver in peer?.receivers ?? [] { receiver.track?.isEnabled=false } }
  func mute(_ muted:Bool) { track?.isEnabled = !muted }
  func send(_ event:[String:Any]) { if let data=try? JSONSerialization.data(withJSONObject:event) { channel?.sendData(RTCDataBuffer(data:data,isBinary:false)) } }
  func close() { track?.isEnabled=false;channel?.delegate=nil;channel?.close();peer?.delegate=nil;peer?.close();peer=nil;channel=nil;track=nil }
  nonisolated func dataChannelDidChangeState(_ dataChannel:RTCDataChannel) {}
  nonisolated func dataChannel(_ dataChannel:RTCDataChannel,didReceiveMessageWith buffer:RTCDataBuffer) { let data=buffer.data; Task { @MainActor [weak self] in self?.onEvent?(data) } }
  nonisolated func peerConnection(_ peerConnection:RTCPeerConnection,didChange stateChanged:RTCSignalingState) {}
  nonisolated func peerConnection(_ peerConnection:RTCPeerConnection,didAdd stream:RTCMediaStream) {}
  nonisolated func peerConnection(_ peerConnection:RTCPeerConnection,didRemove stream:RTCMediaStream) {}
  nonisolated func peerConnectionShouldNegotiate(_ peerConnection:RTCPeerConnection) {}
  nonisolated func peerConnection(_ peerConnection:RTCPeerConnection,didChange newState:RTCIceConnectionState) { if newState == .failed || newState == .disconnected { Task { @MainActor [weak self] in self?.onFailure?() } } }
  nonisolated func peerConnection(_ peerConnection:RTCPeerConnection,didChange newState:RTCIceGatheringState) {}
  nonisolated func peerConnection(_ peerConnection:RTCPeerConnection,didGenerate candidate:RTCIceCandidate) {}
  nonisolated func peerConnection(_ peerConnection:RTCPeerConnection,didRemove candidates:[RTCIceCandidate]) {}
  nonisolated func peerConnection(_ peerConnection:RTCPeerConnection,didOpen dataChannel:RTCDataChannel) { Task { @MainActor [weak self] in self?.channel=dataChannel; self?.channel?.delegate=self } }
}
