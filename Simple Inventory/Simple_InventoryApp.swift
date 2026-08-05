//
//  Simple_InventoryApp.swift
//  Simple Inventory
//
//  Created by Kishyr Ramdial on 2025-12-22.
//

import SwiftUI
import SwiftData

@main
struct Simple_InventoryApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            InventoryItem.self,
            QuantityRecord.self,
            Tag.self,
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
