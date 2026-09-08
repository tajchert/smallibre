import SwiftUI
import SmallibreCore

struct InspectorView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if let book = model.selected {
                bookDetails(book)
            } else if let book = model.selectedDeviceBook {
                deviceDetails(book)
            } else {
                emptyState
            }
        }
        .background(SmallibreTheme.inspector)
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Image(systemName: Glyph.format).font(.system(size: 30, weight: .light))
                .foregroundStyle(SmallibreTheme.text3).accessibilityHidden(true)
            Text("A closer look").font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SmallibreTheme.text).padding(.top, 14)
            Text("Select a book to see its details, make it yours, or take it with you.")
                .font(.system(size: 13)).foregroundStyle(SmallibreTheme.text2)
                .multilineTextAlignment(.center).lineSpacing(4).padding(.top, 4)
        }
        .padding(.horizontal, 30).padding(.vertical, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func bookDetails(_ book: LibraryBook) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BookCover(book: book, root: model.root).frame(width: 136)
                    .frame(maxWidth: .infinity).padding(.top, 6).padding(.bottom, 18)
                title(book.metadata.title)
                author(book.metadata.authors)
                HStack(spacing: 6) {
                    MetaPill(text: book.metadata.format)
                    MetaPill(text: ByteCountFormatter.string(fromByteCount: Int64(book.byteCount), countStyle: .file))
                    if book.typography.enabled { MetaPill(text: "Personalized", highlighted: true) }
                }
                .frame(maxWidth: .infinity).padding(.top, 10)

                VStack(spacing: 8) {
                    if model.reader.folder != nil {
                        Button { model.reader.sendToDevice(book, model: model) } label: {
                            actionLabel(model.reader.deviceMatch(book) == nil ? "Send to Kindle" : "On Kindle · Send Again", Glyph.send)
                        }
                        .buttonStyle(.accentAction(height: 30, fillsWidth: true))
                        .disabled(model.operation != nil || model.reader.busy || !model.reader.libraryReady || model.reader.deviceMatch(book) != nil)
                    }
                    Button { model.openPreview(book) } label: { actionLabel("Preview Book", Glyph.book) }
                        .buttonStyle(.control(height: 28, fillsWidth: true))
                        .disabled(book.metadata.format != "EPUB" || model.operation != nil)
                    Button { model.editing = book } label: { actionLabel("Details & Typography…", Glyph.details) }
                        .buttonStyle(.control(height: 28, fillsWidth: true))
                    Button { model.metadataBook = book } label: { actionLabel("Find Book Details…", Glyph.search) }
                        .buttonStyle(.control(height: 28, fillsWidth: true))
                    if model.reader.busy {
                        ProgressView(model.reader.status ?? "Working with device…")
                            .progressViewStyle(.linear)
                            .font(.system(size: 11)).foregroundStyle(SmallibreTheme.text2)
                            .padding(.top, 2)
                        Button("Stop") { model.reader.cancel() }
                            .buttonStyle(.control(height: 26, fontSize: 12, fillsWidth: true))
                    }
                }
                .padding(.top, 18)

                Hairline().padding(.top, 20)
                Grid(alignment: Alignment(horizontal: .leading, vertical: .firstTextBaseline), horizontalSpacing: 14, verticalSpacing: 9) {
                    detailRow("Language", book.metadata.language.isEmpty ? "Not specified" : Locale.current.localizedString(forLanguageCode: book.metadata.language) ?? book.metadata.language)
                    if !book.metadata.publisher.isEmpty { detailRow("Publisher", book.metadata.publisher) }
                    if let year = book.metadata.publishedYear { detailRow("Published", year) }
                    detailRow("Added", book.addedAt.formatted(date: .abbreviated, time: .omitted))
                    detailRow("File", book.originalFilename, secondary: true)
                    if !book.metadata.identifier.isEmpty { detailRow("Identifier", book.metadata.identifier, secondary: true) }
                }
                .font(.system(size: 12)).padding(.top, 14)

                if !book.metadata.description.isEmpty {
                    Hairline().padding(.top, 16)
                    Text(book.metadata.description)
                        .font(.system(size: 12)).foregroundStyle(SmallibreTheme.text2).lineSpacing(4.5)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                }
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 24)
        }
    }

    /// A book found on the reader with no library counterpart: read-only, and it says so.
    private func deviceDetails(_ book: ReaderBook) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                RoundedRectangle(cornerRadius: 7).fill(SmallibreTheme.fill)
                    .frame(width: 136, height: 204)
                    .overlay { Image(systemName: Glyph.book).font(.system(size: 34, weight: .light)).foregroundStyle(SmallibreTheme.text3) }
                    .accessibilityLabel("Book on device")
                    .frame(maxWidth: .infinity).padding(.top, 6).padding(.bottom, 18)
                title(book.title)
                author(book.metadata?.authors ?? [])
                HStack(spacing: 6) {
                    MetaPill(text: book.formatLabel)
                    MetaPill(text: book.byteCount > 0 ? ByteCountFormatter.string(fromByteCount: Int64(book.byteCount), countStyle: .file) : "Size unavailable")
                }
                .frame(maxWidth: .infinity).padding(.top, 10)
                HStack(spacing: 6) {
                    Image(systemName: Glyph.device).font(.system(size: 11))
                    Text("On device · not in your library")
                }
                .font(.system(size: 12)).foregroundStyle(SmallibreTheme.text3)
                .frame(maxWidth: .infinity).padding(.top, 10)

                Hairline().padding(.top, 20)
                Grid(alignment: Alignment(horizontal: .leading, vertical: .firstTextBaseline), horizontalSpacing: 14, verticalSpacing: 9) {
                    if let metadata = book.metadata {
                        if !metadata.language.isEmpty { detailRow("Language", Locale.current.localizedString(forLanguageCode: metadata.language) ?? metadata.language) }
                        if !metadata.publisher.isEmpty { detailRow("Publisher", metadata.publisher) }
                        if let year = metadata.publishedYear { detailRow("Published", year) }
                        if !metadata.identifier.isEmpty { detailRow("Identifier", metadata.identifier, secondary: true) }
                    }
                    detailRow("File", book.relativePath, secondary: true)
                }
                .font(.system(size: 12)).padding(.top, 14)

                if book.metadata == nil {
                    Text("Book metadata is unavailable. Showing the device filename and file details.")
                        .font(.system(size: 12)).foregroundStyle(SmallibreTheme.text3).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 12)
                }
                if let description = book.metadata?.description, !description.isEmpty {
                    Hairline().padding(.top, 16)
                    Text(description)
                        .font(.system(size: 12)).foregroundStyle(SmallibreTheme.text2).lineSpacing(4.5)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                }
                if let issue = book.issue {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "info.circle").font(.system(size: 11))
                        Text(issue).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.system(size: 12)).foregroundStyle(SmallibreTheme.text3).padding(.top, 12)
                }
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 24)
        }
    }

    private func title(_ value: String) -> some View {
        Text(value).font(.system(size: 17, weight: .bold)).tracking(-0.25)
            .foregroundStyle(SmallibreTheme.text).multilineTextAlignment(.center)
            .textSelection(.enabled).frame(maxWidth: .infinity)
    }
    private func author(_ authors: [String]) -> some View {
        Text(authors.isEmpty ? "Unknown author" : authors.joined(separator: ", "))
            .font(.system(size: 13)).foregroundStyle(SmallibreTheme.text2)
            .multilineTextAlignment(.center).textSelection(.enabled)
            .frame(maxWidth: .infinity).padding(.top, 3)
    }
    private func actionLabel(_ title: String, _ symbol: String) -> some View {
        HStack(spacing: 7) { Image(systemName: symbol).font(.system(size: 13)); Text(title) }
    }
    private func detailRow(_ label: String, _ value: String, secondary: Bool = false) -> some View {
        GridRow {
            Text(label).foregroundStyle(SmallibreTheme.text3)
            Text(value).foregroundStyle(secondary ? SmallibreTheme.text2 : SmallibreTheme.text)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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

    private var isEPUB: Bool { book.metadata.format == "EPUB" }
    /// nil while the store is still answering; the controls stay inert until it does.
    private var typographyLocked: Bool { supportsTypography == nil }
    private var lineLabel: String { book.typography.lineHeight.formatted(.number.precision(.fractionLength(1))) }
    private var marginLabel: String { "\(Int(book.typography.marginPercent))%" }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Make it yours").font(.system(size: 20, weight: .bold)).tracking(-0.4).foregroundStyle(SmallibreTheme.text)
                Text("Small adjustments. A better reading experience.").font(.system(size: 13)).foregroundStyle(SmallibreTheme.text2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("Book details") {
                        FormGroup {
                            FormRow(label: "Title") { DesignTextField(placeholder: "Title", text: $book.metadata.title, alignment: .trailing) }
                            Hairline()
                            FormRow(label: "Authors") { DesignTextField(placeholder: "Separate authors with a semicolon", text: $authors, alignment: .trailing) }
                            Hairline()
                            FormRow(label: "Language") { DesignTextField(placeholder: "en, pl, fr…", text: $book.metadata.language, alignment: .trailing) }
                            Hairline()
                            FormRow(label: "Publisher") { DesignTextField(placeholder: "Publisher", text: $book.metadata.publisher, alignment: .trailing) }
                        }
                    }
                    section("Description") {
                        TextEditor(text: $book.metadata.description)
                            .textEditorStyle(.plain).scrollContentBackground(.hidden)
                            .font(.system(size: 13)).foregroundStyle(SmallibreTheme.text)
                            .frame(minHeight: 72)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(SmallibreTheme.group)
                            .clipShape(.rect(cornerRadius: 9))
                            .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(SmallibreTheme.separator, lineWidth: 1) }
                            .accessibilityLabel("Description")
                    }
                    if isEPUB, supportsTypography != false {
                        section("Reading preferences") {
                            FormGroup {
                                preferenceRow("Personalize body typography") {
                                    Toggle("Personalize body typography", isOn: $book.typography.enabled)
                                        .toggleStyle(.switch).labelsHidden().tint(SmallibreTheme.accent)
                                        .disabled(typographyLocked)
                                }
                                Hairline()
                                VStack(spacing: 0) {
                                    preferenceRow("Body font") {
                                        PillPicker(selection: $book.typography.font, options: [.original, .serif, .sansSerif]) { font in
                                            switch font {
                                            case .original: "Publisher’s choice"
                                            case .serif: "Serif"
                                            case .sansSerif: "Sans serif"
                                            }
                                        }
                                    }
                                    Hairline()
                                    sliderRow("Line spacing", lineLabel) {
                                        Slider(value: $book.typography.lineHeight, in: 1...2.4, step: 0.1).accessibilityLabel("Line spacing")
                                    }
                                    Hairline()
                                    sliderRow("Side margins", marginLabel) {
                                        Slider(value: $book.typography.marginPercent, in: 0...12, step: 1).accessibilityLabel("Side margins")
                                    }
                                }
                                .opacity(book.typography.enabled ? 1 : 0.45)
                                .disabled(!book.typography.enabled || typographyLocked)
                            }
                            Text("Applied when sending to a device. Your original EPUB is never modified.")
                                .font(.system(size: 12)).foregroundStyle(SmallibreTheme.text3).lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                        }
                    } else if !isEPUB {
                        note("These details are saved in your library. MOBI and AZW3 export their original bytes; embedded metadata and typography editing are not supported yet.")
                    } else {
                        section("Reading preferences") {
                            note("This book uses a specialized layout. Smallibre preserves its typography.")
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.bottom, 20)
            }

            VStack(spacing: 0) {
                Hairline()
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: Glyph.assurance).font(.system(size: 11))
                        Text("Original preserved")
                    }
                    .font(.system(size: 12)).foregroundStyle(SmallibreTheme.text3)
                    Spacer(minLength: 8)
                    Button("Cancel") { dismiss() }.buttonStyle(.control).keyboardShortcut(.cancelAction)
                    Button("Save Changes") {
                        book.metadata.authors = authors.components(separatedBy: ";")
                        saving = true
                        Task { await model.save(book); saving = false }
                    }
                    .buttonStyle(.accentAction()).keyboardShortcut(.defaultAction)
                    .disabled(saving || book.metadata.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 20).padding(.vertical, 14)
            }
            .background(SmallibreTheme.inspector)
        }
        .frame(width: 600, height: 650)
        .background(SmallibreTheme.sheet).tint(SmallibreTheme.accent)
        .task {
            if let store = model.store { supportsTypography = (try? await store.supportsTypography(for: book.id)) ?? false }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(SmallibreTheme.text)
            content()
        }
    }
    /// A grouped row whose label takes the slack, the way the reading-preference rows do.
    private func preferenceRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(label).foregroundStyle(SmallibreTheme.text)
            Spacer(minLength: 8)
            content()
        }
        .font(.system(size: 13)).padding(.horizontal, 12).frame(height: 36)
    }
    private func sliderRow<Content: View>(_ label: String, _ value: String, @ViewBuilder slider: () -> Content) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text(label).font(.system(size: 13)).foregroundStyle(SmallibreTheme.text)
                Spacer(minLength: 8)
                Text(value).font(.system(size: 13)).foregroundStyle(SmallibreTheme.text2).monospacedDigit()
            }
            slider()
        }
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 10)
    }
    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(SmallibreTheme.text2).lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(SmallibreTheme.fill, in: .rect(cornerRadius: 9))
    }
}
