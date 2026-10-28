import StoreKit
import SwiftUI
import UIKit
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
  /// Yearly first: it's the anchor the weekly price is measured against. Prices and the weekly intro offer live in
  /// App Store Connect (and `Config/Drillbit.storekit` for the simulator), never in code.
  static let productIDs = ["dawi.drillbit.pro.yearly", "dawi.drillbit.pro.weekly"]
  /// Non-nil while the native paywall is up.
  private(set) var presenting: PaywallPlacement?
  /// Presented from UIKit over whatever is on top. A SwiftUI sheet on the root can't appear while Settings or an
  /// interview is already presented, so See Pro silently did nothing there.
  private var paywallController: UIViewController?
  private let sheetDelegate = PaywallSheetDelegate()
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
    guard presenting == nil else { return }
    pendingFeature = feature
    presenting = placement
    Task { await presentNative(placement) }
  }

  private func presentNative(_ placement: PaywallPlacement) async {
    // Wait out a presentation in flight, such as the alert whose See Pro button was just tapped.
    for _ in 0..<20 {
      guard presenting == placement else { return }
      if let top = Self.topController(), !top.isBeingDismissed, !top.isBeingPresented, top.transitionCoordinator == nil {
        let host = UIHostingController(rootView: NativePaywallSheet(placement: placement).tint(AppPalette.accent))
        host.overrideUserInterfaceStyle = top.traitCollection.userInterfaceStyle
        host.presentationController?.delegate = sheetDelegate
        sheetDelegate.onSwipeDown = { [weak self] in self?.paywallController = nil; self?.dismissed() }
        paywallController = host
        top.present(host, animated: true)
        return
      }
      try? await Task.sleep(for: .milliseconds(100))
    }
    dismissed()
  }

  private func closePaywall() {
    presenting = nil
    paywallController?.dismiss(animated: true)
    paywallController = nil
  }

  private static func topController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    var top = (scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first)?.rootViewController
    while let next = top?.presentedViewController, !next.isBeingDismissed { top = next }
    return top
  }

  /// The native sheet reports a finished purchase or restore here.
  func purchased() async {
    closePaywall()
    await syncEntitlements()
    let feature = pendingFeature
    pendingFeature = nil
    await feature?()
  }
  func dismissed() { closePaywall(); pendingFeature = nil }

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
  /// Products are checked up front so a store that sends nothing gets a plain explanation and a retry, not
  /// StoreKit's bare "Subscription unavailable".
  private enum Availability { case checking, ready, missing }
  @State private var availability = Availability.checking
  @State private var attempt = 0

  var body: some View {
    NavigationStack {
      Group {
        if availability == .missing { unavailable } else { store }
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Not now") { PlanCoordinator.shared.dismissed() }.accessibilityIdentifier("paywallDismiss") }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--fixtures") {
          ToolbarItem(placement: .primaryAction) {
            Button("Simulate") { Task { await PlanCoordinator.shared.fixturePurchase() } }
              .accessibilityIdentifier("paywallFixturePurchase")
          }
        }
        #endif
      }
    }
    .accessibilityIdentifier("paywall")
    .task(id: attempt) {
      let found = (try? await Product.products(for: PlanCoordinator.productIDs)) ?? []
      availability = found.isEmpty ? .missing : .ready
    }
  }

  private var store: some View {
    SubscriptionStoreView(productIDs: PlanCoordinator.productIDs) {
      PaywallHeader(placement: placement)
    }
    .subscriptionStoreControlStyle(PlanPicker())
    .containerBackground(for: .subscriptionStoreFullHeight) { PaywallBackdrop() }
    .storeButton(.visible, for: .restorePurchases)
    .storeButton(.visible, for: .policies)
    // One way out: Not now, which also drops the feature waiting behind the paywall.
    .storeButton(.hidden, for: .cancellation)
    .subscriptionStorePolicyDestination(url: LegalLinks.terms, for: .termsOfService)
    .modifier(PrivacyPolicyDestination())
    .onInAppPurchaseCompletion { _, result in
      if case .success(.success) = result { Task { await PlanCoordinator.shared.purchased() } }
    }
  }

  private var unavailable: some View {
    ContentUnavailableView {
      Label("Couldn’t load Pro", systemImage: "sparkles")
    } description: {
      Text("The App Store didn’t send the plans over. Check your connection, then give it another go.")
    } actions: {
      Button("Try again") { availability = .checking; attempt += 1 }
        .buttonStyle(PracticeButtonStyle()).frame(maxWidth: 240)
        .accessibilityIdentifier("paywallRetry")
    }
    .accessibilityIdentifier("paywallUnavailable")
  }
}

