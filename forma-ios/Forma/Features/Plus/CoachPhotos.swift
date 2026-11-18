import SwiftUI
import PhotosUI
import UIKit
import ImageIO

/// Ein Foto für den Coach: kleine Vorschau für die Anzeige, verkleinertes JPEG zum Senden.
/// Lange Kante höchstens 1568 px, höchstens 1 MB (Vorgabe für Bildeingaben der Anbieter).
struct CoachPhoto: Identifiable, Equatable {
    let id = UUID()
    /// Zum Senden. Leer bei Fotos, die nur noch im Chatverlauf stehen.
    let jpeg: Data
    /// Vorschau, lange Kante höchstens 480 px.
    let image: UIImage

    static let maxEdge = 1568
    static let maxBytes = 1_000_000
    static let previewEdge = 480
    static let maxCount = 4

    static func == (lhs: CoachPhoto, rhs: CoachPhoto) -> Bool { lhs.id == rhs.id }

    /// Nur die Vorschau behalten (Chatverlauf). Das Sende-JPEG wird nicht aufbewahrt.
    var forChat: CoachPhoto { CoachPhoto(jpeg: Data(), image: image) }

    /// Verkleinert und komprimiert beliebige Bilddaten. `nil`, wenn es kein Bild ist oder
    /// sich nicht unter 1 MB bringen lässt. EXIF-Drehung wird angewendet, Metadaten (Ort) gehen verloren.
    static func prepare(_ data: Data) -> CoachPhoto? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let full = thumbnail(source, edge: maxEdge),
              let preview = thumbnail(source, edge: previewEdge) else { return nil }
        let image = UIImage(cgImage: full)
        var quality: CGFloat = 0.85
        while quality >= 0.25 {
            if let jpeg = image.jpegData(compressionQuality: quality), jpeg.count <= maxBytes {
                return CoachPhoto(jpeg: jpeg, image: UIImage(cgImage: preview))
            }
            quality -= 0.15
        }
        return nil
    }

    private static func thumbnail(_ source: CGImageSource, edge: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: edge
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// Foto-Knopf links im Eingabefeld: Kamera oder Fotos. Legt bis zu vier Fotos in `photos` ab.
struct CoachPhotoButton: View {
    @Binding var photos: [CoachPhoto]
    @State private var showLibrary = false
    @State private var showCamera = false
    @State private var items: [PhotosPickerItem] = []

    private var remaining: Int { CoachPhoto.maxCount - photos.count }
    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        Menu {
            if cameraAvailable {
                Button("Kamera", systemImage: "camera") { showCamera = true }
            }
            Button("Fotos", systemImage: "photo.on.rectangle") { showLibrary = true }
        } label: {
            Image(systemName: "camera")
                .font(.system(size: 17, weight: .medium))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .disabled(remaining <= 0)
        .accessibilityLabel("Foto hinzufügen")
        .accessibilityHint(remaining <= 0 ? "Höchstens vier Fotos pro Nachricht" : "Kamera oder Fotos")
        .accessibilityIdentifier("coach.photo")
        .photosPicker(isPresented: $showLibrary, selection: $items, maxSelectionCount: max(1, remaining), matching: .images)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { data in add(data) }.ignoresSafeArea()
        }
        .onChange(of: items) { _, picked in
            guard !picked.isEmpty else { return }
            items = []
            Task {
                for item in picked {
                    if let data = try? await item.loadTransferable(type: Data.self) { add(data) }
                }
            }
        }
    }

    private func add(_ data: Data) {
        guard photos.count < CoachPhoto.maxCount, let photo = CoachPhoto.prepare(data) else { return }
        photos.append(photo)
    }
}

/// Vorschau der gewählten Fotos über dem Eingabefeld, jedes mit eigenem Entfernen-Knopf.
struct CoachPhotoStrip: View {
    @Binding var photos: [CoachPhoto]

    var body: some View {
        if !photos.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s3) {
                    ForEach(photos) { photo in
                        Image(uiImage: photo.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    photos.removeAll { $0.id == photo.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(Theme.textPrimary, Color.black.opacity(0.65))
                                        .font(.system(size: 22))
                                        .frame(width: 44, height: 44)
                                }
                                .offset(x: 12, y: -12)
                                .accessibilityLabel("Foto entfernen")
                            }
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel("Angehängtes Foto")
                    }
                }
                .padding(.horizontal, Space.page)
                .padding(.vertical, Space.s1)
            }
            .frame(height: 68)
        }
    }
}

/// Fotos in einer Nutzer-Blase.
struct CoachBubblePhotos: View {
    let photos: [CoachPhoto]

    var body: some View {
        let single = photos.count == 1
        LazyVGrid(columns: [GridItem(.adaptive(minimum: single ? 180 : 86), spacing: 6)], spacing: 6) {
            ForEach(photos) { photo in
                Image(uiImage: photo.image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: single ? 180 : 86)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                    .accessibilityLabel("Gesendetes Foto")
            }
        }
        .frame(maxWidth: 220)
    }
}

/// Kamera als Vollbild. Liefert das Foto als JPEG-Daten.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.9) {
                parent.onImage(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
