import SwiftUI

/// The floating quick-input panel. Hosted as an overlay by `MainWindowView`.
struct PaletteView: View {
    @Bindable var palette: PaletteController
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField(palette.placeholder, text: $palette.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .focused($isFocused)
                .onSubmit { palette.activateSelection() }
                .onMoveCommand { direction in
                    switch direction {
                    case .up: palette.moveSelection(by: -1)
                    case .down: palette.moveSelection(by: 1)
                    default: break
                    }
                }
            Divider()
            if palette.results.isEmpty {
                Text(palette.query.isEmpty ? "Nothing to show" : "No matching results")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                    .padding(12)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(palette.results.enumerated()), id: \.element.id) { index, result in
                                PaletteRowView(result: result, isSelected: index == palette.selectedIndex)
                                    .id(result.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture { palette.activate(result) }
                                    .onHover { if $0 { palette.selectedIndex = index } }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 360)
                    .onChange(of: palette.selectedIndex) { _, index in
                        guard palette.results.indices.contains(index) else { return }
                        proxy.scrollTo(palette.results[index].id, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 580)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator, lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        .onExitCommand { palette.dismiss() }
        .onAppear { isFocused = true }
    }
}

struct PaletteRowView: View {
    let result: PaletteResult
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(highlightedTitle)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let subtitle = result.candidate.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            if let detail = result.candidate.detail {
                Text(detail)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.22) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 6)
        .opacity(result.candidate.isEnabled ? 1 : 0.45)
    }

    private var highlightedTitle: AttributedString {
        var attributed = AttributedString(result.candidate.title)
        let utf16 = result.candidate.title.utf16
        for position in result.positions {
            guard position < utf16.count else { continue }
            let start = String.Index(utf16Offset: position, in: result.candidate.title)
            let end = String.Index(utf16Offset: position + 1, in: result.candidate.title)
            guard let lower = AttributedString.Index(start, within: attributed),
                  let upper = AttributedString.Index(end, within: attributed) else { continue }
            attributed[lower..<upper].font = .system(size: 13, weight: .bold)
            attributed[lower..<upper].foregroundColor = .accentColor
        }
        return attributed
    }
}
