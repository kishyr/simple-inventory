//
//  TagPickerField.swift
//  Simple Inventory
//

import SwiftUI
import SwiftData

/// Inline tap-to-toggle tag chips for the Add/Edit item forms, including
/// a "+ New Tag" chip that creates a tag in place.
struct TagPickerField: View {
    @Environment(\.modelContext) private var modelContext

    let allTags: [Tag]
    @Binding var selectedTags: Set<Tag>

    @State private var isAddingTag = false
    @State private var newTagName = ""
    @FocusState private var newTagFocused: Bool

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(allTags) { tag in
                Button {
                    withAnimation(.snappy) {
                        if selectedTags.contains(tag) {
                            selectedTags.remove(tag)
                        } else {
                            selectedTags.insert(tag)
                        }
                    }
                } label: {
                    TagChip(tag: tag, isSelected: selectedTags.contains(tag))
                }
                .buttonStyle(.plain)
                .expandedTapTarget()
                .accessibilityAddTraits(selectedTags.contains(tag) ? .isSelected : [])
            }

            if isAddingTag {
                TextField("Tag name", text: $newTagName)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .focused($newTagFocused)
                    .frame(width: 110)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.quaternary, in: .capsule)
                    .submitLabel(.done)
                    .onSubmit(commitNewTag)
                    .onAppear { newTagFocused = true }
                    .onChange(of: newTagFocused) { _, focused in
                        if !focused {
                            commitNewTag()
                        }
                    }
            } else {
                Button {
                    withAnimation(.snappy) {
                        isAddingTag = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("New Tag")
                    }
                    .font(.subheadline.weight(.medium))
                    .fixedSize()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .foregroundStyle(.secondary)
                    .background(.quaternary, in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .sensoryFeedback(.selection, trigger: selectedTags)
    }

    private func commitNewTag() {
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        newTagName = ""
        withAnimation(.snappy) {
            isAddingTag = false
        }
        guard !name.isEmpty else { return }

        // Reuse an existing tag with the same name instead of duplicating.
        if let existing = allTags.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            withAnimation(.snappy) {
                _ = selectedTags.insert(existing)
            }
            return
        }

        let usedHexes = Set(allTags.map(\.colorHex))
        let hex = Tag.presetHexes.first { !usedHexes.contains($0) }
            ?? Tag.presetHexes[allTags.count % Tag.presetHexes.count]

        let tag = Tag(name: name, colorHex: hex)
        modelContext.insert(tag)
        withAnimation(.snappy) {
            _ = selectedTags.insert(tag)
        }
    }
}
