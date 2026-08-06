# Multi-User Shared Inventory — Implementation Spec

**Audience:** an AI coding agent (or engineer) implementing this feature in a fresh session. This document is self-contained — you do not need any other document or prior conversation. Architectural decisions here are FINAL; do not re-litigate them (the research behind them is summarized in `docs/multi-user-sharing-plan.md`, reference only).

**Goal:** Multiple iCloud users collaborate on one shared inventory. The owner invites others with the native iCloud share sheet (like Notes/Reminders). A joiner's app shows the shared inventory as their only inventory. The owner can remove participants; removal revokes access and deletes the data from the removed device automatically.

---

## 1. Context you must know before touching anything

**The app:** "Simple Inventory" — SwiftUI inventory tracker. Items have a photo, tags, warning limits (`yellowLimit`/`redLimit`), and a **ledger**: `InventoryItem.currentQuantity` is the clamped (≥0) sum of signed `QuantityRecord.amount` values. There is no stored quantity today — it is always computed from records.

**Current stack:** SwiftData (`@Model`, `@Query`, autosave) with `ModelConfiguration(cloudKitDatabase: .automatic)`. This spec migrates it to **Core Data + `NSPersistentCloudKitContainer`**, because SwiftData has no CloudKit sharing support (verified through iOS 27 beta 4; not re-checkable by you — take it as given).

**Greenfield:** the app has never shipped and has no users. No data migration. Delete/ignore old store files.

**Targets:** one app target ("Simple Inventory"), `SUPPORTED_PLATFORMS = iphoneos iphonesimulator macosx xros xrsimulator`. Every change must compile for **iOS, macOS, and visionOS**. Deployment targets: iOS 26.2, macOS 26.1, visionOS 26.2. Bundle id `to.catalystai.Simple-Inventory`, iCloud container `iCloud.to.catalystai.Simple-Inventory`, team `W5GBN6H723`.

**Project format:** filesystem-synchronized groups (`objectVersion 77`) — new/deleted files are picked up automatically; **no pbxproj edits are needed to add files** (only the build-setting edits in Phase 0).

**Source layout (all under `Simple Inventory/`):**

| File | Role | Migration impact |
|---|---|---|
| `Simple_InventoryApp.swift` | App entry; builds SwiftData `ModelContainer` | Rewrite (Phase 1) |
| `Models/InventoryItem.swift`, `Models/QuantityRecord.swift`, `Models/Tag.swift` | `@Model` classes + domain logic | Rewrite as `NSManagedObject` (Phase 1) |
| `ContentView.swift` | Nav shell, undo bridge (`modelContext.undoManager`) | Edit (Phases 1–2) |
| `Views/InventoryListView.swift` | `@Query` items+tags; filtering in-memory; quickAdjust/delete | Edit (Phases 1–2) |
| `Views/ItemDetailView.swift` | The hard one: `@Bindable`, session-record coalescing (`quickAdjust`), record delete + `reconcileLedger`, undo toast | Edit (Phase 1) |
| `Views/AddItemView.swift`, `Views/EditItemView.swift`, `Views/AdjustStockSheet.swift`, `Views/TagManagementView.swift` | Forms; insert/mutate models | Edit (Phases 1–2) |
| `Views/Components/TagPickerField.swift` | Inline tag creation (`modelContext.insert`) | Edit (Phases 1–2) |
| `Views/InventoryItemRow.swift`, `Views/QuantityRecordRow.swift` | Row views; read-only model access + `import SwiftData` | Import swap + `#Preview` rewrite |
| `Views/Components/` (TagChip, StockRing, StockHistoryChart, StatusBadge, NumericField, PhotoWell) | Pure UI | **Unchanged** (type names preserved) |
| `Utilities/ImageProcessing.swift`, `Utilities/FlowLayout.swift` | Image downscaling, cross-platform helpers (`glassButton()` etc.), flow layout | Unchanged |
| `Utilities/StockStatus.swift` | Enums | Unchanged |
| `Simple_Inventory.entitlements` | CloudKit container + push — **currently applied to no build** | Edit (Phase 0) |
| `Info.plist` | Camera usage + remote-notification background mode | Edit (Phase 0) |
| `Simple InventoryTests/Simple_InventoryTests.swift` | Empty template | Write tests (Phase 0) |

## 2. Locked decisions

1. **Core Data + `NSPersistentCloudKitContainer`**, two persistent stores (`.private` + `.shared` database scopes). No SwiftData, no CKSyncEngine, no third-party persistence.
2. **One root `Inventory` entity**; the whole graph hangs off it; sharing = `share([root])` once. All objects must stay reachable from the root (CloudKit forbids cross-zone relationships).
3. **Native share links** via `ShareLink` + `CKShareTransferRepresentation`. No share codes, no `UICloudSharingController` (unavailable on macOS + known stale-cache bugs).
4. **Custom Members screen** over `CKShare.participants` — identical SwiftUI on iOS/macOS/visionOS.
5. **Join replaces**: participant's app shows the shared inventory exclusively; their private data stays dormant locally and reappears if they leave / are removed.
6. **All platforms** get sharing UI. Primary manual testing on iPhone.
7. Sharing UX assumes **eventual consistency** (CloudKit sync latency is seconds-to-minutes). Never block the UI waiting for sync; never poll with timers.

## 3. Guardrails (violating any of these is a defect)

