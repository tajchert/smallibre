import SwiftUI

@main
struct SmallibreApp: App {
    @State private var model = AppModel()
    init() { Appearance.apply() }
    var body: some Scene {
        WindowGroup("Smallibre") {
            if model.store != nil { LibraryView(model: model) }
            else {
                VStack(spacing: 18) {
                    ContentUnavailableView("Library unavailable", systemImage: "books.vertical", description: Text(model.startupFailure ?? "The library could not be opened."))
                    Button("Try again") { model.initializeLibrary() }.buttonStyle(.borderedProminent)
                }.padding(30).frame(minWidth: 500, minHeight: 350).background(SmallibreTheme.content).tint(SmallibreTheme.accent)
            }
        }
            .defaultSize(width: 1180, height: 760)
            .commands { LibraryCommands() }
    }
}
