import SwiftUI
import SmallibreCore

struct BulkMetadataView: View {
    let model: AppModel
    let selection: BulkEditSelection
    @Environment(\.dismiss) private var dismiss
    @State private var fields: Set<String> = []
    @State private var authors = ""
    @State private var publisher = ""
    @State private var language = ""
    @State private var tags = ""
    @State private var tagMode = "Add"
    @State private var series = ""
    @State private var number = ""
    @State private var isRead = false
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit \(selection.ids.count) books").font(.system(size: 20, weight: .bold))
            Text("Only checked fields change. Blank replacements clear existing values.")
                .font(.system(size: 13)).foregroundStyle(SmallibreTheme.text2)
            ScrollView {
                FormGroup {
                    field("Authors") { DesignTextField(placeholder: "Separate authors with a semicolon", text: $authors) }
                    Hairline()
                    field("Publisher") { DesignTextField(placeholder: "Publisher", text: $publisher) }
                    Hairline()
                    field("Language") { DesignTextField(placeholder: "en, pl, fr…", text: $language) }
                    Hairline()
                    field("Tags") {
                        Picker("Tag action", selection: $tagMode) { ForEach(["Add", "Remove", "Replace"], id: \.self) { Text($0) } }
                            .labelsHidden().frame(width: 110)
                        DesignTextField(placeholder: "Separate tags with a semicolon", text: $tags)
                    }
                    Hairline()
                    field("Series") {
                        DesignTextField(placeholder: "Series name", text: $series)
                        DesignTextField(placeholder: "Number", text: $number).frame(width: 75)
                    }
                    Hairline()
                    field("Read state") {
                        Picker("Read state", selection: $isRead) { Text("Unread").tag(false); Text("Read").tag(true) }.labelsHidden()
                    }
                }
            }
            Text("Tags, series and read state stay in your library. Original files are preserved.")
                .font(.system(size: 12)).foregroundStyle(SmallibreTheme.text3)
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(SmallibreTheme.destructive) }
            Hairline()
            HStack {
                if saving { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.control).keyboardShortcut(.cancelAction).disabled(saving)
                Button("Apply to \(selection.ids.count) Books") { save() }
                    .buttonStyle(.accentAction).keyboardShortcut(.defaultAction).disabled(fields.isEmpty || saving)
            }
        }
        .padding(24).frame(width: 660, height: 470)
        .background(SmallibreTheme.sheet).foregroundStyle(SmallibreTheme.text).tint(SmallibreTheme.accent)
        .interactiveDismissDisabled(saving)
    }

    private func field<Content: View>(_ name: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Toggle(name, isOn: Binding(get: { fields.contains(name) }, set: { if $0 { fields.insert(name) } else { fields.remove(name) } }))
                .toggleStyle(.checkbox).frame(width: 105, alignment: .leading)
            HStack { content() }.frame(maxWidth: .infinity, alignment: .leading).disabled(!fields.contains(name)).opacity(fields.contains(name) ? 1 : 0.5)
        }.font(.system(size: 13)).padding(.horizontal, 12).frame(height: 40)
    }
    private func save() {
        var edit = BulkMetadataEdit()
        if fields.contains("Authors") { edit.authors = authors.components(separatedBy: ";") }
        if fields.contains("Publisher") { edit.publisher = publisher }
        if fields.contains("Language") { edit.language = language }
        if fields.contains("Read state") { edit.isRead = isRead }
        if fields.contains("Tags") {
            let values = tags.components(separatedBy: ";")
            edit.tags = tagMode == "Add" ? .add(values) : tagMode == "Remove" ? .remove(values) : .replace(values)
        }
        if fields.contains("Series") {
            let number = number.trimmingCharacters(in: .whitespacesAndNewlines)
            guard number.isEmpty || Double(number) != nil else { error = "Enter a valid series number."; return }
            edit.series = .init(name: series, number: number.isEmpty ? nil : Double(number))
        }
        saving = true; error = nil
        Task {
            do { try await model.saveBulk(edit, ids: selection.ids) }
            catch { self.error = error.localizedDescription }
            saving = false
        }
    }
}
