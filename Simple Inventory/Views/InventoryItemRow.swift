//
//  InventoryItemRow.swift
//  Simple Inventory
//

import SwiftUI
import SwiftData

struct InventoryItemRow: View {
    let item: InventoryItem

    var body: some View {
        HStack(spacing: 12) {
            // Item image or placeholder
            Group {
                if let imageData = item.imageData,
                   let image = Image(data: imageData) {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "cube.box.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 52, height: 52)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Item details
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)
                    .lineLimit(1)

                if let tags = item.tags, !tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            // Status must stay readable even on tagged rows —
                            // the small ring's stroke color alone isn't enough
                            // (and fails for red/green color blindness).
                            if item.stockStatus != .normal {
                                StatusBadge(status: item.stockStatus, prominent: false)
                            }
                            ForEach(tags) { tag in
                                TagChip(tag: tag, size: .small)
                            }
                        }
                    }
                    .scrollClipDisabled(false)
                } else if item.stockStatus != .normal {
                    StatusBadge(status: item.stockStatus, prominent: false)
                }
            }

            Spacer()

            StockRing(
                quantity: item.currentQuantity,
                yellowLimit: item.yellowLimit,
                status: item.stockStatus,
                diameter: 44
            )
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: InventoryItem.self, configurations: config)

    let item = InventoryItem(name: "Sample Item", yellowLimit: 5, redLimit: 2)
    item.addStock(amount: 3)
    container.mainContext.insert(item)

    return List {
        InventoryItemRow(item: item)
    }
    .modelContainer(container)
}
