import Foundation
import Testing

#if canImport(DrillbitCore)
  @testable import DrillbitCore
#else
  @testable import Drillbit
#endif

struct PlanPricingTests {
  @Test func yearlySavingRoundsDown() {
    // 39.99 against 52 × 6.99 = 363.48 saves 88.99%: the badge says 88, never 89.
    #expect(PlanPricing.yearlySaving(yearly: Decimal(string: "39.99")!, weekly: Decimal(string: "6.99")!) == 88)
    #expect(PlanPricing.yearlySaving(yearly: 100, weekly: 2.5) == 23)
    // Launch prices: 79.99 against 52 × 7.99 = 415.48 saves 80.75%.
    #expect(PlanPricing.yearlySaving(yearly: Decimal(string: "79.99")!, weekly: Decimal(string: "7.99")!) == 80)
  }
  @Test func noBadgeWithoutASaving() {
    #expect(PlanPricing.yearlySaving(yearly: 52, weekly: 1) == nil)
    #expect(PlanPricing.yearlySaving(yearly: 60, weekly: 1) == nil)
    #expect(PlanPricing.yearlySaving(yearly: Decimal(string: "51.99")!, weekly: 1) == nil, "Under one percent rounds to nothing")
    #expect(PlanPricing.yearlySaving(yearly: 10, weekly: 0) == nil)
  }
  @Test func monthlyFromYearly() {
    #expect(PlanPricing.monthly(fromYearly: 120) == 10)
  }
}
