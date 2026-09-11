import SwiftUI
import AppKit
import SmallibreCore

struct LibraryView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var dropTarget = false
    @FocusState private var searchFocused: Bool
    @State private var appearanceHover = false

    var body: some View {
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } content: {
            Group {
                if model.filter == "device" { ReaderView(reader: model.reader, model: model) } else { shelf }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SmallibreTheme.content)
            .navigationSplitViewColumnWidth(min: 400, ideal: 660)
        } detail: {
            InspectorView(model: model).navigationSplitViewColumnWidth(min: 280, ideal: 300, max: 340)
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle(model.collectionTitle)
        .tint(SmallibreTheme.accent)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ToolbarPlain {
                    HStack(spacing: 10) {
                        sortMenu
                        searchField
                        Button { model.chooseBooks() } label: {
                            HStack(spacing: 5) {
                                Image(systemName: Glyph.add).font(.system(size: 11, weight: .bold))
                                Text("Add Books")
                            }
                        }
                        .buttonStyle(.accentAction(height: 28, radius: 7))
                        .disabled(model.importing)
                        .help("Add books to library (⌘O)")
                    }
                    .padding(.trailing, 4)
                }
            }
        }
        .focusedSceneValue(\.libraryCommands, model.commandsAvailable ? LibraryCommandContext(model: model) { global in
            model.prepareSearch(global: global)
            searchFocused = true
        } : nil)
        .task { await model.start() }
        .onOpenURL { model.importURLs([$0]) }
        .dropDestination(for: URL.self) { urls, _ in
            guard !model.importing else { return false }
            model.importURLs(urls); return true
        } isTargeted: { dropTarget = $0 }
        .overlay { if dropTarget { RoundedRectangle(cornerRadius: 12).stroke(SmallibreTheme.accent, style: StrokeStyle(lineWidth: 3, dash: [8])).padding(8).allowsHitTesting(false) } }
        .sheet(isPresented: $model.namingFilter) { SaveLibraryFilterView(model: model) }
        .sheet(item: $model.bulkEditing) { selection in BulkMetadataView(model: model, selection: selection) }
        .sheet(item: $model.editing) { book in EditBookView(model: model, book: book) }
        .sheet(item: $model.preview) { PreviewView(content: $0) }
        .sheet(item: $model.exportBook) { book in TransferView(model: model, book: book, localExport: true) }
        .sheet(item: $model.transferBook) { book in TransferView(model: model, book: book) }
        .sheet(item: $model.metadataBook) { book in MetadataView(model: model, book: book) }
        .alert("Couldn’t complete the operation", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .frame(minWidth: 960, minHeight: 620)
    }

    // MARK: Toolbar

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: Glyph.search).font(.system(size: 12, weight: .medium)).foregroundStyle(SmallibreTheme.text3)
            TextField(model.filter == "device" ? "Search books or authors" : "Search library", text: $model.search)
                .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(SmallibreTheme.text)
                .focused($searchFocused)
                .onExitCommand { model.search = ""; searchFocused = false }
            if !model.search.isEmpty {
                Button { model.search = ""; searchFocused = true } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(SmallibreTheme.text3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9).frame(width: 230, height: 28)
        .background(SmallibreTheme.field, in: .rect(cornerRadius: 7))
        .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(searchFocused ? SmallibreTheme.accent : SmallibreTheme.controlBorder, lineWidth: 1) }
        .help(model.filter == "device" ? "Search books or authors (⌘F)" : "Search titles, authors, publishers, descriptions, identifiers, tags and series (⌘F)")
    }

    private var sortMenu: some View {
        PopupMenuButton(items: AppModel.Sort.allCases.filter { model.filter != "device" || $0 != .series }.map { sort in
            let active = model.sort == sort
            let title = active ? "\(sort.rawValue) \(model.sortAscending ? "↑" : "↓")" : sort.rawValue
            return PopupMenuItem(title: title, checked: active) { model.selectSort(sort) }
        }) {
            HStack(spacing: 5) {
                Image(systemName: Glyph.sort).font(.system(size: 11, weight: .semibold))
                Text(model.sort.rawValue).font(.system(size: 13))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(SmallibreTheme.text)
            .padding(.leading, 9).padding(.trailing, 8).frame(height: 28)
            .background(SmallibreTheme.control, in: .rect(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(SmallibreTheme.controlBorder, lineWidth: 1) }
            .shadow(color: .black.opacity(0.08), radius: 0.5, x: 0, y: 0.5)
        }
        .fixedSize()
        .help(model.filter == "device" ? "Sort device books. Recently added uses file creation dates, or modification dates when unavailable." : "Sort library books")
    }

    // MARK: Sidebar

    private var sidebar: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: Glyph.library).font(.system(size: 22, weight: .regular)).foregroundStyle(SmallibreTheme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Smallibre").font(.system(size: 14, weight: .semibold)).foregroundStyle(SmallibreTheme.text)
                    Text("A home for your books").font(.system(size: 11)).foregroundStyle(SmallibreTheme.text3)
                }
            }
            .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 6)

            SidebarSectionHeader(title: "Library").padding(.top, 14).padding(.bottom, 4)
            SidebarRow(title: "All Books", systemImage: Glyph.library, count: model.books.count,
                       selected: model.filter == "all") { model.filter = "all" }
            SidebarRow(title: "Personalized", systemImage: Glyph.personalized, count: model.books.filter(\.typography.enabled).count,
                       selected: model.filter == "prepared") { model.filter = "prepared" }

            SidebarRow(title: "Unread", systemImage: "book", count: model.books.filter { !$0.organization.isRead }.count,
                       selected: model.filter == "unread") { model.filter = "unread" }
            SidebarRow(title: "Read", systemImage: "checkmark.circle", count: model.books.filter { $0.organization.isRead }.count,
                       selected: model.filter == "read") { model.filter = "read" }

            SidebarSectionHeader(title: "Formats").padding(.top, 16).padding(.bottom, 4)
            ForEach(["EPUB", "MOBI", "AZW3"], id: \.self) { format in
                SidebarRow(title: format == "AZW3" ? "Kindle / AZW3" : format, systemImage: Glyph.format,
                           count: model.books.filter { $0.metadata.format == format }.count,
                           selected: model.filter == format) { model.filter = format }
            }

            if !model.savedFilters.isEmpty {
                SidebarSectionHeader(title: "Saved views").padding(.top, 16).padding(.bottom, 4)
                ForEach(model.savedFilters) { saved in
                    SidebarRow(title: saved.name, systemImage: "line.3.horizontal.decrease.circle",
                               selected: model.currentQuery == saved.query) { model.applyFilter(saved) }
                        .contextMenu { Button("Delete Saved View", role: .destructive) { model.deleteSavedFilter(saved) } }
                }
            }
            SidebarSectionHeader(title: "Device").padding(.top, 16).padding(.bottom, 4)
            if model.reader.folder != nil {
                SidebarRow(title: "Kindle", systemImage: Glyph.device, count: model.reader.books.count, online: true,
                           selected: model.filter == "device") { model.filter = "device" }
            } else {
                SidebarRow(title: "Connect reader…", systemImage: Glyph.device,
                           selected: model.filter == "device") { model.filter = "device" }
            }

            Spacer(minLength: 12)

            if model.reader.folder == nil {
                VStack(alignment: .leading, spacing: 0) {
                    Image(systemName: Glyph.device).font(.system(size: 17, weight: .regular)).foregroundStyle(SmallibreTheme.text2)
                    Text("Bring your library along").font(.system(size: 13, weight: .semibold)).foregroundStyle(SmallibreTheme.text).padding(.top, 8)
                    // No fixedSize here: in a NavigationSplitView sidebar it reports an unbounded
                    // ideal height and pushes every column out of the window.
                    Text("Connect a reader, select a book, then choose Send to Kindle.")
                        .font(.system(size: 12)).foregroundStyle(SmallibreTheme.text2).lineSpacing(3)
                        .multilineTextAlignment(.leading).padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                .background(SmallibreTheme.fill, in: .rect(cornerRadius: 10))
                .padding(.horizontal, 2).padding(.bottom, 10)
            }

            appearanceToggle.padding(.horizontal, 2)
        }
        .padding(.horizontal, 10).padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(SmallibreTheme.sidebar)
    }

    private var appearanceToggle: some View {
        let dark = colorScheme == .dark
        let title = dark ? "Switch to light appearance" : "Switch to dark appearance"
        return Button { Appearance.set(dark ? .light : .dark) } label: {
            Image(systemName: dark ? Glyph.light : Glyph.dark).font(.system(size: 13))
                .frame(width: 28, height: 28)
                .background(appearanceHover ? SmallibreTheme.fill : .clear, in: .rect(cornerRadius: 6))
                .contentShape(.rect)
        }
        .buttonStyle(.plain).foregroundStyle(SmallibreTheme.text2)
        .onHover { appearanceHover = $0 }
        .help(title).accessibilityLabel(title)
        .contextMenu { Button("Follow System Appearance") { Appearance.set(.system) } }
    }

    // MARK: Library

    private var shelf: some View {
        VStack(spacing: 0) {
            LibraryFilterBar(model: model)
            if model.books.isEmpty {
                emptyLibrary
            } else if model.visibleBooks.isEmpty {
                hero(title: model.search.isEmpty ? "Nothing here yet" : "No matches",
                     message: model.search.isEmpty ? "No books in this view." : "Nothing in this view matches “\(model.search)”.")
            } else {
                if model.libraryList { bookList } else { grid }
            }
            footer
        }
        .onChange(of: model.visibleBooks.map(\.id)) { _, ids in
            model.librarySelection.formIntersection(Set(ids))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SmallibreTheme.content)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 166, maximum: 166), spacing: 22, alignment: .top)], alignment: .leading, spacing: 28) {
                ForEach(model.visibleBooks) { book in cell(book) }
            }
            .padding(.horizontal, 28).padding(.top, 26).padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var bookList: some View {
        List(selection: $model.librarySelection) {
            ForEach(model.visibleBooks) { book in
                HStack(spacing: 12) {
                    Image(systemName: book.organization.isRead ? "checkmark.circle" : "book")
                        .foregroundStyle(SmallibreTheme.text3)
                        .accessibilityLabel(book.organization.isRead ? "Read" : "Unread")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(book.metadata.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(book.metadata.authors.joined(separator: ", ")).font(.system(size: 12)).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Text(book.organization.seriesLabel).font(.system(size: 12)).lineLimit(1).frame(maxWidth: 160, alignment: .trailing)
                    Text(book.metadata.format).font(.system(size: 11)).frame(width: 45, alignment: .trailing)
                }
                .padding(.vertical, 5).tag(book.id)
            }
        }
        .listStyle(.inset).scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: UUID.self) { ids in
            Button("Edit details…") {
                model.librarySelection = ids
                model.editSelectedBooks()
            }.disabled(ids.isEmpty)
        } primaryAction: { ids in
            model.librarySelection = ids
            model.editSelectedBooks()
        }
    }

    private func cell(_ book: LibraryBook) -> some View {
        let selected = model.librarySelection.contains(book.id)
        let author = book.metadata.authors.isEmpty ? "Unknown author" : book.metadata.authors.joined(separator: ", ")
        // A Button keeps the cell reachable from the keyboard and assistive technology; the
        // double click that opens the sheet rides alongside it rather than replacing it.
        return Button {
            let modifiers = NSEvent.modifierFlags
            model.selectLibraryBook(book.id, extending: modifiers.contains(.shift), toggling: modifiers.contains(.command))
        } label: { cellLabel(book, author: author, selected: selected) }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture(count: 2).onEnded { model.editing = book })
            .contextMenu {
                if model.selectedLibraryBooks.count > 1, selected {
                    Button("Edit selected books…") { model.editSelectedBooks() }
                    Divider()
                }
                Button("Preview", systemImage: Glyph.book) { model.openPreview(book) }.disabled(book.metadata.format != "EPUB")
                Button("Edit details & typography", systemImage: Glyph.details) { model.editing = book }
                Button("Export book…", systemImage: Glyph.send) { model.export(book) }
                Button("Show original in Finder", systemImage: "folder") { model.revealOriginal(book) }
            }
            .accessibilityLabel("\(book.metadata.title), \(author), \(book.metadata.format)")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func cellLabel(_ book: LibraryBook, author: String, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            BookCover(book: book, root: model.root).frame(width: 148)
                .padding(5)
                .background(selected ? SmallibreTheme.accentSoft : .clear, in: .rect(cornerRadius: 9))
                .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? SmallibreTheme.accent : .clear, lineWidth: 2) }
            VStack(alignment: .leading, spacing: 0) {
                Text(book.metadata.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(SmallibreTheme.text)
                    .lineLimit(1).truncationMode(.tail)
                Text(author).font(.system(size: 12)).foregroundStyle(SmallibreTheme.text2)
                    .lineLimit(1).truncationMode(.tail).padding(.top, 2)
                HStack(spacing: 6) {
                    Text(book.metadata.format).tracking(0.8)
                    if book.typography.enabled {
                        Image(systemName: Glyph.personalized).font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(SmallibreTheme.accent).accessibilityLabel("Personalized")
                    }
                    if model.reader.deviceMatch(book) != nil { Text("· ON KINDLE") }
                }
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(SmallibreTheme.text3)
                .lineLimit(1).padding(.top, 5)
            }
            .padding(.top, 8).padding(.horizontal, 5)
        }
        .frame(width: 166, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var emptyLibrary: some View {
        VStack(spacing: 0) {
            Text("Nothing here yet").font(.system(size: 15, weight: .semibold)).foregroundStyle(SmallibreTheme.text)
            Text("Drop EPUB, MOBI or AZW3 files anywhere in this window, or press ⌘O.")
                .font(.system(size: 13)).foregroundStyle(SmallibreTheme.text2).multilineTextAlignment(.center).padding(.top, 4)
            Button { model.chooseBooks() } label: {
                HStack(spacing: 5) {
                    Image(systemName: Glyph.add).font(.system(size: 11, weight: .bold))
                    Text("Add Books")
                }
            }
            .buttonStyle(.accentAction(height: 30, radius: 7)).disabled(model.importing).padding(.top, 18)
            Button("Explore with a sample book") { model.sample() }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(SmallibreTheme.text2)
                .disabled(model.importing).padding(.top, 10)
        }
        .padding(.horizontal, 40).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func hero(title: String, message: String) -> some View {
        VStack(spacing: 0) {
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(SmallibreTheme.text)
            Text(message).font(.system(size: 13)).foregroundStyle(SmallibreTheme.text2)
                .multilineTextAlignment(.center).padding(.top, 4)
        }
        .padding(.horizontal, 40).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 6) {
                if model.operation != nil { ProgressView().controlSize(.mini).scaleEffect(0.7).frame(width: 12, height: 12) }
                else { Image(systemName: Glyph.assurance).font(.system(size: 11)) }
                Text(model.operation ?? model.status ?? "Original files are always preserved").lineLimit(1)
                Spacer(minLength: 8)
                if model.importing {
                    Button("Cancel") { model.importTask?.cancel() }.buttonStyle(.plain).foregroundStyle(SmallibreTheme.accent)
                }
            }
            .font(.system(size: 12)).foregroundStyle(SmallibreTheme.text3)
            .padding(.horizontal, 28).padding(.vertical, 8)
        }
    }
}
