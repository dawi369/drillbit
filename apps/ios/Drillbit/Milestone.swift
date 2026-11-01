import Foundation

/// Round ticket numbers get a moment. It counts reps, never skill.
enum Milestone {
  static func line(for ticket: Int?) -> String? {
    guard let ticket else { return nil }
    switch ticket {
    case 10: return "Ten reps in. That’s a habit now."
    case 25: return "25 reps. You’re not winging these anymore."
    case 50: return "50 reps. That’s a lot of design calls."
    case 100: return "100 reps. Genuinely a lot of system design."
    case let n where n > 100 && n % 100 == 0: return "\(n) reps. Still showing up."
    default: return nil
    }
  }
}
