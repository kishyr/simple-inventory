//
//  PhotoWell.swift
//  Simple Inventory
//

import SwiftUI
import PhotosUI

/// Large tappable photo area used by the Add and Edit item forms.
/// Offers camera capture (iOS), library selection, and removal via a
/// confirmation dialog. Incoming images are downscaled before storage.
struct PhotoWell: View {
    @Binding var imageData: Data?

    @State private var showingOptions = false
    @State private var showingLibrary = false
    @State private var showingCamera = false
    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        #if os(iOS)
        core
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { data in
                    apply(data)
                }
                .ignoresSafeArea()
            }
        #else
        core
        #endif
    }

    private var core: some View {
        Button {
            showingOptions = true
        } label: {
            wellContent
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .confirmationDialog("Item Photo", isPresented: $showingOptions, titleVisibility: .hidden) {
            #if os(iOS)
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showingCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera")
                }
            }
            #endif

            Button {
                showingLibrary = true
            } label: {
                Label("Choose From Library", systemImage: "photo.on.rectangle")
            }

            if imageData != nil {
                Button("Remove Photo", role: .destructive) {
                    withAnimation {
                        imageData = nil
                        selectedPhotoItem = nil
                    }
                }
            }
        }
        .photosPicker(isPresented: $showingLibrary, selection: $selectedPhotoItem, matching: .images)
        .onChange(of: selectedPhotoItem) { _, newValue in
            guard let newValue else { return }
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self) {
                    apply(data)
                }
            }
        }
    }

    @ViewBuilder
    private var wellContent: some View {
        if let imageData, let image = Image(data: imageData) {
            image
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(alignment: .bottomTrailing) {
                    Label("Edit", systemImage: "pencil")
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.regularMaterial, in: .capsule)
                        .padding(8)
                }
                .contentTransition(.opacity)
        } else {
            RoundedRectangle(cornerRadius: 16)
                .fill(.quaternary)
                .frame(maxWidth: .infinity)
                .frame(height: 110)
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "camera.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                        Text("Add Photo")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                }
        }
    }

    private func apply(_ data: Data) {
        let processed = ImageProcessing.downscaled(data) ?? data
        withAnimation {
            imageData = processed
        }
    }
}

#if os(iOS)
/// Minimal camera capture wrapper. Only offered when a camera is available.
struct CameraPicker: UIViewControllerRepresentable {
    var onCapture: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.9) {
                parent.onCapture(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
#endif
