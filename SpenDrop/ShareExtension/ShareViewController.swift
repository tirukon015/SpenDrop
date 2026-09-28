import UIKit
import SwiftUI
import UniformTypeIdentifiers

@objc(ShareViewController)
public class ShareViewController: UIViewController {

    private var hostingController: UIHostingController<AnyView>?
    private let viewModel = ShareExtensionViewModel()

    public override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        shareLog("[SpenDropShare][LIFECYCLE] ShareViewController init")
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        shareLog("[SpenDropShare][LIFECYCLE] ShareViewController init")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        shareLog("[SpenDropShare][LIFECYCLE] viewDidLoad")

        // Ensure default background matches system appearance (light/dark)
        view.backgroundColor = .systemBackground

        // Immediately create and attach root UI so the extension NEVER presents a black screen
        shareLog("[SpenDropShare][UI] SwiftUI root creation started")
        setupRootHostingController()
        shareLog("[SpenDropShare][UI] root view attached")

        // Asynchronously load the shared image using multi-strategy fallback
        loadImageAsync()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        shareLog("[SpenDropShare][LIFECYCLE] viewWillAppear")
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        shareLog("[SpenDropShare][LIFECYCLE] viewDidAppear")
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        shareLog("[SpenDropShare][LIFECYCLE] viewWillDisappear")
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        shareLog("[SpenDropShare][LIFECYCLE] viewDidDisappear")
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let hc = hostingController {
            hc.view.frame = view.bounds
            shareLog("[SpenDropShare][UI] hosting view frame = \(hc.view.frame)")
        }
    }

    private func setupRootHostingController() {
        let extensionRootView = ShareExtensionView(
            viewModel: viewModel,
            onComplete: { [weak self] in
                self?.completeAndDismiss()
            },
            onCancel: { [weak self] in
                self?.cancelAndDismiss()
            }
        )
        .modelContainer(ExpenseDataContainer.shared)

        let hc = UIHostingController(rootView: AnyView(extensionRootView))
        hc.view.backgroundColor = .systemBackground

        addChild(hc)
        view.addSubview(hc.view)

        // Sizing & Auto Layout synchronization
        hc.view.frame = view.bounds
        hc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hc.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hc.view.topAnchor.constraint(equalTo: view.topAnchor),
            hc.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hc.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hc.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        hc.didMove(toParent: self)
        self.hostingController = hc

        shareLog("[SpenDropShare][UI] UIHostingController created")
        shareLog("[SpenDropShare][UI] hosting view frame = \(hc.view.frame)")
    }

    private func loadImageAsync() {
        shareLog("[SpenDropShare][LIFECYCLE] extensionContext exists: \(extensionContext != nil)")

        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem else {
            shareLog("[SpenDropShare][IMAGE][ERROR] input item received: 0 (nil)")
            viewModel.phase = .error("No input item received from Share Sheet.")
            return
        }

        let inputItemsCount = extensionContext?.inputItems.count ?? 0
        shareLog("[SpenDropShare][IMAGE] input item received: \(inputItemsCount) items")

        guard let attachments = extensionItem.attachments, !attachments.isEmpty else {
            shareLog("[SpenDropShare][IMAGE][ERROR] attachments count: 0")
            viewModel.phase = .error("No attachments found in shared item.")
            return
        }

        shareLog("[SpenDropShare][IMAGE] attachments count: \(attachments.count)")
        for (i, att) in attachments.enumerated() {
            shareLog("[SpenDropShare][IMAGE] provider types = \(att.registeredTypeIdentifiers)")
        }

        shareLog("[SpenDropShare][IMAGE] image load started")
        viewModel.phase = .receiving

        Task { @MainActor in
            do {
                let (image, uti) = try await self.extractImageWithFallback(from: attachments)
                shareLog("[SpenDropShare][IMAGE] image load completed (size: \(image.size), uti: \(uti))")

                // Downsample image strictly with format.scale = 1.0 to keep memory < 30MB
                let finalImage = self.downsampleImageIfNeeded(image, maxDimension: 1280)

                self.viewModel.inputImage = finalImage
                self.viewModel.utiIdentifier = uti

                // Automatically start Vision OCR immediately upon image receipt
                self.viewModel.startAutomaticOCR(image: finalImage)
            } catch {
                shareLog("[SpenDropShare][IMAGE][ERROR] image load FAILED: \(error.localizedDescription)")
                self.viewModel.phase = .error("Failed to load shared image: \(error.localizedDescription)")
            }
        }
    }

    private func extractImageWithFallback(from attachments: [NSItemProvider]) async throws -> (UIImage, String) {
        let prioritizedUTIs = [
            UTType.png.identifier,
            UTType.jpeg.identifier,
            UTType.heic.identifier,
            UTType.image.identifier,
            UTType.fileURL.identifier,
            UTType.url.identifier,
            UTType.data.identifier
        ]

        var lastError: Error?

        for attachment in attachments {
            // Find best matching UTI for this provider
            var candidateUTIs: [String] = []

            // Check actual registered identifiers first
            for regUTI in attachment.registeredTypeIdentifiers {
                if candidateUTIs.contains(regUTI) { continue }
                if prioritizedUTIs.contains(regUTI) {
                    candidateUTIs.append(regUTI)
                } else if attachment.hasItemConformingToTypeIdentifier(regUTI) {
                    candidateUTIs.append(regUTI)
                }
            }

            // Append standard conforming UTIs
            for uti in prioritizedUTIs {
                if !candidateUTIs.contains(uti) && attachment.hasItemConformingToTypeIdentifier(uti) {
                    candidateUTIs.append(uti)
                }
            }

            shareLog("Evaluating candidate UTIs: \(candidateUTIs)")

            for uti in candidateUTIs {
                shareLog("Attempting load for UTI: \(uti)")

                // Strategy 1: loadItem(forTypeIdentifier:)
                if let image = await loadViaLoadItem(provider: attachment, typeIdentifier: uti) {
                    shareLog("SUCCESS via loadItem with UTI: \(uti)")
                    return (image, uti)
                }

                // Strategy 2: loadDataRepresentation(forTypeIdentifier:)
                if let image = await loadViaDataRepresentation(provider: attachment, typeIdentifier: uti) {
                    shareLog("SUCCESS via loadDataRepresentation with UTI: \(uti)")
                    return (image, uti)
                }

                // Strategy 3: loadFileRepresentation(forTypeIdentifier:)
                if let image = await loadViaFileRepresentation(provider: attachment, typeIdentifier: uti) {
                    shareLog("SUCCESS via loadFileRepresentation with UTI: \(uti)")
                    return (image, uti)
                }
            }
        }

        throw lastError ?? NSError(domain: "com.spendrop.share", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Could not decode an image from any of the shared representations."
        ])
    }

    private func loadViaLoadItem(provider: NSItemProvider, typeIdentifier: String) async -> UIImage? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { (item, error) in
                if let error = error {
                    shareLog("loadItem [\(typeIdentifier)] error: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }

                if let image = item as? UIImage {
                    continuation.resume(returning: image)
                    return
                }

                if let url = item as? URL {
                    let access = url.startAccessingSecurityScopedResource()
                    defer {
                        if access { url.stopAccessingSecurityScopedResource() }
                    }
                    if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                        continuation.resume(returning: img)
                        return
                    }
                }

                if let data = item as? Data, let img = UIImage(data: data) {
                    continuation.resume(returning: img)
                    return
                }

                continuation.resume(returning: nil)
            }
        }
    }

    private func loadViaDataRepresentation(provider: NSItemProvider, typeIdentifier: String) async -> UIImage? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { (data, error) in
                if let error = error {
                    shareLog("loadDataRepresentation [\(typeIdentifier)] error: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }
                guard let data = data, let image = UIImage(data: data) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: image)
            }
        }
    }

    private func loadViaFileRepresentation(provider: NSItemProvider, typeIdentifier: String) async -> UIImage? {
        await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { (url, error) in
                if let error = error {
                    shareLog("loadFileRepresentation [\(typeIdentifier)] error: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }
                guard let url = url else {
                    continuation.resume(returning: nil)
                    return
                }
                if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                    continuation.resume(returning: image)
                    return
                }
                continuation.resume(returning: nil)
            }
        }
    }

    private func downsampleImageIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension, maxSide > 0 else {
            return image
        }

        let scale = maxDimension / maxSide
        let newSize = CGSize(width: round(size.width * scale), height: round(size.height * scale))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private func completeAndDismiss() {
        shareLog("[SpenDropShare][OCR] completeAndDismiss called")
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func cancelAndDismiss() {
        shareLog("[SpenDropShare][OCR] cancelAndDismiss called")
        let cancelError = NSError(domain: "com.spendrop.share", code: NSUserCancelledError, userInfo: nil)
        extensionContext?.cancelRequest(withError: cancelError)
    }
}
