//
//  ContentView.swift
//  Simple Inventory
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var systemUndoManager
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @State private var selectedItem: InventoryItem?
    @State private var searchText = ""
    @State private var stockFilter: StockFilter = .all
    @State private var selectedTags: Set<Tag> = []
    @State private var sortOption: SortOption = .nameAsc
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        Group {
            #if os(iOS)
            if horizontalSizeClass == .compact {
                compactStack
            } else {
                splitView
            }
            #else
            splitView
            #endif
        }
        .onAppear {
            // Bridge SwiftData undo into the system undo manager so shake /
            // three-finger-swipe (iOS) and Cmd+Z (macOS) actually work — a
            // detached UndoManager would never be reached by those gestures.
            modelContext.undoManager = systemUndoManager
        }
        .onChange(of: systemUndoManager == nil) { _, _ in
            modelContext.undoManager = systemUndoManager
        }
    }

    /// iPhone: plain push navigation. The split view's selection binding
    /// machinery buys nothing on compact width and was the source of the
    /// stale-detail-after-delete bug.
    private var compactStack: some View {
        NavigationStack {
            InventoryListView(
                selectedItem: $selectedItem,
                searchText: $searchText,
                stockFilter: $stockFilter,
                selectedTags: $selectedTags,
                sortOption: $sortOption,
                usesSelection: false
            )
            .navigationDestination(for: InventoryItem.self) { item in
                    ItemDetailView(
                        item: item,
                        onTagTap: { tag in
                            selectedTags = [tag]
                            stockFilter = .all
                        }
                    )
                }
        }
    }

    /// iPad / Mac: two-column layout where selection genuinely earns its keep.
    private var splitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            listView
            #if os(macOS)
                .navigationSplitViewColumnWidth(min: 280, ideal: 320)
            #endif
        } detail: {
            if let item = selectedItem {
                ItemDetailView(
                    item: item,
                    onTagTap: { tag in
                        selectedTags = [tag]
                        stockFilter = .all
                        selectedItem = nil
                    },
                    onDeleted: {
                        selectedItem = nil
                    }
                )
            } else {
                ContentUnavailableView {
                    Label("No Item Selected", systemImage: "cube.box")
                        .symbolRenderingMode(.hierarchical)
                } description: {
                    Text("Select an item from the list to view its details.")
                }
            }
        }
    }

    private var listView: some View {
        InventoryListView(
            selectedItem: $selectedItem,
            searchText: $searchText,
            stockFilter: $stockFilter,
            selectedTags: $selectedTags,
            sortOption: $sortOption
        )
    }
}

#Preview {
    ContentView()
        .modelContainer(for: InventoryItem.self, inMemory: true)
}
