//
//  EditItemView.swift
//  Simple Inventory
//

import SwiftUI
import SwiftData

struct EditItemView: View {
    @Environment(\.dismiss) private var dismiss

    @Bindable var item: InventoryItem
    let allTags: [Tag]

    @State private var name: String
    @State private var imageData: Data?
    @State private var yellowLimit: Int
    @State private var redLimit: Int
    @State private var selectedTags: Set<Tag>
    @State private var didSave = false

    init(item: InventoryItem, allTags: [Tag]) {
        self.item = item
        self.allTags = allTags
        _name = State(initialValue: item.name)
        _imageData = State(initialValue: item.imageData)
        _yellowLimit = State(initialValue: item.yellowLimit)
        _redLimit = State(initialValue: item.redLimit)
        _selectedTags = State(initialValue: Set(item.tags ?? []))
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotoWell(imageData: $imageData)
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                Section {
                    TextField("Name", text: $name)
                }

                Section("Tags") {
                    TagPickerField(allTags: allTags, selectedTags: $selectedTags)
                }

                Section {
                    NumericField(label: "Low Stock Warning", value: Binding(
                        get: { yellowLimit },
                        set: { newValue in
                            yellowLimit = newValue
                            redLimit = min(redLimit, newValue)
                        }
                    ), range: 0...10000)

                    NumericField(label: "Critical Warning", value: $redLimit, range: 0...yellowLimit)
                } header: {
                    Text("Warning Levels")
                } footer: {
                    Text("Critical is always at or below the low stock limit.")
                }
            }
            .navigationTitle("Edit Item")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(macOS)
            .formStyle(.grouped)
            .padding(.horizontal)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .sensoryFeedback(.success, trigger: didSave)
        #if os(macOS)
        .frame(minWidth: 500, idealWidth: 550, minHeight: 500)
        #endif
    }

    private func saveChanges() {
        item.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.imageData = imageData
        item.yellowLimit = yellowLimit
        item.redLimit = redLimit
        item.tags = Array(selectedTags)
        didSave = true
        dismiss()
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: InventoryItem.self, configurations: config)

    let item = InventoryItem(name: "Sample Item")
    container.mainContext.insert(item)

    return EditItemView(item: item, allTags: [])
        .modelContainer(container)
}
