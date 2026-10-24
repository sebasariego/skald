import SwiftUI

struct SettingsView: View {
    @Environment(Workspace.self) private var workspace
    @State private var families: [String] = []
    @AppStorage("fontPicker.showsAllFonts") private var showsAllFonts = false

    var body: some View {
        @Bindable var workspace = workspace
        Form {
            Section("Appearance") {
                Picker("Theme", selection: themeSelection) {
                    ForEach(workspace.availableThemes) { theme in
                        Text(theme.name).tag(theme.name)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Slider(value: $workspace.editorConfiguration.backgroundOpacity, in: EditorConfiguration.minimumBackgroundOpacity...1, step: 0.05) {
                        Text("Background opacity")
                    } minimumValueLabel: {
                        Image(systemName: "circle.dotted")
                    } maximumValueLabel: {
                        Image(systemName: "circle.fill")
                    }
                    Text("\(Int((workspace.editorConfiguration.clampedBackgroundOpacity * 100).rounded()))% \u{2014} below 100% the desktop shows through the editor, blurred.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                Toggle("Show all installed fonts, not only monospaced", isOn: $showsAllFonts)
                    .onChange(of: showsAllFonts) { _, _ in reloadFamilies() }
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
            Section("Terminal") {
                Picker("Open in Terminal uses", selection: terminalSelection) {
                    Text(ExternalTerminal.automatic.name).tag(ExternalTerminal.automatic.id)
                    Divider()
                    ForEach(ExternalTerminal.installed()) { terminal in
                        Text(terminal.name).tag(terminal.id)
                    }
                }
                Text("Opens a new window in the current file's folder. Shortcut: \u{2303}` (Control and backtick).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .task { reloadFamilies() }
    }

    private func reloadFamilies() {
        families = showsAllFonts ? MonospacedFontCatalog.allFamilyNames() : MonospacedFontCatalog.familyNames()
    }

    private var themeSelection: Binding<String> {
        Binding(
            get: { workspace.theme.name },
            set: { workspace.selectTheme(named: $0) }
        )
    }

    private var terminalSelection: Binding<String> {
        Binding(
            get: { workspace.terminalID ?? ExternalTerminal.automatic.id },
            set: { workspace.terminalID = $0 == ExternalTerminal.automatic.id ? nil : $0 }
        )
    }

    private var fontFamilySelection: Binding<String> {
        Binding(
            get: { MonospacedFontCatalog.family(forFontName: workspace.editorConfiguration.fontName) },
            set: { workspace.editorConfiguration.fontName = MonospacedFontCatalog.fontName(forFamily: $0) }
        )
    }
}
