import SwiftUI

/// Library at a glance: what's worth another go, which areas you've worked, and your reps as tickets by week.
/// Per-question detail and the skipped list stay one tap away; the old filtered list is developer-only.
struct LibraryHomeView: View {
  var model: AppModel
  @State private var area: String?
  @State private var search = ""
  @State private var retrying: LibraryQuestion?
  @State private var loadingRetry: String?
  @State private var started: Challenge?
  @State private var retryFailure: String?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var developer: Bool { model.bootstrap?.capabilities?.developerTools == true }
  /// Finished reps, newest first. Warm-ups never counted, so they don't show either.
  private var reps: [Challenge] {
    model.memory.sessions.filter { $0.lifecycle == "completed" && !$0.isWarmUp }
      .sorted { ($0.completedAt ?? "") > ($1.completedAt ?? "") }
  }
  private var shown: [Challenge] {
    reps.filter { rep in
      (area == nil || (rep.conceptIds ?? []).contains(area!) || rep.primaryConceptId == area)
        && (search.isEmpty || rep.title.localizedCaseInsensitiveContains(search))
    }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        if reps.isEmpty {
          ContentUnavailableView("Your library", systemImage: AppIcon.books.rawValue,
                                 description: Text("Finished questions land here, with the one thing to carry forward."))
            .padding(.top, 48)
        } else {
          if !areas.isEmpty { areaStrip }
          if !worthAnotherGo.isEmpty { worthSection }
          history
        }
      }
      .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 40)
      .frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity)
    }
    .background(AppPalette.background)
    .containerBackground(AppPalette.background, for: .navigation)
    .navigationTitle("Library")
    .navigationSubtitle(statsLine ?? "")
    .searchable(text: $search, prompt: "Search your questions")
    .toolbar {
      Menu {
        NavigationLink { LibraryView(model: model, skipped: true) } label: { Label("Skipped questions", systemImage: AppIcon.skip.rawValue) }
        if developer {
          NavigationLink { LibraryView(model: model) } label: { Label("All questions", systemImage: AppIcon.books.rawValue) }
          NavigationLink { PracticeEvidenceView(model: model) } label: { Label("Practice evidence", systemImage: "checklist") }
        }
      } label: { Image(systemName: AppIcon.more.rawValue) }.accessibilityLabel("Library menu")
    }
    .animation(reduceMotion ? nil : DrillbitMotion.reveal, value: area)
    .task { await model.loadTaxonomy(); await model.loadMemory() }
    .refreshable { await model.loadMemory() }
    .sheet(item: $retrying, onDismiss: { if let started { model.presented = started; self.started = nil } }) { question in
      QuestionRetrySheet(model: model, question: question, onStarted: { started = $0; retrying = nil }, close: { retrying = nil })
    }
    .alert("Couldn’t open that question", isPresented: Binding(get: { retryFailure != nil }, set: { if !$0 { retryFailure = nil } })) {
      Button("OK") { retryFailure = nil }
    } message: { Text(retryFailure ?? "") }
  }

  // MARK: Stats

  private var statsLine: String? {
    guard let stats = model.memory.statistics, stats.completed > 0 else { return nil }
    let total = "\(stats.completed) \(stats.completed == 1 ? "rep" : "reps")"
    return stats.lastSevenDays > 0 ? "\(total) · \(stats.lastSevenDays) this week" : total
  }

  // MARK: Areas

  private struct Area: Identifiable { let id: String; let label: String; let count: Int; let stale: Bool }
  /// Areas you've worked, most-practised first. A dot marks ones untouched for two weeks.
  private var areas: [Area] {
    var counts: [String: (count: Int, last: Date?)] = [:]
    for rep in reps {
      let date = rep.completedAt.flatMap(Date.fromAPI)
      for id in Set((rep.conceptIds ?? []) + [rep.primaryConceptId].compactMap { $0 }) {
        let previous = counts[id]
        counts[id] = ((previous?.count ?? 0) + 1, [previous?.last, date].compactMap { $0 }.max())
      }
    }
    let twoWeeks = Date().addingTimeInterval(-14 * 86_400)
    return counts.compactMap { id, value in
      guard let label = model.taxonomy.first(where: { $0.id == id })?.label else { return nil }
      return Area(id: id, label: label, count: value.count, stale: (value.last ?? .distantPast) < twoWeeks)
    }
    .sorted { $0.count == $1.count ? $0.label < $1.label : $0.count > $1.count }
  }

  private var areaStrip: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 8) {
        chip(label: "All", count: nil, stale: false, selected: area == nil) { area = nil }
        ForEach(areas) { item in
          chip(label: item.label, count: item.count, stale: item.stale, selected: area == item.id) { area = area == item.id ? nil : item.id }
        }
      }
      .padding(.horizontal, 20)
    }
    .scrollIndicators(.hidden)
    .padding(.horizontal, -20)
    .accessibilityIdentifier("libraryAreas")
  }

  private func chip(label: String, count: Int?, stale: Bool, selected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 6) {
        if stale { Circle().fill(AppPalette.accent).frame(width: 6, height: 6).accessibilityHidden(true) }
        Text(label).font(.subheadline.weight(.medium))
        if let count { Text("\(count)").font(.subheadline.monospacedDigit()).opacity(0.65) }
      }
      .foregroundStyle(selected ? AppPalette.actionInk : AppPalette.primary)
      .padding(.horizontal, 16).frame(minHeight: 36)
      .background(selected ? AppPalette.action : AppPalette.elevated, in: Capsule())
      .overlay { if !selected { Capsule().stroke(AppPalette.hairline, lineWidth: 0.5) } }
      .frame(minHeight: 44)
      .contentShape(Capsule())
    }
    .buttonStyle(DrillbitPressStyle())
    .accessibilityLabel([label, count.map { "\($0) reps" }, stale ? "not practised in two weeks" : nil].compactMap { $0 }.joined(separator: ", "))
    .accessibilityAddTraits(selected ? .isSelected : [])
    .accessibilityIdentifier("libraryArea-" + label)
  }

  // MARK: Worth another go

  private struct Revisit: Identifiable { let rep: Challenge; let fix: String; var id: String { rep.id } }
  /// Up to three questions whose feedback left something to fix, and that haven't been tried again since.
  private var worthAnotherGo: [Revisit] {
    var seen = Set<String>()
    var picks: [Revisit] = []
    for rep in shown {
      guard let question = rep.questionId, seen.insert(question).inserted else { continue }
      let gap = rep.reflection?.evidence?.first { $0.signal == "needs_practice" }?.observation
      let fix = (gap ?? rep.reflection?.improve)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !fix.isEmpty else { continue }
      picks.append(Revisit(rep: rep, fix: fix))
      if picks.count == 3 { break }
    }
    return picks
  }

  private var worthSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      SignalEyebrow(text: "Worth another go")
      ForEach(worthAnotherGo) { item in worthCard(item) }
    }
  }

  private func worthCard(_ item: Revisit) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      if let area = areaLabel(item.rep) { DrillbitMetadata(text: area) }
      Text(item.fix).font(.body.weight(.medium)).foregroundStyle(AppPalette.primary)
        .lineLimit(4).fixedSize(horizontal: false, vertical: true)
      HStack(alignment: .center, spacing: 12) {
        Text(item.rep.title).font(.subheadline).foregroundStyle(AppPalette.secondary).lineLimit(2)
        Spacer(minLength: 8)
        Button { openRetry(item.rep) } label: {
          HStack(spacing: 6) {
            if loadingRetry == item.rep.id { ProgressView().controlSize(.small).tint(AppPalette.actionInk) }
            Text("Try again")
          }
          .font(.subheadline.weight(.semibold)).foregroundStyle(AppPalette.actionInk)
          .padding(.horizontal, 16).frame(minHeight: 36)
          .background(AppPalette.action, in: Capsule())
          .frame(minHeight: 44).contentShape(Capsule())
        }
        .buttonStyle(DrillbitPressStyle())
        .disabled(loadingRetry != nil)
        .accessibilityLabel("Try \(item.rep.title) again")
        .accessibilityIdentifier("worthTryAgain")
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(AppPalette.ticket, in: RoundedRectangle(cornerRadius: 12))
    .overlay { RoundedRectangle(cornerRadius: 12).stroke(AppPalette.ticketEdge, lineWidth: 1) }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("worth-" + item.rep.id)
  }

  private func openRetry(_ rep: Challenge) {
    guard let id = rep.questionId else { return }
    loadingRetry = rep.id
    Task {
      defer { loadingRetry = nil }
      do { retrying = try await model.libraryDetail(id: id, path: "questions/" + id).question }
      catch { retryFailure = "Check your connection and try again." }
    }
  }

  // MARK: History

  private var history: some View {
    VStack(alignment: .leading, spacing: 24) {
      if shown.isEmpty {
        Text(search.isEmpty ? "Nothing in this area yet." : "No questions match “\(search)”.")
          .font(.subheadline).foregroundStyle(AppPalette.secondary)
      }
      ForEach(weeks, id: \.title) { week in
        VStack(alignment: .leading, spacing: 12) {
          SignalEyebrow(text: week.title)
          ForEach(week.reps) { rep in
            NavigationLink { SessionDetailView(model: model, initial: rep) } label: { repCard(rep) }
              .buttonStyle(TicketPressStyle())
              .accessibilityIdentifier("library-rep-" + rep.id)
          }
        }
      }
      if reps.count >= 100 {
        NavigationLink("Older reps") { HistoryView(model: model) }.font(.subheadline.weight(.medium))
      }
    }
  }

  private func repCard(_ rep: Challenge) -> some View {
    let date = rep.completedAt.flatMap(Date.fromAPI)
    let line = rep.reflection?.takeaway.trimmingCharacters(in: .whitespacesAndNewlines)
    return VStack(alignment: .leading, spacing: 8) {
      if rep.ticket != nil || date != nil {
        TicketHeader(number: rep.ticket.map { String(format: "No. %03d", $0) } ?? "", detail: date?.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) ?? "")
      }
      Text(rep.title).font(.headline).foregroundStyle(AppPalette.primary)
        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
      if let line, !line.isEmpty {
        Text(line).font(.subheadline).foregroundStyle(AppPalette.secondary)
          .multilineTextAlignment(.leading).lineLimit(2).fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(AppPalette.ticket, in: RoundedRectangle(cornerRadius: 12))
    .overlay { RoundedRectangle(cornerRadius: 12).stroke(AppPalette.ticketEdge, lineWidth: 1) }
    .contentShape(RoundedRectangle(cornerRadius: 12))
  }

  private struct Week { let title: String; let reps: [Challenge] }
  /// This week, last week, then by month.
  private var weeks: [Week] {
    let calendar = Calendar.current
    let now = Date()
    let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)
    let lastWeek = thisWeek.flatMap { calendar.dateInterval(of: .weekOfYear, for: $0.start.addingTimeInterval(-1)) }
    var order: [String] = []
    var grouped: [String: [Challenge]] = [:]
    for rep in shown {
      let title: String
      if let date = rep.completedAt.flatMap(Date.fromAPI) {
        if thisWeek?.contains(date) == true { title = "This week" }
        else if lastWeek?.contains(date) == true { title = "Last week" }
        else if calendar.isDate(date, equalTo: now, toGranularity: .year) { title = date.formatted(.dateTime.month(.wide)) }
        else { title = date.formatted(.dateTime.month(.wide).year()) }
      } else { title = "Earlier" }
      if grouped[title] == nil { order.append(title) }
      grouped[title, default: []].append(rep)
    }
    return order.map { Week(title: $0, reps: grouped[$0] ?? []) }
  }

  private func areaLabel(_ rep: Challenge) -> String? {
    let id = rep.primaryConceptId ?? rep.conceptIds?.first
    return id.flatMap { id in model.taxonomy.first { $0.id == id }?.label }
  }
}