- **Never use `Task.sleep`** — anywhere, for anything (user's standing rule). Waiting for sync state = listen for `NSPersistentStoreRemoteChange` notifications or `NSManagedObjectContextObjectsDidChange`, not sleep/poll loops.
- **Every change compiles on all five platform slices** (`iphoneos iphonesimulator macosx xros xrsimulator`). Known traps and their mandatory helpers (in `Utilities/ImageProcessing.swift`): `.buttonStyle(.glass/.glassProminent)` doesn't exist on visionOS → use `glassButton()`/`glassProminentButton()`; `.menuActionDismissBehavior(.disabled)` doesn't exist on macOS → use `multiSelectMenuBehavior()`.
- **Never put a `Label` inside a styled Button** (iOS 26 rendering bug) — use `HStack { Image(systemName:); Text() }` as the existing code does.
- **Keep class names** `InventoryItem`, `QuantityRecord`, `Tag` and the public property/method surface listed in §5.2 — that is what keeps the 6 `Views/Components/` files and `Utilities/` compiling untouched (the two row views additionally need their `#Preview` blocks rewritten, §5.5).
- **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`** is set project-wide. Core Data background callbacks (`performBackgroundTask`, notification handlers, share completions) are NOT main-actor: mark background work `nonisolated`, hop to `MainActor` explicitly for UI state, and pass `NSManagedObjectID`s (never managed objects) between contexts.
- **No unique constraints** in the Core Data model (CloudKit forbids them). No `.deny` delete rules.
- **`viewContext` is the only context views touch.** History processing uses one background context; it must set its own `transactionAuthor` (§8.1) to avoid processing loops.
- Match the existing code style: comment only non-obvious constraints, keep the `#if os(...)` conditional patterns already in use.
- Commit at each phase boundary with a message like `feature: <phase summary>` (no ticket prefix — this repo doesn't use tickets).

## 4. Phase 0 — Project plumbing + safety net

### 4.1 Wire the entitlements (CloudKit has never worked without this)

In `Simple Inventory.xcodeproj/project.pbxproj`, the app target has two `XCBuildConfiguration` blocks (Debug ≈ line 287, Release ≈ line 332 — the two blocks that contain `PRODUCT_BUNDLE_IDENTIFIER = "to.catalystai.Simple-Inventory";`, NOT the `...Tests` ones). In **both**, add inside `buildSettings`, alphabetically before `CODE_SIGN_STYLE`:

```
CODE_SIGN_ENTITLEMENTS = "Simple Inventory/Simple_Inventory.entitlements";
```

### 4.2 Entitlements file

Replace `Simple Inventory/Simple_Inventory.entitlements` content with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>aps-environment</key>
	<string>development</string>
	<key>com.apple.developer.aps-environment</key>
	<string>development</string>
	<key>com.apple.developer.icloud-container-identifiers</key>
	<array>
		<string>iCloud.to.catalystai.Simple-Inventory</string>
	</array>
	<key>com.apple.developer.icloud-services</key>
	<array>
		<string>CloudKit</string>
	</array>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
</dict>
</plist>
```

(`network.client` is required for CloudKit inside the sandboxed macOS build; the sandbox key makes the file valid standalone for macOS.)

### 4.3 Info.plist

Add to `Simple Inventory/Info.plist`:

```xml
<key>CKSharingSupported</key>
<true/>
```

### 4.4 Ledger unit tests (the safety net for the migration)

Replace `Simple InventoryTests/Simple_InventoryTests.swift` with Swift Testing (`import Testing`) tests against the **current SwiftData models** (in-memory `ModelContainer`). After Phase 1 these same behavioral tests must be ported to Core Data using `PersistenceController(inMemory: true)` — the single test harness for Phases 1–4 — and stay green. Porting note: quantity is cached after Phase 1, so any test that deletes a record must then call `item.reconcileLedger(excludingRecordID: record.id)` (mirroring what every view deletion path does) before asserting. Required cases:

| Test | Setup | Expectation |
|---|---|---|
| `currentQuantityClampsAtZero` | records +5, −3, then delete the +5 record | `currentQuantity == 0` (not −3) |
| `addStockCreatesPositiveRecord` | `addStock(amount: 5)` | record amount +5, `currentQuantity == 5` |
| `addStockZeroIsNoop` | `addStock(amount: 0)` | returns nil, no record |
| `removeStockCapsAtCurrent` | qty 3, `removeStock(amount: 10)` | record amount −3, `currentQuantity == 0` |
| `removeStockAtZeroIsNoop` | qty 0, `removeStock(amount: 1)` | returns nil, no record |
| `reconcileLedgerRepairsNegativeSum` | +10, −8; delete the +10; `reconcileLedger(excludingRecordID:)` | removal reduced/deleted so raw sum ≥ 0 |
| `reconcileLedgerReducesMostRecentRemovalFirst` | +10, −4 (old), −5 (new); delete +10, reconcile | newer −5 zeroed & deleted first, then −4 |
| `stockStatusThresholds` | limits 5/2; qty 6→normal, 5→low, 3→low, 2→critical, 0→critical | boundary values land as listed |
| (Phase 1 addition) `cachedQuantityTracksLedger` | every mutation path and every deletion+reconcile | `cachedQuantityRaw` equals `max(0, Σ amount)` computed independently in the test over live (non-deleted) records — do NOT compare against `currentQuantity`, which reads the same storage |

**Definition of done (Phase 0):** app builds for iOS simulator, macOS, visionOS simulator; tests pass (`xcodebuild test -scheme "Simple Inventory" -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`); running on iOS simulator shows CloudKit activity in the console (no "not entitled" errors).

## 5. Phase 1 — Core Data migration

### 5.1 The model file

Create directory `Simple Inventory/SimpleInventory.xcdatamodeld/SimpleInventory.xcdatamodel/` containing a file named `contents` with exactly:

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0" lastSavedToolsVersion="1" systemVersion="11A491" minimumToolsVersion="Automatic" sourceLanguage="Swift" usedWithSwiftData="NO" userDefinedModelVersionIdentifier="">
    <entity name="Inventory" representedClassName="Inventory" syncable="YES">
        <attribute name="createdAtRaw" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
        <attribute name="uuid" optional="YES" attributeType="UUID" usesScalarValueType="NO"/>
        <relationship name="itemsRel" optional="YES" toMany="YES" deletionRule="Cascade" destinationEntity="InventoryItem" inverseName="inventory" inverseEntity="InventoryItem"/>
        <relationship name="tagsRel" optional="YES" toMany="YES" deletionRule="Cascade" destinationEntity="Tag" inverseName="inventory" inverseEntity="Tag"/>
    </entity>
    <entity name="InventoryItem" representedClassName="InventoryItem" syncable="YES">
        <attribute name="cachedQuantityRaw" optional="NO" attributeType="Integer 64" defaultValueString="0" usesScalarValueType="YES"/>
        <attribute name="createdAtRaw" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
        <attribute name="imageData" optional="YES" attributeType="Binary" allowsExternalBinaryDataStorage="YES"/>
        <attribute name="nameRaw" optional="NO" attributeType="String" defaultValueString=""/>
        <attribute name="redLimitRaw" optional="NO" attributeType="Integer 64" defaultValueString="2" usesScalarValueType="YES"/>
        <attribute name="uuid" optional="YES" attributeType="UUID" usesScalarValueType="NO"/>
        <attribute name="yellowLimitRaw" optional="NO" attributeType="Integer 64" defaultValueString="5" usesScalarValueType="YES"/>
        <relationship name="inventory" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Inventory" inverseName="itemsRel" inverseEntity="Inventory"/>
        <relationship name="quantityRecordsRel" optional="YES" toMany="YES" deletionRule="Cascade" destinationEntity="QuantityRecord" inverseName="item" inverseEntity="QuantityRecord"/>
        <relationship name="tagsRel" optional="YES" toMany="YES" deletionRule="Nullify" destinationEntity="Tag" inverseName="itemsRel" inverseEntity="Tag"/>
    </entity>
    <entity name="QuantityRecord" representedClassName="QuantityRecord" syncable="YES">
        <attribute name="amountRaw" optional="NO" attributeType="Integer 64" defaultValueString="0" usesScalarValueType="YES"/>
        <attribute name="dateRaw" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
        <attribute name="uuid" optional="YES" attributeType="UUID" usesScalarValueType="NO"/>
        <relationship name="item" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="InventoryItem" inverseName="quantityRecordsRel" inverseEntity="InventoryItem"/>
    </entity>
    <entity name="Tag" representedClassName="Tag" syncable="YES">
        <attribute name="colorHexRaw" optional="NO" attributeType="String" defaultValueString="007AFF"/>
        <attribute name="nameRaw" optional="NO" attributeType="String" defaultValueString=""/>
        <attribute name="uuid" optional="YES" attributeType="UUID" usesScalarValueType="NO"/>
        <relationship name="inventory" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Inventory" inverseName="tagsRel" inverseEntity="Inventory"/>
        <relationship name="itemsRel" optional="YES" toMany="YES" deletionRule="Nullify" destinationEntity="InventoryItem" inverseName="tagsRel" inverseEntity="InventoryItem"/>
    </entity>
</model>
```

Rules encoded there (do not deviate): every attribute is optional **or** has a model-level default (CloudKit requirement); `UUID`/`Date` cannot have defaults so they are optional and set in `awakeFromInsert`; relationships are all optional with inverses; no unique constraints; no `.deny` rules; **codegen is Manual/None** (no `codeGenerationType` attribute) because we write the classes ourselves. If Xcode's model editor normalizes this XML on open, that's fine — semantics above must survive.

Also create `Simple Inventory/SimpleInventory.xcdatamodeld/.xccurrentversion`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>_XCCurrentVersionName</key>
	<string>SimpleInventory.xcdatamodel</string>
</dict>
</plist>
```

Verify the model compiles into the app (the synchronized group should pick it up; check the built `.app` contains `SimpleInventory.momd`).

### 5.2 Model classes — the compatibility-bridge pattern

The `Raw`-suffixed storage names + computed bridges keep the **entire view layer's property surface identical** to today. Views keep using `item.name`, `item.tags`, `record.date`, `record.id`, etc. Replace the three model files (and add `Inventory.swift`) as follows. `InventoryItem.swift` in full — the other classes follow the same pattern:

```swift
import Foundation
import CoreData

@objc(InventoryItem)
final class InventoryItem: NSManagedObject, Identifiable {
    @NSManaged var uuid: UUID?
    @NSManaged var nameRaw: String
    @NSManaged var imageData: Data?
    @NSManaged var yellowLimitRaw: Int64
    @NSManaged var redLimitRaw: Int64
    @NSManaged var cachedQuantityRaw: Int64
    @NSManaged var createdAtRaw: Date?
    @NSManaged var inventory: Inventory?
    @NSManaged var tagsRel: NSSet?
    @NSManaged var quantityRecordsRel: NSSet?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        uuid = UUID()
        createdAtRaw = Date()
    }

    // MARK: - Bridges (public surface must stay identical to the old @Model)

    var id: UUID { uuid ?? UUID() }          // uuid is nil only on deleted/faulted objects
    var name: String {
        get { nameRaw }
        set { nameRaw = newValue }
    }
    var yellowLimit: Int {
        get { Int(yellowLimitRaw) }
        set { yellowLimitRaw = Int64(newValue) }
    }
    var redLimit: Int {
        get { Int(redLimitRaw) }
        set { redLimitRaw = Int64(newValue) }
    }
    var createdAt: Date { createdAtRaw ?? .distantPast }

    /// Sorted for deterministic chip order (SwiftData's array order was arbitrary).
    var tags: [Tag]? {
        get { (tagsRel as? Set<Tag>)?.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
        set { tagsRel = newValue.map { NSSet(array: $0) } }
    }
    var quantityRecords: [QuantityRecord]? {
        get { (quantityRecordsRel as? Set<QuantityRecord>)?.sorted { $0.date < $1.date } }
        set { quantityRecordsRel = newValue.map { NSSet(array: $0) } }
    }

    // MARK: - Ledger

    var currentQuantity: Int { Int(cachedQuantityRaw) }

    /// Recomputes the clamped ledger sum into cachedQuantityRaw. Called by every
    /// local mutation helper and by the remote-change reconciler (§8.2).
    /// Must skip pending-deleted records: Core Data leaves a deleted object in
    /// the to-many relationship until processPendingChanges/save runs.
    func refreshCachedQuantity() {
        let sum = ((quantityRecordsRel as? Set<QuantityRecord>) ?? [])
            .filter { !$0.isDeleted }
            .reduce(0) { $0 + Int($1.amountRaw) }
        cachedQuantityRaw = Int64(max(0, sum))
    }

    var stockStatus: StockStatus {
        let qty = currentQuantity
        if qty <= redLimit { return .critical }
        if qty <= yellowLimit { return .low }
        return .normal
    }

    @discardableResult
    func addStock(amount: Int, date: Date = Date()) -> QuantityRecord? {
        guard amount != 0, let context = managedObjectContext else { return nil }
        let record = QuantityRecord(context: context)
        record.amountRaw = Int64(abs(amount))
        record.dateRaw = date
        record.item = self
        refreshCachedQuantity()
        return record
    }

    @discardableResult
    func removeStock(amount: Int, date: Date = Date()) -> QuantityRecord? {
        let capped = min(abs(amount), currentQuantity)
        guard capped > 0, let context = managedObjectContext else { return nil }
        let record = QuantityRecord(context: context)
        record.amountRaw = Int64(-capped)
        record.dateRaw = date
        record.item = self
        refreshCachedQuantity()
        return record
    }

    /// Port of the SwiftData version: after deleting a record, reduce the most
    /// recent removals until the raw sum is non-negative. Must also refresh
    /// cachedQuantityRaw before returning.
    func reconcileLedger(excludingRecordID excluded: UUID? = nil) {
        let remaining = ((quantityRecordsRel as? Set<QuantityRecord>) ?? []).filter { $0.uuid != excluded && !$0.isDeleted }
        var sum = remaining.reduce(0) { $0 + Int($1.amountRaw) }
        defer { refreshCachedQuantity() }
        guard sum < 0 else { return }
        for record in remaining.sorted(by: { $0.date > $1.date }) where record.amountRaw < 0 {
            let adjustment = min(Int(-record.amountRaw), -sum)
            record.amountRaw += Int64(adjustment)
            sum += adjustment
            if record.amountRaw == 0 { managedObjectContext?.delete(record) }
            if sum >= 0 { break }
        }
    }

    /// Convenience initializer mirroring the old @Model init. The caller must
    /// still attach the item to the current Inventory root (Phase 2).
    convenience init(context: NSManagedObjectContext, name: String, imageData: Data? = nil,
                     yellowLimit: Int = 5, redLimit: Int = 2, createdAt: Date = Date()) {
        self.init(context: context)
        self.nameRaw = name
        self.imageData = imageData
        self.yellowLimitRaw = Int64(yellowLimit)
        self.redLimitRaw = Int64(redLimit)
        self.createdAtRaw = createdAt
    }
}
```

`QuantityRecord`: `@NSManaged uuid/amountRaw/dateRaw/item`; `awakeFromInsert` sets `uuid`+`dateRaw`; bridges `id: UUID`, `amount: Int { get set }` (setter also calls `item?.refreshCachedQuantity()` — this is what keeps the session-record in-place edits in `ItemDetailView.quickAdjust` consistent), `date: Date { get { dateRaw ?? .distantPast } set { dateRaw = newValue } }`, plus the existing `isAddition`/`isRemoval`/`absoluteAmount`.

`Tag`: `@NSManaged uuid/nameRaw/colorHexRaw/inventory/itemsRel`; bridges `id`, `name`, `colorHex`, `items: [InventoryItem]?` (sorted by name); a `convenience init(context:name:colorHex:)` mirroring the old init; keep `color`, `prefersDarkText`, `presetHexes`, and the `Color` hex extensions exactly as they are (move them over verbatim).

`Inventory` (new, `Inventory.swift`): `@NSManaged uuid/createdAtRaw/itemsRel/tagsRel`; `awakeFromInsert` sets both.

**Every** view-level `QuantityRecord` deletion must be followed by `item.reconcileLedger(excludingRecordID: record.id)` before saving — that is three sites in `ItemDetailView`: `deleteRecord` (already the pattern today), the net-to-zero branch of `quickAdjust` (session record deleted when taps cancel out), and `undoQuickAdjustments`. Reconcile refreshes the cache; missing one of these leaves a stale `cachedQuantityRaw` that then syncs to every device. Item deletion needs no cache work.

### 5.3 Persistence stack

New file `Simple Inventory/PersistenceController.swift` (complete):

```swift
import CoreData
import CloudKit

final class PersistenceController {
    static let shared = PersistenceController()
    static let cloudKitContainerID = "iCloud.to.catalystai.Simple-Inventory"
    /// Author string for UI-context saves; the history reconciler skips these
    /// only when deciding what *it* wrote (§8.1).
    static let appTransactionAuthor = "app"
    static let reconcilerTransactionAuthor = "reconciler"

    let container: NSPersistentCloudKitContainer
    private(set) var privateStore: NSPersistentStore!
    private(set) var sharedStore: NSPersistentStore!

    var viewContext: NSManagedObjectContext { container.viewContext }

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "SimpleInventory")

        let baseURL = inMemory
            ? URL(fileURLWithPath: "/dev/null")
            : NSPersistentContainer.defaultDirectoryURL()

        let privateDesc = NSPersistentStoreDescription(
            url: inMemory ? baseURL : baseURL.appendingPathComponent("private.sqlite"))
        privateDesc.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        privateDesc.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        if !inMemory {
            let opts = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.cloudKitContainerID)
            opts.databaseScope = .private
            privateDesc.cloudKitContainerOptions = opts
        }

        var descriptions: [NSPersistentStoreDescription] = [privateDesc]
        if !inMemory {
            // No shared store in-memory: sharedStore stays nil for the test/
            // preview controller, and test code must not touch it.
            let sharedDesc = NSPersistentStoreDescription(url: baseURL.appendingPathComponent("shared.sqlite"))
            sharedDesc.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            sharedDesc.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            let opts = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.cloudKitContainerID)
            opts.databaseScope = .shared
            sharedDesc.cloudKitContainerOptions = opts
            descriptions.append(sharedDesc)
        }
        container.persistentStoreDescriptions = descriptions

        container.loadPersistentStores { [weak container] description, error in
            if let error { fatalError("Store load failed: \(error)") }
            guard let container else { return }
            let store = container.persistentStoreCoordinator.persistentStore(for: description.url!)
            switch description.cloudKitContainerOptions?.databaseScope {
            case .shared: self.sharedStore = store
            default: self.privateStore = store   // includes the inMemory case
            }
        }

        viewContext.automaticallyMergesChangesFromParent = true
        viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        viewContext.transactionAuthor = Self.appTransactionAuthor
        viewContext.name = "viewContext"

        #if DEBUG
        if !inMemory {
            // Pushes the model to the CloudKit Development schema. Harmless when
            // unchanged; must run after model edits. Never ships in Release.
            try? container.initializeCloudKitSchema(options: [])
        }
        #endif
    }

    /// One save path so every mutation site behaves identically (SwiftData's
    /// autosave is gone). Rollback on failure keeps the context consistent.
    func save() {
        let context = viewContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            context.rollback()
            assertionFailure("Save failed: \(error)")
        }
    }

    static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        // Seed sample data for #Previews here (one Inventory root, one item
        // with a few records, two tags).
        return controller
    }()
}
```

Notes: `loadPersistentStores` runs its completion synchronously because `shouldAddStoreAsynchronously` defaults to `false` (CloudKit mirroring setup then continues in the background), so `privateStore`/`sharedStore` are set before first use; do not set `shouldAddStoreAsynchronously = true`. `NSMergeByPropertyObjectTrumpMergePolicy` = local in-memory edits win over incoming store versions at save; CloudKit's own server-side merge still applies field-level last-writer-wins between devices — that is why `cachedQuantity` needs the reconciler (§8.2).

### 5.4 App entry

Rewrite `Simple_InventoryApp.swift`: drop SwiftData; hold `PersistenceController.shared`; inject `.environment(\.managedObjectContext, persistence.viewContext)` and `.environmentObject(...)` for the Phase 2/3 stores; add the `@UIApplicationDelegateAdaptor`/`@NSApplicationDelegateAdaptor` from §7.3 (Phase 3 — leave a TODO until then).

### 5.5 View-layer edits (mechanical, file-by-file)

Global: replace `import SwiftData` → `import CoreData` (or delete the import where unused); `@Environment(\.modelContext)` → `@Environment(\.managedObjectContext) private var viewContext`; `modelContext.delete(x)` → `viewContext.delete(x)`; `modelContext.insert(x)` → construct with `X(context: viewContext)` instead (Core Data objects are born inserted).

**Save discipline:** call `PersistenceController.shared.save()` (inject the controller or use the singleton) after every user-committed mutation. Exact sites:
1. `InventoryListView.quickAdjust` (after add/removeStock) and `.delete(item)`.
2. `ItemDetailView.quickAdjust` — save on each tap (records coalesce in the session record; a crash mid-session must not lose taps), `undoQuickAdjustments`, `deleteRecord`, `deleteItem`, and `LimitEditor` (save in `NumericField` binding setters or `onDisappear`). Reminder from §5.2: the record deletions inside `quickAdjust` (net-to-zero branch) and `undoQuickAdjustments` must call `item.reconcileLedger(excludingRecordID: record.id)` before the save.
3. `ItemDetailView.dateBinding` setter (record date edit).
4. `AddItemView.addItem`, `EditItemView.saveChanges`.
5. `AdjustStockSheet.save`.
6. `TagManagementView` delete paths + `TagEditorSheet.save`.
7. `TagPickerField.commitNewTag`.

**Queries:** `@Query(sort: \InventoryItem.name)` → `@FetchRequest` — but in Phase 2 these become root-scoped, so build them in `init` from day one:

```swift
@FetchRequest private var items: FetchedResults<InventoryItem>
// in init(...):
_items = FetchRequest<InventoryItem>(
    sortDescriptors: [NSSortDescriptor(key: "nameRaw", ascending: true,
        selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))],
    predicate: nil,  // Phase 2 replaces with inventory == root
    animation: .default)
