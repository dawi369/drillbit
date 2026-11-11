import SwiftUI

/// The Bit tab for a free account: their real map, and they can touch it. A practised dot shows its quote, a new one
/// what interviewers probe there. What Pro reads from the map sits underneath as locked rows, and one See Pro opens
/// the plans.
struct ProShowcaseView: View {
  var model: AppModel
  @State private var appeared = false
  @State private var selected: String?
  @AppStorage("bit.tapHintSeen") private var tapHintSeen = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private static let locked: [(symbol: String, title: String, line: String)] = [
    ("chart.line.uptrend.xyaxis", "Your level", "After three solid reps, Bit places you somewhere from intern to principal. An estimate, not a hiring call."),
    ("scope", "Next up", "The gap worth closing next, picked from your own feedback."),
    ("sunrise", "A question every morning", "Written for you overnight, from what you practised last."),
  ]

  var body: some View {
    let nodes = KnowledgeNode.build(model: model)
    ScrollView {
      VStack(alignment: .leading, spacing: 32) {
        hero.padding(.horizontal, 20)
        VStack(alignment: .leading, spacing: 16) {
          ConstellationMap(nodes: nodes, selected: $selected, appeared: appeared)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("showcaseMap")
            .padding(.horizontal, 4)
            .overlay(alignment: .top) {
              if !tapHintSeen && nodes.contains(where: { $0.state != .unexplored }) {
                Label("Tap", systemImage: "hand.tap.fill")
                  .font(.caption.weight(.semibold)).foregroundStyle(AppPalette.primary)
                  .padding(.horizontal, 10).padding(.vertical, 6)
                  .background(AppPalette.elevated, in: Capsule())
                  .overlay { Capsule().stroke(AppPalette.ticketEdge, lineWidth: 1) }
                  .symbolEffect(.bounce, options: .repeat(2), value: appeared)
                  .transition(.opacity.combined(with: .scale(scale: 0.9)))
                  .accessibilityHidden(true)
              }
            }
            .onChange(of: selected) { _, now in if now != nil { withAnimation(DrillbitMotion.fast) { tapHintSeen = true } } }
          MapLegend().padding(.horizontal, 20)
          Group {
            if let id = selected, let node = nodes.first(where: { $0.id == id }) {
              detail(node).transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 8)))
            } else {
              reaction(mapSummary(nodes)).transition(.opacity)
            }
          }
          .padding(.horizontal, 20)
        }
        VStack(alignment: .leading, spacing: 20) {
          lockedRows
          Button("See Pro") { PlanCoordinator.shared.register(.knowledgeMap) { await model.refresh() } }
          .buttonStyle(PracticeButtonStyle())
          .accessibilityIdentifier("showcaseSeePro")
        }
        .padding(.horizontal, 20)
        .signalEntrance(1)
      }
      .padding(.top, 4).padding(.bottom, 40)
      .frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity)
    }
    .background(AppPalette.background)
    .containerBackground(AppPalette.background, for: .navigation)
    .navigationTitle("Bit")
    .navigationSubtitle("Your map")
    .accessibilityIdentifier("proShowcase")
    .animation(reduceMotion ? nil : DrillbitMotion.reveal, value: selected)
    .task {
      await model.loadTaxonomy()
      await model.loadMemory()
      withAnimation(reduceMotion ? nil : .easeOut(duration: 0.9)) { appeared = true }
    }
  }

  private var hero: some View {
    Text("See what you actually know.")
      .font(.largeTitle.weight(.semibold)).tracking(-0.6)
      .foregroundStyle(AppPalette.primary)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityAddTraits(.isHeader)
      .padding(.top, 12)
      .signalEntrance(0)
  }

  private func mapSummary(_ nodes: [KnowledgeNode]) -> String {
    let explored = nodes.filter { $0.state != .unexplored }.count
    guard explored > 0 else { return "Your map’s empty for now. Do a rep and a dot lights up." }
    return "\(explored) of \(nodes.count) areas on your map so far. Pro reads it and tells you where that puts you."
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

  /// Free, like the feedback it comes from: your quote and what it showed, or what interviewers probe on a new concept.
  private func detail(_ node: KnowledgeNode) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      DrillbitMetadata(text: node.category)
      Text(node.label).font(.title3.weight(.semibold)).foregroundStyle(AppPalette.primary)
      Text(node.statusLine).font(.subheadline.weight(.medium))
        .foregroundStyle(node.state == .strong || node.state == .revisit ? AppPalette.accent : AppPalette.secondary)
      if let evidence = node.evidence {
        Text("“\(evidence.quote)”").font(.subheadline).foregroundStyle(AppPalette.primary).fixedSize(horizontal: false, vertical: true)
        Text(evidence.observation).font(.subheadline).foregroundStyle(AppPalette.secondary).fixedSize(horizontal: false, vertical: true)
      } else if let description = node.description {
        Text(description).font(.subheadline).foregroundStyle(AppPalette.secondary).fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .ticketCard()
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("showcaseDetail")
  }

  private var lockedRows: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 6) { Text("What"); ProWordmark(font: .title3.weight(.semibold)); Text("reads from it") }
        .font(.title3.weight(.semibold)).foregroundStyle(AppPalette.primary)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
      VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(Self.locked.enumerated()), id: \.element.title) { index, row in
          if index > 0 { Divider().overlay(AppPalette.hairline).padding(.leading, 36) }
          HStack(alignment: .top, spacing: 12) {
            Image(systemName: row.symbol).font(.body).foregroundStyle(AppPalette.secondary)
              .frame(width: 24, height: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
              Text(row.title).font(.body.weight(.semibold)).foregroundStyle(AppPalette.primary)
              Text(row.line).font(.subheadline).foregroundStyle(AppPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: "lock.fill").font(.footnote).foregroundStyle(AppPalette.secondary).accessibilityHidden(true)
          }
          .padding(.vertical, 12)
          .accessibilityElement(children: .combine)
          .accessibilityLabel("\(row.title), part of Pro. \(row.line)")
        }
      }
    }
  }
}
