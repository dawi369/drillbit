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
    // Cues are cleaned once the pieces are joined: the provider streams "[tongue" and " click]" separately.
    return rows.map { var row = $0; row.text = speechOnly(row.text); return row }.filter { !$0.text.isEmpty }
  }
  /// Drops the provider's sound cues ("[scoff]", "(tongue click)", "*laughs*") and one still arriving at the end.
  static func speechOnly(_ text: String) -> String {
    let cue = #"\s*(\[[^\]\n]{1,40}\]|\([^)\n]{1,40}\)|\*[^*\n]{1,40}\*)"#
    let unclosed = #"\s*[\[(*][^\])*\n]{0,40}$"#
    return text
      .replacingOccurrences(of: cue, with: "", options: .regularExpression)
      .replacingOccurrences(of: unclosed, with: "", options: .regularExpression)
      .replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespaces)
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