```

Same for `@Query(sort: \Tag.name)` in `InventoryListView`, `ItemDetailView`, `AddItemView`, `TagManagementView` (key `"nameRaw"`). `FetchedResults` is a `RandomAccessCollection`, not an array — three call sites need explicit conversion or they won't compile: `filteredAndSortedItems` starts with `var result = Array(items)`; `InventoryListView`'s `.onChange(of: allTags)` becomes `.onChange(of: Array(allTags))` (`FetchedResults` isn't `Equatable`); and `EditItemView(item:allTags:)` / `TagPickerField(allTags:)` keep their `[Tag]` parameters, so pass `Array(allTags)` at those call sites.

**`@Bindable` → `@ObservedObject`** in `ItemDetailView`, `LimitEditor`, `EditItemView`, `AdjustStockSheet` (NSManagedObject is an ObservableObject). `$item.redLimit` bindings on computed bridges don't come for free with `@ObservedObject` — replace the one `$item.redLimit` (in `LimitEditor`) with a manual `Binding(get:set:)`.

**`ItemDetailView` specifics:** `activeSessionRecord` membership check works as-is via the `quantityRecords` bridge. `record.amount = newAmount` flows through the bridge setter → `refreshCachedQuantity()` → `@ObservedObject` sees `cachedQuantityRaw` change → StockRing updates. Keep `.onChange(of: item.id)`. `HistoryEntry.id` (`record.id`) still compiles (bridge returns non-optional `UUID`).

**`ContentView`:** undo bridge becomes `viewContext.undoManager = systemUndoManager` (same two hook points). NSManagedObject satisfies `Hashable`; `navigationDestination(for: InventoryItem.self)` and `List(selection: $selectedItem)` keep working.

**Previews:** all 9 `#Preview` blocks (including `InventoryItemRow` and `QuantityRecordRow`): replace `ModelContainer`/`modelContainer(...)` with `PersistenceController.preview` + `.environment(\.managedObjectContext, PersistenceController.preview.viewContext)`, constructing sample objects in the preview context (`QuantityRecordRow`'s preview record too — a context-free `QuantityRecord(amount:date:)` no longer exists).

