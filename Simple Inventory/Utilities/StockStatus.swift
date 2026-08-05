//
//  StockStatus.swift
//  Simple Inventory
//
//  Created by Kishyr Ramdial on 2025-12-22.
//

import SwiftUI

enum StockStatus: String, CaseIterable, Identifiable {
    case normal
    case low
    case critical

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .normal:
            return .green
        case .low:
            // Orange, not yellow: yellow fails contrast as a foreground
            // color on light backgrounds. "Yellow limit" naming stays internal.
            return .orange
        case .critical:
            return .red
        }
    }

    var icon: String {
        switch self {
        case .normal:
            return "checkmark.circle.fill"
        case .low:
            return "exclamationmark.triangle.fill"
        case .critical:
            return "xmark.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .normal:
            return "In Stock"
        case .low:
            return "Running Low"
        case .critical:
            return "Critical"
        }
    }

    /// Shorter label for compact UI (sidebar rows)
    var shortLabel: String {
        switch self {
        case .normal:
            return "OK"
        case .low:
            return "Low"
        case .critical:
            return "Critical"
        }
    }
}

enum StockFilter: String, CaseIterable, Identifiable {
    case all
    case low
    case critical

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:
            return "All Items"
        case .low:
            return "Running Low"
        case .critical:
            return "Critical"
        }
    }
}

enum SortOption: String, CaseIterable, Identifiable {
    case nameAsc
    case nameDesc
    case quantityAsc
    case quantityDesc

    var id: String { rawValue }

    var label: String {
        switch self {
        case .nameAsc:
            return "Name (A-Z)"
        case .nameDesc:
            return "Name (Z-A)"
        case .quantityAsc:
            return "Quantity (Low to High)"
        case .quantityDesc:
            return "Quantity (High to Low)"
        }
    }

    var icon: String {
        switch self {
        case .nameAsc, .quantityAsc:
            return "arrow.up"
        case .nameDesc, .quantityDesc:
            return "arrow.down"
        }
    }
}
