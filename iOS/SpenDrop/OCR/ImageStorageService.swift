import UIKit
import ImageIO
import UniformTypeIdentifiers
import SwiftData

public struct ImageStorageService {
    public static let shared = ImageStorageService()

    private let folderName = "SpenDropReceipts"
    private let legacyFolderName = "SpendDropReceipts"
    /// Set only for tests/tools; the shared instance uses the App Group folder with its fallbacks.
    private let customDirectory: URL?

    private init() {
        customDirectory = nil
        createFolderIfNeeded()
    }

    /// A store rooted at `directory` (no fallback folders). Used by the in-app tests.
    public init(directory: URL) {
        customDirectory = directory
        createFolderIfNeeded()
    }

    public var storageDirectory: URL {
        if let customDirectory { return customDirectory }
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

    /// Optimizes the image (see `ScreenshotOptimizer`), writes it atomically and returns the file name that
    /// SwiftData stores in `Expense.imageRelativePath` (e.g. "<UUID>.heic"). The image bytes never go into SwiftData.
    public func saveImage(_ image: UIImage, id: UUID = UUID()) -> String? {
        createFolderIfNeeded()
        guard let output = ScreenshotOptimizer.optimize(image) else {
            return nil
        }
        let filename = "\(id.uuidString).\(output.fileExtension)"
        let fileURL = storageDirectory.appendingPathComponent(filename)

        do {
            try output.data.write(to: fileURL, options: .atomic)
            return filename
        } catch {
            print("Failed to save receipt image: \(error)")
            return nil
        }
    }

    /// Folders searched for an existing file, primary first (fallbacks only for the shared store).
    private var searchDirectories: [URL] {
        guard customDirectory == nil else { return [storageDirectory] }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var dirs = [storageDirectory, documents.appendingPathComponent(folderName, isDirectory: true)]
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.spenddrop.shared") {
            dirs.append(containerURL.appendingPathComponent(legacyFolderName, isDirectory: true))
        }
        dirs.append(documents.appendingPathComponent(legacyFolderName, isDirectory: true))
        return dirs
    }

