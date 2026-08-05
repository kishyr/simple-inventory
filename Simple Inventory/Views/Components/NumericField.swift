//
//  NumericField.swift
//  Simple Inventory
//

import SwiftUI

/// Form row combining direct numeric text entry with a stepper for nudging —
/// replaces stepper-only rows where magnitudes can be large.
struct NumericField: View {
    let label: String
    @Binding var value: Int
    var range: ClosedRange<Int> = 0...10000

    var body: some View {
        HStack(spacing: 12) {
            Text(label)

            Spacer()

            TextField("0", value: $value, format: .number)
                .numericKeyboard()
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 64)
                .onChange(of: value) { _, newValue in
                    if newValue < range.lowerBound {
                        value = range.lowerBound
                    } else if newValue > range.upperBound {
                        value = range.upperBound
                    }
                }

            Stepper(label, value: $value, in: range)
                .labelsHidden()
        }
    }
}
