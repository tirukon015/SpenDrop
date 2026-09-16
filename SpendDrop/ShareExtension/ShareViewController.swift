import UIKit
import SwiftUI
import UniformTypeIdentifiers

@objc(ShareViewController)
public class ShareViewController: UIViewController {

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        loadImageAndPresentUI()
    }

    private func loadImageAndPresentUI() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = extensionItem.attachments,
              !attachments.isEmpty else {
            dismissWithError("No attachments found.")
            return
        }

        let imageTypeIdentifier = UTType.image.identifier

        // Find the first attachment that conforms to image
        guard let provider = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(imageTypeIdentifier) }) else {
            dismissWithError("Shared item is not an image.")
            return
        }

        provider.loadItem(forTypeIdentifier: imageTypeIdentifier, options: nil) { [weak self] (item, error) in
            DispatchQueue.main.async {
                guard let self = self else { return }

                if let error = error {
                    self.dismissWithError("Failed to load image: \(error.localizedDescription)")
                    return
                }

                var resolvedImage: UIImage?

                if let image = item as? UIImage {
                    resolvedImage = image
                } else if let url = item as? URL {
                    if let data = try? Data(contentsOf: url) {
                        resolvedImage = UIImage(data: data)
                    }
                } else if let data = item as? Data {
                    resolvedImage = UIImage(data: data)
                }

                guard let image = resolvedImage else {
                    self.dismissWithError("Could not decode image from shared data.")
                    return
                }

                self.presentHostingController(with: image)
            }
        }
    }

    private func presentHostingController(with image: UIImage) {
        let extensionView = ShareExtensionView(
            inputImage: image,
            onComplete: { [weak self] in
                self?.completeAndDismiss()
            },
            onCancel: { [weak self] in
                self?.cancelAndDismiss()
            }
        )
        .modelContainer(ExpenseDataContainer.shared)

        let hostingController = UIHostingController(rootView: extensionView)
        addChild(hostingController)
        hostingController.view.frame = view.bounds
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)
    }

    private func completeAndDismiss() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func cancelAndDismiss() {
        let cancelError = NSError(domain: "com.spenddrop.share", code: NSUserCancelledError, userInfo: nil)
        extensionContext?.cancelRequest(withError: cancelError)
    }

    private func dismissWithError(_ message: String) {
        let alert = UIAlertController(title: "SpendDrop", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { [weak self] _ in
            self?.cancelAndDismiss()
        }))
        present(alert, animated: true, completion: nil)
    }
}
