import SwiftUI
import AppKit
import SmallibreCore

/// Every control on this screen is the mock's short 26pt bordered button.
private let controlHeight: CGFloat = 26

/// The three device-table columns, shared by the sticky header and every row so they line up.
private struct ReaderColumns<Title: View, Status: View, Format: View>: View {
    @ViewBuilder var title: Title
    @ViewBuilder var status: Status
    @ViewBuilder var format: Format
    var body: some View {
        HStack(spacing: 10) {
            title.frame(maxWidth: .infinity, alignment: .leading)
            status.frame(width: 110, alignment: .leading)
            format.frame(width: 70, alignment: .trailing)
        }
    }
}

struct ReaderView: View {
    @Bindable var reader: ReaderModel
    @Bindable var model: AppModel
    @State private var deletion: [ReaderBook] = []
    @State private var editing: ReaderBook?
    @State private var history = false
    private var selection: [ReaderBook] { reader.selectedBooks(search: model.search) }
    private var filtered: [ReaderBook] { reader.visibleBooks(search: model.search, sort: model.sort, reversed: model.sortReversed) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            // The gauge gets its own row: sharing one with the buttons makes the header overflow
            // a narrow window, and an HStack will not reflow.
            if let capacity = reader.capacity { gauge(capacity).padding(.top, 8) }
            if reader.folder == nil {
                ContentUnavailableView("No mounted Kindle", systemImage: "externaldrive", description: Text("Connect a Kindle that appears in Finder, or choose its documents folder. MTP is not supported yet."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                table.padding(.top, 18)
                if !selection.isEmpty { actions.padding(.top, 12) }
            }
            if reader.busy { ProgressView(value: reader.progress).progressViewStyle(.linear).padding(.top, 12) }
            Text(reader.status ?? "Matches use identical file contents; Refresh reuses unchanged files, Recheck reads every file.")
                .font(.system(size: 12)).foregroundStyle(SmallibreTheme.text3).lineLimit(3)
                .padding(.top, 12).padding(.bottom, 14)
        }
        .padding(.top, 26).padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SmallibreTheme.content)
        .onChange(of: reader.generation) { _, _ in deletion = []; editing = nil }
        .onChange(of: selection.map { $0.id + ":" + $0.hash }) { _, _ in
            deletion = []; editing = nil
        }
        .task { reader.localRoot = model.root; reader.reloadHistory(); if reader.folder == nil { reader.discover() } }
        .confirmationDialog("Back up and delete \(deletion.count) device copies?", isPresented: Binding(get: { !deletion.isEmpty }, set: { if !$0 { deletion = [] } }), titleVisibility: .visible) {
            Button("Back up & delete", role: .destructive) { reader.run("delete", books: deletion, model: model); deletion = [] }
            Button("Cancel", role: .cancel) { deletion = [] }
        } message: { Text("Each book is verified and backed up on your Mac before its device file is deleted. Annotations and companion folders stay on Kindle. If any step fails, the batch stops.") }
        .sheet(item: $editing) { book in DeviceMetadataView(book: book) { metadata in reader.run("metadata", books: [book], model: model, metadata: metadata) } }
        .sheet(isPresented: $history) { ReaderHistoryView(reader: reader) }
        .alert("Device operation stopped", isPresented: Binding(get: { reader.error != nil }, set: { if !$0 { reader.error = nil } })) { Button("OK") { reader.error = nil } } message: { Text(reader.error ?? "") }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                // Title and buttons keep their intrinsic width; only the path gives way.
                Text("Kindle").font(.system(size: 26, weight: .bold)).tracking(-0.5).foregroundStyle(SmallibreTheme.text)
                    .lineLimit(1).fixedSize()
                Text(reader.folder?.path ?? "Connect your Kindle in USB drive mode")
                    .font(.system(size: 13)).foregroundStyle(SmallibreTheme.text2)
                    .lineLimit(1).truncationMode(.middle).padding(.top, 4)
            }
            .layoutPriority(-1)
            Spacer(minLength: 8)
            // The buttons keep their intrinsic width; the path beside them truncates instead.
            HStack(spacing: 8) {
                Button("Choose folder…") { reader.choose() }
                    .buttonStyle(.control(height: controlHeight, radius: 6, fontSize: 12)).disabled(reader.busy)
                refreshMenu
                Button("Backups & history") { reader.reloadHistory(); history = true }
                    .buttonStyle(.control(height: controlHeight, radius: 6, fontSize: 12))
                if reader.busy {
                    Button("Cancel") { reader.cancel() }
                        .buttonStyle(.control(height: controlHeight, radius: 6, fontSize: 12))
                }
            }
            .lineLimit(1)
        }
    }

    /// Both refresh depths live behind one control that has to read as a plain bordered button.
    private var refreshMenu: some View {
        Menu {
            Button("Refresh changes") { reader.refresh() }
            Button("Recheck every file") { reader.refresh(full: true) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: Glyph.refresh).font(.system(size: 11, weight: .semibold))
                Text("Refresh")
            }
            .font(.system(size: 12)).foregroundStyle(SmallibreTheme.text)
            .padding(.horizontal, 11).frame(height: controlHeight)
            .contentShape(.rect)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .background(SmallibreTheme.control, in: .rect(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(SmallibreTheme.controlBorder, lineWidth: 1) }
        .shadow(color: .black.opacity(0.08), radius: 0.5, x: 0, y: 0.5)
        .opacity(reader.busy ? 0.4 : 1)
        .disabled(reader.busy)
        .help("Refresh reuses unchanged files; Recheck reads every file.")
    }

    private func gauge(_ capacity: ReaderCapacity) -> some View {
        HStack(spacing: 10) {
            ZStack(alignment: .leading) {
                Capsule().fill(SmallibreTheme.fill2)
                Capsule().fill(SmallibreTheme.accent).frame(width: 180 * CGFloat(capacity.usedFraction))
            }
            .frame(width: 180, height: 5)
            Text("\(bytes(capacity.usedBytes)) of \(bytes(capacity.totalBytes)) used · \(bytes(capacity.freeBytes)) free")
                .font(.system(size: 12)).monospacedDigit().foregroundStyle(SmallibreTheme.text2)
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func bytes(_ value: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }

    private var table: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(filtered) { row($0) }
                } header: {
                    ReaderColumns { Text("Title") } status: { Text("Status") } format: { Text("Format") }
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(SmallibreTheme.text3)
                        .padding(.vertical, 6).padding(.horizontal, 14)
                        .background(SmallibreTheme.content)
                        .overlay(alignment: .bottom) { Hairline() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SmallibreTheme.group)
        .clipShape(.rect(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(SmallibreTheme.separator, lineWidth: 1) }
        .overlay { if filtered.isEmpty && !reader.busy { ContentUnavailableView("No books found", systemImage: "books.vertical") } }
    }

    private func row(_ item: ReaderBook) -> some View {
        let selected = reader.selectedIDs.contains(item.id)
        let primary = selected ? SmallibreTheme.onAccent : SmallibreTheme.text
        let secondary = selected ? SmallibreTheme.onAccent : SmallibreTheme.text2
        return Button { select(item) } label: {
            ReaderColumns {
                HStack(spacing: 10) {
                    Image(systemName: Glyph.book).font(.system(size: 15)).foregroundStyle(secondary).frame(width: 17)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(primary).lineLimit(1)
                        Text(item.metadata?.authors.joined(separator: ", ") ?? "\(item.formatLabel) · metadata unavailable")
                            .font(.system(size: 12)).foregroundStyle(secondary).lineLimit(1)
                    }
                }
            } status: {
                Text(reader.libraryLabel(for: item, library: model.books))
                    .font(.system(size: 12)).foregroundStyle(secondary).lineLimit(1)
            } format: {
                Text(item.formatLabel).font(.system(size: 11, weight: .semibold)).tracking(0.7)
                    .foregroundStyle(secondary).lineLimit(1)
            }
            .padding(.vertical, 7).padding(.horizontal, 14)
            .background(selected ? SmallibreTheme.accent : .clear, in: .rect(cornerRadius: 6))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2).padding(.horizontal, 4)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The table is hand-built, so modifier-aware clicking is too: a plain click replaces the
    /// selection, ⌘ or ⇧ extends it.
    private func select(_ item: ReaderBook) {
        let flags = NSEvent.modifierFlags
        guard flags.contains(.command) || flags.contains(.shift) else { reader.selectedIDs = [item.id]; return }
        if reader.selectedIDs.contains(item.id) { reader.selectedIDs.remove(item.id) } else { reader.selectedIDs.insert(item.id) }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("\(selection.count) selected · ⌘-click to select more")
                    .font(.system(size: 13)).foregroundStyle(SmallibreTheme.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Download to library") { reader.run("download", books: selection, model: model) }
                    .buttonStyle(.control(height: controlHeight, radius: 6, fontSize: 12))
                    .disabled(selection.contains { !$0.canImport })
                Button("Save file backups") { reader.run("copy", books: selection, model: model) }
                    .buttonStyle(.control(height: controlHeight, radius: 6, fontSize: 12))
                    .disabled(selection.contains { $0.hash.isEmpty })
                Button("Delete…", role: .destructive) { deletion = selection }
                    .buttonStyle(.control(height: controlHeight, radius: 6, fontSize: 12, tint: SmallibreTheme.destructive))
                    .disabled(selection.contains { $0.hash.isEmpty })
            }
            .disabled(reader.busy)
            if selection.count == 1, let book = selection.first { single(book) }
        }
    }

    /// Everything the mock leaves out for a single device book: where it lives, why it may be
    /// unusable, and the two editing routes.
    private func single(_ book: ReaderBook) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(book.relativePath).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                if let issue = book.issue { Text(issue).lineLimit(2) }
                if !book.metadataEditable { Text("Device editing requires a supported DRM-free standalone MOBI/AZW3 file.").lineLimit(2) }
            }
            .font(.system(size: 12)).foregroundStyle(SmallibreTheme.text3)
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Button("Edit Kindle details…") { editing = book }
                    .buttonStyle(.control(height: controlHeight, radius: 6, fontSize: 12))
                    .disabled(!book.metadataEditable)
                Button("Edit library copy…") { reader.download(book, model: model, edit: true) }
                    .buttonStyle(.control(height: controlHeight, radius: 6, fontSize: 12))
                    .disabled(!book.canImport)
            }
            .disabled(reader.busy)
        }
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
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Edit Kindle details").font(.system(size: 20, weight: .bold)).tracking(-0.4).foregroundStyle(SmallibreTheme.text)
                FormGroup {
                    field("Title", $title)
                    Hairline()
                    field("Authors (separate with semicolons)", $authors)
                    Hairline()
                    field("Publisher", $publisher)
                }
                Text("Smallibre backs up the original on your Mac, updates metadata and verifies the device copy. Book content is preserved. Eject Kindle to let it refresh its index.")
                    .font(.system(size: 12)).foregroundStyle(SmallibreTheme.text2).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 20)
            Hairline()
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Cancel") { dismiss() }.buttonStyle(.control())
                Button("Back up & update Kindle") {
                    guard var value = book.metadata else { return }
                    value.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    value.authors = authors.split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    value.publisher = publisher; save(value); dismiss()
                }
                .buttonStyle(.accentAction())
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(SmallibreTheme.inspector)
        }
        .frame(width: 480)
        .background(SmallibreTheme.sheet)
        .onAppear { title = book.metadata?.title ?? ""; authors = book.metadata?.authors.joined(separator: "; ") ?? ""; publisher = book.metadata?.publisher ?? "" }
    }
    private func field(_ placeholder: String, _ text: Binding<String>) -> some View {
        DesignTextField(placeholder: placeholder, text: text)
            .padding(.horizontal, 12).frame(height: 36)
    }
}

