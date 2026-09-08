import SwiftUI
import SmallibreCore

struct TransferView: View {
    @Bindable var model: AppModel
    let book: LibraryBook
    var localExport = false
    @State private var reader = "epub"
    @State private var folder: URL?
    @State private var artifact: PreparedBookArtifact?
    @State private var preparing = false
    @State private var preparationID = UUID()
    @State private var preparationError: String?
    @Environment(\.dismiss) private var dismiss
    private var kindle: Bool { localExport || reader == "kindle" }
    private var needsConversion: Bool { kindle && book.metadata.format == "EPUB" }
    private var compatible: Bool { kindle ? ["EPUB", "MOBI", "AZW3"].contains(book.metadata.format) : book.metadata.format == "EPUB" }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: localExport ? "square.and.arrow.up" : "externaldrive").font(.system(size: 32, weight: .light)).foregroundStyle(SmallibreTheme.accent)
                VStack(alignment: .leading, spacing: 5) {
                    Text(localExport ? "Export Kindle AZW3" : "Take a book with you").font(.system(size: 25, design: .serif))
                    Text(book.metadata.title).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            if !localExport {
                Picker("Reader", selection: $reader) { Text("EPUB reader / Kobo").tag("epub"); Text("Kindle").tag("kindle") }.pickerStyle(.segmented)
            }
            if compatible {
                Text(localExport ? "Create a verified AZW3 copy with your saved changes. Your original and existing destination files are kept." : "Choose the books folder on your connected reader. Smallibre will copy and verify the file, keeping any existing books.").font(.callout).foregroundStyle(.secondary)
                if needsConversion {
                    if preparing { ProgressView("Preparing Kindle copy…") }
                    if let preparationError { Label(preparationError, systemImage: "exclamationmark.triangle").foregroundStyle(.red).textSelection(.enabled) }
                    if let artifact {
                        Text("Kindle copy ready. Review conversion notes before continuing.").font(.callout)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Conversion supports a limited set of reflowable EPUB features. Check the result on your reader.")
                                ForEach(Array(artifact.warnings.enumerated()), id: \.offset) { _, warning in
                                    Label(warning, systemImage: "exclamationmark.triangle")
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.font(.caption).frame(maxHeight: 140)
                    }
                }
                Button {
                    let panel = NSOpenPanel()
                    panel.title = localExport ? "Choose export folder" : "Choose your reader’s books folder"
                    panel.prompt = "Use this folder"
                    panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = localExport
                    if !localExport { panel.directoryURL = URL(fileURLWithPath: "/Volumes", isDirectory: true) }
                    if panel.runModal() == .OK { folder = panel.url }
                } label: { Label(folder?.lastPathComponent ?? "Choose folder…", systemImage: "folder").frame(maxWidth: .infinity) }.controlSize(.large)
                if let folder { Text(folder.path).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            } else {
                Label("This reader needs EPUB. Conversion from \(book.metadata.format) is not available yet.", systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
            }
            if !localExport { Text("Supports readers that appear in Finder. MTP transfers are not supported. Eject your reader in Finder when the transfer finishes.").font(.caption).foregroundStyle(.secondary) }
            if let error = localExport ? model.error : model.reader.error {
                Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
            Divider()
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(localExport ? "Export AZW3" : "Send book", systemImage: "arrow.up.doc") {
                    guard let folder else { return }
                    if localExport {
                        if let artifact { model.exportKindle(artifact, book: book, to: folder) }
                    } else {
                        model.reader.send(book, destination: folder, model: model, artifact: needsConversion ? artifact : nil)
                        if model.reader.busy { dismiss() }
                    }
                }.buttonStyle(.borderedProminent)
                    .disabled(!compatible || folder == nil || model.operation != nil || model.reader.busy || preparing || (needsConversion && artifact == nil))
            }
        }.padding(28).frame(width: 490).background(SmallibreTheme.canvas).tint(SmallibreTheme.accent)
            .onAppear { reader = book.metadata.format == "EPUB" ? "epub" : "kindle" }
            .task(id: needsConversion) {
                guard !Task.isCancelled else { return }
                let token = UUID()
                preparationID = token
                artifact = nil; preparationError = nil; preparing = false
                guard needsConversion, let store = model.store else { return }
                preparing = true
                defer { if preparationID == token { preparing = false } }
                do {
                    let prepared = try await store.prepareKindleArtifact(for: book.id)
                    try Task.checkCancellation()
                    guard preparationID == token else { return }
                    artifact = prepared
                } catch is CancellationError {} catch {
                    if preparationID == token && !Task.isCancelled { preparationError = error.localizedDescription }
                }
            }
    }
}