/// The question as it was, and one button to practise it again. Used from a question's page and from
/// Library's "Worth another go".
struct QuestionRetrySheet: View {
  var model: AppModel
  let question: LibraryQuestion
  let onStarted: (Challenge) -> Void
  let close: () -> Void
  @State private var busy = false
  @State private var failure: String?
  @State private var command = UUID().uuidString
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Text(question.title).font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
          QuestionBody(markup: question.prompt).textSelection(.enabled)
          if let failure { Text(failure).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(24)
      }
      .safeAreaInset(edge: .bottom) {
        Button {
          Task {
            busy = true; defer { busy = false }
            let account = model.bootstrap?.account.id
            do {
              let attempt = try await model.startLibraryQuestion(question, command: command)
              guard model.bootstrap?.account.id == account, let account else { return }
              _ = try await model.disk.load(account: account, challenge: attempt)
              model.bootstrap?.challenge = attempt
              onStarted(attempt)
            } catch { failure = error.localizedDescription }
          }
        } label: {
          HStack(spacing: 8) {
            if busy { ProgressView().controlSize(.small).tint(AppPalette.actionInk) }
            Text("Start practice")
          }
        }
        .buttonStyle(PracticeButtonStyle()).disabled(busy).padding(24).background(AppPalette.background)
        .accessibilityIdentifier("retryStart")
      }
      .background(AppPalette.background)
      .navigationTitle("Question preview").navigationBarTitleDisplayMode(.inline)
      .toolbar { Button("Close", action: close) }
    }
    .presentationBackground(AppPalette.background)
  }
}
