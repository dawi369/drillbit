import ClerkKit
import Foundation

@MainActor final class APIClient {
  let baseURL: URL
  private let tokenProvider: @MainActor () async throws -> String?
  private let transport: @MainActor (URLRequest) async throws -> (Data, URLResponse)
  init(baseURL: URL,
       tokenProvider: @escaping @MainActor () async throws -> String? = { try await Clerk.shared.session?.getToken(.init(template: "drillbit")) },
       transport: @escaping @MainActor (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }) {
    self.baseURL = baseURL; self.tokenProvider = tokenProvider; self.transport = transport
  }
  func request(_ path: String, method: String = "GET", body: Data? = nil, command: String? = nil)
    async throws -> URLRequest
  {
    guard let token = try await tokenProvider() else {
      throw APIError(code: "unauthenticated", message: "Sign in to continue.", status: 401)
    }
    var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
    let pieces = path.split(separator: "?", maxSplits: 1).map(String.init)
    components.path = "/v1/" + pieces[0]
    if pieces.count > 1 { components.percentEncodedQuery = pieces[1] }
    guard let url = components.url else { throw URLError(.badURL) }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.httpBody = body
    request.timeoutInterval = 70
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let command { request.setValue(command, forHTTPHeaderField: "Idempotency-Key") }
    return request
  }
  func send<T: Decodable>(
    _ path: String, method: String = "GET", body: (any Encodable)? = nil, command: String? = nil
  ) async throws -> T {
    let encoded = try body.map { try JSONEncoder().encode($0) }
    let request = try await request(path, method: method, body: encoded, command: command)
    let (data, response) = try await transport(request)
    try validate(data, response)
    return try JSONDecoder.api.decode(T.self, from: data)
  }
  func coach(id: String, question: String, command: String, onDelta: @MainActor (String) -> Void)
    async throws
  {
    let request = try await request(
      "challenges/\(id)/coach", method: "POST",
      body: JSONEncoder().encode(Question(question: question)), command: command)
    let (bytes, response) = try await URLSession.shared.bytes(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
      throw APIError(
        code: "coach_failed",
        message: "Coaching is unavailable. Check your connection and AI access.",
        status: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
    var event = ""
    var data = ""
    var completed = false
    for try await line in bytes.lines {
      try Task.checkCancellation()
      if line.isEmpty {
        if !data.isEmpty,
          let value = try? JSONDecoder().decode(StreamEvent.self, from: Data(data.utf8))
        {
          if event == "delta", let text = value.text { onDelta(text) }
          if event == "completed" { completed = true }
          if event == "failed" {
            throw APIError(
              code: "interrupted", message: value.message ?? "Coaching was interrupted.", status: 0)
          }
        }
        event = ""
        data = ""
      } else if line.hasPrefix("event:") {
        event = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
      } else if line.hasPrefix("data:") {
        data += String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
      }
    }
    if !completed {
      throw APIError(
        code: "interrupted",
        message: "Coaching was interrupted. The partial response is not saved.", status: 0)
    }
  }
  func interviewStream(id: String, turn: String, onSnapshot: @MainActor (InterviewStreamSnapshot) -> Void) async throws {
    let request = try await request("challenges/\(id)/interview/\(turn)/stream")
    let (bytes, response) = try await URLSession.shared.bytes(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
    for try await line in bytes.lines {
      try Task.checkCancellation()
      guard line.hasPrefix("data:") else { continue }
      let value = try JSONDecoder().decode(InterviewStreamSnapshot.self, from: Data(line.dropFirst(5).utf8))
      onSnapshot(value)
      if !["pending", "running"].contains(value.status) { return }
    }
    throw URLError(.networkConnectionLost)
  }
  private func validate(_ data: Data, _ response: URLResponse) throws {
    guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    guard (200..<300).contains(http.statusCode) else {
      let error = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
      throw APIError(
        code: error?.error.code ?? "request_failed",
        message: error?.error.message ?? "The request could not finish.", status: http.statusCode)
    }
  }
}
