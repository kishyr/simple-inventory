//
//  QuantityRecordRow.swift
//  Simple Inventory
//

import SwiftUI
import SwiftData

/// One ledger entry: signed delta plus the running balance after it, so the
/// history reads like a bank statement instead of a list of raw deltas.
struct HistoryRecordRow: View {
    let record: QuantityRecord
    let balance: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.isAddition ? "plus.circle.fill" : "minus.circle.fill")
                .foregroundStyle(record.isAddition ? .green : .red)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)

            Text(record.isAddition ? "+\(record.absoluteAmount)" : "-\(record.absoluteAmount)")
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(record.isAddition ? .green : .red)

            Text(record.date.formatted(date: .abbreviated, time: .omitted))
                .font(.subheadline)
                .foregroundStyle(.tertiary)

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "arrow.right")
                    .font(.caption2)
                Text("\(balance)")
                    .monospacedDigit()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(record.isAddition ? "Added" : "Removed") \(record.absoluteAmount) on \(record.date.formatted(date: .long, time: .omitted)), balance \(balance)"
        )
    }
}

struct DateEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var date: Date

    @State private var selectedDate: Date

    init(date: Binding<Date>) {
        self._date = date
        self._selectedDate = State(initialValue: date.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(
                    "Date",
                    selection: $selectedDate,
                    in: ...Date(),
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
            }
            .navigationTitle("Edit Date")
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
                    Button("Save") {
                        date = selectedDate
                        dismiss()
                    }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium])
        #endif
        #if os(macOS)
        .frame(minWidth: 400, idealWidth: 450, minHeight: 450)
        #endif
    }
}

#Preview {
    let record = QuantityRecord(amount: 5, date: Date())

    return List {
        HistoryRecordRow(record: record, balance: 12)
    }
}
