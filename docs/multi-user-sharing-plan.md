# Multi-User Shared Inventory — Implementation Plan

**Status:** Approved decisions baked in (2026-08-05). Not yet started.
**Implementation:** hand-off spec at `docs/multi-user-sharing-spec.md` — that document is the authoritative one for implementers; this one records the decisions and research rationale.
**Goal:** Multiple iCloud users collaborate on one shared inventory. The creator invites others via the native iCloud share sheet; joiners' app shows the shared inventory as their only inventory; the creator can remove participants.

## Decisions (confirmed with Kishyr, 2026-08-05)

| Decision | Choice |
|---|---|
| Existing data | Greenfield — app has never shipped; no store migration needed |
| Platforms | Sharing works on iOS, macOS, and visionOS |
| Join behavior | Replace — shared list becomes the joiner's only inventory; their old local items stay dormant and return if they leave/are removed |
| Invite method | Native iCloud share link (system share sheet, like Notes/Reminders) — no share codes |

## Why this architecture (research summary)

All claims below were verified against Apple primary sources in Aug 2026.

- **SwiftData cannot do CloudKit sharing.** As of iOS 26.x, `ModelConfiguration.CloudKitDatabase` offers only `.automatic` / `.private` / `.none` — private-database mirroring only. WWDC 2025 and WWDC 2026 added nothing for sharing (iOS 27 gets sectioned queries, `@Attribute(.codable)`, observers — no CKShare). Apple DTS explicitly directs multi-user use cases to Core Data + `NSPersistentCloudKitContainer`.
  ([ModelConfiguration.CloudKitDatabase](https://developer.apple.com/documentation/swiftdata/modelconfiguration/cloudkitdatabase-swift.struct), [DTS forum statement](https://developer.apple.com/forums/thread/756721), [WWDC26 SwiftData session](https://developer.apple.com/videos/play/wwdc2026/274/))
- **`NSPersistentCloudKitContainer` sharing is record-zone sharing.** `share(_:to:)` moves an object *and its entire relationship graph* into a new zone in the owner's private database with a zone-wide `CKShare`. Everything reachable from the shared object — including records added later by anyone — is shared. This matches "everyone shares the whole inventory" exactly: share one root object once.
  ([Apple sample: Sharing Core Data objects between iCloud users](https://developer.apple.com/documentation/coredata/sharing-core-data-objects-between-icloud-users))
- **Participants mirror the share via a second persistent store** (`.shared` database scope) on the same coordinator. Owner's data lives in the private store; a joiner's copy materializes in their shared store. Removal (by owner) or leaving auto-deletes the graph from the participant's device — which is precisely the "replace / revert" semantics chosen above, for free.
- **Native invite/acceptance UI:** SwiftUI `ShareLink` + `CKShareTransferRepresentation` works on iOS 16+/macOS 13+/visionOS 1+ (all our targets). `UICloudSharingController` is not available on macOS AppKit and has documented stale-cache bugs, so the members list will be a small custom SwiftUI screen over `CKShare.participants` — identical on all three platforms.
- **Two pre-existing defects block everything** (found during codebase analysis, must be fixed first):
  1. `CODE_SIGN_ENTITLEMENTS` is not set anywhere in `project.pbxproj` — `Simple_Inventory.entitlements` exists on disk but is applied to **no** build. CloudKit sync has never actually functioned.
  2. Every model attribute is non-optional with defaults only in `init()`, violating CloudKit mirroring rules (attributes must be optional or have *model-level* defaults). Sync would fail the moment entitlements are wired. (This applies to SwiftData and Core Data equally.)

## Target architecture

```
Owner's iCloud private DB          Participant's device
┌───────────────────────────┐
│ com.apple.coredata.       │      ┌─────────────────────────┐
│ cloudkit.share.<zoneID>   │ ───▶ │ Shared store (.shared   │
│  Inventory (root) ── CKShare     │  scope) mirrors the     │
│   ├── InventoryItem*      │      │  owner's shared zone    │
│   │     └── QuantityRecord*     └─────────────────────────┘
│   └── Tag*                │      Private store: joiner's old
└───────────────────────────┘      items, dormant
```

- **New root entity `Inventory`** with to-many relationships to both `InventoryItem` and `Tag` so *every* object is reachable from the root (a tag with zero items must still sync). Cross-zone relationships are prohibited, so reachability from the root is a hard invariant.
- **"Current inventory" resolution rule:** if a root `Inventory` exists in the shared store → that is the inventory (user is a participant). Otherwise use (or create) the root in the private store (solo user or owner). This one rule implements both "once they join, that's their only inventory" and automatic fallback after removal.
- Every user starts solo with a private root. Tapping **Share** converts the owner's root into a shared one (`share([root], to: nil)`); nothing else changes for the owner.

## Data model (Core Data, CloudKit-legal)

All attributes optional or model-defaulted; `UUID`/`Date` become optional and are set in `awakeFromInsert`. Class names stay `InventoryItem` / `QuantityRecord` / `Tag` so the 7 component views (TagChip, StockRing, StockHistoryChart, StatusBadge, NumericField, PhotoWell, FlowLayout) compile untouched.

| Entity | Attributes | Relationships |
|---|---|---|
| `Inventory` (new) | `id: UUID?`, `createdAt: Date?` | `items` →→ InventoryItem (cascade), `tags` →→ Tag (cascade) |
| `InventoryItem` | `id: UUID?`, `name: String?` (default ""), `imageData: Data?` (external storage → CKAsset), `yellowLimit`/`redLimit: Int` (model defaults 5/2), `createdAt: Date?`, **`cachedQuantity: Int` (new, default 0)** | `inventory` → Inventory (nullify), `tags` ←→ Tag (nullify), `quantityRecords` →→ QuantityRecord (cascade) |
| `QuantityRecord` | `id: UUID?`, `amount: Int` (default 0), `date: Date?` | `item` → InventoryItem (nullify) |
| `Tag` | `id: UUID?`, `name: String?` (default ""), `colorHex: String?` (default "007AFF") | `inventory` → Inventory (nullify), `items` ←→ InventoryItem |

**`cachedQuantity` is new and load-bearing.** SwiftData's observation re-renders `item.currentQuantity` when a child record changes; Core Data's `@ObservedObject` on the item does **not** fire when a child record's scalar mutates in place (which the one-tap "session record" coalescing does constantly). Fix: mutation helpers (`addStock`/`removeStock`/`reconcileLedger` and session-record edits) also update `cachedQuantity` on the item, and a remote-change handler recomputes it from the ledger for items touched by incoming syncs (protects against last-writer-wins drift when two users adjust simultaneously). Views read `cachedQuantity`; the ledger remains the source of truth.

Ledger semantics (clamping, capping, `reconcileLedger`) port verbatim onto the `NSManagedObject` subclasses. `record.modelContext?.delete` → `record.managedObjectContext?.delete`.

## UX flows

- **Share (owner):** toolbar/settings → "Share Inventory" → system share sheet via `ShareLink(item:preview:)` + `CKShareTransferRepresentation` (`.prepareShare` creates the CKShare on first use) → send via Messages/Mail/AirDrop. Default access "Only people you invite" (system standard) — this makes removal fully enforceable; a removed person cannot rejoin without a fresh invite.
- **Join:** invitee taps the link → app opens → acceptance callback → `acceptShareInvitations(from:into: sharedStore)` → "Joining…" progress state until the shared root appears in the shared store (sync takes seconds-to-minutes) → confirmation prompt "This will replace your inventory" (per the Replace decision, shown before accepting if local items exist) → shared inventory becomes the inventory.
- **Members (all users):** a "Members" screen listing `share.participants` (name/avatar where available). Owner sees Remove buttons → `share.removeParticipant(_:)` + `persistUpdatedShare(_:in:)`. Participants see "Leave Inventory" → purge local shared zone. Owner "Stop sharing" v1 = remove all participants (the deep-copy + `purgeObjectsAndRecordsInZone` dance is deferred; owner's data is already in their private DB so nothing is lost).
- **Removed participant experience:** CloudKit deletes the shared graph from their device on next sync; the resolution rule falls back to their dormant private root. Show a one-time notice ("You no longer have access to the shared inventory").
- **No iCloud account:** app keeps working locally (private store); sharing UI disabled with an explanatory banner (`CKContainer.accountStatus`).

## Implementation phases

**Phase 0 — Foundations (blockers, no sharing yet)**
1. Wire `CODE_SIGN_ENTITLEMENTS = "Simple Inventory/Simple_Inventory.entitlements"` into the app target (Debug + Release).
2. Add `com.apple.security.network.client` to the entitlements (sandboxed macOS build needs it for CloudKit).
3. Add `CKSharingSupported = YES` to Info.plist (share links must launch the app).
4. Unit tests for ledger logic (`currentQuantity` clamp, `addStock`/`removeStock` caps, `reconcileLedger`) — written against the current models, kept green through the port. The test target is currently an empty template.

**Phase 1 — Core Data migration (greenfield)**
1. New `.xcdatamodeld` per the table above (filesystem-synchronized groups: no pbxproj edits).
2. `NSManagedObject` subclasses with ported domain logic + `awakeFromInsert` defaults + `cachedQuantity` maintenance.
3. `PersistenceController`: `NSPersistentCloudKitContainer`, **two store descriptions** (private + shared scopes), persistent history tracking + remote change notifications on both, `viewContext.automaticallyMergesChangesFromParent = true`, `initializeCloudKitSchema` behind `#if DEBUG`.
4. Views: `@Query` → `@FetchRequest` (5 views, 3 trivial sorts, zero predicates today), `@Bindable` → `@ObservedObject` (3 views), `@Environment(\.modelContext)` → `\.managedObjectContext`, explicit `save()` at each of the ~7 mutation sites (SwiftData autosave disappears), undo bridge re-pointed at `NSManagedObjectContext.undoManager`, 8 `#Preview` blocks get an in-memory container helper.
5. Remove SwiftData.

**Phase 2 — Root entity & inventory resolution**
1. Backfill: on first launch, create the private root and attach any existing objects (trivial in greenfield, but keeps the invariant explicit).
2. All fetches scoped to the current root (`inventory == root` predicates) so dormant private items never leak into a participant's view.
3. Creation paths (`AddItemView`, inline tag creation in `TagPickerField`, `TagManagementView`) attach new objects to the current root — the reachability invariant.

**Phase 3 — Sharing**
1. Share creation + `ShareLink`/`CKShareTransferRepresentation` (cross-platform).
2. Acceptance wiring: `UIApplicationDelegateAdaptor` + `configurationForConnecting` installing a `UIWindowSceneDelegate` (`windowScene(_:userDidAcceptCloudKitShareWith:)`) for iOS/visionOS; `NSApplicationDelegateAdaptor` (`application(_:userDidAcceptCloudKitShareWith:)`) for macOS; both call `acceptShareInvitations(from:into:)`.
3. Join progress state + Replace confirmation.
4. Members screen with owner remove / participant leave.

**Phase 4 — Multi-user edge cases**
1. Remote-change `cachedQuantity` reconciliation (see above).
2. Tag dedup: two users creating "Groceries" concurrently yields duplicates; dedup on the owner's device via persistent-history processing (keep lowest UUID, re-point items), per Apple's sample pattern.
3. Removal/leave fallback UX and stale-object crash guards (deleted-object faults after a zone purge).
4. Permission-aware UI: hide destructive/owner-only actions using `canUpdateRecord`/`canDeleteRecord` and `share.currentUserParticipant`.

**Phase 5 — Release readiness (before TestFlight)**
1. Deploy the CloudKit schema to Production in CloudKit Console (mirroring only auto-creates the Development schema).
2. Physical-device test matrix: sharing flows require two real devices with two iCloud accounts — the share-invitation flow does not work simulator-to-simulator. (Private-DB sync alone can be smoke-tested in the simulator.)
3. TestFlight notes via the existing `testflight-notes` skill.

Rough effort: Phases 0–1 are the bulk (the migration), 2–3 the feature, 4–5 hardening. Order is strict; each phase leaves the app shippable.

## Risks & known limitations

- **Sync is not real-time.** CloudKit mirroring runs at utility QoS; owner→participant propagation is seconds-to-minutes. UX must never promise instant updates (fine for a home-inventory app; both users' ledgers merge cleanly since records are insert-only).
- **iOS 26 participant-privacy entitlement.** Custom sharing UI showing participant names/emails needs the `com.apple.developer.icloud-extended-share-access` entitlement; without it the members list degrades to generic labels ("Participant 2"). Request it; ship degraded labels as fallback.
- **Cold-start link acceptance** (long-standing CloudKit bug): if someone *installs the app for the first time by tapping a share link*, metadata may not arrive on first launch and the link needs a second tap. Low impact for us (TestFlight users install first), worth a line in the join instructions.
- **CloudKit debuggability** is famously poor server-side, with community reliability complaints through iOS 26.4. Accepted: this is Apple's supported stack, the app is low-stakes, and the ledger model (insert-only records) is unusually merge-friendly.
- **"Anyone with link" mode** would weaken removal (someone holding the link could rejoin), so the app restricts the share sheet to invite-only via `CKAllowedSharingOptions(allowedParticipantAccessOptions: .specifiedRecipientsOnly)` — removal is then a guaranteed revocation. (Detailed in the implementation spec.)

## Alternatives considered (and rejected)

- **Share code + public-database lookup** (original idea): viable and production-proven (code → CKShare URL record in the public DB → programmatic accept), but requires making shares world-joinable (`publicPermission = .readWrite`), custom code lifecycle (rotation on removal), and the code becomes the secret. Dropped in favor of native links (2026-08-05). The research is preserved in the session archive if we ever want it.
- **Keep SwiftData + hand-rolled CloudKit sharing layer:** building a sync engine (custom zones, `record.parent` hierarchies, subscriptions, conflict handling). Far more work and fragility than migrating persistence.
- **CKSyncEngine:** full control, but you own the entire local store + record conversion + merges. Weeks vs. days; unjustified here.
- **Point-Free SQLiteData:** third-party persistence with built-in CloudKit sharing and a SwiftData-like API. Competitive, but a full rewrite onto a third-party dependency vs. Apple's first-party stack.
- **Wait for SwiftData sharing:** confirmed not coming in iOS 27 — re-verified against iOS 27 **beta 4** (2026-08-05): the beta doc set still lists only `.automatic`/`.private`/`.none` for `ModelConfiguration.CloudKitDatabase` (while beta-badging the genuinely new `ResultsObserver`/`HistoryObserver`), per-beta CloudKit header diffs show zero new sharing API in b1–b4, and beta release notes list only bug fixes.

## Key sources

- [Sharing Core Data objects between iCloud users](https://developer.apple.com/documentation/coredata/sharing-core-data-objects-between-icloud-users) (Apple sample — the blueprint for Phases 1–4)
- [Accepting share invitations in a SwiftUI app](https://developer.apple.com/documentation/coredata/accepting-share-invitations-in-a-swiftui-app) (Apple — the Phase 3 delegate wiring)
- [DTS: SwiftData shared/public DB not supported](https://developer.apple.com/forums/thread/756721) · [WWDC26 What's new in SwiftData](https://developer.apple.com/videos/play/wwdc2026/274/)
- [CKShareTransferRepresentation](https://developer.apple.com/documentation/cloudkit/cksharetransferrepresentation) · [UICloudSharingController availability/caveats](https://developer.apple.com/documentation/uikit/uicloudsharingcontroller)
- fatbobman's Core Data with CloudKit series (sharing part): practical `persistUpdatedShare` / controller-bug workarounds
