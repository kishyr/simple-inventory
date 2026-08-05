//
//  AddItemView.swift
//  Simple Inventory
//

import SwiftUI
import SwiftData

struct AddItemView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Tag.name) private var allTags: [Tag]

    @State private var name = ""
    @State private var imageData: Data?
    @State private var yellowLimit = 5
    @State private var redLimit = 2
    @State private var initialQuantity = 0
    @State private var initialDate = Date()
    @State private var didSave = false

    @State private var selectedTags: Set<Tag> = []

    @FocusState private var nameFocused: Bool

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
                        .focused($nameFocused)
                        .submitLabel(.done)
                }

                Section("Initial Stock") {
                    NumericField(label: "Quantity", value: $initialQuantity, range: 0...10000)

                    DatePicker(
                        "Date Added",
                        selection: $initialDate,
                        in: ...Date(),
                        displayedComponents: [.date]
                    )
                }

                Section("Tags") {
                    TagPickerField(allTags: allTags, selectedTags: $selectedTags)
                }

                Section {
                    DisclosureGroup("Warning Levels") {
                        NumericField(label: "Low Stock Warning", value: Binding(
                            get: { yellowLimit },
                            set: { newValue in
                                yellowLimit = newValue
                                redLimit = min(redLimit, newValue)
                            }
                        ), range: 0...10000)

                        NumericField(label: "Critical Warning", value: $redLimit, range: 0...yellowLimit)
                    }
                } footer: {
                    Text("Warn at \(yellowLimit) or fewer, critical at \(redLimit) or fewer.")
                }
            }
            .navigationTitle("Add Item")
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
                    Button("Add") {
                        addItem()
                    }
                    .disabled(!isValid)
                }
            }
            .onAppear {
                nameFocused = true
            }
        }
        .sensoryFeedback(.success, trigger: didSave)
        #if os(macOS)
        .frame(minWidth: 500, idealWidth: 550, minHeight: 550)
        #endif
    }

    private func addItem() {
        let item = InventoryItem(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            imageData: imageData,
            yellowLimit: yellowLimit,
            redLimit: redLimit
        )

        item.tags = Array(selectedTags)

        if initialQuantity > 0 {
            item.addStock(amount: initialQuantity, date: initialDate)
        }

        modelContext.insert(item)
        didSave = true
        dismiss()
    }
}

#Preview {
    AddItemView()
        .modelContainer(for: InventoryItem.self, inMemory: true)
}
