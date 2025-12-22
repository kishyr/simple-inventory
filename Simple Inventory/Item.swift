//
//  Item.swift
//  Simple Inventory
//
//  Created by Kishyr Ramdial on 2025-12-22.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
