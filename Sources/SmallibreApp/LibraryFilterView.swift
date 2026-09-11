import SwiftUI
import SmallibreCore

struct LibraryFilterBar: View {
    @Bindable var model: AppModel
    @State private var showingFilters = false
    private var active: Bool { model.currentQuery.readState != .any || !model.tagFilter.isEmpty || !model.seriesFilter.isEmpty }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { showingFilters.toggle() } label: {
                    Label(active ? "Filtered" : "Filters", systemImage: "line.3.horizontal.decrease.circle")
                }
                .buttonStyle(.control(height: 26))
                .popover(isPresented: $showingFilters) { filters }
                if active {
                    Button("Clear") {
                        if model.filter == "read" || model.filter == "unread" { model.filter = "all" }
                        model.clearOrganizationFilters()
                    }.buttonStyle(.plain).foregroundStyle(SmallibreTheme.text2)
                }
                Button("Save View…") { model.namingFilter = true }
                    .buttonStyle(.control(height: 26)).disabled(model.store == nil)
                Spacer(minLength: 4)
                Text("\(model.visibleBooks.count) \(model.visibleBooks.count == 1 ? "book" : "books")").foregroundStyle(SmallibreTheme.text3).lineLimit(1)
                Button { model.libraryList.toggle() } label: {
                    Image(systemName: model.libraryList ? "square.grid.2x2" : "list.bullet")
                }.buttonStyle(.control(height: 26))
                    .help(model.libraryList ? "Show covers" : "Show list")
                    .accessibilityLabel(model.libraryList ? "Show covers" : "Show list")
            }
            .font(.system(size: 12)).padding(.horizontal, 20).padding(.vertical, 8)
            Hairline()
        }
    }
    private var filters: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Filter books").font(.headline)
            Picker("Reading", selection: Binding(get: { model.currentQuery.readState }, set: {
                if model.filter == "read" || model.filter == "unread" { model.filter = "all" }
                model.readState = $0
            })) {
                Text("Any").tag(LibraryQuery.ReadState.any)
                Text("Unread").tag(LibraryQuery.ReadState.unread)
                Text("Read").tag(LibraryQuery.ReadState.read)
            }
            Picker("Tag", selection: $model.tagFilter) {
                Text("Any tag").tag("")
                ForEach(Array(Set(model.allTags + [model.tagFilter])).filter { !$0.isEmpty }.sorted(), id: \.self) { Text($0).tag($0) }
            }
            Picker("Series", selection: $model.seriesFilter) {
                Text("Any series").tag("")
                ForEach(Array(Set(model.allSeries + [model.seriesFilter])).filter { !$0.isEmpty }.sorted(), id: \.self) { Text($0).tag($0) }
            }
            Text("Combine these with search and the selected format.")
                .font(.system(size: 12)).foregroundStyle(SmallibreTheme.text3)
            HStack { Spacer(); Button("Done") { showingFilters = false }.buttonStyle(.accentAction) }
        }.padding(20).frame(width: 320).tint(SmallibreTheme.accent)
    }
}

struct SaveLibraryFilterView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error: String?
    @State private var saving = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save this view").font(.system(size: 20, weight: .bold))
            Text("Keep this search and its filters in the sidebar. Matching books update automatically.")
                .font(.system(size: 13)).foregroundStyle(SmallibreTheme.text2)
            DesignTextField(placeholder: "View name", text: $name, bordered: true).accessibilityLabel("View name")
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(SmallibreTheme.destructive) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.control).keyboardShortcut(.cancelAction).disabled(saving)
                Button("Save View") {
                    saving = true
                    Task {
                        do { try await model.saveCurrentFilter(name: name) }
                        catch { self.error = error.localizedDescription }
                        saving = false
                    }
                }.buttonStyle(.accentAction).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
            }
        }.padding(24).frame(width: 420).background(SmallibreTheme.sheet).foregroundStyle(SmallibreTheme.text)
    }
}
