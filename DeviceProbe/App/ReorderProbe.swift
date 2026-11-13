import SwiftUI

/// A List whose rows reorder with SwiftUI's own onMove — the List path a reorderable Collection takes on every iOS
/// (jsonui-cli ticket jui-collection-drag-to-reorder) — for MoveItemOnDeviceTests. Rows are addressed by position,
/// `list_item_<n>`, as the libraries address a Collection's rows; each move is recorded under `moves` as
/// "from>to" with `to` counted after the move (onMove's destination converted, as the libraries do), and the order
/// under `order`, so a test reads what the app did, not only what is drawn.
struct ReorderProbeView: View {
    @State private var rows = (0..<12).map { "R\($0)" }
    @State private var moves: [String] = []

    var body: some View {
        VStack(spacing: 4) {
            Text(rows.joined(separator: ",")).font(.caption2).accessibilityIdentifier("order")
            Text(moves.joined(separator: " ")).font(.caption2).accessibilityIdentifier("moves")
            List {
                ForEach(Array(rows.enumerated()), id: \.element) { index, name in
                    Text(name)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .accessibilityIdentifier("list_item_\(index)")
                }
                .onMove { source, destination in
                    guard let from = source.first else { return }
                    let to = destination > from ? destination - 1 : destination
                    rows.move(fromOffsets: source, toOffset: destination)
                    moves.append("\(from)>\(to)")
                }
            }
            .listStyle(.plain)
        }
    }
}