**Detached preview object:** `TagEditorSheet.previewTag` currently builds a throwaway `Tag(name:colorHex:)` on every body evaluation. Do NOT convert it to `Tag(context: viewContext)` — that would insert a phantom, un-scoped tag on every render that syncs to CloudKit. Use a detached object instead: `Tag(entity: Tag.entity(), insertInto: nil)`, then set `nameRaw`/`colorHexRaw` directly.

**Definition of done (Phase 1):** all five platform slices build; ported ledger tests green (including `cachedQuantityTracksLedger`); app runs in iOS simulator with full feature parity (add/edit/delete items, tags, quick ±, session coalescing, history edit/delete, undo toast, filters, search, sort); private-DB CloudKit sync smoke-tested in simulator (create item → console shows successful CKModifyRecords export; simulator account signed into iCloud).

## 6. Phase 2 — Root entity & inventory resolution

New file `Simple Inventory/InventoryStore.swift` — `@MainActor final class InventoryStore: ObservableObject`:

- `@Published private(set) var currentInventory: Inventory?`
- `func resolveCurrentInventory()`: fetch all `Inventory` objects from `viewContext`. **Rule: an inventory whose store is the shared store wins** (participant case): `if let shared = persistence.sharedStore, object.objectID.persistentStore === shared` — the non-nil guard matters because `sharedStore` is nil in the in-memory controller and an unsaved object's `persistentStore` is nil too (`nil === nil` must not classify a fresh private root as shared). Otherwise use the private-store root, creating one (+ `save()`) if none exists — first launch. Call `resolveCurrentInventory()` once in `init`.
- Re-resolve on `NSPersistentStoreRemoteChange` (this is how the app notices "the shared inventory arrived after join" and "my access was revoked": the shared root appears/disappears). Debounce bursts with a `Task` that awaits `Task.yield()`-style coalescing or a simple `DispatchQueue.main.async` flag — **no timers, no sleep**.
- On revocation (shared root disappeared): fall back to the private root and set a `@Published var lostSharedAccess = true` flag; `ContentView` shows a one-time alert ("You no longer have access to the shared inventory").