private struct ReaderHistoryView: View {
    @Bindable var reader: ReaderModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Backups & operation history").font(.system(size: 20, weight: .bold)).tracking(-0.4).foregroundStyle(SmallibreTheme.text)
                Text("Unfinished operations need review: refresh Kindle before retrying. A timeout can happen after a write completes. Backups are ordinary files you can import or copy back to the reader.")
                    .font(.system(size: 12)).foregroundStyle(SmallibreTheme.text2).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 16)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(reader.receipts) { receipt in
                        row(receipt)
                        if receipt.id != reader.receipts.last?.id { Hairline() }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SmallibreTheme.group)
            .clipShape(.rect(cornerRadius: 9))
            .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(SmallibreTheme.separator, lineWidth: 1) }
            .overlay { if reader.receipts.isEmpty { ContentUnavailableView("No device operations yet", systemImage: "clock") } }
            .padding(.horizontal, 24).padding(.bottom, 16)
            Hairline()
            HStack {
                Spacer(minLength: 0)
                Button("Done") { dismiss() }.buttonStyle(.accentAction()).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(SmallibreTheme.inspector)
        }
        .frame(width: 600, height: 480)
        .background(SmallibreTheme.sheet)
    }
    private func row(_ receipt: ReaderReceipt) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(receipt.transfer == nil ? receipt.operation.capitalized : "Send Kindle copy") · \(receipt.transfer?.artifact.suggestedFilename ?? receipt.source)")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(SmallibreTheme.text).lineLimit(2)
            Text("\((receipt.state == "completed" || receipt.transfer?.state == .verified) ? "Completed" : "Needs review") · \(receipt.date.formatted())")
                .font(.system(size: 12)).foregroundStyle(SmallibreTheme.text2)
            if let detail = receipt.detail { Text(detail).font(.system(size: 12)).foregroundStyle(SmallibreTheme.text2) }
            if let artifact = receipt.transfer?.artifact, !artifact.warnings.isEmpty {
                DisclosureGroup("Conversion notes") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(artifact.warnings.enumerated()), id: \.offset) { _, warning in
                            Text(warning).font(.system(size: 12)).foregroundStyle(SmallibreTheme.text2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .font(.system(size: 12))
            }
            Button("Show backup in Finder") { NSWorkspace.shared.activateFileViewerSelecting([receipt.backup]) }
                .buttonStyle(.control(height: 24, radius: 6, fontSize: 12))
                .padding(.top, 2)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
