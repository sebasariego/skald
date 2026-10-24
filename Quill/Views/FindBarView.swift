import SwiftUI

/// The find (and replace) bar shown above the editor.
struct FindBarView: View {
    @Bindable var find: FindController
    @FocusState private var focusedField: Field?

    private enum Field {
        case query
        case replacement
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Find", text: $find.query)
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .query)
                        .onSubmit { NSApp.currentEvent?.modifierFlags.contains(.shift) == true ? find.findPrevious() : find.findNext() }
                    Toggle(isOn: $find.isCaseSensitive) { Text("Aa") }
                        .toggleStyle(.button)
                        .help("Match Case")
                    Toggle(isOn: $find.isRegex) { Text(".*") }
                        .toggleStyle(.button)
                        .help("Use Regular Expression")
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(queryBorderColor, lineWidth: focusedField == .query ? 2 : 1))
                .frame(maxWidth: 420)

                Text(find.statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(find.errorMessage == nil ? .secondary : Color.red)
                    .frame(minWidth: 80, alignment: .leading)
                    .lineLimit(1)

                Button { find.findPrevious() } label: { Image(systemName: "chevron.up") }
                    .help("Find Previous (\u{21E7}\u{2318}G)")
                Button { find.findNext() } label: { Image(systemName: "chevron.down") }
                    .help("Find Next (\u{2318}G)")

                Toggle(isOn: $find.showsReplace) { Image(systemName: "arrow.left.arrow.right") }
                    .toggleStyle(.button)
                    .help("Toggle Replace")

                Spacer()

                Button { find.hide() } label: { Image(systemName: "xmark") }
                    .help("Close (Esc)")
            }
            .buttonStyle(.borderless)
            .disabled(false)

            if find.showsReplace {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left.arrow.right").foregroundStyle(.secondary)
                        TextField("Replace", text: $find.replacement)
                            .textFieldStyle(.plain)
                            .focused($focusedField, equals: .replacement)
                            .onSubmit { find.replaceCurrent() }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(focusedField == .replacement ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: focusedField == .replacement ? 2 : 1))
                    .frame(maxWidth: 420)

                    Button("Replace") { find.replaceCurrent() }
                        .disabled(find.matches.isEmpty)
                    Button("Replace All") { find.replaceAll() }
                        .disabled(find.matches.isEmpty)
                    Spacer()
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
        .onExitCommand { find.hide() }
        .onAppear { focusedField = .query }
        .onChange(of: find.focusRequest) { _, _ in focusedField = .query }
    }

    private var queryBorderColor: Color {
        if find.errorMessage != nil { return .red }
        return focusedField == .query ? .accentColor : .secondary.opacity(0.3)
    }
}
