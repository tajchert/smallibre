import SwiftUI
import SmallibreCore

/// Commands are supplied by the library in the active window.
struct LibraryCommandContext {
    let model: AppModel
    let focusSearch: (_ global: Bool) -> Void
}

private struct LibraryCommandKey: FocusedValueKey {
    typealias Value = LibraryCommandContext
}

extension FocusedValues {
    var libraryCommands: LibraryCommandContext? {
        get { self[LibraryCommandKey.self] }
        set { self[LibraryCommandKey.self] = newValue }
    }
}

struct LibraryCommands: Commands {
    @FocusedValue(\.libraryCommands) private var context
    private var model: AppModel? { context?.model }
    private var selected: SmallibreCore.LibraryBook? { model?.commandSelection }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Books…") { model?.chooseBooks() }
                .keyboardShortcut("o")
                .disabled(model == nil || model?.importing == true)
        }
        CommandGroup(after: .textEditing) {
            Button("Search All Books") { context?.focusSearch(true) }.keyboardShortcut("k")
                .disabled(context == nil)
            Button("Find in Current Collection") { context?.focusSearch(false) }.keyboardShortcut("f")
                .disabled(context == nil)
        }
        CommandMenu("Navigate") {
            Button("All Books") { model?.filter = "all" }.keyboardShortcut("1").disabled(context == nil)
            Button("Personalized") { model?.filter = "prepared" }.keyboardShortcut("2").disabled(context == nil)
            Button("EPUB") { model?.filter = "EPUB" }.keyboardShortcut("3").disabled(context == nil)
            Button("MOBI") { model?.filter = "MOBI" }.keyboardShortcut("4").disabled(context == nil)
            Button("Kindle / AZW3") { model?.filter = "AZW3" }.keyboardShortcut("5").disabled(context == nil)
            Button("Kindle Reader") { model?.filter = "device" }.keyboardShortcut("6").disabled(context == nil)
        }
        CommandMenu("Book") {
            Button("Preview") { if let selected { model?.openPreview(selected) } }
                .keyboardShortcut("r").disabled(selected?.metadata.format != "EPUB")
            Button("Edit Details…") { model?.editSelectedBooks() }
                .keyboardShortcut("i").disabled(model?.selectedLibraryBooks.isEmpty != false)
            Button("Export File…") { if let selected { model?.export(selected) } }
                .keyboardShortcut("e").disabled(selected == nil || model?.operation != nil)
            Button("Show Original in Finder") { if let selected { model?.revealOriginal(selected) } }
                .keyboardShortcut("f", modifiers: [.command, .shift]).disabled(selected == nil)
        }
        CommandMenu("Reader") {
            Button("Refresh Reader") { model?.reader.refresh() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model?.reader.libraryReady != true || model?.reader.folder == nil || model?.reader.busy == true)
        }
    }
}
