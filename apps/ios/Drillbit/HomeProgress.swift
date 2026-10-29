import SwiftUI

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

/// This week at a glance: a dot per day, gold where a rep landed. Resets every week, so a missed day never wipes anything out.
struct HomeWeekStrip: View {
  /// Start of each day that has a finished rep.
  let days: Set<Date>
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.calendar) private var calendar

  private var week: [Date] {
    guard let start = calendar.dateInterval(of: .weekOfYear, for: .now)?.start else { return [] }
    return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
  }

  var body: some View {
    let today = calendar.startOfDay(for: .now)
    HStack(spacing: 12) {
      ForEach(week, id: \.self) { day in
        let done = days.contains(day)
        let isToday = day == today
        VStack(spacing: 8) {
          Text(day.formatted(.dateTime.weekday(.narrow)))
            .font(.caption2.weight(isToday ? .bold : .medium).monospaced())
            .foregroundStyle(isToday ? AppPalette.primary : AppPalette.secondary)
          ZStack {
            Circle().fill(done ? AppPalette.action : AppPalette.elevated)
            if isToday && !done { Circle().stroke(AppPalette.accent, lineWidth: 1.5) }
          }
          .frame(width: 12, height: 12)
          .scaleEffect(done || reduceMotion ? 1 : 0.84)
          .animation(reduceMotion ? nil : DrillbitMotion.selection, value: done)
        }
        .frame(minWidth: 20)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(spoken)
    .accessibilityIdentifier("homeWeek")
  }

  private var spoken: String {
    let done = week.filter { days.contains($0) }
    guard !done.isEmpty else { return "This week: no reps yet" }
    let names = done.map { calendar.isDateInToday($0) ? "today" : $0.formatted(.dateTime.weekday(.wide)) }
    return "This week: \(done.count) \(done.count == 1 ? "rep day" : "rep days"), " + names.formatted(.list(type: .and))
  }
}

/// A one-time gold sweep across a milestone ticket. Reduce Motion keeps the gold and drops the sweep.
struct FoilSheen: View {
  @State private var phase: CGFloat = -1
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    GeometryReader { proxy in
      LinearGradient(colors: [.clear, .white.opacity(0.28), .clear], startPoint: .leading, endPoint: .trailing)
        .frame(width: proxy.size.width * 0.5)
        .rotationEffect(.degrees(18))
        .offset(x: phase * proxy.size.width * 1.4)
        .opacity(reduceMotion ? 0 : 1)
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
    .task {
      guard !reduceMotion else { return }
      try? await Task.sleep(for: .milliseconds(450))
      withAnimation(.easeInOut(duration: 1.3)) { phase = 1 }
    }
  }
}

/// What a milestone shares: the ticket, flattened to an image.
struct MilestoneShareCard: View {
  let ticket: Int
  let line: String
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(String(format: "No. %03d", ticket))
        .font(.caption.weight(.semibold).monospaced()).tracking(1.2)
        .foregroundStyle(AppPalette.accent)
      Text(line).font(.title2.weight(.semibold)).foregroundStyle(AppPalette.primary)
        .fixedSize(horizontal: false, vertical: true)
      Text("System design reps on Drillbit").font(.subheadline).foregroundStyle(AppPalette.secondary)
    }
    .padding(24)
    .frame(width: 360, alignment: .leading)
    .background(LinearGradient(colors: [AppPalette.accentSoft, AppPalette.ticket], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 12))
    .overlay { RoundedRectangle(cornerRadius: 12).stroke(AppPalette.accent.opacity(0.5), lineWidth: 1) }
    .padding(20)
    .background(AppPalette.background)
  }

  @MainActor static func image(ticket: Int, line: String, scheme: ColorScheme) -> Image? {
    let renderer = ImageRenderer(content: MilestoneShareCard(ticket: ticket, line: line).environment(\.colorScheme, scheme))
    renderer.scale = 3
    return renderer.uiImage.map { Image(uiImage: $0) }
  }
}
