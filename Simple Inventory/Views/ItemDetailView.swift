//
//  ItemDetailView.swift
//  Simple Inventory
//

import SwiftUI
import SwiftData
import Combine

struct ItemDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var item: InventoryItem

    /// Invoked when the user taps a tag chip — the owner applies it as a
    /// list filter. The detail view dismisses itself afterwards.
    var onTagTap: ((Tag) -> Void)? = nil
    /// Invoked after the item is deleted so the owner can clear selection.
    var onDeleted: (() -> Void)? = nil

    @Query(sort: \Tag.name) private var allTags: [Tag]

    @State private var showingAdjustSheet = false
    @State private var adjustSheetIsAdding = true
    @State private var showingEditItem = false
    @State private var showingDeleteConfirmation = false
    @State private var editingLimit: LimitKind?
    @State private var editingRecord: QuantityRecord?

    /// All one-tap ± adjustments made while this screen is presented coalesce
    /// into this single ledger record; the session ends when the screen is
    /// dismissed/popped (or the displayed item changes on iPad/Mac).
    @State private var sessionRecord: QuantityRecord?

    // Transient undo toast for the coalesced session record.
    @State private var pendingUndo: PendingUndo?
    private let undoTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private struct PendingUndo {
        var delta: Int
        var shownAt: Date
    }

    enum LimitKind: String, Identifiable {
        case low, critical
        var id: String { rawValue }
    }

    var body: some View {
        presentedContent
            .overlay(alignment: .bottom) {
                undoToast
            }
            .onReceive(undoTimer, perform: handleUndoTick)
            .onDisappear(perform: endAdjustmentSession)
            .onChange(of: item.id) { _, _ in
                endAdjustmentSession()
            }
            .sensoryFeedback(trigger: item.currentQuantity, quantityFeedback)
            .sensoryFeedback(.warning, trigger: item.stockStatus, condition: warningCondition)
    }

    private func handleUndoTick(_ now: Date) {
        if let pendingUndo, now.timeIntervalSince(pendingUndo.shownAt) > 6 {
            withAnimation(.snappy) {
                self.pendingUndo = nil
            }
        }
    }

    private func quantityFeedback(old: Int, new: Int) -> SensoryFeedback? {
        new > old ? .increase : .decrease
    }

    private func warningCondition(old: StockStatus, new: StockStatus) -> Bool {
        new == .critical || (new == .low && old == .normal)
    }

    private var presentedContent: some View {
        sheetHost
            .popover(item: $editingLimit) { (kind: LimitKind) in
                LimitEditor(item: item, kind: kind)
                    .presentationCompactAdaptation(.popover)
            }
            .alert("Delete Item", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteItem()
                }
            } message: {
                Text("Are you sure you want to delete \"\(item.name)\"? This action cannot be undone.")
            }
    }

    private var sheetHost: some View {
        navigationContent
            .sheet(isPresented: $showingAdjustSheet) {
                AdjustStockSheet(item: item, isAdding: adjustSheetIsAdding)
            }
            .sheet(isPresented: $showingEditItem) {
                EditItemView(item: item, allTags: allTags)
            }
            .sheet(item: $editingRecord) { (record: QuantityRecord) in
                DateEditSheet(date: dateBinding(for: record))
            }
    }

    private func dateBinding(for record: QuantityRecord) -> Binding<Date> {
        Binding<Date>(
            get: { record.date },
            set: { record.date = $0 }
        )
    }

    private var navigationContent: some View {
        listContent
            // The name lives in the custom header row (with the photo square);
            // an empty inline bar avoids showing it twice.
            #if os(iOS)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            #else
            .navigationTitle(item.name)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") {
                        showingEditItem = true
                    }
                }

                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete Item", systemImage: "trash")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
    }

    private var listContent: some View {
        List {
            headerSection
            tagsSection
            trendSection
            historySections
        }
    }

    @ViewBuilder
    private var tagsSection: some View {
        if let tags = item.tags, !tags.isEmpty {
            Section("Tags") {
                FlowLayout(spacing: 8) {
                    ForEach(tags) { tag in
                        Button {
                            if let onTagTap {
                                onTagTap(tag)
                                dismiss()
                            }
                        } label: {
                            TagChip(tag: tag)
                        }
                        .buttonStyle(.plain)
                        .expandedTapTarget()
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private var trendSection: some View {
        if (item.quantityRecords?.count ?? 0) >= 2 {
            Section("Trend") {
                StockHistoryChart(
                    records: item.quantityRecords ?? [],
                    yellowLimit: item.yellowLimit,
                    redLimit: item.redLimit
                )
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerSection: some View {
        // Title row on the plain background: name left, photo square right.
        Section {
            HStack(alignment: .center, spacing: 16) {
                Text(item.name)
                    .font(.largeTitle.weight(.bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                Spacer()

                if let imageData = item.imageData, let image = Image(data: imageData) {
                    Button {
                        showingEditItem = true
                    } label: {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Item photo. Edit item.")
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
        }

        Section {
            VStack(spacing: 20) {
                HStack(spacing: 28) {
                    Button {
                        quickAdjust(-1)
                    } label: {
                        Image(systemName: "minus")
                            .font(.title3.weight(.bold))
                            .frame(width: 22, height: 22)
                    }
                    .glassButton()
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .tint(.red)
                    .buttonRepeatBehavior(.enabled)
                    .disabled(item.currentQuantity == 0)
                    .accessibilityLabel("Remove one")

                    StockRing(
                        quantity: item.currentQuantity,
                        yellowLimit: item.yellowLimit,
                        status: item.stockStatus,
                        diameter: 150
                    )

                    Button {
                        quickAdjust(1)
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3.weight(.bold))
                            .frame(width: 22, height: 22)
                    }
                    .glassProminentButton()
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .tint(.green)
                    .buttonRepeatBehavior(.enabled)
                    .accessibilityLabel("Add one")
                }

                StatusBadge(status: item.stockStatus)

                // FlowLayout so the chips wrap instead of overflowing at
                // accessibility Dynamic Type sizes.
                FlowLayout(spacing: 8) {
                    limitChip(
                        kind: .low,
                        label: "Low ≤ \(item.yellowLimit)",
                        icon: "exclamationmark.triangle.fill",
                        color: .orange
                    )
                    limitChip(
                        kind: .critical,
                        label: "Critical ≤ \(item.redLimit)",
                        icon: "xmark.circle.fill",
                        color: .red
                    )

                    Button {
                        adjustSheetIsAdding = true
                        showingAdjustSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.forwardslash.minus")
                            Text("Adjust")
                        }
                        .font(.subheadline.weight(.medium))
                        .fixedSize()
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }
            }
            .frame(maxWidth: .infinity)
            .listRowInsets(EdgeInsets(top: 20, leading: 16, bottom: 20, trailing: 16))
        }
    }

    private func limitChip(kind: LimitKind, label: String, icon: String, color: Color) -> some View {
        Button {
            editingLimit = kind
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.subheadline.weight(.medium))
            .fixedSize()
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12), in: .capsule)
            .contentTransition(.numericText())
        }
        .buttonStyle(.plain)
        .expandedTapTarget()
    }

    // MARK: - History

    private struct HistoryEntry: Identifiable {
        let record: QuantityRecord
        let balance: Int
        var id: UUID { record.id }
    }

    private var historyGroups: [(title: String, entries: [HistoryEntry])] {
        let ascending = (item.quantityRecords ?? []).sorted { $0.date < $1.date }
        var running = 0
        var balances: [UUID: Int] = [:]
        for record in ascending {
            running += record.amount
            balances[record.id] = max(0, running)
        }

        var groups: [(title: String, entries: [HistoryEntry])] = []
        for record in ascending.reversed() {
            let title = groupTitle(for: record.date)
            let entry = HistoryEntry(record: record, balance: balances[record.id] ?? 0)
            if groups.last?.title == title {
                groups[groups.count - 1].entries.append(entry)
            } else {
                groups.append((title: title, entries: [entry]))
            }
        }
        return groups
    }

    @ViewBuilder
    private var historySections: some View {
        if historyGroups.isEmpty {
            Section("Stock History") {
                Text("No stock changes recorded")
                    .foregroundStyle(.secondary)
            }
        } else {
            ForEach(historyGroups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.entries) { entry in
                        HistoryRecordRow(record: entry.record, balance: entry.balance)
                            .swipeActions(edge: .leading) {
                                Button {
                                    editingRecord = entry.record
                                } label: {
                                    Label("Edit Date", systemImage: "calendar")
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    deleteRecord(entry.record)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button {
                                    editingRecord = entry.record
                                } label: {
                                    Label("Edit Date", systemImage: "calendar")
                                }
                                Button(role: .destructive) {
                                    deleteRecord(entry.record)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
    }

    private func groupTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) { return "This Week" }
        if calendar.isDate(date, equalTo: Date(), toGranularity: .month) { return "This Month" }
        return date.formatted(.dateTime.month(.wide).year())
    }

    // MARK: - Undo toast

    @ViewBuilder
    private var undoToast: some View {
        if let pendingUndo {
            HStack(spacing: 12) {
                Text(pendingUndo.delta > 0 ? "+\(pendingUndo.delta)" : "\(pendingUndo.delta)")
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(pendingUndo.delta)))
                    .foregroundStyle(pendingUndo.delta > 0 ? .green : .red)

                Button("Undo") {
                    undoQuickAdjustments()
                }
                .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: .capsule)
            // Sits clear of the home-indicator gesture zone.
            .padding(.bottom, 44)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Actions

    /// The session record, but only while it still exists in the item's
    /// ledger. `isDeleted` is unreliable here: it reverts to false once
    /// autosave commits a deletion, so membership is the real check.
    private var activeSessionRecord: QuantityRecord? {
        guard let sessionRecord,
              item.quantityRecords?.contains(where: { $0.id == sessionRecord.id }) == true
        else { return nil }
        return sessionRecord
    }

    private func quickAdjust(_ delta: Int) {
        guard delta != 0 else { return }
        // Never drive the ledger below zero from the one-tap path.
        if delta < 0 && item.currentQuantity + delta < 0 { return }

        withAnimation(.snappy) {
            if let record = activeSessionRecord {
                let newAmount = record.amount + delta
                if newAmount == 0 {
                    // Netted back to where the session started — no entry.
                    modelContext.delete(record)
                    sessionRecord = nil
                } else {
                    record.amount = newAmount
                    // The group carries the time of its latest change so it
                    // never lands in a stale day bucket.
                    record.date = Date()
                }
            } else {
                sessionRecord = delta > 0
                    ? item.addStock(amount: delta)
                    : item.removeStock(amount: -delta)
            }

            if let record = sessionRecord {
                pendingUndo = PendingUndo(delta: record.amount, shownAt: Date())
                let direction = record.amount > 0 ? "Added" : "Removed"
                AccessibilityNotification.Announcement(
                    "\(direction) \(abs(record.amount)) this session. Undo available."
                ).post()
            } else {
                pendingUndo = nil
            }
        }
    }

    private func undoQuickAdjustments() {
        withAnimation(.snappy) {
            if let record = activeSessionRecord {
                modelContext.delete(record)
            }
            sessionRecord = nil
            pendingUndo = nil
        }
    }

    /// Single path for deleting a history record: ends the tap session if it
    /// was the session record, and rebalances the ledger so the raw sum can't
    /// go negative.
    private func deleteRecord(_ record: QuantityRecord) {
        withAnimation(.snappy) {
            if record.id == sessionRecord?.id {
                endAdjustmentSession()
            }
            modelContext.delete(record)
            item.reconcileLedger(excludingRecordID: record.id)
        }
    }

    private func endAdjustmentSession() {
        sessionRecord = nil
        pendingUndo = nil
    }

    private func deleteItem() {
        modelContext.delete(item)
        onDeleted?()
        dismiss()
    }
}

/// Anchored editor for a single stock limit; writes straight to the model.
struct LimitEditor: View {
    @Bindable var item: InventoryItem
    let kind: ItemDetailView.LimitKind

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(kind == .low ? "Low Stock Warning" : "Critical Warning")
                .font(.headline)

            if kind == .low {
                NumericField(label: "Warn at ≤", value: Binding(
                    get: { item.yellowLimit },
                    set: { newValue in
                        item.yellowLimit = newValue
                        // Critical always stays at or below the low limit.
                        item.redLimit = min(item.redLimit, newValue)
                    }
                ), range: 0...10000)
            } else {
                NumericField(label: "Critical at ≤", value: $item.redLimit, range: 0...item.yellowLimit)

                Text("Always at or below the low stock limit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(minWidth: 260)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: InventoryItem.self, configurations: config)

    let item = InventoryItem(name: "Sample Item", yellowLimit: 5, redLimit: 2)
    item.addStock(amount: 10, date: Date().addingTimeInterval(-86400 * 10))
    item.removeStock(amount: 3, date: Date().addingTimeInterval(-86400))
    container.mainContext.insert(item)

    return NavigationStack {
        ItemDetailView(item: item)
    }
    .modelContainer(container)
}