Wire-up:
- `Simple_InventoryApp` creates the store, injects via `.environmentObject`.
- `ContentView` blocks list rendering until `currentInventory != nil` (brief; creation is synchronous on first run).
- `InventoryListView` + the 3 other tag-querying views take `let inventory: Inventory` in `init` and scope both fetch requests: `NSPredicate(format: "inventory == %@", inventory)` for items; same for tags. Pass `inventory` down from `ContentView`.
- Attach on create: `AddItemView.addItem` sets `item.inventory = inventory`; `TagPickerField.commitNewTag` and `TagEditorSheet.save` set `tag.inventory = inventory` (add an `inventory` property to both views, passed from their presenters). `TagPickerField` has two presenters: `AddItemView` (has `inventory` already) and `EditItemView` — give `EditItemView` a `let inventory: Inventory` passed explicitly from `ItemDetailView` and forward it; do not derive it from `item.inventory`. **Every new object must be attached to the current root — unreachable objects won't sync into the share.**

**Definition of done:** builds everywhere; tests green; feature parity in simulator; every `InventoryItem`/`Tag` creation path sets `.inventory` — verify by re-reading each creation site listed above (the creation bodies are private view methods, so this is a review check, not a unit test).

## 7. Phase 3 — Sharing

New file `Simple Inventory/ShareCoordinator.swift` — `@MainActor final class ShareCoordinator: ObservableObject`. `share`, `persistUpdatedShare`, `acceptShareInvitations`, and `purgeObjectsAndRecordsInZone` are completion-based — wrap them with `withCheckedThrowingContinuation` and branch on the trailing `Error?` parameter (`share(_:to:completion:)`'s completion delivers several values plus `Error?`, not a `(value, error)` pair). `fetchShares(matching:)` is synchronous and throws — call it directly, no wrapper. API surface:

```swift
@Published private(set) var currentShare: CKShare?

func fetchShare(for inventory: Inventory)            // container.fetchShares(matching: [inventory.objectID]) — synchronous
func createShare(forObjectWith id: NSManagedObjectID) async throws -> CKShare
    // let inventory = viewContext.object(with: id)
    // container.share([inventory], to: nil) → set share[CKShare.SystemFieldKey.title] = "Shared Inventory"
    // → persistUpdatedShare(share, in: persistence.privateStore) → set currentShare
func removeParticipant(_ p: CKShare.Participant) async throws
    // owner-only: share.removeParticipant(p) → persistUpdatedShare(share, in: privateStore)
func leaveShare() async throws
    // participant: purge the whole shared zone locally + on server:
    // container.purgeObjectsAndRecordsInZone(with: share.recordID.zoneID, in: persistence.sharedStore)
var isOwner: Bool      // currentShare.flatMap { $0.currentUserParticipant == $0.owner } ?? true
var isShared: Bool     // resolved share exists for the current inventory
func accept(_ metadata: CKShare.Metadata)             // container.acceptShareInvitations(from: [metadata], into: persistence.sharedStore)
```

**Wiring:** call `fetchShare(for:)` whenever `InventoryStore.currentInventory` resolves or changes, and re-fetch it on the same debounced `NSPersistentStoreRemoteChange` path — that is how the owner's Members list learns an invitee accepted, and how a joining device learns it is now a participant.

### 7.1 Invite UI (owner)

`ShareLink` + `CKShareTransferRepresentation` with a small `Transferable` wrapper:

The exporter closure is `@Sendable` and runs off the main actor — under this project's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` it MUST NOT read `@MainActor` state (that is a compile error) or capture non-Sendable `NSManagedObject`s. Snapshot everything up front; this exact shape typechecks under the project's settings:

```swift
/// Built on the MainActor by the presenting view. The share-sheet machinery
/// calls the exporter off-actor, so it only reads immutable snapshots and
/// awaits into the (implicitly Sendable) @MainActor coordinator.
nonisolated struct SharedInventory: Transferable {
    let share: CKShare?                 // snapshot of coordinator.currentShare
    let inventoryID: NSManagedObjectID  // NSManagedObjectID is thread-safe
    let coordinator: ShareCoordinator

    static let sharingOptions = CKAllowedSharingOptions(
        allowedParticipantPermissionOptions: .any,
        allowedParticipantAccessOptions: .specifiedRecipientsOnly)

    static var transferRepresentation: some TransferRepresentation {
        CKShareTransferRepresentation { wrapper in
            let container = CKContainer(identifier: PersistenceController.cloudKitContainerID)
            if let share = wrapper.share {
                return .existing(share, container: container, allowedSharingOptions: sharingOptions)
            }
            let coordinator = wrapper.coordinator
            let inventoryID = wrapper.inventoryID
            return .prepareShare(container: container, allowedSharingOptions: sharingOptions) {
                try await coordinator.createShare(forObjectWith: inventoryID)
            }
        }
    }
}
```

Placement: a "Share Inventory" item in `InventoryListView`'s toolbar `Menu` (next to "Edit Tags…"): `ShareLink(item: SharedInventory(share: coordinator.currentShare, inventoryID: inventory.objectID, coordinator: coordinator), preview: SharePreview("Shared Inventory", image: Image(systemName: "shippingbox")))`. Because the presenting view observes the coordinator, the `ShareLink` rebuilds with a fresh snapshot after share creation. When a share already exists, also show "Members…" (opens `MembersView`). The explicit invite-only `allowedSharingOptions` (`.specifiedRecipientsOnly`) is deliberate and load-bearing: Apple documents no default access mode, and an "anyone with link" share would let a removed participant rejoin with an old link — invite-only makes removal a guaranteed revocation. Do not use `.standard`.

### 7.2 Members screen (all platforms, custom UI)

New `Views/MembersView.swift` — plain SwiftUI `List` over `coordinator.currentShare?.participants`:
- Row: name from `participant.userIdentity.nameComponents` (`PersonNameComponentsFormatter`) → fallback `participant.userIdentity.lookupInfo?.emailAddress ?? "Participant"`; sub-line: role ("Owner"/"Member") + acceptance status ("Invited" if `.pending`). *iOS 26 privacy note: without the `com.apple.developer.icloud-extended-share-access` entitlement, identity fields may be empty for non-owner participants — the fallback label must look intentional. Do not add that entitlement (it needs an Apple request/approval flow the user does separately); code defensively.*
- Owner: swipe-to-remove (confirm dialog) → `removeParticipant`. Participants can't be removed by non-owners (`isOwner` gates it).
- Participant: "Leave Inventory" (destructive, confirm) → `leaveShare()` → `InventoryStore` falls back to the private root via the remote-change/resolution path (a local purge fires it immediately).
- Owner "Stop Sharing" v1 = remove every non-owner participant (loop + single `persistUpdatedShare`). Do NOT purge the owner's zone.

### 7.3 Acceptance wiring

- iOS/visionOS (`#if os(iOS) || os(visionOS)`): `AppDelegate: NSObject, UIApplicationDelegate` with `application(_:configurationForConnecting:options:)` returning a `UISceneConfiguration` whose `delegateClass = SceneDelegate.self`. `SceneDelegate: NSObject, UIWindowSceneDelegate` implements BOTH `windowScene(_:userDidAcceptCloudKitShareWith:)` (warm) and cold-launch delivery via `scene(_:willConnectTo:options:)` → `connectionOptions.cloudKitShareMetadata`. Both paths hand the metadata to the join flow below. Register with `@UIApplicationDelegateAdaptor(AppDelegate.self)` in the App struct.
- macOS (`#if os(macOS)`): `AppDelegate: NSObject, NSApplicationDelegate` implementing `application(_:userDidAcceptCloudKitShareWith:)`, registered with `@NSApplicationDelegateAdaptor`.
- Metadata handoff from delegates to SwiftUI: `@MainActor final class ShareAcceptanceBroker: ObservableObject { static let shared = ShareAcceptanceBroker(); @Published var pendingMetadata: CKShare.Metadata? }` — delegates set `ShareAcceptanceBroker.shared.pendingMetadata`; `ContentView` observes it (`@ObservedObject private var broker = ShareAcceptanceBroker.shared`) and is the host that presents the Replace alert and joining overlay below (App structs can't present alerts).

**Join flow (the Replace confirmation happens BEFORE accepting):** when `pendingMetadata` arrives — if the private root has any items, present an alert: "Join shared inventory? Your current items will be hidden while you're a member. Leaving brings them back." Cancel → discard metadata. Confirm (or empty private inventory) → `coordinator.accept(metadata)` → show a joining overlay ("Joining shared inventory…", `ProgressView`) until `InventoryStore` resolves a shared-store root (remote-change driven; typically seconds). Provide a Cancel that just hides the overlay (sync continues in background) — never block, never sleep.

**Definition of done:** all platforms build; in iOS simulator: Share menu item produces the system share sheet with a generated link; MembersView renders with just the owner; acceptance path compiles on all platforms. (Confirming the share record in CloudKit Console → Development → Private DB is a manual step for the user — flag it, don't claim it.) Actual two-account join/remove testing is hardware-only and lands in Phase 5's checklist — do not claim it verified.

## 8. Phase 4 — Multi-user edge cases

### 8.1 Persistent-history processor

New `Simple Inventory/HistoryProcessor.swift`. On each `NSPersistentStoreRemoteChange` notification (observe once, both stores):
1. In `container.performBackgroundTask` (context `transactionAuthor = reconcilerTransactionAuthor`, `name = "history"`), fetch history since the last processed token (persist tokens per store in `UserDefaults` as archived `NSPersistentHistoryToken`).
2. Skip transactions authored by `reconcilerTransactionAuthor` (its own saves would loop).
3. Collect changed `NSManagedObjectID`s of `QuantityRecord` (and their items) and `Tag` inserts.
4. Delete processed history **only for history older than the token both this processor and the CloudKit mirror have consumed — simplest safe policy: don't delete history at all in v1** (stores are small; revisit post-TestFlight).

### 8.2 `cachedQuantity` reconciliation

For every `InventoryItem` touched by remote `QuantityRecord` changes (from §8.1 step 3): in the background context, call `refreshCachedQuantity()`; save if changed. Rationale: records are insert-only between users so ledgers merge cleanly, but `cachedQuantityRaw` itself merges last-writer-wins and can drift under concurrent edits; recomputing from the ledger on every remote delta converges every device to the true clamped sum. (Local edits are already covered synchronously by the mutation helpers.)

### 8.3 Tag dedup (owner's device only)

Concurrent creation of an identically-named tag by two users yields duplicates. On remote Tag inserts (§8.1 step 3), the **owner's** device (participants skip — dedup deletes objects, and only one device should) groups the current inventory's tags by `nameRaw.lowercased()`; for each group >1: keep the tag with the lowest `uuid.uuidString`, re-point every item from the losers (union `itemsRel`), delete the losers, save. The existing case-insensitive reuse in `TagPickerField.commitNewTag` already prevents most local dupes.

### 8.4 Stale-object hardening

After a participant is removed, the container deletes the shared graph — possibly while `ItemDetailView` is showing one of those items. Guard: in `ItemDetailView`, if `item.isDeleted || item.managedObjectContext == nil`, render a `ContentUnavailableView` and pop (use `onChange` of those via the item's `objectWillChange`). Same guard pattern in `MembersView` for a vanished share. Never force-unwrap `uuid`/`dateRaw` anywhere (the bridges already don't).

### 8.5 Permission gating

`readWrite` participants can edit everything, so v1 needs no per-action gating except: Members management (remove) is owner-only (§7.2), and "Share Inventory" is hidden for participants (they see "Members…"). If a `readOnly` participant joins (owner chose it in the system sheet), rely on `PersistenceController.save()`'s rollback to revert rejected edits in v1; a polished read-only UI (disabled controls via `canUpdateRecord(forManagedObjectWith:)`) is explicitly out of scope.

**Definition of done:** builds everywhere; unit tests for §8.2 (simulate divergent `cachedQuantityRaw`, run reconciler logic, converges) and §8.3 (two same-named tags → one survives with merged items) using the in-memory controller; manual simulator run shows no history-processing loops (console: reconciler saves don't retrigger themselves).

## 9. Phase 5 — Release readiness (before TestFlight)

1. **Deploy the CloudKit schema to Production** (CloudKit Console → container → Development → "Deploy Schema Changes…"). Development-only `initializeCloudKitSchema` never runs in Release; without deployment, TestFlight builds sync nothing.
2. **Hardware test matrix** (two physical devices, two iCloud accounts — the user runs this; produce the checklist in the PR/commit description): create+sync solo → share → send link via Messages → accept on device B (Replace prompt → joined) → B adds/adjusts items → A sees them (allow minutes) → concurrent ± on the same item on both → quantities converge to ledger sum → A removes B → B's app falls back to private root with notice → B re-taps old link → cannot rejoin (invite-only is enforced via the §7.1 `CKAllowedSharingOptions`) → B re-invited → rejoin works → B leaves voluntarily → same fallback.
3. TestFlight notes via the repo's `testflight-notes` skill; `aps-environment` switches to production automatically at distribution signing.

## 10. Verification constraints (be honest in reports)

- **Simulator CAN:** build all platforms, run unit tests, full local feature parity, private-DB sync smoke test (signed-in iCloud account), share-record creation, all UI states.
- **Simulator CANNOT:** accept a share / join / participant flows / removal propagation (requires two physical devices + two iCloud accounts). Never report these as verified from the simulator; leave them to the Phase 5 human checklist.
- Build commands: `xcodebuild build -scheme "Simple Inventory" -destination 'generic/platform=iOS Simulator'` (and `platform=macOS`, `generic/platform=visionOS Simulator`); tests as in §4.4. The Claude iOS Simulator MCP tooling works in this repo for interactive runs (iPhone 17 Pro).

## 11. Reference sources (for looking up API details — not for revisiting decisions)

- Apple sample: *Sharing Core Data objects between iCloud users* — the blueprint for the two-store setup, share lifecycle, dedup, purge semantics.
- Apple: *Accepting share invitations in a SwiftUI app* — the §7.3 delegate wiring.
- Apple docs: `NSPersistentCloudKitContainer.share(_:to:)`, `persistUpdatedShare(_:in:)`, `fetchShares(matching:)`, `acceptShareInvitations(from:into:)`, `purgeObjectsAndRecordsInZone(with:in:)`, `CKShareTransferRepresentation`.
- fatbobman's *Core Data with CloudKit* series, part on sharing — practical pitfalls.
