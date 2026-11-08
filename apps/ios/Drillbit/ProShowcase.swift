import StoreKit
import SwiftUI

/// The Bit tab for a free account: their real map so far, what Pro reads from it, how the first week works, and the
/// plans side by side. The tab itself is the pitch, so it opens like any other tab instead of bouncing to a sheet.
struct ProShowcaseView: View {
  var model: AppModel
  @State private var appeared = false
  @State private var products: [StoreKit.Product] = []
  @State private var introEligible: Set<String> = []
  @State private var selection: String?
  @State private var loading = true
  @State private var attempt = 0
  @State private var working = false
  @State private var note: String?
  @Environment(\.purchase) private var purchase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var typeSize

  private static let features: [(symbol: String, title: String, line: String)] = [
    ("chart.line.uptrend.xyaxis", "Your level", "After three solid reps, Bit places you somewhere from intern to principal. An estimate, not a hiring call."),
    ("circle.hexagongrid", "What held up", "Every concept you’ve used, gold where it held up and ringed where it’s worth another go."),
    ("scope", "Next up", "The gap worth closing next, picked from your own feedback."),
    ("infinity", "The rest of Pro", "More reps, voice mode and every nudge and follow-up."),
  ]

  var body: some View {
    let nodes = KnowledgeNode.build(model: model)
    ScrollView {
      VStack(alignment: .leading, spacing: 32) {
        hero.padding(.horizontal, 20)
        VStack(alignment: .leading, spacing: 12) {
          ConstellationMap(nodes: nodes, selected: .constant(nil), appeared: appeared)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            // The line under it reads the map out; this only names it, so VoiceOver doesn't say it twice.
            .accessibilityLabel("Your knowledge map")
            .accessibilityIdentifier("showcaseMap")
            .padding(.horizontal, 4)
          reaction(mapSummary(nodes)).padding(.horizontal, 20)
        }
        VStack(alignment: .leading, spacing: 32) {
          features
          if let product = selectedProduct { timeline(for: product) }
          plans
        }
        .padding(.horizontal, 20)
      }
      .padding(.top, 4).padding(.bottom, 40)
      .frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity)
    }
    .background(AppPalette.background)
    .containerBackground(AppPalette.background, for: .navigation)
    .navigationTitle("Bit")
    .navigationSubtitle("Part of Pro")
    .accessibilityIdentifier("proShowcase")
    .task {
      await model.loadTaxonomy()
      await model.loadMemory()
      withAnimation(reduceMotion ? nil : .easeOut(duration: 0.9)) { appeared = true }
    }
    .task { await model.recordPaywallView(.knowledgeMap) }
    .task(id: attempt) { await loadProducts() }
    .animation(reduceMotion ? nil : DrillbitMotion.selection, value: selection)
  }

  // MARK: Pitch

  private var hero: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("See what you actually know.")
        .font(.largeTitle.weight(.semibold)).tracking(-0.6)
        .foregroundStyle(AppPalette.primary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
      Text("Every rep lands on Bit’s map. Pro reads it for you.")
        .font(.title3).foregroundStyle(AppPalette.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.top, 12)
    .signalEntrance(0)
  }

  private func mapSummary(_ nodes: [KnowledgeNode]) -> String {
    let explored = nodes.filter { $0.state != .unexplored }.count
    guard explored > 0 else { return "This is your map. Your first rep puts the first dot on it." }
    return "That’s your map: \(explored) of \(nodes.count) areas so far. Pro shows what held up, what didn’t, and where that puts you."
  }

  /// Onboarding's way of saying something: a sparkle and a line, no box.
  private func reaction(_ text: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "sparkle").font(.caption.weight(.semibold)).foregroundStyle(AppPalette.accent).padding(.top, 3)
        .accessibilityHidden(true)
      Text(text).font(.subheadline).foregroundStyle(AppPalette.secondary).fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, 4)
    .accessibilityElement(children: .combine)
  }

  private func sectionTitle(_ text: String) -> some View {
    Text(text).font(.title3.weight(.semibold)).foregroundStyle(AppPalette.primary)
      .accessibilityAddTraits(.isHeader)
  }

  private var features: some View {
    VStack(alignment: .leading, spacing: 16) {
      sectionTitle("What Pro adds here")
      VStack(alignment: .leading, spacing: 20) {
        ForEach(Self.features, id: \.title) { feature in
          HStack(alignment: .top, spacing: 12) {
            Image(systemName: feature.symbol)
              .font(.body).foregroundStyle(AppPalette.secondary)
              .frame(width: 24, height: 24)
              .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
              Text(feature.title).font(.body.weight(.semibold)).foregroundStyle(AppPalette.primary)
              Text(feature.line).font(.subheadline).foregroundStyle(AppPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
          .accessibilityElement(children: .combine)
        }
      }
    }
    .signalEntrance(1)
  }

  // MARK: How it works

  private struct Step { let when: String; let what: String; let symbol: String }

  /// What happens to the money, in order, for the plan that's selected. Prices come from the product.
  private func steps(for product: StoreKit.Product) -> (title: String, steps: [Step]) {
    let yearly = product.isYearlyPlan
    let cancel = Step(when: "Anytime", what: "Cancel in your iPhone’s Settings. Pro stays until the time you paid for runs out.", symbol: "xmark.circle")
    if yearly {
      return ("How it works", [
        Step(when: "Today", what: "\(product.displayPrice) for the year. All of Pro opens up.", symbol: "lock.open"),
        Step(when: "In a year", what: "Renews at \(product.displayPrice) unless you cancel.", symbol: "arrow.clockwise"),
        cancel,
      ])
    }
    if let intro = firstWeek(product) {
      return ("How your first week works", [
        Step(when: "Today", what: "\(intro.displayPrice) for your first week. All of Pro opens up.", symbol: "lock.open"),
        Step(when: "Day 8", what: "\(product.displayPrice) a week from then, unless you cancel.", symbol: "arrow.clockwise"),
        cancel,
      ])
    }
    return ("How it works", [
      Step(when: "Today", what: "\(product.displayPrice) for the week. All of Pro opens up.", symbol: "lock.open"),
      Step(when: "Every week", what: "Renews at \(product.displayPrice) unless you cancel.", symbol: "arrow.clockwise"),
      cancel,
    ])
  }

  private func timeline(for product: StoreKit.Product) -> some View {
    let plan = steps(for: product)
    return VStack(alignment: .leading, spacing: 16) {
      sectionTitle(plan.title)
      VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(plan.steps.enumerated()), id: \.element.when) { index, step in
          HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
              Image(systemName: step.symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(index == 0 ? AppPalette.actionInk : AppPalette.secondary)
                .frame(width: 32, height: 32)
                .background(index == 0 ? AppPalette.action : AppPalette.elevated, in: Circle())
              if index < plan.steps.count - 1 {
                Rectangle().fill(AppPalette.hairline).frame(width: 2).frame(maxHeight: .infinity)
              }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
              Text(step.when).font(.body.weight(.semibold)).foregroundStyle(AppPalette.primary)
              Text(step.what).font(.subheadline).foregroundStyle(AppPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
            }
            .padding(.top, 5).padding(.bottom, index < plan.steps.count - 1 ? 20 : 0)
          }
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityElement(children: .combine)
        }
      }
    }
    .accessibilityIdentifier("showcaseTimeline")
  }

  // MARK: Plans

  private var selectedProduct: StoreKit.Product? { products.first { $0.id == selection } }
  private var weekly: StoreKit.Product? { products.first { $0.isWeeklyPlan } }

  private func introOffer(_ product: StoreKit.Product) -> StoreKit.Product.SubscriptionOffer? {
    guard introEligible.contains(product.id), let offer = product.subscription?.introductoryOffer, offer.paymentMode != .freeTrial else { return nil }
    return offer
  }

  @ViewBuilder private var plans: some View {
    // Room above the cards for the tags that sit on their top edge.
    VStack(alignment: .leading, spacing: 28) {
      sectionTitle("Pick a plan")
      if loading {
        ProgressView().frame(maxWidth: .infinity, minHeight: 120)
      } else if products.isEmpty {
        VStack(alignment: .leading, spacing: 12) {
          Text("The App Store didn’t send the plans over. Check your connection, then give it another go.")
            .font(.subheadline).foregroundStyle(AppPalette.secondary).fixedSize(horizontal: false, vertical: true)
          Button("Try again") { attempt += 1 }.buttonStyle(PracticeButtonStyle(secondary: true))
            .accessibilityIdentifier("showcaseRetry")
          #if DEBUG
          if model.fixture, !ProcessInfo.processInfo.arguments.contains("--fixture-customer") {
            Button("Simulate purchase") { Task { await PlanCoordinator.shared.fixturePurchase() } }
              .accessibilityIdentifier("showcaseFixturePurchase")
          }
          #endif
        }
      } else {
        let row = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        row {
          ForEach(products) { product in planCard(product) }
        }
        .fixedSize(horizontal: false, vertical: true)
        if let product = selectedProduct { checkout(product) }
      }
    }
    .padding(.top, 8)
  }

  private func planCard(_ product: StoreKit.Product) -> some View {
    let selected = product.id == selection
    let yearly = product.isYearlyPlan
    let saving = yearly ? weekly.flatMap { PlanPricing.yearlySaving(yearly: product.price, weekly: $0.price) } : nil
    let intro = firstWeek(product)
    let tag = intro.map { "First week \($0.displayPrice)" } ?? saving.map { "Save \($0)%" }
    return Button { selection = product.id } label: {
      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .firstTextBaseline) {
          Text(yearly ? "Yearly" : "Weekly").font(.headline).foregroundStyle(AppPalette.primary)
          Spacer(minLength: 4)
          Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.title3).foregroundStyle(selected ? AppPalette.action : AppPalette.secondary)
            .contentTransition(.symbolEffect(.replace))
        }
        Text("\(product.displayPrice) / \(yearly ? "year" : "week")")
          .font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(AppPalette.primary)
          .lineLimit(1).minimumScaleFactor(0.7)
        planDetail(product, yearly: yearly).font(.footnote).foregroundStyle(AppPalette.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
      }
      .padding(16)
      .frame(maxWidth: .infinity, minHeight: 132, maxHeight: .infinity, alignment: .topLeading)
      .background(AppPalette.ticket, in: RoundedRectangle(cornerRadius: 12))
      .overlay {
        RoundedRectangle(cornerRadius: 12)
          .stroke(selected ? AppPalette.action : AppPalette.ticketEdge, lineWidth: selected ? 2 : 1)
      }
      .overlay(alignment: .topTrailing) {
        if let tag {
          Text(tag)
            .font(.caption.weight(.semibold)).monospacedDigit()
            .foregroundStyle(intro != nil ? AppPalette.actionInk : AppPalette.primary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(intro != nil ? AppPalette.action : AppPalette.elevated, in: Capsule())
            .overlay { if intro == nil { Capsule().stroke(AppPalette.ticketEdge, lineWidth: 1) } }
            .offset(x: -12, y: -12)
        }
      }
      .contentShape(RoundedRectangle(cornerRadius: 12))
    }
    .buttonStyle(TicketPressStyle())
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(selected ? .isSelected : [])
    .accessibilityIdentifier("showcasePlan-\(yearly ? "yearly" : "weekly")")
  }

  /// The weekly plan's one-week intro price, when this account can still have it.
  private func firstWeek(_ product: StoreKit.Product) -> StoreKit.Product.SubscriptionOffer? {
    guard product.isWeeklyPlan, let intro = introOffer(product),
          intro.lastsOneWeek else { return nil }
    return intro
  }

  /// The renewal price is the big number (App Review 3.1.2); the first week is called out in gold right under it.
  private func planDetail(_ product: StoreKit.Product, yearly: Bool) -> Text {
    if yearly {
      // The billed price leads (App Review 3.1.2); the per-week figure only puts it next to the weekly plan.
      return Text("That’s \(PlanPricing.weekly(fromYearly: product.price).formatted(product.priceFormatStyle)) a week")
    }
    if let intro = firstWeek(product) {
      return Text("\(Text(intro.displayPrice).foregroundStyle(AppPalette.accent).fontWeight(.semibold)) to start, then \(product.displayPrice) a week")
    }
    return Text("Billed every week")
  }

  /// The terms App Review wants next to the button, the button, then Restore and the legal links.
  private func checkout(_ product: StoreKit.Product) -> some View {
    let yearly = product.isYearlyPlan
    let intro = introOffer(product)
    let terms = firstWeek(product).map { "First week \($0.displayPrice), then \(product.displayPrice) a week. Auto-renews." }
      ?? intro.map { "\($0.displayPrice) to start, then \(product.displayPrice) \(yearly ? "a year" : "a week"). Auto-renews." }
      ?? "\(product.displayPrice) \(yearly ? "a year" : "a week"). Auto-renews, cancel anytime."
    return VStack(spacing: 12) {
      Text(terms).font(.footnote).foregroundStyle(AppPalette.secondary)
        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        .contentTransition(.opacity)
        .accessibilityIdentifier("showcaseTerms")
      Button { buy(product) } label: {
        HStack(spacing: 8) {
          if working { ProgressView().controlSize(.small).tint(AppPalette.actionInk) }
          Text(intro.map { "Start for \($0.displayPrice)" } ?? "Subscribe")
        }
      }
      .buttonStyle(PracticeButtonStyle()).disabled(working)
      .accessibilityIdentifier("showcaseSubscribe")
      HStack(spacing: 20) {
        Button("Restore") { restore() }.accessibilityIdentifier("showcaseRestore")
        Link("Terms", destination: LegalLinks.terms)
        if let privacy = LegalLinks.privacy { Link("Privacy", destination: privacy) }
      }
      .font(.footnote.weight(.medium))
      .tint(AppPalette.secondary)
      .disabled(working)
      if let note { Text(note).font(.footnote).foregroundStyle(AppPalette.secondary).multilineTextAlignment(.center) }
    }
    .frame(maxWidth: .infinity)
    .transaction(value: product.id) { $0.animation = nil }
  }

  // MARK: StoreKit

  private func loadProducts() async {
    loading = true
    let found = (try? await StoreKit.Product.products(for: PlanCoordinator.productIDs)) ?? []
    var eligible: Set<String> = []
    for product in found where await product.subscription?.isEligibleForIntroOffer == true { eligible.insert(product.id) }
    // Weekly first and selected: its first week is the easiest yes.
    products = PlanCoordinator.productIDs.compactMap { id in found.first { $0.id == id } }
    introEligible = eligible
    if selection == nil || !products.contains(where: { $0.id == selection }) { selection = products.first?.id }
    loading = false
  }

  private func buy(_ product: StoreKit.Product) {
    working = true; note = nil
    Task {
      defer { working = false }
      do {
        if case .success(let verification) = try await purchase(product) {
          if case .verified(let transaction) = verification { await transaction.finish() }
          await PlanCoordinator.shared.purchased()
        }
      } catch {
        CrashReporting.reportStore(error, operation: "purchase")
        note = "That didn’t go through. You haven’t been charged."
      }
    }
  }

  private func restore() {
    working = true; note = nil
    Task {
      defer { working = false }
      note = PlanCoordinator.restoreNote(await PlanCoordinator.shared.restore())
    }
  }
}
