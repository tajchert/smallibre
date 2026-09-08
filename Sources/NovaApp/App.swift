import SwiftUI

@main
struct NovaApp: App {
    @State private var model = AppModel()
    var body: some Scene {
        WindowGroup("Calibre Nova") { LibraryView(model: model) }
            .defaultSize(width: 1200, height: 780)
            .commands {
                CommandGroup(replacing: .newItem) { Button("Add Books…") { model.chooseBooks() }.keyboardShortcut("o").disabled(model.importing) }
                CommandMenu("Book") {
                    Button("Preview") { if let book = model.selected { model.openPreview(book) } }.keyboardShortcut("r").disabled(model.selected?.metadata.format != "EPUB")
                    Button("Edit Details…") { model.editing = model.selected }.keyboardShortcut("i").disabled(model.selected == nil)
                    Button("Export a Copy…") { if let book = model.selected { model.export(book) } }.keyboardShortcut("e").disabled(model.selected == nil)
                }
            }
    }
}