    /// The file for a stored reference. If the exact name is gone because the screenshot was optimized
    /// (e.g. an older backup still says "<id>.jpg" but the file is now "<id>.heic"), the optimized copy is used.
    public func resolveURL(relativePath: String) -> URL? {
        let stem = (relativePath as NSString).deletingPathExtension
        let candidates = [relativePath] + ScreenshotOptimizer.optimizedNames(forStem: stem).filter { $0 != relativePath }
        for name in candidates {
            for dir in searchDirectories {
                let url = dir.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: url.path) { return url }
            }
        }
        return nil
    }

    /// Loads a UIImage from the relative path
    public func loadImage(relativePath: String) -> UIImage? {
        guard let url = resolveURL(relativePath: relativePath) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    /// Deletes the image from disk
    public func deleteImage(relativePath: String) {
        let fileURL = storageDirectory.appendingPathComponent(relativePath)
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Count and total size of the screenshot files referenced by `relativePaths` (missing files are not counted).
    public func storageStats(relativePaths: [String]) -> (count: Int, totalBytes: Int64) {
        var seen = Set<URL>()
        var total: Int64 = 0
        for path in relativePaths {
            guard let url = resolveURL(relativePath: path), seen.insert(url).inserted else { continue }
            total += ScreenshotOptimizer.fileSize(url)
        }
        return (seen.count, total)
    }
}

// MARK: - Screenshot optimization (ImageIO / Core Graphics only, fully on-device)

/// Turns a payment screenshot into a small, readable file.
///
/// The image is resized once from the original (only when larger than `maxLongEdge`), then encoded at a few
/// decreasing qualities until it fits `targetBytes`. Every attempt starts from that same rendering, never from a
/// previous compressed result, so trying more qualities cannot stack compression damage. If even the lowest
/// quality is too big, one smaller size (`minLongEdge`) is tried; below that readability wins over the target.
public enum ScreenshotOptimizer {
    public struct Settings {
        public var maxLongEdge: CGFloat = 1800
        /// Readability floor: never resized below this (OCR itself works at 1280 px).
        public var minLongEdge: CGFloat = 1440
        public var targetBytes = 150 * 1024
        public var qualities: [CGFloat] = [0.72, 0.62, 0.52, 0.45]
        public var preferHEIC = true
        public init() {}
    }

    public struct Output {
        public let data: Data
        public let fileExtension: String
        public let quality: CGFloat
        public let pixelSize: CGSize
    }

    /// HEIC when the device can encode it (iPhone XS and later), otherwise JPEG. PNG is never used.
    public static var canEncodeHEIC: Bool {
        let types = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
        return types.contains(UTType.heic.identifier)
    }

    /// Names an optimized copy of `<stem>` may have.
    static func optimizedNames(forStem stem: String) -> [String] {
        ["\(stem).heic", "\(stem)-opt.jpg"]
    }

    public static func optimize(_ image: UIImage, settings: Settings = Settings()) -> Output? {
        let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let originalLongEdge = max(pixelSize.width, pixelSize.height)
        guard originalLongEdge > 0 else { return nil }
        return search(originalLongEdge: originalLongEdge, settings: settings) { longEdge in
            render(image, pixelSize: pixelSize, longEdge: longEdge)
        }
    }

    /// Optimizes an existing file, reading it through ImageIO (downsampled while decoding, low memory).
    public static func optimize(fileAt url: URL, settings: Settings = Settings()) -> Output? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let size = pixelSize(of: source) else { return nil }
        let originalLongEdge = max(size.width, size.height)
        return search(originalLongEdge: originalLongEdge, settings: settings) { longEdge in
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(longEdge.rounded())
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }
    }

    /// Pixel size of a decodable image file, or nil when the file cannot be read as an image.
    public static func decodedPixelSize(at url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width > 0, image.height > 0 else { return nil }
        return CGSize(width: image.width, height: image.height)
    }

    static func fileSize(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private static func search(originalLongEdge: CGFloat, settings: Settings,
                               render: (CGFloat) -> CGImage?) -> Output? {
        let useHEIC = settings.preferHEIC && canEncodeHEIC
        var edges = [min(originalLongEdge, settings.maxLongEdge)]
        if settings.minLongEdge < edges[0] { edges.append(settings.minLongEdge) }

        var smallest: Output?
        for edge in edges {
            guard let cgImage = autoreleasepool(invoking: { render(edge) }) else { continue }
            for quality in settings.qualities {
                guard let data = encode(cgImage, quality: quality, heic: useHEIC) else { continue }
                let output = Output(data: data, fileExtension: useHEIC ? "heic" : "jpg", quality: quality,
                                    pixelSize: CGSize(width: cgImage.width, height: cgImage.height))
                if data.count <= settings.targetBytes { return output }
                if smallest == nil || data.count < smallest!.data.count { smallest = output }
            }
        }
        return smallest
    }

    private static func render(_ image: UIImage, pixelSize: CGSize, longEdge: CGFloat) -> CGImage? {
        let scale = min(1, longEdge / max(pixelSize.width, pixelSize.height))
        let target = CGSize(width: max(1, (pixelSize.width * scale).rounded()), height: max(1, (pixelSize.height * scale).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: target))
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.cgImage
    }

    private static func encode(_ image: CGImage, quality: CGFloat, heic: Bool) -> Data? {
        let data = NSMutableData()
        let type = (heic ? UTType.heic : UTType.jpeg).identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(data, type, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private static func pixelSize(of source: CGImageSource) -> CGSize? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = props[kCGImagePropertyPixelHeight] as? NSNumber,
              width.intValue > 0, height.intValue > 0 else { return nil }
        return CGSize(width: width.doubleValue, height: height.doubleValue)
    }
}

// MARK: - Optimizing screenshots saved before this change (user-triggered, restart-safe)

public enum ScreenshotStorageMigrator {
    public struct Report: Equatable {
        /// Distinct screenshot files referenced by expenses.
        public var checked = 0
        public var optimized = 0
        public var alreadySmall = 0
        public var keptOriginal = 0
        public var missing = 0
        public var bytesBefore: Int64 = 0
        public var bytesAfter: Int64 = 0
        public init() {}
    }

    /// Files at or below this size are left alone, which also keeps already-optimized files from being re-encoded
    /// (decided by the file's real size, not its name or extension).
    public static let skipBelowBytes: Int64 = 200 * 1024

    private enum Step {
        case done(Report.Field)
        case encode(source: URL, sizeBefore: Int64, stem: String)
        case reuse(source: URL, sizeBefore: Int64, copy: URL)
    }

    /// For every referenced screenshot larger than `skipBelowBytes`:
    /// write an optimized copy next to it → check it decodes and is smaller and within the size limit → point the
    /// Expense(s) at it and save → only then delete the old file. Any failure keeps the original file and reference.
    /// Re-running after an interruption reuses a finished copy and removes an old file left behind.
    @MainActor
    public static func optimizeExisting(in context: ModelContext, storage: ImageStorageService = .shared,
                                        settings: ScreenshotOptimizer.Settings = .init()) -> Report {
        var report = Report()
        let items = referencedFiles(in: context)
        let referenced = Set(items.map(\.0))
        report.checked = items.count
        for (path, owners) in items {
            switch step(for: path, storage: storage, referenced: referenced) {
            case .done(let field): report.add(field)
            case .reuse(let source, let size, let copy):
                commit(path: path, owners: owners, source: source, sizeBefore: size, copy: copy, settings: settings, context: context, report: &report)
            case .encode(let source, let size, let stem):
                let output = ScreenshotOptimizer.optimize(fileAt: source, settings: settings)
                let copy = write(output, stem: stem, source: source, sizeBefore: size)
                commit(path: path, owners: owners, source: source, sizeBefore: size, copy: copy, settings: settings, context: context, report: &report)
            }
        }
        return report
    }

    /// Same as above, one file at a time with image encoding off the main thread, reporting progress
    /// (`done`, `total`) so the UI stays responsive. Used before every cloud backup.
    @MainActor
    public static func optimizeExisting(in context: ModelContext, storage: ImageStorageService = .shared,
                                        settings: ScreenshotOptimizer.Settings = .init(),
                                        progress: @escaping @MainActor (Int, Int) -> Void) async -> Report {
        var report = Report()
        let items = referencedFiles(in: context)
        let referenced = Set(items.map(\.0))
        report.checked = items.count
        progress(0, items.count)
        for (index, (path, owners)) in items.enumerated() {
            if Task.isCancelled { break }
            switch step(for: path, storage: storage, referenced: referenced) {
            case .done(let field): report.add(field)
            case .reuse(let source, let size, let copy):
                commit(path: path, owners: owners, source: source, sizeBefore: size, copy: copy, settings: settings, context: context, report: &report)
            case .encode(let source, let size, let stem):
                let output = await Task.detached(priority: .utility) { ScreenshotOptimizer.optimize(fileAt: source, settings: settings) }.value
                let copy = write(output, stem: stem, source: source, sizeBefore: size)
                commit(path: path, owners: owners, source: source, sizeBefore: size, copy: copy, settings: settings, context: context, report: &report)
            }
            progress(index + 1, items.count)
            await Task.yield()
        }
        return report
    }

    // MARK: Steps

    @MainActor
    private static func referencedFiles(in context: ModelContext) -> [(String, [Expense])] {
        let expenses = (try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.imageRelativePath != nil }))) ?? []
        let byPath = Dictionary(grouping: expenses.filter { !($0.imageRelativePath ?? "").isEmpty }, by: { $0.imageRelativePath! })
        return byPath.sorted(by: { $0.key < $1.key }).map { ($0.key, $0.value) }
    }

    private static func step(for path: String, storage: ImageStorageService, referenced: Set<String>) -> Step {
        let fm = FileManager.default
        guard let url = resolveExact(path, storage: storage) else {
            // Already optimized earlier (exact name gone, optimized copy present) or truly missing.
            return .done(storage.resolveURL(relativePath: path) == nil ? .missing : .alreadySmall)
        }
        let sizeBefore = ScreenshotOptimizer.fileSize(url)
        if sizeBefore <= skipBelowBytes {
            removeLeftoverOriginal(for: path, storage: storage, referenced: referenced)
            return .done(.alreadySmall)
        }
        let stem = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            .replacingOccurrences(of: "-opt", with: "")
        let directory = url.deletingLastPathComponent()
        if let copy = ScreenshotOptimizer.optimizedNames(forStem: stem).map({ directory.appendingPathComponent($0) })
            .first(where: { $0 != url && fm.fileExists(atPath: $0.path) && ScreenshotOptimizer.decodedPixelSize(at: $0) != nil }) {
            return .reuse(source: url, sizeBefore: sizeBefore, copy: copy)
        }
        return .encode(source: url, sizeBefore: sizeBefore, stem: stem)
    }

    /// Writes the optimized copy next to the original under a new name; nil if it isn't an improvement or can't be written.
    private static func write(_ output: ScreenshotOptimizer.Output?, stem: String, source: URL, sizeBefore: Int64) -> URL? {
        guard let output, Int64(output.data.count) < sizeBefore else { return nil }
        let name = output.fileExtension == "heic" ? "\(stem).heic" : "\(stem)-opt.jpg"
        let candidate = source.deletingLastPathComponent().appendingPathComponent(name)
        guard candidate != source, (try? output.data.write(to: candidate, options: .atomic)) != nil else { return nil }
        return candidate
    }

    /// Verifies the copy, saves the new reference, then deletes the original. Any failure keeps the original.
    @MainActor
    private static func commit(path: String, owners: [Expense], source: URL, sizeBefore: Int64, copy: URL?,
                               settings: ScreenshotOptimizer.Settings, context: ModelContext, report: inout Report) {
        guard let copy, let pixels = ScreenshotOptimizer.decodedPixelSize(at: copy),
              max(pixels.width, pixels.height) <= max(settings.maxLongEdge, 1) + 1,
              ScreenshotOptimizer.fileSize(copy) < sizeBefore else {
            report.keptOriginal += 1
            return
        }
        let newPath = (path as NSString).deletingLastPathComponent.isEmpty
            ? copy.lastPathComponent
            : ((path as NSString).deletingLastPathComponent as NSString).appendingPathComponent(copy.lastPathComponent)
        owners.forEach { $0.imageRelativePath = newPath }
        do {
            try context.save()
        } catch {
            owners.forEach { $0.imageRelativePath = path }
            report.keptOriginal += 1
            return
        }
        try? FileManager.default.removeItem(at: source)
        report.optimized += 1
        report.bytesBefore += sizeBefore
        report.bytesAfter += ScreenshotOptimizer.fileSize(copy)
    }

    /// The file stored under exactly this name (no optimized-copy fallback).
    private static func resolveExact(_ path: String, storage: ImageStorageService) -> URL? {
        guard let url = storage.resolveURL(relativePath: path), url.lastPathComponent == (path as NSString).lastPathComponent else { return nil }
        return url
    }

    /// After an interruption between "reference saved" and "old file deleted", the old "<stem>.jpg" remains.
    /// It is removed only when no expense references it and the optimized file it was replaced by decodes.
    private static func removeLeftoverOriginal(for path: String, storage: ImageStorageService, referenced: Set<String>) {
        let name = (path as NSString).lastPathComponent
        guard name.hasSuffix(".heic") || name.hasSuffix("-opt.jpg"),
              let current = storage.resolveURL(relativePath: path),
              ScreenshotOptimizer.decodedPixelSize(at: current) != nil else { return }
        let stem = (name as NSString).deletingPathExtension.replacingOccurrences(of: "-opt", with: "")
        let oldName = "\(stem).jpg"
        let oldPath = ((path as NSString).deletingLastPathComponent as NSString).appendingPathComponent(oldName)
        guard !referenced.contains(oldName), !referenced.contains(oldPath) else { return }
        let oldURL = current.deletingLastPathComponent().appendingPathComponent(oldName)
        if oldURL != current { try? FileManager.default.removeItem(at: oldURL) }
    }
}

extension ScreenshotStorageMigrator.Report {
    enum Field { case alreadySmall, missing }
    mutating func add(_ field: Field) {
        switch field {
        case .alreadySmall: alreadySmall += 1
        case .missing: missing += 1
        }
    }
}
