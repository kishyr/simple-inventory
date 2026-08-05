//
//  StatusBadge.swift
//  Simple Inventory
//

import SwiftUI

/// Stock status rendered as a tinted capsule so status color always sits on
/// its own field rather than as raw colored text.
struct StatusBadge: View {
    let status: StockStatus
    var prominent: Bool = true

    var body: some View {
        Label(status.label, systemImage: status.icon)
            .font((prominent ? Font.subheadline : .caption).weight(.medium))
            .foregroundStyle(status.color)
            .padding(.horizontal, prominent ? 12 : 8)
            .padding(.vertical, prominent ? 6 : 3)
            .background(status.color.opacity(0.15), in: .capsule)
            .contentTransition(.symbolEffect(.replace))
    }
}
