import SwiftUI
import SmallibreCore

struct TransferView: View {
    @Bindable var model: AppModel
    let book: LibraryBook
    var localExport = false
    @State private var reader = "epub"
    @State private var exportKindle = false
    @State private var folder: URL?
    @State private var artifact: PreparedBookArtifact?
    @State private var preparing = false
    @State private var preparationID = UUID()
    @State private var preparationError: String?
    @Environment(\.dismiss) private var dismiss
    private var kindle: Bool { localExport ? exportKindle : reader == "kindle" }
    private var needsConversion: Bool { kindle && book.metadata.format == "EPUB" }
    private var compatible: Bool { localExport || (kindle ? ["EPUB", "MOBI", "AZW3"].contains(book.metadata.format) : book.metadata.format == "EPUB") }
    private var blocked: Bool { !compatible || folder == nil || model.operation != nil || model.reader.busy || preparing || (needsConversion && artifact == nil) }
    private var showsConversion: Bool { compatible && needsConversion && (preparing || preparationError != nil || artifact != nil) }
    private var explanation: String {
        guard localExport else { return "Choose the books folder on your connected reader. Smallibre will copy and verify the file, keeping any existing books." }
        return book.metadata.format == "EPUB"
            ? "Export a copy with your saved changes. Your original and existing files are kept."
            : "Export the original file. Library metadata changes are not embedded. Existing files are kept."
    }
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(localExport ? "Export file" : "Take a book with you").font(.system(size: 20, weight: .bold)).tracking(-0.4)
                Text(book.metadata.title).font(.system(size: 13)).foregroundStyle(SmallibreTheme.text2).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 14)
            VStack(alignment: .leading, spacing: 18) {
                destination
                if showsConversion { conversion }
                if !localExport {
                    caption("Supports readers that appear in Finder. MTP transfers are not supported. Eject your reader in Finder when the transfer finishes.")
                }
                if let error = localExport ? model.error : model.reader.error {
                    Text(error).font(.system(size: 12)).foregroundStyle(SmallibreTheme.destructive)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 20)
            footer
        }
        .frame(width: 520).background(SmallibreTheme.sheet).foregroundStyle(SmallibreTheme.text).tint(SmallibreTheme.accent)
            .onAppear { reader = "kindle" }
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

    private var destination: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Destination").font(.system(size: 13, weight: .semibold))
            FormGroup {
                FormRow(label: localExport ? "File format" : "Reader") {
                    HStack(spacing: 0) {
                        Spacer(minLength: 8)
                        if localExport {
                            if book.metadata.format == "EPUB" {
                                PillPicker(selection: $exportKindle, options: [false, true]) { $0 ? "Kindle AZW3" : book.metadata.format }
                                    .disabled(model.operation != nil).opacity(model.operation != nil ? 0.45 : 1)
                            } else {
                                Text(book.metadata.format).font(.system(size: 13)).foregroundStyle(SmallibreTheme.text2)
                            }
                        } else {
                            PillPicker(selection: $reader, options: ["epub", "kindle"]) { $0 == "kindle" ? "Kindle" : "EPUB reader / Kobo" }
                        }
                    }
                }
                if compatible {
                    Hairline()
                    FormRow(label: "Folder") {
                        HStack(spacing: 0) {
                            Spacer(minLength: 8)
                            Button {
                                let panel = NSOpenPanel()
                                panel.title = localExport ? "Choose export folder" : "Choose your reader’s books folder"
                                panel.prompt = "Use this folder"
                                panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = localExport
                                if !localExport { panel.directoryURL = URL(fileURLWithPath: "/Volumes", isDirectory: true) }
                                if panel.runModal() == .OK { folder = panel.url }
                            } label: {
                                Label(folder?.lastPathComponent ?? "Choose folder…", systemImage: "folder").lineLimit(1)
                            }
                            .buttonStyle(.control(height: 26, fontSize: 12))
                            .help(folder?.path ?? "Choose the destination folder")
                        }
                    }
                }
            }
            if compatible {
                caption(explanation)
                if let folder {
                    Text(folder.path).font(.system(size: 12)).foregroundStyle(SmallibreTheme.text2).lineLimit(2).textSelection(.enabled)
                }
            } else {
                Label("This reader needs EPUB. Conversion from \(book.metadata.format) is not available yet.", systemImage: "info.circle")
                    .font(.system(size: 12)).foregroundStyle(SmallibreTheme.text2).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var conversion: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Kindle conversion").font(.system(size: 13, weight: .semibold))
            if preparing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Preparing Kindle copy…").font(.system(size: 12)).foregroundStyle(SmallibreTheme.text2)
                }
            }
            if let preparationError {
                Label(preparationError, systemImage: "exclamationmark.triangle").font(.system(size: 12))
                    .foregroundStyle(SmallibreTheme.destructive).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            if let artifact {
                caption("Kindle copy ready. Review conversion notes before continuing.")
                FormGroup {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            note("Conversion supports a limited set of reflowable EPUB features. Check the result on your reader.", icon: nil)
                            ForEach(Array(artifact.warnings.enumerated()), id: \.offset) { _, warning in
                                Hairline()
                                note(warning, icon: "exclamationmark.triangle")
                            }
                        }
                    }
                    .frame(maxHeight: 140)
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 8) {
                Label("Original preserved", systemImage: Glyph.assurance)
                    .font(.system(size: 12)).foregroundStyle(SmallibreTheme.text3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Cancel") { dismiss() }.buttonStyle(.control).keyboardShortcut(.cancelAction)
                Button {
                    guard let folder else { return }
                    if localExport {
                        if needsConversion {
                            if let artifact { model.exportKindle(artifact, book: book, to: folder) }
                        } else {
                            model.export(book, destination: folder)
                        }
                    } else {
                        model.reader.send(book, destination: folder, model: model, artifact: needsConversion ? artifact : nil)
                        if model.reader.busy { dismiss() }
                    }
                } label: {
                    Label(localExport ? "Export" : "Send to device", systemImage: Glyph.send)
                }
                .buttonStyle(.accentAction).disabled(blocked)
            }
            .padding(.horizontal, 20).padding(.vertical, 14).background(SmallibreTheme.inspector)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(SmallibreTheme.text3)
            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One hairline-separated line inside the conversion-notes card.
    private func note(_ text: String, icon: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            if let icon { Image(systemName: icon).font(.system(size: 11)).foregroundStyle(SmallibreTheme.text3) }
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12)).foregroundStyle(SmallibreTheme.text2)
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 9)
    }
}
