import SwiftUI

/// The strip under the editor: caret position, indentation, encoding, line ending, language.
struct StatusBarView: View {
    @Environment(Workspace.self) private var workspace
    let document: Document

    var body: some View {
        HStack(spacing: 16) {
            Text(positionText)
            Spacer()
            Button(indentationText) { workspace.showSettings() }
                .help("Indentation (opens Settings)")
            Text(encodingText)
            Text(document.lineEnding.displayName)
            Text(document.language?.displayName ?? "Plain Text")
        }
        .buttonStyle(.plain)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 22)
        .background(.bar)
    }

    private var positionText: String {
        let status = workspace.status
        var text = "Ln \(status.line), Col \(status.column)"
        if status.selectedCharacters > 0 {
            text += " (\(status.selectedCharacters) selected"
            if status.selectedLines > 1 { text += ", \(status.selectedLines) lines" }
            text += ")"
        }
        return text
    }

    private var indentationText: String {
        let configuration = workspace.editorConfiguration
        return configuration.insertSpaces ? "Spaces: \(configuration.tabWidth)" : "Tabs: \(configuration.tabWidth)"
    }

    private var encodingText: String {
        switch document.encoding {
        case .utf8: return "UTF-8"
        case .utf16: return "UTF-16"
        case .isoLatin1: return "ISO Latin 1"
        default: return String(describing: document.encoding)
        }
    }
}
