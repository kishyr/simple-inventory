//
//  Tag.swift
//  Simple Inventory
//
//  Created by Kishyr Ramdial on 2025-12-22.
//

import Foundation
import SwiftData
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@Model
final class Tag {
    var id: UUID
    var name: String
    var colorHex: String

    @Relationship(inverse: \InventoryItem.tags)
    var items: [InventoryItem]?

    init(name: String, colorHex: String = "007AFF") {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.items = []
    }

    var color: Color {
        Color(hex: colorHex) ?? .blue
    }

    /// Whether text over this tag's color should be dark (light hues like
    /// yellow/mint/cyan fail contrast with white text).
    var prefersDarkText: Bool {
        let sanitized = colorHex.replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        guard Scanner(string: sanitized).scanHexInt64(&rgb) else { return false }
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        // Perceived luminance (Rec. 601).
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance > 0.6
    }

    /// Preset palette used by the tag editor swatches and for auto-assigning
    /// a color to inline-created tags (system colors as hex).
    static let presetHexes: [String] = [
        "007AFF", // blue
        "34C759", // green
        "FF3B30", // red
        "FF9500", // orange
        "FFCC00", // yellow
        "AF52DE", // purple
        "FF2D55", // pink
        "32ADE6", // cyan
        "00C7BE", // mint
        "5856D6", // indigo
    ]
}

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }

    func toHex() -> String {
        #if canImport(UIKit)
        guard let components = UIColor(self).cgColor.components, components.count >= 3 else {
            return "007AFF"
        }
        #elseif canImport(AppKit)
        guard let color = NSColor(self).usingColorSpace(.deviceRGB),
              let components = color.cgColor.components, components.count >= 3 else {
            return "007AFF"
        }
        #else
        return "007AFF"
        #endif
        // Round, don't truncate — truncation makes preset colors drift on
        // every round-trip and breaks swatch-selection/dedupe comparisons.
        let r = Int((components[0] * 255).rounded())
        let g = Int((components[1] * 255).rounded())
        let b = Int((components[2] * 255).rounded())
        return String(format: "%02X%02X%02X", r, g, b)
    }
}
