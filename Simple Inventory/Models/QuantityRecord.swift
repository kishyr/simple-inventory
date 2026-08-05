//
//  QuantityRecord.swift
//  Simple Inventory
//
//  Created by Kishyr Ramdial on 2025-12-22.
//

import Foundation
import SwiftData

@Model
final class QuantityRecord {
    var id: UUID
    var amount: Int
    var date: Date

    var item: InventoryItem?

    init(amount: Int, date: Date = Date()) {
        self.id = UUID()
        self.amount = amount
        self.date = date
    }

    var isAddition: Bool {
        amount > 0
    }

    var isRemoval: Bool {
        amount < 0
    }

    var absoluteAmount: Int {
        abs(amount)
    }
}
