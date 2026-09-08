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
    private var canSearch: Bool { !loading && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var body: some View {
        VStack(spacing: 0) {
            header
            card.padding(.horizontal, 24).padding(.top, 16)
            Text("Applying a match updates title and authors only. Publisher, language and your other details are kept.")
                .font(.system(size: 12)).foregroundStyle(SmallibreTheme.text3).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24).padding(.top, 10)
            footer.padding(.top, 10)
        }
        .frame(width: 600, height: 600)
        .background(SmallibreTheme.sheet)
        .foregroundStyle(SmallibreTheme.text)
        .tint(SmallibreTheme.accent)
        .onDisappear { task?.cancel() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Find book details").font(.system(size: 20, weight: .bold)).tracking(-0.4)
            Text("Search Open Library by title and author. Your book files stay on this Mac.")
                .font(.system(size: 13)).foregroundStyle(SmallibreTheme.text2)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 2)
            HStack(spacing: 8) {
                DesignTextField(placeholder: "Title", text: $title, bordered: true).frame(maxWidth: .infinity)
                DesignTextField(placeholder: "Author", text: $author, bordered: true).frame(width: 150)
                Button { search() } label: { Text("Search").fixedSize() }
                    .buttonStyle(.accentAction(height: 30)).disabled(!canSearch)
                if loading { ProgressView().controlSize(.small) }
            }
            .padding(.top, 16)
            .onSubmit { if canSearch { search() } }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24).padding(.top, 22)
    }

    private var card: some View {
        VStack(spacing: 0) {
            if let error {
                Text(error).font(.system(size: 12)).foregroundStyle(SmallibreTheme.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                Hairline()
            }
            if results.isEmpty { placeholder } else { candidateList }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SmallibreTheme.group)
        .clipShape(.rect(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(SmallibreTheme.separator, lineWidth: 1) }
    }

    private var placeholder: some View {
        VStack(spacing: 0) {
            Image(systemName: Glyph.book).font(.system(size: 30, weight: .light)).foregroundStyle(SmallibreTheme.text3)
            Text(searched ? "No matching books" : "Discover the right match")
                .font(.system(size: 15, weight: .semibold)).padding(.top, 12)
            Text(searched ? "Try fewer title words or leave the author blank." : "Nothing is sent until you search. Suggestions are never applied automatically.")
                .font(.system(size: 13)).foregroundStyle(SmallibreTheme.text2).lineSpacing(4)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320).padding(.top, 4)
        }
        .padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var candidateList: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(results) { candidate in row(candidate) }
            }
            .padding(4)
        }
    }

    private func row(_ candidate: MetadataCandidate) -> some View {
        let picked = candidate.id == selected
        return Button { selected = candidate.id } label: {
            HStack(spacing: 12) {
                SmallibreTheme.covers[coverIndex(candidate.id)].background
                    .frame(width: 34, height: 50)
                    .clipShape(.rect(topLeadingRadius: 2, bottomLeadingRadius: 2, bottomTrailingRadius: 4, topTrailingRadius: 4))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(candidate.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    Text(subline(candidate)).font(.system(size: 12)).lineLimit(1)
                        .foregroundStyle(picked ? SmallibreTheme.onAccent : SmallibreTheme.text2)
                }
                Spacer(minLength: 0)
                Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold))
                    .frame(width: 14).opacity(picked ? 1 : 0).accessibilityHidden(true)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(picked ? SmallibreTheme.accent : .clear, in: .rect(cornerRadius: 7))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(picked ? SmallibreTheme.onAccent : SmallibreTheme.text)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Cancel") { task?.cancel(); dismiss() }.buttonStyle(.control).keyboardShortcut(.cancelAction)
                Button("Apply Selected Details") { apply() }.buttonStyle(.accentAction)
                    .disabled(selected == nil || loading)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(SmallibreTheme.inspector)
        }
    }

    /// Open Library ids are not hex, so the jacket colour comes from our own stable digest of them.
    private func coverIndex(_ id: String) -> Int {
        var value = 0
        for byte in id.utf8 { value = (value &* 31 &+ Int(byte)) & 0xffff }
        return value % SmallibreTheme.covers.count
    }

    private func subline(_ candidate: MetadataCandidate) -> String {
        var parts: [String] = []
        let authors = candidate.authors.joined(separator: ", ")
        if !authors.isEmpty { parts.append(authors) }
        if let year = candidate.firstPublished { parts.append("First published \(String(year))") }
        return parts.joined(separator: " · ")
    }

    private func apply() {
        guard let candidate = results.first(where: { $0.id == selected }) else { return }
        var updated = book
        updated.metadata.title = candidate.title
        if !candidate.authors.isEmpty { updated.metadata.authors = candidate.authors }
        Task { await model.save(updated); if model.error == nil { model.metadataBook = nil } }
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
