import Foundation

struct VoiceRow: Identifiable {
  var id: String
  var speaker: String
  var text: String
  var endMs: Int
}
enum VoiceTranscript {
  static func latestRows(_ fragments: [VoiceFragment]) -> [VoiceRow] {
    let grouped = rows(fragments)
    let user = grouped.lastIndex { $0.speaker == "user" }
    let assistant = grouped.lastIndex { $0.speaker == "assistant" }
    guard let start = [user, assistant].compactMap({ $0 }).min() else { return [] }
    return Array(grouped[start...])
  }
  // A display grouping only. Raw fragments remain immutable and independently persisted.
  static func rows(_ fragments: [VoiceFragment]) -> [VoiceRow] {
    var rows: [VoiceRow] = []
    var latest: [String: Int] = [:]
    for fragment in fragments.sorted(by: { $0.sequence < $1.sequence }) {
      if let index = latest[fragment.speaker], fragment.startMs >= rows[index].endMs,
         fragment.startMs - rows[index].endMs <= 1500 {
        rows[index].text += fragment.text
        rows[index].endMs = fragment.endMs
      } else {
        latest[fragment.speaker] = rows.count
        rows.append(VoiceRow(id: fragment.id, speaker: fragment.speaker, text: fragment.text, endMs: fragment.endMs))
      }
    }
    return rows
  }
}

/// Resolves once, including when a response and the deadline race on the main
/// actor. The clock is injected so timeout behavior doesn't need real sleeps.
struct VoiceGuidanceDelivery {
  enum Outcome { case response, unavailable }
  let deadline: ContinuousClock.Instant
  private(set) var resolved = false
  mutating func resolve(at now: ContinuousClock.Instant) -> Outcome? {
    guard !resolved else { return nil }
    resolved = true
    return now < deadline ? .response : .unavailable
  }
}
