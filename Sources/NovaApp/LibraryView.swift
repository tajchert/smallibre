import SwiftUI
import NovaCore

struct LibraryView: View {
    @Bindable var model: AppModel
    @State private var dropTarget = false

    var body: some View {
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 185, ideal: 205, max: 240)
        } content: {
            shelf.navigationSplitViewColumnWidth(min: 380, ideal: 650)
        } detail: {
            InspectorView(model: model).navigationSplitViewColumnWidth(min: 250, ideal: 285, max: 340)
        }
        .navigationSplitViewStyle(.balanced)
        .tint(NovaTheme.accent)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { model.chooseBooks() } label: { Label("Add books", systemImage: "plus") }.keyboardShortcut("o").disabled(model.importing)
            }
            ToolbarItem(placement: .automatic) {
                Menu { Picker("Sort by", selection: $model.sort) { ForEach(AppModel.Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) } } }
                label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
            }
        }
        .searchable(text: $model.search, placement: .toolbar, prompt: "Search books or authors")
        .task { await model.start() }
        .onOpenURL { model.importURLs([$0]) }
        .dropDestination(for: URL.self) { urls, _ in
            guard !model.importing else { return false }
            model.importURLs(urls); return true
        } isTargeted: { dropTarget = $0 }
        .overlay { if dropTarget { RoundedRectangle(cornerRadius: 12).stroke(NovaTheme.accent, style: StrokeStyle(lineWidth: 3, dash: [8])).padding(8).allowsHitTesting(false) } }
        .sheet(item: $model.editing) { book in EditBookView(model: model, book: book) }
        .sheet(item: $model.preview) { PreviewView(content: $0) }
        .sheet(item: $model.transferBook) { book in TransferView(model: model, book: book) }
        .sheet(item: $model.metadataBook) { book in MetadataView(model: model, book: book) }
        .alert("Couldn’t complete the operation", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .frame(minWidth: 920, minHeight: 600)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "books.vertical.fill").font(.system(size: 25, weight: .light)).foregroundStyle(NovaTheme.accent)
                VStack(alignment: .leading, spacing: 1) { Text("Calibre Nova").font(.system(size: 17, weight: .semibold, design: .serif)); Text("A home for your books").font(.system(size: 10)).foregroundStyle(.secondary) }
            }.padding(.horizontal, 18).padding(.top, 25).padding(.bottom, 32)
            Text("LIBRARY").font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary).padding(.horizontal, 21).padding(.bottom, 10)
            navigationRow("All books", icon: "books.vertical", key: "all", count: model.books.count)
            navigationRow("Personalized", icon: "slider.horizontal.3", key: "prepared", count: model.books.filter(\.typography.enabled).count)
            Text("FORMATS").font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary).padding(.horizontal, 21).padding(.top, 28).padding(.bottom, 10)
            ForEach(["EPUB", "MOBI", "AZW3"], id: \.self) { format in
                navigationRow(format == "AZW3" ? "Kindle / AZW3" : format, icon: "doc.text", key: format, count: model.books.filter { $0.metadata.format == format }.count)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "externaldrive").font(.system(size: 20, weight: .light))
                Text("Bring your library along").font(.system(size: 12, weight: .medium))
                Text("Connect a reader, select a book, then choose Send to reader.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
            }.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(.primary.opacity(0.035), in: .rect(cornerRadius: 10)).padding(14)
            HStack(spacing: 6) { Circle().fill(NovaTheme.accent).frame(width: 5, height: 5); Text("On your Mac. Always yours.").font(.system(size: 10)).foregroundStyle(.secondary) }.padding(.horizontal, 20).padding(.bottom, 20)
        }.background(NovaTheme.panel)
    }
    private func navigationRow(_ title: String, icon: String, key: String, count: Int) -> some View {
        Button { model.filter = key } label: {
            HStack(spacing: 10) { Image(systemName: icon).frame(width: 18); Text(title); Spacer(); Text("\(count)").font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary) }
                .font(.system(size: 12, weight: model.filter == key ? .semibold : .regular))
                .padding(.horizontal, 12).padding(.vertical, 9)
                .foregroundStyle(model.filter == key ? NovaTheme.accent : .primary)
                .background(model.filter == key ? NovaTheme.accent.opacity(0.11) : .clear, in: .rect(cornerRadius: 7))
        }.buttonStyle(.plain).padding(.horizontal, 10).accessibilityAddTraits(model.filter == key ? .isSelected : [])
    }
    private var shelf: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(model.collectionTitle).font(.system(size: 30, weight: .regular, design: .serif))
                    Text(model.books.isEmpty ? "Good books deserve a little breathing room." : "\(model.visibleBooks.count) \(model.visibleBooks.count == 1 ? "book" : "books") · ready for your next chapter")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(.horizontal, 28).padding(.top, 27).padding(.bottom, 25)
            if model.books.isEmpty { emptyLibrary }
            else if model.visibleBooks.isEmpty {
                ContentUnavailableView.search(text: model.search).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 135, maximum: 180), spacing: 25, alignment: .top)], alignment: .leading, spacing: 30) {
                        ForEach(model.visibleBooks) { book in
                            Button { model.selection = book.id } label: {
                                VStack(alignment: .leading, spacing: 9) {
                                    BookCover(book: book, root: model.root).padding(7)
                                        .background(model.selection == book.id ? NovaTheme.accent.opacity(0.1) : .clear, in: .rect(cornerRadius: 8))
                                        .overlay { RoundedRectangle(cornerRadius: 8).stroke(model.selection == book.id ? NovaTheme.accent.opacity(0.6) : .clear, lineWidth: 1.5) }
                                    Text(book.metadata.title).font(.system(size: 12, weight: .medium)).lineLimit(2).foregroundStyle(.primary)
                                    Text(book.metadata.authors.isEmpty ? "Unknown author" : book.metadata.authors.joined(separator: ", ")).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                    HStack(spacing: 6) { Text(book.metadata.format).font(.system(size: 8, weight: .semibold)).tracking(0.8); if book.typography.enabled { Image(systemName: "slider.horizontal.3").font(.system(size: 9)) } }.foregroundStyle(.secondary)
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityLabel("\(book.metadata.title), \(book.metadata.authors.joined(separator: ", ")), \(book.metadata.format)")
                                .contextMenu {
                                    Button("Preview", systemImage: "book") { model.openPreview(book) }.disabled(book.metadata.format != "EPUB")
                                    Button("Edit details & typography", systemImage: "slider.horizontal.3") { model.editing = book }
                                    Button("Export book…", systemImage: "square.and.arrow.up") { model.export(book) }
                                    Button("Show original in Finder", systemImage: "folder") { model.revealOriginal(book) }
                                }
                        }
                    }.padding(.horizontal, 25).padding(.bottom, 28)
                }
            }
            footer
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(NovaTheme.canvas)
    }
    private var emptyLibrary: some View {
        VStack(spacing: 18) {
            Image(systemName: "book.closed").font(.system(size: 55, weight: .ultraLight)).foregroundStyle(NovaTheme.accent).padding(.bottom, 6)
            Text("Your next chapter\nstarts here.").font(.system(size: 34, weight: .regular, design: .serif)).multilineTextAlignment(.center)
            Text("Drop your EPUB or MOBI files here.\nWe’ll take care of the shelves.").font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
            Button("Add your first books", systemImage: "plus") { model.chooseBooks() }.buttonStyle(.borderedProminent).controlSize(.large).padding(.top, 7)
            Button("Explore with a sample book") { model.sample() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.bottom, 35)
    }
    private var footer: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.5)
            HStack(spacing: 8) {
                if model.operation != nil { ProgressView().controlSize(.mini) } else { Image(systemName: "checkmark.shield").foregroundStyle(NovaTheme.accent) }
                Text(model.operation ?? model.status ?? "Original files are always preserved").lineLimit(1)
                Spacer()
                if model.importing { Button("Cancel") { model.importTask?.cancel() }.buttonStyle(.plain) }
            }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 12)
        }
    }
}
