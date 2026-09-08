import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NovaCore

@MainActor @Observable
final class AppModel {
    let reader = ReaderModel()
    var books: [LibraryBook] = []
    var selection: UUID?
    var filter = "all"
    var search = ""
    var sort: Sort = .recent
    var error: String?
    var status: String?
    var importing = false
    var progress = 0.0
    var operation: String?
    var preview: PreviewContent?
    var editing: LibraryBook?
    var transferBook: LibraryBook?
    var metadataBook: LibraryBook?
    let metadataLookup = MetadataLookup()
    var importTask: Task<Void, Never>?
    var store: LibraryStore?
    let root: URL
    enum Sort: String, CaseIterable { case recent = "Recently added", title = "Title", author = "Author" }

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--library"), arguments.indices.contains(index + 1) {
            root = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        } else {
            root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Calibre Nova", isDirectory: true)
        }
        do { store = try LibraryStore(root: root) } catch { self.error = error.localizedDescription }
    }
    var selected: LibraryBook? { books.first { $0.id == selection } }
    var visibleBooks: [LibraryBook] {
        let filtered = books.filter {
            (filter == "all" || (filter == "prepared" ? $0.typography.enabled : $0.metadata.format == filter)) &&
            (search.isEmpty || ($0.metadata.title + " " + $0.metadata.authors.joined(separator: " ")).localizedStandardContains(search))
        }
        return filtered.sorted {
            switch sort {
            case .recent: return $0.addedAt > $1.addedAt
            case .title: return $0.metadata.title.localizedStandardCompare($1.metadata.title) == .orderedAscending
            case .author: return $0.metadata.authors.joined().localizedStandardCompare($1.metadata.authors.joined()) == .orderedAscending
            }
        }
    }
    var collectionTitle: String {
        switch filter { case "EPUB": "EPUB books"; case "MOBI": "MOBI books"; case "AZW3": "Kindle books"; case "prepared": "Personalized"; default: "Your library" }
    }
    func start() async {
        await reload()
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--import"), args.indices.contains(index + 1) { importURLs([URL(fileURLWithPath: args[index + 1])]) }
    }
    func reload() async {
        guard let store else { return }
        do { books = try await store.books() } catch { self.error = error.localizedDescription }
    }
    func chooseBooks() {
        let panel = NSOpenPanel()
        panel.title = "Add books to your library"
        panel.prompt = "Add books"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType.epub] + ["mobi", "azw3", "azw", "prc"].compactMap { UTType(filenameExtension: $0) }
        if panel.runModal() == .OK { importURLs(panel.urls) }
    }
    func importURLs(_ urls: [URL]) {
        guard !importing, let store else { return }
        importing = true; progress = 0; status = nil
        importTask = Task {
            var added = 0, duplicates = 0, failures: [String] = []
            for (index, url) in urls.enumerated() {
                if Task.isCancelled { break }
                operation = "Adding \(index + 1) of \(urls.count) · \(url.lastPathComponent)"
                let access = url.startAccessingSecurityScopedResource()
                do {
                    let result = try await store.importBook(from: url)
                    if result.isDuplicate { duplicates += 1 } else { added += 1 }
                    selection = result.book.id
                } catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
                if access { url.stopAccessingSecurityScopedResource() }
                progress = Double(index + 1) / Double(urls.count)
                await reload()
            }
            status = "\(added) \(added == 1 ? "book" : "books") added" + (duplicates > 0 ? " · \(duplicates) already in your library" : "")
            if !failures.isEmpty { error = failures.prefix(6).joined(separator: "\n\n") + (failures.count > 6 ? "\n\n…and \(failures.count - 6) more files." : "") }
            importing = false; operation = nil; importTask = nil
        }
    }
    func save(_ book: LibraryBook) async {
        guard let store else { return }
        do { try await store.update(book); await reload(); editing = nil; status = "Changes saved · your original is preserved" }
        catch { self.error = error.localizedDescription }
    }
    func export(_ book: LibraryBook, destination: URL? = nil) {
        guard let store, operation == nil else { return }
        let folder: URL
        if let destination { folder = destination } else {
            let panel = NSOpenPanel()
            panel.title = "Export \(book.metadata.title)"
            panel.message = book.metadata.format == "EPUB" ? "Exports an EPUB with your saved changes. Existing files are kept." : "Exports the original \(book.metadata.format) file. Library metadata changes are not embedded yet."
            panel.prompt = "Export here"; panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            folder = url
        }
        operation = "Preparing \(book.metadata.title)…"
        Task {
            let access = folder.startAccessingSecurityScopedResource()
            defer { if access { folder.stopAccessingSecurityScopedResource() }; operation = nil }
            do {
                let url = try await store.export(book.id, to: folder)
                status = "Exported and verified · \(url.lastPathComponent)"
                if let device = reader.folder, folder.path.hasPrefix(device.path) { reader.refresh() }
                transferBook = nil
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch { self.error = error.localizedDescription }
        }
    }
    func openPreview(_ book: LibraryBook) {
        guard let store, operation == nil else { return }
        guard book.metadata.format == "EPUB" else { error = "Chapter preview currently supports EPUB. You can export this \(book.metadata.format) unchanged."; return }
        operation = "Preparing preview…"
        Task {
            do {
                let data = try await store.preparedData(for: book.id)
                let epub = try await Task.detached { try EPUBBook(data: data) }.value
                guard epub.chapters.allSatisfy({ ["html", "xhtml", "htm"].contains(($0 as NSString).pathExtension.lowercased()) }) else {
                    throw BookError.unsupported("This book uses a chapter format that Nova cannot preview yet. You can still export the original.")
                }
                preview = PreviewContent(id: UUID(), title: book.metadata.title, epub: epub)
            } catch { self.error = error.localizedDescription }
            operation = nil
        }
    }
    func revealOriginal(_ book: LibraryBook) {
        guard let store else { return }
        Task {
            do { NSWorkspace.shared.activateFileViewerSelecting([try await store.originalURL(for: book.id)]) }
            catch { self.error = error.localizedDescription }
        }
    }
    func sample() {
        if let url = Bundle.main.url(forResource: "Small Hours", withExtension: "epub") { importURLs([url]) }
        else { error = "The sample book is included in the packaged application. Run scripts/build-app.sh to create it." }
    }
}

struct PreviewContent: Identifiable { let id: UUID; let title: String; let epub: EPUBBook }
