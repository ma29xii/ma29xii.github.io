import SwiftUI
import UIKit
import ImageIO

struct ProfileButton: View {
    @Environment(AppState.self) private var app

    var body: some View {
        Button { app.showProfile = true } label: {
            ProfileAvatar(image: app.profilePhoto, size: 32)
        }
        .accessibilityLabel("Profil und Einstellungen")
    }
}

struct ProfileAvatar: View {
    let image: UIImage?
    let size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                // Ohne Bild: ruhiger Graphit-Kreis mit Silhouette statt leerem Umriss.
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.46, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: size, height: size)
                    .background(Circle().fill(Theme.cardRaised))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75))
        .accessibilityHidden(true)
    }
}

@MainActor
enum ProfilePhotoStore {
    enum PhotoError: Error { case invalidImage }

    static func load() -> UIImage? {
        guard let url = try? fileURL(createDirectory: false) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    static func save(_ data: Data) throws -> UIImage {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 256
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            throw PhotoError.invalidImage
        }
        let image = UIImage(cgImage: thumbnail)
        guard let compressed = image.jpegData(compressionQuality: 0.88) else { throw PhotoError.invalidImage }
        try compressed.write(to: fileURL(createDirectory: true), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return image
    }

    static func remove() throws {
        let url = try fileURL(createDirectory: false)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    private static func fileURL(createDirectory: Bool) throws -> URL {
        let manager = FileManager.default
        let support = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: createDirectory)
        var directory = support.appendingPathComponent("FormaProfile", isDirectory: true)
        if createDirectory {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            var resources = URLResourceValues()
            resources.isExcludedFromBackup = true
            try directory.setResourceValues(resources)
        }
        return directory.appendingPathComponent("avatar.jpg")
    }
}
