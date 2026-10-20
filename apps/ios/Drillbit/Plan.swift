import StoreKit
import SwiftUI
#if canImport(SuperwallKit)
import SuperwallKit
#endif

/// Where a free account meets the paywall. Names match the Superwall dashboard.
enum PaywallPlacement: String {
  case practiceRep = "practice_rep"
  case voiceSession = "voice_session"
}

private struct EntitlementUpload: Encodable { var signedTransaction: String }
private struct EntitlementReceipt: Decodable { var plan: String }

/// Paywall and entitlement bridge. Superwall draws the paywall when its key is configured; otherwise the
/// native subscription store does. Either way the Worker decides the plan from Apple's signed transaction.
@MainActor @Observable final class PlanCoordinator {
  static let shared = PlanCoordinator()
  static let productIDs = ["dawi.drillbit.pro.monthly", "dawi.drillbit.pro.yearly"]
  /// Non-nil while the native paywall sheet is up.
  var presenting: PaywallPlacement?
  private(set) var superwallConfigured = false
  private var pendingFeature: (() async -> Void)?
  private var updates: Task<Void, Never>?
  private weak var model: AppModel?

  func configure(apiKey: String) {
    #if canImport(SuperwallKit)
    guard !apiKey.isEmpty, !superwallConfigured else { return }
    Superwall.configure(apiKey: apiKey)
    superwallConfigured = true
    #endif
  }

  /// Keeps Superwall's user in step with the Drillbit account; call after bootstrap and on sign-out.
  func identify(account: String?) {
    #if canImport(SuperwallKit)
    guard superwallConfigured else { return }
    if let account { Superwall.shared.identify(userId: account) } else { Superwall.shared.reset() }
    #endif
  }

  /// Shows the paywall for a placement; `feature` runs once the account is Pro.
  func register(_ placement: PaywallPlacement, feature: @escaping () async -> Void) {
    #if canImport(SuperwallKit)
    if superwallConfigured {
      Superwall.shared.register(placement: placement.rawValue) { [weak self] in
        Task { @MainActor in await self?.syncEntitlements(); await feature() }
      }
      return
    }
    #endif
    pendingFeature = feature
    presenting = placement
  }

  /// The native sheet reports a finished purchase or restore here.
  func purchased() async {
    presenting = nil
    await syncEntitlements()
    let feature = pendingFeature
    pendingFeature = nil
    await feature?()
  }
  func dismissed() { presenting = nil; pendingFeature = nil }

  /// Listens for StoreKit transactions for the app's lifetime and posts each to the Worker.
  func start(model: AppModel) {
    self.model = model
    guard updates == nil, !model.fixture else { return }
    updates = Task { [weak self] in
      for await result in Transaction.updates {
        guard case .verified(let transaction) = result else { continue }
        await self?.upload(result.jwsRepresentation)
        await transaction.finish()
      }
    }
    Task { await syncEntitlements() }
  }

  /// Posts every current entitlement, then refreshes bootstrap so the plan is the server's word.
  func syncEntitlements() async {
    guard let model, !model.fixture else { return }
    var uploaded = false
    for await result in Transaction.currentEntitlements {
      guard case .verified(let transaction) = result, Self.productIDs.contains(transaction.productID) else { continue }
      if await upload(result.jwsRepresentation) { uploaded = true }
    }
    if uploaded { await model.refresh() }
  }

  @discardableResult private func upload(_ jws: String) async -> Bool {
    guard let model else { return false }
    do {
      let _: EntitlementReceipt = try await model.api.send("entitlement", method: "POST", body: EntitlementUpload(signedTransaction: jws))
      return true
    } catch let failure as APIError where failure.code == "entitlement_taken" {
      model.entitlementNotice = failure.message
      return false
    } catch { return false }
  }

  #if DEBUG
  /// Fixture purchase: flips the local bootstrap to Pro so UI tests can cross the gate offline.
  func fixturePurchase() async {
    model?.bootstrap?.account.plan = "pro"
    model?.bootstrap?.practice = PracticeAccess(plan: "pro", freeReps: false, available: true)
    if var voice = model?.bootstrap?.capabilities?.voice { voice.available = true; voice.plan = "pro"; voice.remaining = nil; voice.limit = nil; voice.reason = nil; model?.bootstrap?.capabilities?.voice = voice }
    await purchased()
  }
  #endif
}

/// Fallback paywall: Apple's own subscription store for the Pro products.
struct NativePaywallSheet: View {
  let placement: PaywallPlacement
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      SubscriptionStoreView(productIDs: PlanCoordinator.productIDs) {
        VStack(spacing: 8) {
          Text("Drillbit Pro").font(.title.weight(.semibold))
          Text(placement == .voiceSession ? "Talk it through whenever you want, for as long as the interview needs." : "Practice as much as you like. Voice any time.")
            .font(.subheadline).foregroundStyle(AppPalette.secondary).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
      }
      .storeButton(.visible, for: .restorePurchases)
      .onInAppPurchaseCompletion { _, result in
        if case .success(.success) = result { Task { await PlanCoordinator.shared.purchased() } }
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Not now") { PlanCoordinator.shared.dismissed(); dismiss() }.accessibilityIdentifier("paywallDismiss") }
      }
      .safeAreaInset(edge: .bottom) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--fixtures") {
          Button("Simulate purchase") { Task { await PlanCoordinator.shared.fixturePurchase() } }
            .font(.footnote).accessibilityIdentifier("paywallFixturePurchase")
        }
        #endif
      }
    }
    .accessibilityIdentifier("paywall")
  }
}

/// One line of why, plus the way through. Sits wherever a free account hits a limit.
struct ProNudge: View {
  let message: String
  let placement: PaywallPlacement
  let feature: () async -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(message).font(.subheadline).foregroundStyle(AppPalette.secondary).fixedSize(horizontal: false, vertical: true)
      Button("See Pro") { PlanCoordinator.shared.register(placement, feature: feature) }
        .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
        .accessibilityIdentifier("seePro")
    }
  }
}

/// Hosts the native paywall sheet above the whole app when Superwall isn't configured.
struct PaywallHost: ViewModifier {
  @State private var plan = PlanCoordinator.shared
  func body(content: Content) -> some View {
    content.sheet(isPresented: Binding(get: { plan.presenting != nil }, set: { if !$0 { plan.dismissed() } })) {
      if let placement = plan.presenting { NativePaywallSheet(placement: placement) }
    }
  }
}
