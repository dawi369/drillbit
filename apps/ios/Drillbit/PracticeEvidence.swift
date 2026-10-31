import SwiftUI
import UniformTypeIdentifiers

struct PracticeEvidenceView: View {
  var model: AppModel
  /// Only areas with something to show; untouched concepts would be a wall of empty sections.
  private var concepts: [PracticeConcept] {
    model.taxonomy.filter { concept in
      (model.memory.evidence ?? []).contains { $0.conceptId == concept.id }
        || (model.libraryCoverage.first { $0.conceptId == concept.id }?.completedAttempts ?? 0) > 0
    }
  }
  var body: some View {
    SignalList {
      Section {
        Text("What your last 100 sessions showed, each linked to the answer behind it. Counts show how often you practised, so read them as a rough guide.")
          .foregroundStyle(.secondary)
      }
      if concepts.isEmpty {
        ContentUnavailableView("Nothing here yet", systemImage: AppIcon.books.rawValue,
          description: Text("Finish a session and what you showed will land here."))
      }
      ForEach(concepts, id: \.id) { concept in
        let observations = (model.memory.evidence ?? []).filter { $0.conceptId == concept.id }
        let coverage = model.libraryCoverage.first { $0.conceptId == concept.id }
        Section(concept.label) {
          if let coverage { LabeledContent("Completed attempts", value: String(coverage.completedAttempts)) }
          if observations.isEmpty {
            Text("Nothing recorded yet").foregroundStyle(.secondary)
          }
          ForEach(observations) { evidence in
            VStack(alignment: .leading, spacing: 8) {
              Text(evidence.signal == "demonstrated" ? "Shown in practice" : "Worth practising")
                .font(.subheadline.weight(.medium))
              Text(evidence.observation)
              Text("“\(evidence.quote)”").foregroundStyle(.secondary).textSelection(.enabled)
              Text(evidence.assistance == "assisted" ? "Help was on hand" : "Not tried solo yet")
                .font(.caption).foregroundStyle(.secondary)
              if let id = evidence.sessionId, let session = model.memory.sessions.first(where: { $0.id == id }) {
                NavigationLink("View session") { SessionDetailView(model: model, initial: session) }
              }
            }
          }
        }
      }
    }.navigationTitle("Practice evidence")
  }
}

struct PracticeExportDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.json] }
  var data: Data
  init(data: Data = Data()) { self.data = data }
  init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
struct PracticeExportView: View {
  var model: AppModel
  @State private var working = false
  @State private var document: PracticeExportDocument?
  @State private var exporting = false
  @State private var failure: String?
  var body: some View {
    SignalList {
      Text("Take everything you’ve done here with you as JSON: questions, answers, conversations, feedback and settings. Your keys and sign-in details stay out of it.")
      Button(working ? "Preparing export…" : "Export practice data") {
        Task {
          working = true; failure = nil
          defer { working = false }
          let account = model.bootstrap?.account.id
          do {
            await model.sync()
            guard !model.hasPendingWrites else { throw APIError(code: "pending_writes", message: "Still saving your latest changes. Try the export again in a moment.", status: 0) }
            var pages: [[String: Any]] = []
            var cursor: String?
            repeat {
              try Task.checkCancellation()
              var query = URLComponents()
              if let cursor { query.queryItems = [URLQueryItem(name: "cursor", value: cursor)] }
              let data = try await model.api.exportPage(query: query.percentEncodedQuery)
              guard account == model.bootstrap?.account.id else { throw CancellationError() }
              let page = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
              pages.append(page); cursor = page["nextCursor"] as? String
            } while cursor != nil
            document = PracticeExportDocument(data: try JSONSerialization.data(withJSONObject: ["version": 1, "pages": pages], options: [.prettyPrinted, .sortedKeys]))
            exporting = true
          } catch { failure = error.localizedDescription }
        }
      }.disabled(working || model.fixture)
      if let failure { Text(failure).foregroundStyle(.secondary) }
    }.navigationTitle("Export data")
      .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "Drillbit-practice") { result in
        if case .failure(let error) = result { failure = error.localizedDescription }
        document = nil
      }
  }
}
