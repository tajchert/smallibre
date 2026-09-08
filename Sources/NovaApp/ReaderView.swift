import SwiftUI
import AppKit
import NovaCore

struct ReaderView: View {
    @Bindable var reader: ReaderModel
    @Bindable var model: AppModel
    @State private var selected: Set<String> = []
    @State private var deletion: [ReaderBook] = []
    @State private var editing: ReaderBook?
    @State private var history = false
    private var selection: [ReaderBook] { reader.books.filter { selected.contains($0.id) } }
    private var filtered: [ReaderBook] {
        reader.books.filter { model.search.isEmpty || ($0.title + " " + ($0.metadata?.authors.joined(separator: " ") ?? "")).localizedStandardContains(model.search) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your Kindle").font(.system(size: 30, design: .serif))
            Text(reader.folder?.path ?? "Connect your Kindle in USB drive mode").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Choose folder…") { reader.choose() }.disabled(reader.busy)
                Menu {
                    Button("Refresh changes") { reader.refresh() }
                    Button("Recheck every file") { reader.refresh(full: true) }
                } label: { Label("Refresh", systemImage: "arrow.clockwise") }.disabled(reader.busy)
                Spacer()
                Button("Backups & history") { reader.reloadHistory(); history = true }
                if reader.busy { Button("Cancel") { reader.cancel() } }
            }
            if reader.folder == nil {
                ContentUnavailableView("No mounted Kindle", systemImage: "externaldrive", description: Text("Connect a Kindle that appears in Finder, or choose its documents folder. MTP is not supported yet."))
            } else {
                List(filtered, selection: $selected) { item in
                    HStack {
                        Image(systemName: "book.closed").foregroundStyle(NovaTheme.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.headline).lineLimit(1)
                            Text(item.metadata?.authors.joined(separator: ", ") ?? "\(item.formatLabel) · metadata unavailable").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(model.books.contains { $0.hash == item.hash } ? "In library" : "On device")
                            Text(item.formatLabel)
                        }.font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 5).tag(item.id)
                }.listStyle(.inset).overlay { if filtered.isEmpty && !reader.busy { ContentUnavailableView("No books found", systemImage: "books.vertical") } }
                if !selection.isEmpty {
                    Text("\(selection.count) selected · ⌘-click or ⇧-click to select more").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Download to library") { reader.run("download", books: selection, model: model) }.disabled(selection.contains { !$0.canImport })
                        Button("Save file backups") { reader.run("copy", books: selection, model: model) }.disabled(selection.contains { $0.hash.isEmpty })
                        Spacer()
                        Button("Delete…", role: .destructive) { deletion = selection }.disabled(selection.contains { $0.hash.isEmpty })
                    }.disabled(reader.busy)
                    if selection.count == 1, let book = selection.first {
                        Text(book.relativePath).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        if let issue = book.issue { Text(issue).font(.caption).foregroundStyle(.secondary) }
                        HStack {
                            Button("Edit Kindle details…") { editing = book }.disabled(!book.metadataEditable)
                            Button("Edit library copy…") { reader.download(book, model: model, edit: true) }.disabled(!book.canImport)
                        }.disabled(reader.busy)
                        if !book.metadataEditable { Text("Device editing requires a supported DRM-free standalone MOBI/AZW3 file.").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            if reader.busy { ProgressView(value: reader.progress).progressViewStyle(.linear) }
            Text(reader.status ?? "Matches use identical file contents; Refresh reuses unchanged files, Recheck reads every file.").font(.caption).foregroundStyle(.secondary).lineLimit(3)
        }.padding(24).background(NovaTheme.canvas)
        .onChange(of: reader.generation) { _, _ in deletion = []; selected = []; editing = nil }
        .onChange(of: selected) { _, _ in
            let hash = selection.count == 1 ? selection.first?.hash : nil
            model.selection = model.books.first { $0.hash == hash }?.id
        }
        .task { reader.localRoot = model.root; if reader.folder == nil { reader.discover() } }
        .confirmationDialog("Back up and delete \(deletion.count) device copies?", isPresented: Binding(get: { !deletion.isEmpty }, set: { if !$0 { deletion = [] } }), titleVisibility: .visible) {
            Button("Back up & delete", role: .destructive) { reader.run("delete", books: deletion, model: model); deletion = [] }
            Button("Cancel", role: .cancel) { deletion = [] }
        } message: { Text("Each book is verified and backed up on your Mac before its device file is deleted. Annotations and companion folders stay on Kindle. If any step fails, the batch stops.") }
        .sheet(item: $editing) { book in DeviceMetadataView(book: book) { metadata in reader.run("metadata", books: [book], model: model, metadata: metadata) } }
        .sheet(isPresented: $history) { ReaderHistoryView(reader: reader) }
        .alert("Device operation stopped", isPresented: Binding(get: { reader.error != nil }, set: { if !$0 { reader.error = nil } })) { Button("OK") { reader.error = nil } } message: { Text(reader.error ?? "") }
    }
}

private struct DeviceMetadataView: View {
    let book: ReaderBook
    let save: (BookMetadata) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var authors = ""
    @State private var publisher = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Edit Kindle details").font(.title2)
            TextField("Title", text: $title)
            TextField("Authors (separate with semicolons)", text: $authors)
            TextField("Publisher", text: $publisher)
            Text("Nova backs up the original on your Mac, updates metadata and verifies the device copy. Book content is preserved. Eject Kindle to let it refresh its index.").font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { dismiss() }; Spacer()
                Button("Back up & update Kindle") {
                    guard var value = book.metadata else { return }
                    value.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    value.authors = authors.split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    value.publisher = publisher; save(value); dismiss()
                }.buttonStyle(.borderedProminent).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(26).frame(width: 480).onAppear { title = book.metadata?.title ?? ""; authors = book.metadata?.authors.joined(separator: "; ") ?? ""; publisher = book.metadata?.publisher ?? "" }
    }
}

private struct ReaderHistoryView: View {
    @Bindable var reader: ReaderModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Backups & operation history").font(.title2)
            Text("Unfinished operations need review: refresh Kindle before retrying. A timeout can happen after a write completes. Backups are ordinary files you can import or copy back to the reader.").font(.callout).foregroundStyle(.secondary)
            List(reader.receipts) { receipt in
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(receipt.operation.capitalized) · \(receipt.source)").lineLimit(2)
                    Text("\(receipt.state == "completed" ? "Completed" : "Needs review") · \(receipt.date.formatted())").font(.caption).foregroundStyle(.secondary)
                    if let detail = receipt.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                    Button("Show backup in Finder") { NSWorkspace.shared.activateFileViewerSelecting([receipt.backup]) }
                }.padding(.vertical, 5)
            }.overlay { if reader.receipts.isEmpty { ContentUnavailableView("No device operations yet", systemImage: "clock") } }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 600, height: 480)
    }
}
