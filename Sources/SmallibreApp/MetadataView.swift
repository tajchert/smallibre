import SwiftUI
import SmallibreCore

struct MetadataView: View {
    @Bindable var model: AppModel
    let book: LibraryBook
    @State private var title: String
    @State private var author: String
    @State private var results: [MetadataCandidate] = []
    @State private var selected: String?
    @State private var loading = false
    @State private var searched = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    init(model: AppModel, book: LibraryBook) {
        self.model = model; self.book = book
        _title = State(initialValue: book.metadata.title); _author = State(initialValue: book.metadata.authors.first ?? "")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Find book details").font(.system(size: 27, design: .serif))
            Text("Search Open Library by title and author. Your book files stay on this Mac.").font(.callout).foregroundStyle(.secondary)
            HStack { TextField("Title", text: $title); TextField("Author", text: $author).frame(width: 170) }.textFieldStyle(.roundedBorder)
            HStack {
                Button("Search Open Library", systemImage: "magnifyingglass") { search() }.disabled(loading || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if loading { ProgressView().controlSize(.small) }
            }
            if let error { Text(error).font(.callout).foregroundStyle(.secondary) }
            if results.isEmpty {
                ContentUnavailableView(searched ? "No matching books" : "Discover the right match", systemImage: "text.book.closed", description: Text(searched ? "Try fewer title words or leave the author blank." : "Nothing is sent until you search. Suggestions are never applied automatically."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(results, selection: $selected) { candidate in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(candidate.title).font(.headline)
                        Text(candidate.authors.joined(separator: ", ")).font(.callout).foregroundStyle(.secondary)
                        if let year = candidate.firstPublished { Text("First published \(String(year))").font(.caption).foregroundStyle(.tertiary) }
                    }.padding(.vertical, 5).tag(candidate.id)
                }.listStyle(.inset).clipShape(.rect(cornerRadius: 8))
            }
            Text("Applying a match updates title and authors only. Check the edition; publisher, language and your other details are kept.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { task?.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply selected details") {
                    guard let candidate = results.first(where: { $0.id == selected }) else { return }
                    var updated = book
                    updated.metadata.title = candidate.title
                    if !candidate.authors.isEmpty { updated.metadata.authors = candidate.authors }
                    Task { await model.save(updated); if model.error == nil { model.metadataBook = nil } }
                }.buttonStyle(.borderedProminent).disabled(selected == nil || loading)
            }
        }.padding(26).frame(width: 590, height: 590).background(SmallibreTheme.canvas).tint(SmallibreTheme.accent)
            .onDisappear { task?.cancel() }
    }
    private func search() {
        loading = true; error = nil; selected = nil
        task = Task {
            do {
                results = try await model.metadataLookup.search(title: title, author: author)
                searched = true
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
            loading = false
        }
    }
}
