import SwiftUI
import AppKit

/// One entry in a `PopupMenuButton` menu.
struct PopupMenuItem {
    let title: String
    var checked = false
    let action: @MainActor () -> Void
}

/// A custom-styled button that pops a native `NSMenu` immediately on press.
/// SwiftUI's `Menu` inside a hosted toolbar item draws a non-native popup after a delay.
struct PopupMenuButton<Label: View>: View {
    let items: [PopupMenuItem]
    @ViewBuilder let label: () -> Label

    var body: some View {
        label().overlay { Presenter(items: items) }
    }

    private struct Presenter: NSViewRepresentable {
        let items: [PopupMenuItem]
        func makeNSView(context: Context) -> PresenterView { PresenterView() }
        func updateNSView(_ view: PresenterView, context: Context) { view.items = items }
    }

    @MainActor
    private final class PresenterView: NSView {
        var items: [PopupMenuItem] = []

        override func mouseDown(with event: NSEvent) {
            let menu = NSMenu()
            for item in items {
                let entry = ActionItem(title: item.title, action: item.action)
                entry.state = item.checked ? .on : .off
                menu.addItem(entry)
            }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 6), in: self)
        }
    }

    @MainActor
    private final class ActionItem: NSMenuItem {
        let handler: @MainActor () -> Void
        init(title: String, action: @escaping @MainActor () -> Void) {
            handler = action
            super.init(title: title, action: #selector(fire), keyEquivalent: "")
            target = self
        }
        required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        @objc private func fire() { handler() }
    }
}
