import SwiftUI
import SmallibreCore

struct InspectorView: View {
    @Bindable var model: AppModel
    var body: some View {
        Group {
            if let book = model.selected {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack { Text("BOOK DETAILS").font(.system(size: 10, weight: .semibold)).tracking(1.3).foregroundStyle(.secondary); Spacer(); Image(systemName: "info.circle").foregroundStyle(.tertiary) }
                        BookCover(book: book, root: model.root, large: true).frame(width: 140).frame(maxWidth: .infinity).padding(.vertical, 4)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(book.metadata.title).font(.system(size: 23, weight: .regular, design: .serif)).textSelection(.enabled)
                            Text(book.metadata.authors.isEmpty ? "Unknown author" : book.metadata.authors.joined(separator: ", ")).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        HStack { badge(book.metadata.format); badge(ByteCountFormatter.string(fromByteCount: Int64(book.byteCount), countStyle: .file)); if book.typography.enabled { badge("Personalized") } }
                        VStack(spacing: 9) {
                            Button { model.openPreview(book) } label: { Label("Preview book", systemImage: "book").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).controlSize(.large).disabled(book.metadata.format != "EPUB" || model.operation != nil)
                            Button { model.editing = book } label: { Label("Details & typography", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity) }.controlSize(.large)
                            Button { model.metadataBook = book } label: { Label("Find book details…", systemImage: "magnifyingglass").frame(maxWidth: .infinity) }.controlSize(.large)
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: 14) {
                            detail("LANGUAGE", book.metadata.language.isEmpty ? "Not specified" : Locale.current.localizedString(forLanguageCode: book.metadata.language) ?? book.metadata.language)
                            if !book.metadata.publisher.isEmpty { detail("PUBLISHER", book.metadata.publisher) }
                            detail("ADDED", book.addedAt.formatted(date: .abbreviated, time: .omitted))
                            if !book.metadata.identifier.isEmpty { detail("IDENTIFIER", book.metadata.identifier) }
                        }
                        if !book.metadata.description.isEmpty {
                            Divider()
                            Text(book.metadata.description).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5).textSelection(.enabled)
                        }
                        Divider()
                        VStack(spacing: 9) {
                            Button { model.transferBook = book } label: { Label("Send to reader…", systemImage: "externaldrive").frame(maxWidth: .infinity) }.controlSize(.large).disabled(model.operation != nil)
                            if book.metadata.format == "EPUB" {
                                Button("Export Kindle AZW3…") { model.kindleExportBook = book }.disabled(model.operation != nil)
                            }
                            Button { model.export(book) } label: { Label("Export a copy…", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }.controlSize(.large).disabled(model.operation != nil)
                        }
                        Label("Your original stays untouched", systemImage: "checkmark.shield").font(.system(size: 10)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }.padding(24)
                }
            } else {
                VStack(spacing: 13) {
                    Image(systemName: "book.pages").font(.system(size: 32, weight: .ultraLight)).foregroundStyle(.tertiary)
                    Text("A closer look").font(.system(size: 21, design: .serif))
                    Text("Select a book to see its details,\nmake it yours, or take it with you.").font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(4)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.background(SmallibreTheme.canvas)
    }
    private func badge(_ value: String) -> some View { Text(value).font(.system(size: 9, weight: .medium)).padding(.horizontal, 7).padding(.vertical, 4).background(.primary.opacity(0.05), in: .capsule).foregroundStyle(.secondary) }
    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(label).font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(.tertiary); Text(value).font(.system(size: 12)).textSelection(.enabled) }
    }
}

struct EditBookView: View {
    @Bindable var model: AppModel
    @State var book: LibraryBook
    @State private var authors: String
    @State private var saving = false
    @State private var supportsTypography: Bool?
    @Environment(\.dismiss) private var dismiss
    init(model: AppModel, book: LibraryBook) { self.model = model; self._book = State(initialValue: book); self._authors = State(initialValue: book.metadata.authors.joined(separator: "; ")) }
    var body: some View {
        VStack(spacing: 0) {
            HStack { VStack(alignment: .leading, spacing: 5) { Text("Make it yours").font(.system(size: 27, design: .serif)); Text("Small adjustments. A better reading experience.").font(.system(size: 12)).foregroundStyle(.secondary) }; Spacer() }.padding(26)
            Form {
                Section("Book details") {
                    TextField("Title", text: $book.metadata.title)
                    TextField("Authors", text: $authors, prompt: Text("Separate authors with a semicolon"))
                    TextField("Language", text: $book.metadata.language, prompt: Text("en, pl, fr…"))
                    TextField("Publisher", text: $book.metadata.publisher)
                }
                if book.metadata.format == "EPUB", supportsTypography != false {
                    Section {
                        Toggle("Personalize body typography", isOn: $book.typography.enabled).disabled(supportsTypography == nil)
                        if book.typography.enabled {
                            Picker("Body font", selection: $book.typography.font) { Text("Publisher’s choice").tag(TypographySettings.Font.original); Text("Serif").tag(TypographySettings.Font.serif); Text("Sans serif").tag(TypographySettings.Font.sansSerif) }
                            LabeledContent("Line spacing", value: book.typography.lineHeight.formatted(.number.precision(.fractionLength(1))))
                            Slider(value: $book.typography.lineHeight, in: 1...2.4, step: 0.1).accessibilityLabel("Line spacing")
                            LabeledContent("Side margins", value: "\(Int(book.typography.marginPercent))%")
                            Slider(value: $book.typography.marginPercent, in: 0...12, step: 1).accessibilityLabel("Side margins")
                            Text("Changes apply to body text in reflowable EPUBs. Preview before exporting; your reader may render fonts differently.").font(.caption).foregroundStyle(.secondary)
                        }
                    } header: { Text("Reading preferences") }
                } else if book.metadata.format != "EPUB" {
                    Section { Text("These details are saved in your library. MOBI and AZW3 export their original bytes; embedded metadata and typography editing are not supported yet.").font(.callout).foregroundStyle(.secondary) }
                } else {
                    Section("Reading preferences") { Text("This book uses a specialized layout. Smallibre preserves its typography.").font(.callout).foregroundStyle(.secondary) }
                }
                Section("Description") { TextEditor(text: $book.metadata.description).frame(minHeight: 65) }
            }.formStyle(.grouped)
            HStack {
                Label("Original preserved", systemImage: "checkmark.shield").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save changes") {
                    book.metadata.authors = authors.components(separatedBy: ";")
                    saving = true
                    Task { await model.save(book); saving = false }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(saving || book.metadata.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(20)
        }.frame(width: 570, height: 650).background(SmallibreTheme.canvas).tint(SmallibreTheme.accent)
            .task {
                if let store = model.store { supportsTypography = (try? await store.supportsTypography(for: book.id)) ?? false }
            }
    }
}
