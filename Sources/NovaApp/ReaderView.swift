import SwiftUI
import AppKit
import NovaCore

@MainActor @Observable final class ReaderModel {
    var books: [ReaderBook] = []
    var generation = UUID()
    var folder: URL?
    var busy = false
    var error: String?
    var status: String?
    var service: ReaderStore?
    var task: Task<Void, Never>?
    var hashes: Set<String> { Set(books.map(\.hash).filter { !$0.isEmpty }) }
    func choose() {
        let panel = NSOpenPanel()
        panel.title = "Choose Kindle documents folder"
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.directoryURL = URL(fileURLWithPath: "/Volumes")
        if panel.runModal() == .OK, let url = panel.url { connect(url) }
    }
    func discover() {
        guard !busy else { return }
        let volumes = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: "/Volumes"), includingPropertiesForKeys: nil)) ?? []
        let candidates = volumes.filter { $0.lastPathComponent.lowercased().hasPrefix("kindle") }.map { $0.appendingPathComponent("documents") }.filter { FileManager.default.fileExists(atPath: $0.path) }
        if candidates.count == 1 { connect(candidates[0]) }
    }
    func connect(_ url: URL) {
        guard !busy else { return }
        generation = UUID(); folder = url; service = ReaderStore(root: url); books = []; refresh()
    }
    func refresh() {
        guard !busy, let service else { return }
        busy = true; status = "Reading device books…"
        task = Task {
            defer { busy = false }
            do { books = try await service.scan(); status = "\(books.count) device files · refreshed just now" }
            catch { books = []; self.error = error.localizedDescription; status = "Device list unavailable" }
        }
    }
    func disconnected(_ url: URL) {
        guard let folder, folder.path.hasPrefix(url.path + "/") else { return }
        generation = UUID(); task?.cancel(); books = []; service = nil; self.folder = nil; status = "Kindle disconnected"
    }
    func download(_ book: ReaderBook, model: AppModel, edit: Bool = false) {
        guard !busy, let service, let library = model.store else { return }
        busy = true
        task = Task {
            defer { busy = false }
            do {
                let result = try await service.download(book, into: library)
                await model.reload(); model.selection = result.book.id
                status = result.isDuplicate ? "Already in your library" : "Downloaded to your library"
                if edit { model.editing = result.book }
            } catch { self.error = error.localizedDescription }
        }
    }
    func delete(_ book: ReaderBook) {
        guard !busy, let service else { return }
        busy = true
        task = Task {
            defer { busy = false }
            do { try await service.delete(book); books.removeAll { $0.id == book.id }; status = "Device copy deleted" }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct ReaderView: View {
    @Bindable var reader: ReaderModel
    @Bindable var model: AppModel
    @State private var selected: String?
    @State private var deletion: ReaderBook?
    private var book: ReaderBook? { reader.books.first { $0.id == selected } }
    private var filtered: [ReaderBook] {
        reader.books.filter { model.search.isEmpty || ($0.title + " " + ($0.metadata?.authors.joined(separator: " ") ?? "")).localizedStandardContains(model.search) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your Kindle").font(.system(size: 30, design: .serif))
                    Text(reader.folder?.path ?? "Connect your Kindle in USB drive mode").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if reader.busy { ProgressView().controlSize(.small) }
                Button("Choose folder…") { reader.choose() }.disabled(reader.busy)
                Button("Refresh", systemImage: "arrow.clockwise") { if reader.service == nil { reader.discover() } else { reader.refresh() } }.disabled(reader.busy)
            }
            if reader.folder == nil {
                ContentUnavailableView("No mounted Kindle", systemImage: "externaldrive", description: Text("Connect a Kindle that appears in Finder, or choose its documents folder. MTP devices are not supported yet."))
            } else {
                List(filtered, selection: $selected) { item in
                    HStack {
                        Image(systemName: "book.closed").foregroundStyle(NovaTheme.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.headline).lineLimit(1)
                            Text(item.metadata?.authors.joined(separator: ", ") ?? "Metadata unavailable").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(model.books.contains { $0.hash == item.hash } ? "In library" : "Only on device").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 5).tag(item.id)
                }.listStyle(.inset).overlay { if filtered.isEmpty && !reader.busy { ContentUnavailableView("No books found", systemImage: "books.vertical") } }
                if let book {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(book.relativePath).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        if let issue = book.issue { Text(issue).font(.caption).foregroundStyle(.secondary) }
                        HStack {
                            Button("Download to library", systemImage: "arrow.down.doc") { reader.download(book, model: model) }.disabled(book.metadata == nil)
                            Button("Edit library details…", systemImage: "pencil") { reader.download(book, model: model, edit: true) }.disabled(book.metadata == nil)
                            Spacer()
                            Button("Delete from Kindle…", role: .destructive) { deletion = book }.disabled(book.hash.isEmpty)
                        }.disabled(reader.busy)
                        Text("Details are edited in Nova. MOBI/AZW3 metadata on the Kindle stays unchanged. Deletion removes the book file only; annotations and companion folders are kept.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Text(reader.status ?? "Matches use identical file contents; different editions or conversions may appear separately.").font(.caption).foregroundStyle(.secondary)
        }.padding(24).background(NovaTheme.canvas)
        .onChange(of: reader.generation) { _, _ in deletion = nil; selected = nil }
        .onChange(of: selected) { _, value in
            let hash = reader.books.first { $0.id == value }?.hash
            model.selection = model.books.first { $0.hash == hash }?.id
        }
        .task { if reader.folder == nil { reader.discover() } }
        .confirmationDialog("Delete this book from Kindle?", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }), titleVisibility: .visible) {
            if let deletion { Button("Delete device copy", role: .destructive) { reader.delete(deletion); self.deletion = nil } }
            Button("Cancel", role: .cancel) { deletion = nil }
        } message: { Text("\(deletion?.title ?? "")\nThis cannot be undone. Any copy already downloaded to Nova will be kept.") }
        .alert("Device operation failed", isPresented: Binding(get: { reader.error != nil }, set: { if !$0 { reader.error = nil } })) { Button("OK") { reader.error = nil } } message: { Text(reader.error ?? "") }
    }
}
