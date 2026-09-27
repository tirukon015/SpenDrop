import UIKit

public struct ImageStorageService {
    public static let shared = ImageStorageService()

    private let folderName = "SpenDropReceipts"
    private let legacyFolderName = "SpendDropReceipts"

    private init() {
        createFolderIfNeeded()
    }

    private var storageDirectory: URL {
        let appGroupIdentifier = ExpenseDataContainer.appGroupIdentifier
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return containerURL.appendingPathComponent(folderName, isDirectory: true)
        } else {
            let docURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            return docURL.appendingPathComponent(folderName, isDirectory: true)
        }
    }

    private func createFolderIfNeeded() {
        let folderURL = storageDirectory
        if !FileManager.default.fileExists(atPath: folderURL.path) {
            try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
        }
    }

    /// Saves a UIImage to disk as compressed JPEG (0.8 quality) and returns the relative path
    public func saveImage(_ image: UIImage, id: UUID = UUID()) -> String? {
        createFolderIfNeeded()
        let filename = "\(id.uuidString).jpg"
        let fileURL = storageDirectory.appendingPathComponent(filename)

        guard let data = image.jpegData(compressionQuality: 0.8) else {
            return nil
        }

        do {
            try data.write(to: fileURL)
            return filename
        } catch {
            print("Failed to save receipt image: \(error)")
            return nil
        }
    }

    /// Loads a UIImage from the relative path
    public func loadImage(relativePath: String) -> UIImage? {
        let fileURL = storageDirectory.appendingPathComponent(relativePath)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return UIImage(contentsOfFile: fileURL.path)
        }
        // Fallback check in documents directory
        let docURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent(relativePath)
        if FileManager.default.fileExists(atPath: docURL.path) {
            return UIImage(contentsOfFile: docURL.path)
        }
        // Legacy folder checks (App Group and Documents)
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.spenddrop.shared") {
            let legacyAppGroupURL = containerURL.appendingPathComponent(legacyFolderName, isDirectory: true).appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: legacyAppGroupURL.path) {
                return UIImage(contentsOfFile: legacyAppGroupURL.path)
            }
        }
        let legacyDocURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(legacyFolderName, isDirectory: true)
            .appendingPathComponent(relativePath)
        return UIImage(contentsOfFile: legacyDocURL.path)
    }

    /// Deletes the image from disk
    public func deleteImage(relativePath: String) {
        let fileURL = storageDirectory.appendingPathComponent(relativePath)
        try? FileManager.default.removeItem(at: fileURL)
    }
}
