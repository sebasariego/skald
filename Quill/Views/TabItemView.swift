import SwiftUI

struct TabItemView: View {
    let document: Document
    let isSelected: Bool
    let select: () -> Void
    let close: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: close) {
                Image(systemName: document.isDirty && !isHovering ? "circle.fill" : "xmark")
                    .font(.system(size: document.isDirty && !isHovering ? 7 : 9, weight: .semibold))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(isHovering || isSelected || document.isDirty ? 1 : 0)
            .help("Close Tab (\u{2318}W)")

            Text(document.displayName)
                .lineLimit(1)
                .truncationMode(.middle)
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(isSelected ? 0.12 : (isHovering ? 0.06 : 0)))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}
