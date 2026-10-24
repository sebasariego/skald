import SwiftUI

struct SettingsView: View {
    @Environment(Workspace.self) private var workspace
    @State private var families: [String] = []

    var body: some View {
        @Bindable var workspace = workspace
        Form {
            Section("Appearance") {
                Picker("Theme", selection: themeSelection) {
                    ForEach(workspace.availableThemes) { theme in
                        Text(theme.name).tag(theme.name)
                    }
                }
            }
            Section("Font") {
                Picker("Family", selection: fontFamilySelection) {
                    Text(MonospacedFontCatalog.systemOption).tag(MonospacedFontCatalog.systemOption)
                    Divider()
                    ForEach(families, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                Stepper(value: $workspace.editorConfiguration.fontSize, in: EditorConfiguration.minimumFontSize...EditorConfiguration.maximumFontSize, step: 1) {
                    LabeledContent("Size", value: "\(Int(workspace.editorConfiguration.fontSize)) pt")
                }
            }
            Section("Editing") {
                Stepper(value: $workspace.editorConfiguration.tabWidth, in: 1...16) {
                    LabeledContent("Tab width", value: "\(workspace.editorConfiguration.tabWidth)")
                }
                Toggle("Insert spaces when pressing Tab", isOn: $workspace.editorConfiguration.insertSpaces)
                Toggle("Trim trailing whitespace on save", isOn: $workspace.editorConfiguration.trimTrailingWhitespaceOnSave)
            }
            Section("Display") {
                Toggle("Soft wrap long lines", isOn: $workspace.editorConfiguration.softWrap)
                Toggle("Show line numbers", isOn: $workspace.editorConfiguration.showLineNumbers)
                Toggle("Highlight current line", isOn: $workspace.editorConfiguration.highlightCurrentLine)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .task { families = MonospacedFontCatalog.familyNames() }
    }

    private var themeSelection: Binding<String> {
        Binding(
            get: { workspace.theme.name },
            set: { workspace.selectTheme(named: $0) }
        )
    }

    private var fontFamilySelection: Binding<String> {
        Binding(
            get: { MonospacedFontCatalog.family(forFontName: workspace.editorConfiguration.fontName) },
            set: { workspace.editorConfiguration.fontName = MonospacedFontCatalog.fontName(forFamily: $0) }
        )
    }
}
