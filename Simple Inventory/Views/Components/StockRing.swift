//
//  StockRing.swift
//  Simple Inventory
//

import SwiftUI

/// Circular capacity ring showing quantity in context of the item's limits.
/// The ring fills against a nominal capacity of twice the low-stock limit,
/// so "how close to empty" is visible without reading any numbers.
struct StockRing: View {
    let quantity: Int
    let yellowLimit: Int
    let status: StockStatus
    var diameter: CGFloat = 150

    private var lineWidth: CGFloat { max(4, diameter * 0.09) }

    private var fraction: Double {
        let capacity = Double(max(yellowLimit * 2, quantity, 1))
        return min(1, Double(quantity) / capacity)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    status.color.gradient,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text("\(quantity)")
                .font(.system(size: diameter * 0.32, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(status.color.gradient)
                .contentTransition(.numericText(value: Double(quantity)))
                .minimumScaleFactor(0.4)
                .padding(diameter * 0.18)
        }
        .frame(width: diameter, height: diameter)
        .animation(.snappy, value: fraction)
        .animation(.default, value: status)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(quantity) in stock, \(status.label)")
    }
}
