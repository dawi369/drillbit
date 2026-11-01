import Foundation

/// The paywall's arithmetic, apart from StoreKit so it can be tested. Prices come from the products; nothing here
/// knows what they are.
enum PlanPricing {
  /// Whole percent the yearly price saves against 52 weeks of the weekly one, rounded down so the badge never
  /// overstates; nil when it saves nothing.
  static func yearlySaving(yearly: Decimal, weekly: Decimal) -> Int? {
    let year = weekly * 52
    guard year > 0, yearly < year else { return nil }
    let whole = Int(NSDecimalNumber(decimal: (1 - yearly / year) * 100).doubleValue.rounded(.down))
    return whole > 0 ? whole : nil
  }
  /// The yearly price spread over 52 weeks, so it reads next to the weekly plan in the same unit.
  static func weekly(fromYearly yearly: Decimal) -> Decimal { yearly / 52 }
}
