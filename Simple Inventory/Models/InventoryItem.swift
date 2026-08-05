//
//  InventoryItem.swift
//  Simple Inventory
//
//  Created by Kishyr Ramdial on 2025-12-22.
//

import Foundation
import SwiftData

@Model
final class InventoryItem {
    var id: UUID
    var name: String

    @Attribute(.externalStorage)
    var imageData: Data?

    var yellowLimit: Int
    var redLimit: Int
    var createdAt: Date

    @Relationship(deleteRule: .nullify)
    var tags: [Tag]?

    @Relationship(deleteRule: .cascade, inverse: \QuantityRecord.item)
    var quantityRecords: [QuantityRecord]?

    init(
        name: String,
        imageData: Data? = nil,
        yellowLimit: Int = 5,
        redLimit: Int = 2,
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.name = name
        self.imageData = imageData
        self.yellowLimit = yellowLimit
        self.redLimit = redLimit
        self.createdAt = createdAt
        self.tags = []
        self.quantityRecords = []
    }

    var currentQuantity: Int {
        // Floored at zero: physical stock can't be negative even if ledger
        // edits (e.g. deleting an addition record) drive the raw sum below it.
        max(0, quantityRecords?.reduce(0) { $0 + $1.amount } ?? 0)
    }

    /// Rebalances the ledger after a record deletion so the raw sum can't
    /// stay negative (which would make subsequent additions look like no-ops
    /// while they silently repay a hidden deficit). Reduces the most recent
    /// removal records until the sum is non-negative.
    func reconcileLedger(excludingRecordID excluded: UUID? = nil) {
        let remaining = (quantityRecords ?? []).filter { $0.id != excluded }
        var sum = remaining.reduce(0) { $0 + $1.amount }
        guard sum < 0 else { return }

        for record in remaining.sorted(by: { $0.date > $1.date }) where record.amount < 0 {
            let adjustment = min(-record.amount, -sum)
            record.amount += adjustment
            sum += adjustment
            if record.amount == 0 {
                record.modelContext?.delete(record)
            }
            if sum >= 0 { break }
        }
    }

    var stockStatus: StockStatus {
        let qty = currentQuantity
        if qty <= redLimit {
            return .critical
        } else if qty <= yellowLimit {
            return .low
        } else {
            return .normal
        }
    }

    @discardableResult
    func addStock(amount: Int, date: Date = Date()) -> QuantityRecord? {
        guard amount != 0 else { return nil }
        let record = QuantityRecord(amount: abs(amount), date: date)
        record.item = self
        if quantityRecords == nil {
            quantityRecords = []
        }
        quantityRecords?.append(record)
        return record
    }

    /// Removes stock, capped at the current quantity so the ledger can never
    /// be driven negative from this path. Returns the record if one was made.
    @discardableResult
    func removeStock(amount: Int, date: Date = Date()) -> QuantityRecord? {
        let capped = min(abs(amount), currentQuantity)
        guard capped > 0 else { return nil }
        let record = QuantityRecord(amount: -capped, date: date)
        record.item = self
        if quantityRecords == nil {
            quantityRecords = []
        }
        quantityRecords?.append(record)
        return record
    }
}
