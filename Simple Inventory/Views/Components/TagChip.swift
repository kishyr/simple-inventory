//
//  TagChip.swift
//  Simple Inventory
//

import SwiftUI

/// The single tag capsule used everywhere tags render: list rows, detail,
/// forms, filter bar, and tag management. Text color is derived by mixing
/// the tag color toward primary so low-contrast hues (yellow, mint, cyan)
/// stay legible in both color schemes.
struct TagChip: View {
    enum ChipSize {
        case small
        case regular

        var font: Font { self == .small ? .caption : .subheadline }
        var horizontalPadding: CGFloat { self == .small ? 8 : 12 }
        var verticalPadding: CGFloat { self == .small ? 3 : 6 }
    }

    let tag: Tag
    var size: ChipSize = .regular
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if isSelected {
                Image(systemName: "checkmark")
                    .font(size.font.weight(.bold))
                    .imageScale(.small)
            }
            Text(tag.name)
        }
        .font(size.font.weight(isSelected ? .semibold : .medium))
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .foregroundStyle(
            isSelected
                ? AnyShapeStyle(tag.prefersDarkText ? Color.black : Color.white)
                : AnyShapeStyle(tag.color.mix(with: .primary, by: 0.4))
        )
        .background(
            isSelected ? AnyShapeStyle(tag.color.mix(with: .black, by: 0.1)) : AnyShapeStyle(tag.color.opacity(0.15)),
            in: .capsule
        )
        .overlay {
            if !isSelected {
                Capsule().strokeBorder(tag.color.opacity(0.35), lineWidth: 1)
            }
        }
    }
}
