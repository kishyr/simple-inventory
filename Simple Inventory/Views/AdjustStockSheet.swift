//
//  AdjustStockSheet.swift
//  Simple Inventory
//

import SwiftUI
import SwiftData

/// Single sheet for larger or backdated stock adjustments. Add/Remove is a
/// segmented control (no more dismiss-and-reopen to switch direction), the
/// amount is keypad-first with quick presets, and the date collapses behind
/// a "Today" row since backdating is the rare case.
struct AdjustStockSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var item: InventoryItem

    @State var isAdding: Bool

    @State private var amount: Int?
    @State private var date = Date()
    @State private var showingDatePicker = false
    @FocusState private var amountFocused: Bool

    private let presets = [1, 5, 10, 25]

    private var effectiveAmount: Int {
        max(0, amount ?? 0)
    }

    private var newTotal: Int {
        isAdding
            ? item.currentQuantity + effectiveAmount
            : max(0, item.currentQuantity - effectiveAmount)
    }

    private var isValid: Bool {
        effectiveAmount > 0 && (isAdding || effectiveAmount <= item.currentQuantity)
    }

    private var newTotalStatus: StockStatus {
        if newTotal <= item.redLimit { return .critical }
        if newTotal <= item.yellowLimit { return .low }
        return .normal
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Direction", selection: $isAdding) {
                        Text("Add").tag(true)
                        Text("Remove").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    TextField("Amount", value: $amount, format: .number)
                        .numericKeyboard()
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .focused($amountFocused)

                    HStack(spacing: 8) {
                        ForEach(presets, id: \.self) { preset in
                            Button("+\(preset)") {
                                withAnimation(.snappy) {
                                    amount = (amount ?? 0) + preset
                                }
                            }
                            .font(.subheadline.weight(.semibold))
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .tint(isAdding ? .green : .red)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                } footer: {
                    if !isAdding {
                        Text("Current stock: \(item.currentQuantity)")
                    }
                }

                Section {
                    Button {
                        withAnimation(.snappy) {
                            showingDatePicker.toggle()
                        }
                    } label: {
                        LabeledContent(isAdding ? "Date Added" : "Date Removed") {
                            Text(dateLabel)
                                .foregroundStyle(.tint)
                        }
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)

                    if showingDatePicker {
                        DatePicker(
                            "Date",
                            selection: $date,
                            in: ...Date(),
                            displayedComponents: [.date]
                        )
                        .datePickerStyle(.graphical)
                    }

                    LabeledContent("New Total") {
                        Text("\(newTotal)")
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(newTotal)))
                            .foregroundStyle(newTotalStatus.color)
                            .animation(.snappy, value: newTotal)
                    }
                }
            }
            .navigationTitle(isAdding ? "Add Stock" : "Remove Stock")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(macOS)
            .formStyle(.grouped)
            .padding(.horizontal)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isAdding ? "Add" : "Remove") {
                        save()
                    }
                    .disabled(!isValid)
                }

                #if os(iOS)
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        amountFocused = false
                    }
                }
                #endif
            }
            .onAppear {
                amountFocused = true
            }
        }
        .sensoryFeedback(.selection, trigger: isAdding)
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
        #if os(macOS)
        .frame(minWidth: 400, idealWidth: 450, minHeight: 420)
        #endif
    }

    private var dateLabel: String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func save() {
        withAnimation(.snappy) {
            if isAdding {
                item.addStock(amount: effectiveAmount, date: date)
            } else {
                item.removeStock(amount: effectiveAmount, date: date)
            }
        }
        dismiss()
    }
}

#Preview("Add Stock") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: InventoryItem.self, configurations: config)

    let item = InventoryItem(name: "Sample Item")
    item.addStock(amount: 10)
    container.mainContext.insert(item)

    return AdjustStockSheet(item: item, isAdding: true)
        .modelContainer(container)
}
