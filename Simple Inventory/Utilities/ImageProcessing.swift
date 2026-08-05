//
//  ImageProcessing.swift
//  Simple Inventory
//

import SwiftUI
import ImageIO

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum ImageProcessing {
    /// Longest edge stored for item photos. The UI never renders them larger
    /// than ~280pt, so 1200px leaves generous headroom for Retina while
    /// keeping CloudKit payloads small.
    static let maxPixelSize = 1200

    /// Downscales and recompresses raw picker/camera data before it is
    /// written to SwiftData (and synced through CloudKit). Uses ImageIO
    /// thumbnailing so the full-size image is never decoded.
    static func downscaled(_ data: Data,
                           maxPixelSize: Int = ImageProcessing.maxPixelSize,
                           compressionQuality: CGFloat = 0.75) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        #if canImport(UIKit)
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: compressionQuality)
        #elseif canImport(AppKit)
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
        #else
        return data
        #endif
    }
}

extension Image {
    /// Cross-platform decode of stored photo data.
    init?(data: Data) {
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: data) else { return nil }
        self.init(uiImage: uiImage)
        #elseif canImport(AppKit)
        guard let nsImage = NSImage(data: data) else { return nil }
        self.init(nsImage: nsImage)
        #else
        return nil
        #endif
    }
}

extension View {
    /// Numeric keypad on iOS; no-op elsewhere.
    func numericKeyboard() -> some View {
        #if os(iOS)
        return self.keyboardType(.numberPad)
        #else
        return self
        #endif
    }

    /// Liquid Glass button style where available; visionOS has no glass styles.
    @ViewBuilder
    func glassButton() -> some View {
        #if os(visionOS)
        self.buttonStyle(.bordered)
        #else
        self.buttonStyle(.glass)
        #endif
    }

    /// Prominent Liquid Glass button style where available.
    @ViewBuilder
    func glassProminentButton() -> some View {
        #if os(visionOS)
        self.buttonStyle(.borderedProminent)
        #else
        self.buttonStyle(.glassProminent)
        #endif
    }

    /// Keeps a Menu open across toggle taps for multi-select; the behavior
    /// (and its API) doesn't exist on macOS, where menus always dismiss.
    @ViewBuilder
    func multiSelectMenuBehavior() -> some View {
        #if os(macOS)
        self
        #else
        self.menuActionDismissBehavior(.disabled)
        #endif
    }

    /// Expands a small control's hit area toward the 44pt minimum without
    /// changing its visual size.
    func expandedTapTarget() -> some View {
        contentShape(.interaction, Rectangle().inset(by: -8))
    }
}
