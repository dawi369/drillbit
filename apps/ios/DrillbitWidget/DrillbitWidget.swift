import SwiftUI
import WidgetKit

struct PracticeEntry: TimelineEntry {
  let date: Date
  let snapshot: WidgetSnapshot?
}
struct PracticeProvider: TimelineProvider {
  func placeholder(in context: Context) -> PracticeEntry {
    PracticeEntry(date: Date(), snapshot: nil)
  }
  func getSnapshot(in context: Context, completion: @escaping (PracticeEntry) -> Void) {
    completion(PracticeEntry(date: Date(), snapshot: SharedStore.snapshot()))
  }
  func getTimeline(
    in context: Context, completion: @escaping @Sendable (Timeline<PracticeEntry>) -> Void
  ) {
    Task {
      var snapshot = SharedStore.snapshot()
      if let base = SharedStore.secret("apiURL"), let token = SharedStore.secret("widgetToken"),
        let url = URL(string: base)?.appendingPathComponent("v1/widget")
      {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let (data, response) = try? await URLSession.shared.data(for: request),
          (response as? HTTPURLResponse)?.statusCode == 200,
          let fresh = try? JSONDecoder.api.decode(WidgetSnapshot.self, from: data)
        {
          snapshot = fresh
          try? SharedStore.save(fresh)
        }
      }
      completion(
        Timeline(
          entries: [PracticeEntry(date: Date(), snapshot: snapshot)],
          policy: .after(Date().addingTimeInterval(3600))))
    }
  }
}
struct PracticeWidgetView: View {
  @Environment(\.widgetFamily) private var family
  var entry: PracticeEntry
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Drillbit").font(.caption).foregroundStyle(.secondary)
      if let challenge = entry.snapshot?.challenge {
        Text(challenge.title).font(.headline).lineLimit(3)
        if family == .systemMedium {
          Text(challenge.prompt).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        Spacer(minLength: 4)
        Text(challenge.lifecycle == "in_progress" ? "Resume practice" : "Open challenge").font(
          .subheadline
        ).foregroundStyle(.tint)
      } else {
        Text("Room for one good question.").font(.headline)
        Spacer(minLength: 4)
        Text("Open Drillbit").font(.subheadline).foregroundStyle(.tint)
      }
    }.containerBackground(.background, for: .widget)
      .widgetURL(
        URL(
          string: entry.snapshot?.challenge.map { "drillbit://challenge/\($0.id)" }
            ?? "drillbit://today"))
  }
}
@main struct DrillbitWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: SharedStore.widgetKind, provider: PracticeProvider()) {
      PracticeWidgetView(entry: $0)
    }.configurationDisplayName("Daily practice").description(
      "One worthwhile question, ready when you are."
    ).supportedFamilies([.systemSmall, .systemMedium])
  }
}
