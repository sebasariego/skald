import SwiftUI

/// Open documents as a row of pill-shaped tabs on a translucent bar. Tabs are laid out
/// by hand from their measured widths so that dragging one moves it with the pointer
/// while the others slide aside live, the way Safari and Xcode tabs behave.
struct TabBarView: View {
    @Environment(Workspace.self) private var workspace
    @State private var widths: [Document.ID: CGFloat] = [:]
    @State private var draggingID: Document.ID?
    @State private var dragX: CGFloat = 0
    @State private var grabOffset: CGFloat = 0

    private let spacing: CGFloat = 2
    private let leadingInset: CGFloat = 8
    private let maxTabWidth: CGFloat = 240

    var body: some View {
        let order = workspace.documents.documents
        let positions = positions(for: order)
        glassContainer {
            tabs(order: order, positions: positions)
        }
        // The 26-point pills sit centered in the 38-point bar: 6 points above and below.
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 38)
        .coordinateSpace(name: "tabBar")
        .onPreferenceChange(TabWidthPreference.self) { widths = $0 }
        .background(.bar, ignoresSafeAreaEdges: [])
    }

    /// Lets neighboring glass pills blend while a dragged tab slides past them.
    @ViewBuilder
    private func glassContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 6) { content() }
        } else {
            content()
        }
    }

    private func tabs(order: [Document], positions: [Document.ID: CGFloat]) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(order) { document in
                TabItemView(
                    document: document,
                    isSelected: document.id == workspace.selectedDocumentID,
                    select: { workspace.selectedDocumentID = document.id },
                    close: { Task { await workspace.close(document) } }
                )
                .frame(maxWidth: maxTabWidth)
                .fixedSize()
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: TabWidthPreference.self, value: [document.id: geometry.size.width])
                })
                .offset(x: document.id == draggingID ? dragX : (positions[document.id] ?? leadingInset))
                .zIndex(document.id == draggingID ? 1 : 0)
                .gesture(dragGesture(for: document, order: order, positions: positions))
            }
        }
    }

    /// Leading x of each tab in the current order.
    private func positions(for order: [Document]) -> [Document.ID: CGFloat] {
        var result: [Document.ID: CGFloat] = [:]
        var x = leadingInset
        for document in order {
            result[document.id] = x
            x += (widths[document.id] ?? 100) + spacing
        }
        return result
    }

    private func dragGesture(for document: Document, order: [Document], positions: [Document.ID: CGFloat]) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("tabBar"))
            .onChanged { value in
                if draggingID != document.id {
                    draggingID = document.id
                    grabOffset = value.startLocation.x - (positions[document.id] ?? leadingInset)
                    workspace.selectedDocumentID = document.id
                }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    dragX = value.location.x - grabOffset
                }
                reorderIfNeeded(dragged: document, order: order)
            }
            .onEnded { _ in
                withAnimation(.spring(duration: 0.28, bounce: 0.15)) {
                    draggingID = nil
                }
            }
    }

    /// Moves the dragged tab in the model once its center crosses a neighbor's center.
    private func reorderIfNeeded(dragged: Document, order: [Document]) {
        let width = widths[dragged.id] ?? 100
        let center = dragX + width / 2
        let others = order.filter { $0.id != dragged.id }
        var x = leadingInset
        var targetIndex = others.count
        for (index, other) in others.enumerated() {
            let otherWidth = widths[other.id] ?? 100
            if center < x + otherWidth / 2 {
                targetIndex = index
                break
            }
            x += otherWidth + spacing
        }
        let currentIndex = order.firstIndex { $0.id == dragged.id } ?? 0
        guard targetIndex != currentIndex else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            workspace.moveTab(dragged.id, toIndex: targetIndex)
        }
    }
}

private struct TabWidthPreference: PreferenceKey {
    static var defaultValue: [Document.ID: CGFloat] = [:]
    static func reduce(value: inout [Document.ID: CGFloat], nextValue: () -> [Document.ID: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}
