import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SmallibreCore

@MainActor @Observable
final class AppModel {
    let reader = ReaderModel()
    var books: [LibraryBook] = []
    var librarySelection: Set<UUID> = [] {
        didSet {
            if librarySelection.count == 1 { selectionAnchor = librarySelection.first }
            else if librarySelection.isEmpty { selectionAnchor = nil }
        }
    }
    private var selectionAnchor: UUID?
    var selection: UUID? {
        get { librarySelection.count == 1 ? librarySelection.first : nil }
        set { librarySelection = Set(newValue.map { [$0] } ?? []); selectionAnchor = newValue }
    }
    var bulkEditing: BulkEditSelection?
    var libraryList = false
    var selectedLibraryBooks: [LibraryBook] {
        filter == "device" ? [] : visibleBooks.filter { librarySelection.contains($0.id) }
    }
    func selectLibraryBook(_ id: UUID, extending: Bool = false, toggling: Bool = false) {
        let ids = visibleBooks.map(\.id)
        guard let end = ids.firstIndex(of: id) else { return }
        if extending, let anchor = selectionAnchor, let start = ids.firstIndex(of: anchor) {
            let range = Set(ids[min(start, end)...max(start, end)])
            librarySelection = toggling ? librarySelection.union(range) : range
        } else if toggling {
            if librarySelection.contains(id) { librarySelection.remove(id) } else { librarySelection.insert(id) }
            selectionAnchor = id
        } else { selection = id }
    }
    func editSelectedBooks() {
        guard commandsAvailable else { return }
        let books = selectedLibraryBooks
        if books.count == 1 { editing = books[0] }
        else if books.count > 1 { bulkEditing = BulkEditSelection(ids: books.map(\.id)) }
    }
    func saveBulk(_ edit: BulkMetadataEdit, ids: [UUID]) async throws {
        guard let store else { throw BookError.invalid("The library is unavailable.") }
        try await store.updateBooks(ids: ids, edit: edit)
        await reload()
        bulkEditing = nil
        status = "Updated \(ids.count) books · originals preserved"
    }
    var filter = "all"
    var search = ""
    var readState: LibraryQuery.ReadState = .any
    var tagFilter = ""
    var seriesFilter = ""
    var savedFilters: [SavedLibraryFilter] = []
    var namingFilter = false
    var currentQuery: LibraryQuery {
        LibraryQuery(text: search, collection: ["read", "unread"].contains(filter) ? "all" : filter,
                     readState: filter == "read" ? .read : filter == "unread" ? .unread : readState,
                     tag: tagFilter, series: seriesFilter)
    }
    var allTags: [String] { Array(Set(books.flatMap { $0.organization.tags })).sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    var allSeries: [String] { Array(Set(books.map { $0.organization.series }.filter { !$0.isEmpty })).sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    func applyFilter(_ saved: SavedLibraryFilter) {
        filter = saved.query.collection; search = saved.query.text; readState = saved.query.readState
        tagFilter = saved.query.tag; seriesFilter = saved.query.series
        librarySelection = []
    }
    func clearOrganizationFilters() { readState = .any; tagFilter = ""; seriesFilter = "" }
    func saveCurrentFilter(name: String) async throws {
        guard let store else { throw BookError.invalid("The library is unavailable.") }
        try await store.saveFilter(SavedLibraryFilter(name: name, query: currentQuery))
        savedFilters = try await store.savedFilters()
        namingFilter = false
    }
    func deleteSavedFilter(_ saved: SavedLibraryFilter) {
        guard let store else { return }
        Task {
            do { try await store.deleteFilter(id: saved.id); savedFilters = try await store.savedFilters() }
            catch { self.error = error.localizedDescription }
        }
    }
    var sort: Sort = .recent
    var sortReversed = false
    var sortAscending: Bool { (sort != .recent) != sortReversed }
    func selectSort(_ selected: Sort) {
        if sort == selected { sortReversed.toggle() }
        else { sort = selected; sortReversed = false }
    }
    var startupFailure: String?
    private var usesDefaultLibrary = true
    var error: String?
    var status: String?
    var importing = false
    var progress = 0.0
    var operation: String?
    var preview: PreviewContent?
    var editing: LibraryBook?
    var transferBook: LibraryBook?
    var exportBook: LibraryBook?
    var metadataBook: LibraryBook?
    let metadataLookup = MetadataLookup()
    var importTask: Task<Void, Never>?
    var store: LibraryStore?
    let root: URL
    enum Sort: String, CaseIterable { case title = "Title", author = "Author", recent = "Recently added", format = "Format", series = "Series" }

    init(rootOverride: URL? = nil, initialize: Bool = true) {
        let arguments = ProcessInfo.processInfo.arguments
        if let rootOverride { root = rootOverride; usesDefaultLibrary = false }
        else if let index = arguments.firstIndex(of: "--library"), arguments.indices.contains(index + 1) {
            root = URL(fileURLWithPath: arguments[index + 1], isDirectory: true); usesDefaultLibrary = false
        } else {
            root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Smallibre", isDirectory: true)
        }
        reader.localRoot = root
        if initialize { initializeLibrary() }
    }
    func initializeLibrary() {
        do {
            if usesDefaultLibrary {
                guard NSRunningApplication.runningApplications(withBundleIdentifier: LibraryLocation.legacyBundleIdentifier).isEmpty else {
                    throw BookError.invalid("Quit the previous app before opening Smallibre so its library can be migrated safely.")
                }
                _ = try LibraryLocation.prepare(in: root.deletingLastPathComponent())
            }
            store = try LibraryStore(root: root)
            reader.libraryReady = true; startupFailure = nil
        } catch { reader.libraryReady = false; startupFailure = error.localizedDescription }
    }
    var selectedDeviceBook: ReaderBook? {
        guard filter == "device" else { return nil }
        let selected = reader.selectedBooks(search: search)
        return selected.count == 1 ? selected.first : nil
    }
    var selected: LibraryBook? {
        if filter == "device" {
            return reader.libraryBook(deviceHash: selectedDeviceBook?.hash, library: books)
        }
        let selected = selectedLibraryBooks
        return selected.count == 1 ? selected.first : nil
    }
    var commandsAvailable: Bool {
        store != nil && editing == nil && bulkEditing == nil && !namingFilter && preview == nil &&
        transferBook == nil && exportBook == nil && metadataBook == nil && error == nil
    }
    func exportUsesReader(_ destination: URL) -> Bool {
        guard let folder = reader.folder else { return false }
        let root = folder.standardizedFileURL.path
        let path = destination.standardizedFileURL.path
        return path == root || path.hasPrefix(root + "/")
    }
    func exportNeedsHelper(_ destination: URL) -> Bool {
        destination.standardizedFileURL.path.hasPrefix("/Volumes/") || exportUsesReader(destination)
    }
    var commandSelection: LibraryBook? {
        guard commandsAvailable, filter != "device", let selected, visibleBooks.contains(where: { $0.id == selected.id }) else { return nil }
        return selected
    }
    func prepareSearch(global: Bool) {
        if global { filter = "all"; clearOrganizationFilters() }
    }
    var visibleBooks: [LibraryBook] {
        let query = currentQuery
        let filtered = books.filter { query.matches($0) }
        let ordered = filtered.sorted {
            switch sort {
            case .recent: return $0.addedAt > $1.addedAt
            case .title: return $0.metadata.title.localizedStandardCompare($1.metadata.title) == .orderedAscending
            case .author: return $0.metadata.authors.joined().localizedStandardCompare($1.metadata.authors.joined()) == .orderedAscending
            case .series:
                let left = $0.organization, right = $1.organization
                if left.series.isEmpty != right.series.isEmpty { return !left.series.isEmpty }
                let comparison = left.series.localizedStandardCompare(right.series)
                if comparison != .orderedSame { return comparison == .orderedAscending }
                if left.seriesNumber != right.seriesNumber { return (left.seriesNumber ?? .infinity) < (right.seriesNumber ?? .infinity) }
                return $0.metadata.title.localizedStandardCompare($1.metadata.title) == .orderedAscending
            case .format:
                let comparison = $0.metadata.format.localizedStandardCompare($1.metadata.format)
                return comparison == .orderedSame ? $0.metadata.title.localizedStandardCompare($1.metadata.title) == .orderedAscending : comparison == .orderedAscending
            }
        }
        return sortReversed ? Array(ordered.reversed()) : ordered
    }
    var collectionTitle: String {
        switch filter {
        case "read": "Read"
        case "unread": "Unread"
        case "EPUB": "EPUB"
        case "MOBI": "MOBI"
        case "AZW3": "Kindle / AZW3"
        case "prepared": "Personalized"
        case "device": "Kindle"
        default: "All Books"
        }
    }
    func start() async {
        await reload()
        reader.reloadHistory()
        reader.discoverMounted()
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--import"), args.indices.contains(index + 1) { importURLs([URL(fileURLWithPath: args[index + 1])]) }
    }
    func reload() async {
        guard let store else { return }
        do { books = try await store.books(); savedFilters = try await store.savedFilters() } catch { self.error = error.localizedDescription }
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
    @discardableResult
    func save(_ book: LibraryBook, reportError: Bool = true) async -> String? {
        guard let store else { return "The library is unavailable." }
        do {
            try await store.update(book); await reload(); editing = nil
            status = "Changes saved · your original is preserved"
            return nil
        } catch {
            if reportError { self.error = error.localizedDescription }
            return error.localizedDescription
        }
    }
    func export(_ book: LibraryBook, destination: URL? = nil) {
        guard let store, operation == nil else { return }
        guard let folder = destination else {
            error = nil
            exportBook = book
            return
        }
        if exportNeedsHelper(folder) {
            guard !reader.busy else { error = "Wait for the current device operation or cancel it first."; return }
            reader.send(book, destination: folder, model: self, updateInventory: exportUsesReader(folder)); transferBook = nil
            if reader.busy { exportBook = nil }
            return
        }
        operation = "Preparing \(book.metadata.title)…"
        Task {
            let access = folder.startAccessingSecurityScopedResource()
            defer { if access { folder.stopAccessingSecurityScopedResource() }; operation = nil }
            do {
                let url = try await store.export(book.id, to: folder)
                status = "Exported and verified · \(url.lastPathComponent)"
                transferBook = nil; exportBook = nil
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch { self.error = error.localizedDescription }
        }
    }
    func exportKindle(_ artifact: PreparedBookArtifact, book: LibraryBook, to folder: URL) {
        guard let store, operation == nil else { return }
        error = nil
        if exportNeedsHelper(folder) {
            guard !reader.busy else { error = "Wait for the current device operation or cancel it first."; return }
            reader.send(book, destination: folder, model: self, artifact: artifact, updateInventory: exportUsesReader(folder))
            if reader.busy { exportBook = nil }
            return
        }
        operation = "Exporting Kindle copy…"
        Task {
            let access = folder.startAccessingSecurityScopedResource()
            defer { if access { folder.stopAccessingSecurityScopedResource() }; operation = nil }
            do {
                let url = try await store.exportKindleArtifact(artifact, to: folder)
                status = "Exported and verified · \(url.lastPathComponent)"
                exportBook = nil
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
                    throw BookError.unsupported("This book uses a chapter format that Smallibre cannot preview yet. You can still export the original.")
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

struct BulkEditSelection: Identifiable { let id = UUID(); let ids: [UUID] }
