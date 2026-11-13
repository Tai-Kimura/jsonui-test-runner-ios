import SwiftUI
#if canImport(SwiftJsonUI)
import SwiftJsonUI
#endif

/// A reorderable stack as SwiftJsonUI draws one (CollectionReorderRows in a VStack carrying
/// collectionReorderContainer, the `lazy: "none"` shape): from iOS 27 SwiftUI's reorderable(), below it the
/// library's own drag; with a handle, the library's drag on every iOS. For MoveItemLibraryOnDeviceTests. Built only
/// when the project is generated with SWIFTJSONUI_PATH (a SwiftJsonUI checkout with CollectionReorder): the driver
/// does not depend on SwiftJsonUI otherwise, and the tests skip naming why.
struct LibraryReorderProbeView: View {
    let usesHandle: Bool

    var body: some View {
        #if canImport(SwiftJsonUI)
        LibraryReorderRows(usesHandle: usesHandle)
        #else
        Text("SwiftJsonUI is not linked (generate the project with SWIFTJSONUI_PATH)").accessibilityIdentifier("unavailable")
        #endif
    }
}

#if canImport(SwiftJsonUI)
private struct LibraryReorderRows: View {
    let usesHandle: Bool
    @State private var rows = (0..<12).map { "R\($0)" }
    @State private var moves: [String] = []

    /// with a handle, R2 is locked (reorderLockedProperty): it is not picked up and no row passes it
    private var locked: Set<Int> { usesHandle ? Set(rows.indices.filter { rows[$0] == "R2" }) : [] }

    var body: some View {
        let reorder = CollectionReorder(isEnabled: true, usesHandle: usesHandle) { _, from, to in
            rows.insert(rows.remove(at: from), at: to)
            moves.append("\(from)>\(to)")
        }
        VStack(spacing: 4) {
            Text(rows.joined(separator: ",")).font(.caption2).accessibilityIdentifier("order")
            Text(moves.joined(separator: " ")).font(.caption2).accessibilityIdentifier("moves")
            ScrollView {
                VStack(spacing: 4) {
                    Text("header").frame(maxWidth: .infinity, minHeight: 30).background(Color.blue.opacity(0.15))
                    CollectionReorderRows(section: 0, ids: rows, locked: locked, reorder: reorder) { index in
                        HStack {
                            Text(rows[index]).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            if usesHandle {
                                Text("≡").frame(width: 44, height: 44).background(Color.gray.opacity(0.3))
                                    .accessibilityIdentifier("grip")
                                    .collectionReorderHandle()
                            }
                        }
                        .padding(.horizontal, 12)
                        .background(Color.white)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("lib_item_\(index)")
                    }
                    Text("footer").frame(maxWidth: .infinity, minHeight: 30).background(Color.blue.opacity(0.15))
                }
                .collectionReorderContainer(reorder)
            }
        }
    }
}
#endif
