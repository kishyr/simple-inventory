//
//  TagManagementView.swift
//  Simple Inventory
//

import SwiftUI
import SwiftData

struct TagManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Tag.name) private var tags: [Tag]

    @State private var showingAddTag = false
    @State private var tagToEdit: Tag?
    @State private var tagToDelete: Tag?

    var body: some View {
        NavigationStack {
            List {
                if tags.isEmpty {
                    ContentUnavailableView {
                        Label("No Tags", systemImage: "tag")
                            .symbolRenderingMode(.hierarchical)
                    } description: {
                        Text("Create tags to organize your inventory items.")
                    } actions: {
                        Button("Create Tag") {
                            showingAddTag = true
                        }
                        .glassProminentButton()
                    }
                } else {
                    ForEach(tags) { tag in
                        Button {
                            tagToEdit = tag
                        } label: {
                            HStack {
                                TagChip(tag: tag)

                                Spacer()

                                if let itemCount = tag.items?.count, itemCount > 0 {
                                    Text("\(itemCount) item\(itemCount == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                requestDelete(tag)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            Button {
                                tagToEdit = tag
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                        // Right-click/long-press parity — on macOS a mouse
                        // can't reach swipe actions.
                        .contextMenu {
                            Button {
                                tagToEdit = tag
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                requestDelete(tag)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Manage Tags")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddTag = true
                    } label: {
                        Label("Add Tag", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddTag) {
                TagEditorSheet(tag: nil)
            }
            .sheet(item: $tagToEdit) { tag in
                TagEditorSheet(tag: tag)
            }
            .confirmationDialog(
                deleteDialogTitle,
                isPresented: Binding(
                    get: { tagToDelete != nil },
                    set: { if !$0 { tagToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Tag", role: .destructive) {
                    if let tagToDelete {
                        withAnimation {
                            modelContext.delete(tagToDelete)
                        }
                    }
                    tagToDelete = nil
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 450, idealWidth: 500, minHeight: 450)
        #endif
    }

    private var deleteDialogTitle: String {
        guard let tag = tagToDelete else { return "" }
        let count = tag.items?.count ?? 0
        if count > 0 {
            return "Delete \"\(tag.name)\"? It will be removed from \(count) item\(count == 1 ? "" : "s")."
        }
        return "Delete \"\(tag.name)\"?"
    }

    private func requestDelete(_ tag: Tag) {
        if (tag.items?.count ?? 0) > 0 {
            tagToDelete = tag
        } else {
            withAnimation {
                modelContext.delete(tag)
            }
        }
    }
}

/// Single create/edit form for tags — replaces the four duplicated variants.
struct TagEditorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let tag: Tag?

    @State private var name: String
    @State private var selectedColor: Color
    @FocusState private var nameFocused: Bool

    init(tag: Tag?) {
        self.tag = tag
        _name = State(initialValue: tag?.name ?? "")
        _selectedColor = State(initialValue: tag?.color ?? Color(hex: Tag.presetHexes[0]) ?? .blue)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tag Name") {
                    TextField("Name", text: $name)
                        .focused($nameFocused)
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(Tag.presetHexes, id: \.self) { hex in
                            let color = Color(hex: hex) ?? .blue
                            Button {
                                withAnimation(.snappy) {
                                    selectedColor = color
                                }
                            } label: {
                                Circle()
                                    .fill(color)
                                    .frame(width: 40, height: 40)
                                    .overlay {
                                        if selectedColor.toHex() == hex {
                                            Circle()
                                                .strokeBorder(.primary, lineWidth: 2)
                                                .padding(-4)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Color \(hex)")
                        }

                        ColorPicker("Custom", selection: $selectedColor, supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 40, height: 40)
                    }
                    .padding(.vertical, 8)
                    .sensoryFeedback(.selection, trigger: selectedColor)
                }

                Section("Preview") {
                    HStack {
                        TagChip(tag: previewTag)
                        Spacer()
                    }
                }
            }
            .navigationTitle(tag == nil ? "New Tag" : "Edit Tag")
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
                    Button(tag == nil ? "Add" : "Save") {
                        save()
                    }
                    .disabled(!isValid)
                }
            }
            .onAppear {
                if tag == nil {
                    nameFocused = true
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, idealWidth: 450, minHeight: 400)
        #endif
    }

    /// Detached preview model — never inserted into the context.
    private var previewTag: Tag {
        Tag(
            name: name.isEmpty ? "Tag Name" : name,
            colorHex: selectedColor.toHex()
        )
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let tag {
            tag.name = trimmed
            tag.colorHex = selectedColor.toHex()
        } else {
            let newTag = Tag(name: trimmed, colorHex: selectedColor.toHex())
            modelContext.insert(newTag)
        }
        dismiss()
    }
}

#Preview {
    TagManagementView()
        .modelContainer(for: Tag.self, inMemory: true)
}
