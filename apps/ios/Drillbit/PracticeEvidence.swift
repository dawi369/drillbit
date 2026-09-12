import SwiftUI
import UniformTypeIdentifiers

struct PracticeEvidenceView: View {
  var model: AppModel
  var body: some View {
    List {
      Section {
        Text("Feedback from your latest 100 sessions, linked to your answers. Counts track practice, not mastery.")
          .foregroundStyle(.secondary)
      }
      ForEach(model.taxonomy, id: \.id) { concept in
        let observations = (model.memory.evidence ?? []).filter { $0.conceptId == concept.id }
        let coverage = model.libraryCoverage.first { $0.conceptId == concept.id }
        Section(concept.label) {
          if let coverage { LabeledContent("Completed attempts", value: String(coverage.completedAttempts)) }
          if observations.isEmpty {
            Text("No recorded evidence yet").foregroundStyle(.secondary)
          }
          ForEach(observations) { evidence in
            VStack(alignment: .leading, spacing: 8) {
              Text(evidence.signal == "demonstrated" ? "Demonstrated in practice" : "Worth practising")
                .font(.subheadline.weight(.medium))
              Text(evidence.observation)
              Text("“\(evidence.quote)”").foregroundStyle(.secondary).textSelection(.enabled)
              Text(evidence.assistance == "assisted" ? "Assistance was available" : "Independence not established")
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
    Form {
      Text("Export your cloud questions, answers, conversations, feedback and practice settings as JSON. Local edits must sync first. Provider keys and sign-in credentials are excluded.")
      Button(working ? "Preparing export…" : "Export practice data") {
        Task {
          working = true; failure = nil
          defer { working = false }
          let account = model.bootstrap?.account.id
          do {
            await model.sync()
            guard !model.hasPendingWrites else { throw APIError(code: "pending_writes", message: "Connect and sync your pending edits before exporting.", status: 0) }
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
