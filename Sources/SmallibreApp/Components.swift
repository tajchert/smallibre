import SwiftUI

/// One place to change the symbols the interface is drawn with.
enum Glyph {
    static let library = "books.vertical"
    static let personalized = "slider.horizontal.3"
    static let format = "doc.text"
    static let device = "ipad"
    static let book = "book"
    static let sort = "arrow.up.arrow.down"
    static let search = "magnifyingglass"
    static let add = "plus"
    static let send = "square.and.arrow.up"
    static let refresh = "arrow.clockwise"
    static let assurance = "checkmark.circle"
    static let details = "slider.horizontal.3"
    static let light = "sun.max"
    static let dark = "moon"
}

struct Hairline: View {
    var body: some View { Rectangle().fill(SmallibreTheme.separator).frame(height: 1) }
}

struct SidebarSectionHeader: View {
    let title: String
    var body: some View {
        Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(SmallibreTheme.text3)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8)
    }
}

struct SidebarRow: View {
    let title: String
    let systemImage: String
    var count: Int?
    var online = false
    var selected = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage).font(.system(size: 13)).frame(width: 16, height: 16)
                    .foregroundStyle(selected ? SmallibreTheme.accent : SmallibreTheme.text2)
                Text(title).lineLimit(1)
                Spacer(minLength: 4)
                if online { Circle().fill(SmallibreTheme.online).frame(width: 7, height: 7).accessibilityLabel("Connected") }
                if let count { Text("\(count)").font(.system(size: 12)).foregroundStyle(SmallibreTheme.text3).monospacedDigit() }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 8).frame(height: 28)
            .background(selected ? SmallibreTheme.fill2 : .clear, in: .rect(cornerRadius: 6))
            .contentShape(.rect)
        }
        .buttonStyle(.plain).foregroundStyle(SmallibreTheme.text)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct MetaPill: View {
    let text: String
    var highlighted = false
    var body: some View {
        Text(text).font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(highlighted ? SmallibreTheme.accentSoft : SmallibreTheme.fill, in: .capsule)
            .foregroundStyle(highlighted ? SmallibreTheme.accent : SmallibreTheme.text2)
    }
}

/// An inset group: one rounded card, hairline separated rows, used by the sheets.
struct FormGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(SmallibreTheme.group)
            .clipShape(.rect(cornerRadius: 9))
            .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(SmallibreTheme.separator, lineWidth: 1) }
    }
}

struct FormRow<Content: View>: View {
    let label: String
    var labelWidth: CGFloat = 110
    var height: CGFloat = 36
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 8) {
            Text(label).foregroundStyle(SmallibreTheme.text2).frame(width: labelWidth, alignment: .leading)
            content
        }
        .font(.system(size: 13)).padding(.horizontal, 12).frame(height: height)
    }
}

struct PillPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let active = option == selection
                Button { selection = option } label: {
                    Text(label(option)).font(.system(size: 12)).padding(.horizontal, 9).frame(height: 20)
                        .background(active ? SmallibreTheme.control : .clear, in: .rect(cornerRadius: 5))
                        .shadow(color: .black.opacity(active ? 0.15 : 0), radius: 1, y: 1)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain).foregroundStyle(SmallibreTheme.text)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(2).background(SmallibreTheme.fill, in: .rect(cornerRadius: 6))
    }
}

struct AccentButtonStyle: ButtonStyle {
    var height: CGFloat = 28
    var radius: CGFloat = 7
    var fillsWidth = false
    func makeBody(configuration: Configuration) -> some View {
        Chrome(configuration: configuration, height: height, radius: radius, fillsWidth: fillsWidth)
    }
    private struct Chrome: View {
        let configuration: ButtonStyleConfiguration
        let height: CGFloat
        let radius: CGFloat
        let fillsWidth: Bool
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SmallibreTheme.onAccent)
                .padding(.horizontal, 12)
                .frame(maxWidth: fillsWidth ? .infinity : nil).frame(height: height)
                .background(SmallibreTheme.accent.opacity(configuration.isPressed ? 0.82 : 1), in: .rect(cornerRadius: radius))
                .shadow(color: .black.opacity(0.15), radius: 1, x: 0, y: 1)
                .opacity(enabled ? 1 : 0.4)
                .contentShape(.rect)
        }
    }
}

struct ControlButtonStyle: ButtonStyle {
    var height: CGFloat = 28
    var radius: CGFloat = 7
    var fontSize: CGFloat = 13
    var tint: Color?
    var fillsWidth = false
    var active = false
    func makeBody(configuration: Configuration) -> some View {
        Chrome(configuration: configuration, height: height, radius: radius, fontSize: fontSize, tint: tint, fillsWidth: fillsWidth, active: active)
    }
    private struct Chrome: View {
        let configuration: ButtonStyleConfiguration
        let height: CGFloat
        let radius: CGFloat
        let fontSize: CGFloat
        let tint: Color?
        let fillsWidth: Bool
        let active: Bool
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            configuration.label
                .font(.system(size: fontSize))
                .foregroundStyle(tint ?? SmallibreTheme.text)
                .padding(.horizontal, 11)
                .frame(maxWidth: fillsWidth ? .infinity : nil).frame(height: height)
                .background(active || configuration.isPressed ? SmallibreTheme.fill2 : SmallibreTheme.control, in: .rect(cornerRadius: radius))
                .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(SmallibreTheme.controlBorder, lineWidth: 1) }
                .shadow(color: .black.opacity(0.08), radius: 0.5, x: 0, y: 0.5)
                .opacity(enabled ? 1 : 0.4)
                .contentShape(.rect)
        }
    }
}

extension ButtonStyle where Self == AccentButtonStyle {
    static var accentAction: AccentButtonStyle { AccentButtonStyle() }
    static func accentAction(height: CGFloat = 28, radius: CGFloat = 7, fillsWidth: Bool = false) -> AccentButtonStyle {
        AccentButtonStyle(height: height, radius: radius, fillsWidth: fillsWidth)
    }
}
extension ButtonStyle where Self == ControlButtonStyle {
    static var control: ControlButtonStyle { ControlButtonStyle() }
    static func control(height: CGFloat = 28, radius: CGFloat = 7, fontSize: CGFloat = 13, tint: Color? = nil, fillsWidth: Bool = false, active: Bool = false) -> ControlButtonStyle {
        ControlButtonStyle(height: height, radius: radius, fontSize: fontSize, tint: tint, fillsWidth: fillsWidth, active: active)
    }
}

/// The plain text field used inside sheets and the grouped rows.
struct DesignTextField: View {
    let placeholder: String
    @Binding var text: String
    var alignment: TextAlignment = .leading
    var bordered = false
    var height: CGFloat = 30
    var body: some View {
        let field = TextField(placeholder, text: $text)
            .textFieldStyle(.plain).font(.system(size: 13)).multilineTextAlignment(alignment)
            .foregroundStyle(SmallibreTheme.text)
        if bordered {
            field.padding(.horizontal, 10).frame(height: height)
                .background(SmallibreTheme.control, in: .rect(cornerRadius: 7))
                .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(SmallibreTheme.controlBorder, lineWidth: 1) }
        } else {
            field
        }
    }
}