/// The paywall's pitch: Bit, one line that says why now, and what Pro actually changes. Compact, so both plans
/// and Subscribe stay on screen without scrolling.
private struct PaywallHeader: View {
  let placement: PaywallPlacement
  @State private var glow = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private static let perks: [(symbol: String, title: String)] = [
    ("infinity", "More reps, whenever it’s clicking"),
    ("waveform", "Voice mocks up to 20 minutes"),
    ("lightbulb", "Every nudge and follow-up"),
    ("sun.max", "A fresh question waiting each day"),
  ]
  var body: some View {
    VStack(spacing: 16) {
      ZStack {
        BitGlow(color: AppPalette.action, opacity: 0.28)
          .frame(width: 128, height: 128)
          .scaleEffect(glow ? 1.08 : 0.94)
          .accessibilityHidden(true)
        BitView(mood: .happy, greets: true).frame(width: 52, height: 60).accessibilityHidden(true)
      }
      .frame(height: 80)
      VStack(spacing: 4) {
        Text("Drillbit Pro").font(.caption.weight(.semibold)).foregroundStyle(AppPalette.accent)
          .textCase(.uppercase).tracking(1.2)
        Text(placement == .voiceSession ? "Say it out loud, as often as you want." : "Don’t stop at three.")
          .font(.title2.weight(.semibold)).multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityAddTraits(.isHeader)
      }
      VStack(alignment: .leading, spacing: 12) {
        ForEach(Self.perks, id: \.title) { perk in
          HStack(spacing: 12) {
            Image(systemName: perk.symbol)
              .font(.subheadline.weight(.semibold)).foregroundStyle(AppPalette.accent)
              .frame(width: 28, height: 28)
              .background(AppPalette.accentSoft, in: Circle())
              .accessibilityHidden(true)
            Text(perk.title).font(.subheadline.weight(.medium))
              .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
          }
        }
      }
      .frame(maxWidth: 320)
    }
    .padding(.horizontal, 24)
    .frame(maxWidth: 520)
    .onAppear {
      guard !reduceMotion else { return }
      withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) { glow = true }
    }
  }
}

/// A warm wash from the top, so the sheet reads as Drillbit rather than a settings form.
private struct PaywallBackdrop: View {
  var body: some View {
    ZStack(alignment: .top) {
      AppPalette.background
      LinearGradient(colors: [AppPalette.action.opacity(0.14), AppPalette.background.opacity(0)], startPoint: .top, endPoint: .center)
    }
    .ignoresSafeArea()
  }
}

/// Where the terms and privacy policy live. Terms are Apple's standard EULA; the privacy policy comes from
/// `PRIVACY_POLICY_URL` in the xcconfig and must be set before the App Store build.
enum LegalLinks {
  static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
  static var privacy: URL? {
    guard let value = Bundle.main.object(forInfoDictionaryKey: "PrivacyPolicyURL") as? String, value.hasPrefix("https://") else { return nil }
    return URL(string: value)
  }
}

private struct PrivacyPolicyDestination: ViewModifier {
  func body(content: Content) -> some View {
    if let privacy = LegalLinks.privacy { content.subscriptionStorePolicyDestination(url: privacy, for: .privacyPolicy) }
    else { content }
  }
}

/// The plan choice: yearly with what it saves against paying weekly, weekly with its first-week offer when they're
/// eligible. Every figure comes from the products themselves, so it stays right whatever the prices become.
private struct PlanPicker: SubscriptionStoreControlStyle {
  func makeBody(configuration: Configuration) -> some View { PlanPickerBody(configuration: configuration) }
}

/// Holds the selection so each option can show whether it's the one Subscribe will buy.
private struct PlanPickerBody: View {
  let configuration: SubscriptionStoreControlStyleConfiguration
  @State private var selection: SubscriptionStoreControlStyleConfiguration.Option?
  var body: some View {
    let weekly = configuration.allOptions.first { $0.subscription?.subscriptionPeriod.unit == .week }
    SubscriptionStorePicker(configuration, selection: $selection) { option in
      PlanOptionLabel(product: option.subscription, offer: option.activeOffer, weekly: weekly,
                      selected: option.subscription.id == selection?.subscription.id)
    } confirmation: { option in
      SubscriptionStoreButton(option)
    }
    .onAppear { if selection == nil { selection = configuration.options.first } }
  }
}

private struct PlanOptionLabel: View {
  let product: StoreKit.Product
  let offer: StoreKit.Product.SubscriptionOffer?
  let weekly: StoreKit.Product?
  var selected = false
  private var period: StoreKit.Product.SubscriptionPeriod.Unit? { product.subscription?.subscriptionPeriod.unit }
  private var format: Decimal.FormatStyle.Currency { product.priceFormatStyle }

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Image(systemName: selected ? "checkmark.circle.fill" : "circle")
        .font(.title3)
        .foregroundStyle(selected ? AppPalette.action : AppPalette.secondary)
        .contentTransition(.symbolEffect(.replace))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(period == .year ? "Yearly" : "Weekly").font(.headline)
        Text(detail).font(.subheadline).foregroundStyle(AppPalette.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      if period == .year, let weekly, let saving = PlanPricing.yearlySaving(yearly: product.price, weekly: weekly.price) {
        Text("Save \(saving)%")
          .font(.caption.weight(.semibold))
          .foregroundStyle(AppPalette.actionInk)
          .padding(.horizontal, 8).padding(.vertical, 4)
          .background(AppPalette.action, in: Capsule())
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private var detail: String {
    if period == .year {
      let monthly = PlanPricing.monthly(fromYearly: product.price).formatted(format)
      return "\(product.displayPrice) a year, so \(monthly) a month"
    }
    if let offer, offer.paymentMode != .freeTrial, offer.period.unit == .week, offer.period.value * offer.periodCount == 1 {
      return "Try a week for \(offer.displayPrice), then \(product.displayPrice) a week"
    }
    return "\(product.displayPrice) a week"
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
/// Swiping the paywall down counts as Not now.
private final class PaywallSheetDelegate: NSObject, UIAdaptivePresentationControllerDelegate {
  var onSwipeDown: (@MainActor () -> Void)?
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    MainActor.assumeIsolated { onSwipeDown?() }
  }
}
