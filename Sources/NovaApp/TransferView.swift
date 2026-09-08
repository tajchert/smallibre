import SwiftUI
import NovaCore

struct TransferView: View {
    @Bindable var model: AppModel
    let book: LibraryBook
    @State private var reader = "epub"
    @State private var folder: URL?
    @Environment(\.dismiss) private var dismiss
    private var compatible: Bool { reader == "kindle" ? ["MOBI", "AZW3"].contains(book.metadata.format) : book.metadata.format == "EPUB" }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(systemName: "externaldrive").font(.system(size: 32, weight: .light)).foregroundStyle(NovaTheme.accent)
                VStack(alignment: .leading, spacing: 5) { Text("Take a book with you").font(.system(size: 25, design: .serif)); Text(book.metadata.title).font(.system(size: 12)).foregroundStyle(.secondary) }
            }
            Picker("Reader", selection: $reader) { Text("EPUB reader / Kobo").tag("epub"); Text("Kindle").tag("kindle") }.pickerStyle(.segmented)
            if compatible {
                Text("Choose the books folder on your connected reader. Nova will copy and verify the file, keeping any existing books.").font(.callout).foregroundStyle(.secondary)
                Button {
                    let panel = NSOpenPanel()
                    panel.title = "Choose your reader’s books folder"; panel.prompt = "Use this folder"
                    panel.canChooseFiles = false; panel.canChooseDirectories = true
                    panel.directoryURL = URL(fileURLWithPath: "/Volumes", isDirectory: true)
                    if panel.runModal() == .OK { folder = panel.url }
                } label: { Label(folder?.lastPathComponent ?? "Choose reader folder…", systemImage: "folder").frame(maxWidth: .infinity) }.controlSize(.large)
                if let folder { Text(folder.path).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            } else {
                Label(reader == "kindle" ? "Kindle USB transfer needs AZW3 or MOBI. EPUB-to-Kindle conversion is not available yet." : "This reader needs EPUB. Conversion from \(book.metadata.format) is not available yet.", systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
            }
            Text("This version supports readers that appear in Finder. Readers using MTP need a future transport update. Eject your reader in Finder when the transfer finishes.").font(.caption).foregroundStyle(.secondary).lineSpacing(3)
            Divider()
            HStack { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Send book", systemImage: "arrow.up.doc") { if let folder { model.export(book, destination: folder) } }.buttonStyle(.borderedProminent).disabled(!compatible || folder == nil || model.operation != nil) }
        }.padding(28).frame(width: 490).background(NovaTheme.canvas).tint(NovaTheme.accent)
            .onAppear { reader = book.metadata.format == "EPUB" ? "epub" : "kindle" }
    }
}
