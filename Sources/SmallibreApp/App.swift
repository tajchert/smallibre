import SwiftUI

@main
struct SmallibreApp: App {
    @State private var model = AppModel()
    var body: some Scene {
        WindowGroup("Smallibre") {
            if model.store != nil { LibraryView(model: model) }
            else {
                VStack(spacing: 18) {
                    ContentUnavailableView("Library unavailable", systemImage: "books.vertical", description: Text(model.startupFailure ?? "The library could not be opened."))
                    Button("Try again") { model.initializeLibrary() }.buttonStyle(.borderedProminent)
                }.padding(30).frame(minWidth: 500, minHeight: 350)
            }
        }
            .defaultSize(width: 1200, height: 780)
            .commands {
                CommandGroup(replacing: .newItem) { Button("Add Books…") { model.chooseBooks() }.keyboardShortcut("o").disabled(model.importing || model.store == nil) }
                CommandMenu("Book") {
                    Button("Preview") { if let book = model.selected { model.openPreview(book) } }.keyboardShortcut("r").disabled(model.selected?.metadata.format != "EPUB")
                    Button("Edit Details…") { model.editing = model.selected }.keyboardShortcut("i").disabled(model.selected == nil)
                    Button("Export a Copy…") { if let book = model.selected { model.export(book) } }.keyboardShortcut("e").disabled(model.selected == nil)
                }
            }
    }
}
