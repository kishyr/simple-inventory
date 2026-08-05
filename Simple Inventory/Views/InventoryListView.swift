//
//  InventoryListView.swift
//  Simple Inventory
//

import SwiftUI
import SwiftData

struct InventoryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \InventoryItem.name) private var items: [InventoryItem]
    @Query(sort: \Tag.name) private var allTags: [Tag]

    @Binding var selectedItem: InventoryItem?
    @Binding var searchText: String
    @Binding var stockFilter: StockFilter
    @Binding var selectedTags: Set<Tag>
    @Binding var sortOption: SortOption
    /// True in the split-view (iPad/Mac) context where List selection drives
    /// the detail column. On compact iPhone the selection binding would
    /// swallow row taps instead of pushing navigation.
    var usesSelection: Bool = true

    @State private var showingAddItem = false
    @State private var showingTagManagement = false
    @State private var adjustingItem: InventoryItem?

    private var lowCount: Int {
        items.filter { $0.stockStatus == .low }.count
    }

    private var criticalCount: Int {
        items.filter { $0.stockStatus == .critical }.count
    }

    private var hasActiveFilters: Bool {
        stockFilter != .all || !selectedTags.isEmpty
    }

    var filteredAndSortedItems: [InventoryItem] {
        var result = items

        // Search filter
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        // Stock status filter
        switch stockFilter {
        case .all:
            break
        case .low:
            result = result.filter { $0.stockStatus == .low || $0.stockStatus == .critical }
        case .critical:
            result = result.filter { $0.stockStatus == .critical }
        }

        // Tags filter
        if !selectedTags.isEmpty {
            result = result.filter { item in
                guard let itemTags = item.tags else { return false }
                return !selectedTags.isDisjoint(with: Set(itemTags))
            }
        }

        // Sorting
        switch sortOption {
        case .nameAsc:
            result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameDesc:
            result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .quantityAsc:
            result.sort { $0.currentQuantity < $1.currentQuantity }
        case .quantityDesc:
            result.sort { $0.currentQuantity > $1.currentQuantity }
        }

        return result
    }

    var body: some View {
        listRoot
            .navigationTitle("Inventory")
            .searchable(text: $searchText, prompt: "Search items")
            .searchScopes($stockFilter, activation: .onSearchPresentation) {
                ForEach(StockFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if !items.isEmpty {
                    filterChipBar
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddItem = true
                    } label: {
                        Label("Add Item", systemImage: "plus")
                    }
                }

                ToolbarItem(placement: .secondaryAction) {
                    filterMenu
                }
            }
            .sheet(isPresented: $showingAddItem) {
                AddItemView()
            }
            .sheet(isPresented: $showingTagManagement) {
                TagManagementView()
            }
            .sheet(item: $adjustingItem) { item in
                AdjustStockSheet(item: item, isAdding: true)
            }
            .sensoryFeedback(.selection, trigger: stockFilter)
            .sensoryFeedback(.selection, trigger: selectedTags)
            .onChange(of: allTags) { _, tags in
                // A deleted tag must not linger as an invisible active filter.
                let valid = Set(tags)
                if !selectedTags.isSubset(of: valid) {
                    selectedTags = selectedTags.intersection(valid)
                }
            }
            .overlay {
                if filteredAndSortedItems.isEmpty {
                    emptyState
                }
            }
    }

    @ViewBuilder
    private var listRoot: some View {
        if usesSelection {
            List(selection: $selectedItem) {
                rowsContent
            }
        } else {
            List {
                rowsContent
            }
        }
    }

    private var rowsContent: some View {
        ForEach(filteredAndSortedItems) { item in
            NavigationLink(value: item) {
                InventoryItemRow(item: item)
            }
            .tag(item)
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        quickAdjust(item, by: 1)
                    } label: {
                        Label("Add 1", systemImage: "plus")
                    }
                    .tint(.green)
                }
                // No full swipe here: a committed swipe on the everyday
                // "Remove 1" edge must never wipe an item and its ledger.
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        delete(item)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }

                    if item.currentQuantity > 0 {
                        Button {
                            quickAdjust(item, by: -1)
                        } label: {
                            Label("Remove 1", systemImage: "minus")
                        }
                        .tint(.orange)
                    }
                }
                .contextMenu {
                    ControlGroup {
                        Button("+1") { quickAdjust(item, by: 1) }
                        Button("+5") { quickAdjust(item, by: 5) }
                        Button("+10") { quickAdjust(item, by: 10) }
                    }

                    if item.currentQuantity > 0 {
                        ControlGroup {
                            Button("−1") { quickAdjust(item, by: -1) }
                            Button("−5") { quickAdjust(item, by: -5) }
                        }
                    }

                    Button {
                        adjustingItem = item
                    } label: {
                        Label("Adjust…", systemImage: "plus.forwardslash.minus")
                    }

                    Divider()

                    Button(role: .destructive) {
                        delete(item)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } preview: {
                    ItemContextPreview(item: item)
                }
            }
        }
    // MARK: - Filter chip bar

    private var filterChipBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                statusChip(.all, label: "All", count: nil, color: .accentColor)
                statusChip(.low, label: "Low", count: lowCount, color: .orange)
                statusChip(.critical, label: "Critical", count: criticalCount, color: .red)

                if !allTags.isEmpty {
                    Divider()
                        .frame(height: 20)

                    ForEach(allTags) { tag in
                        Button {
                            withAnimation(.snappy) {
                                if selectedTags.contains(tag) {
                                    selectedTags.remove(tag)
                                } else {
                                    selectedTags.insert(tag)
                                }
                            }
                        } label: {
                            TagChip(tag: tag, isSelected: selectedTags.contains(tag))
                        }
                        .buttonStyle(.plain)
                        .expandedTapTarget()
                        .accessibilityAddTraits(selectedTags.contains(tag) ? .isSelected : [])
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
        // Near-opaque backdrop so scrolled rows don't bleed through the
        // translucent chips. Must NOT extend into the safe area — the default
        // safe-area expansion paints over the navigation large title.
        .background(chipBarBackground, ignoresSafeAreaEdges: [])
    }

    private var chipBarBackground: some ShapeStyle {
        #if os(iOS)
        return Color(uiColor: .systemGroupedBackground).opacity(0.92)
        #elseif os(macOS)
        return Color(nsColor: .windowBackgroundColor).opacity(0.92)
        #else
        return Color.clear
        #endif
    }

    private func statusChip(_ filter: StockFilter, label: String, count: Int?, color: Color) -> some View {
        let isSelected = stockFilter == filter
        // Orange fails contrast with white text; use black on the Low chip.
        let selectedText: Color = color == .orange ? .black : .white
        return Button {
            withAnimation(.snappy) {
                stockFilter = isSelected ? .all : filter
            }
        } label: {
            HStack(spacing: 5) {
                Text(label)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(count)))
                        .foregroundStyle(isSelected ? AnyShapeStyle(selectedText) : AnyShapeStyle(color))
                }
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? AnyShapeStyle(selectedText) : AnyShapeStyle(.primary))
            .background(
                isSelected ? AnyShapeStyle(color == .accentColor ? Color.accentColor : color) : AnyShapeStyle(.quaternary),
                in: .capsule
            )
        }
        .buttonStyle(.plain)
        .expandedTapTarget()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Filter menu

    private var filterMenu: some View {
        Menu {
            Picker("Status", selection: $stockFilter) {
                ForEach(StockFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }

            Picker("Sort By", selection: $sortOption) {
                ForEach(SortOption.allCases) { option in
                    Label(option.label, systemImage: option.icon).tag(option)
                }
            }

            if !allTags.isEmpty {
                Section("Tags") {
                    ForEach(allTags) { tag in
                        Toggle(isOn: tagToggleBinding(tag)) {
                            Text(tag.name)
                        }
                        .multiSelectMenuBehavior()
                    }
                }
            }

            Divider()

            Button {
                showingTagManagement = true
            } label: {
                Label("Edit Tags…", systemImage: "tag")
            }

            if hasActiveFilters {
                Button(role: .destructive) {
                    withAnimation(.snappy) {
                        stockFilter = .all
                        selectedTags.removeAll()
                    }
                } label: {
                    Label("Reset Filters", systemImage: "arrow.counterclockwise")
                }
            }
        } label: {
            Label(
                "Filter & Sort",
                systemImage: hasActiveFilters
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
            .contentTransition(.symbolEffect(.replace))
        }
    }

    private func tagToggleBinding(_ tag: Tag) -> Binding<Bool> {
        Binding(
            get: { selectedTags.contains(tag) },
            set: { isOn in
                withAnimation(.snappy) {
                    if isOn {
                        selectedTags.insert(tag)
                    } else {
                        selectedTags.remove(tag)
                    }
                }
            }
        )
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                items.isEmpty ? "No Items" : "No Matches",
                systemImage: items.isEmpty ? "cube.box" : "line.3.horizontal.decrease.circle"
            )
            .symbolRenderingMode(.hierarchical)
        } description: {
            if !searchText.isEmpty {
                Text("No items match your search.")
            } else if hasActiveFilters {
                Text("No items match your filters.")
            } else {
                Text("Add your first inventory item to get started.")
            }
        } actions: {
            if items.isEmpty {
                Button("Add Item") {
                    showingAddItem = true
                }
                .glassProminentButton()
                .controlSize(.large)
            } else if hasActiveFilters {
                Button("Reset Filters") {
                    withAnimation(.snappy) {
                        stockFilter = .all
                        selectedTags.removeAll()
                    }
                }
                .glassButton()
            }
        }
    }

    // MARK: - Actions

    private func quickAdjust(_ item: InventoryItem, by delta: Int) {
        withAnimation(.snappy) {
            if delta > 0 {
                item.addStock(amount: delta)
            } else {
                item.removeStock(amount: -delta)
            }
        }
    }

    private func delete(_ item: InventoryItem) {
        withAnimation {
            if selectedItem == item {
                selectedItem = nil
            }
            modelContext.delete(item)
        }
    }
}

/// Context-menu preview: photo, name, and stock at a glance.
private struct ItemContextPreview: View {
    let item: InventoryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let imageData = item.imageData, let image = Image(data: imageData) {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 280, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.name)
                        .font(.headline)
                    StatusBadge(status: item.stockStatus, prominent: false)
                }

                Spacer()

                StockRing(
                    quantity: item.currentQuantity,
                    yellowLimit: item.yellowLimit,
                    status: item.stockStatus,
                    diameter: 52
                )
            }
        }
        .padding()
        .frame(width: 312)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: InventoryItem.self, configurations: config)

    return NavigationStack {
        InventoryListView(
            selectedItem: .constant(nil),
            searchText: .constant(""),
            stockFilter: .constant(.all),
            selectedTags: .constant([]),
            sortOption: .constant(.nameAsc)
        )
    }
    .modelContainer(container)
}
