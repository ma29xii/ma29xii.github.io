import SwiftUI
import UIKit
import Vision
import VisionKit

struct FoodBarcodeScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onUnavailable: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode, onUnavailable: onUnavailable)
    }

    func makeUIViewController(context: Context) -> FoodCameraController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return FoodCameraController(scanner: scanner, onUnavailable: onUnavailable)
    }

    func updateUIViewController(_ controller: FoodCameraController, context: Context) {}

    static func dismantleUIViewController(_ controller: FoodCameraController, coordinator: Coordinator) {
        controller.scanner.stopScanning()
        controller.scanner.delegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        let onUnavailable: () -> Void
        private var delivered = false

        init(onCode: @escaping (String) -> Void, onUnavailable: @escaping () -> Void) {
            self.onCode = onCode
            self.onUnavailable = onUnavailable
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for item in addedItems {
                recognize(item, using: scanner)
            }
        }

        func dataScanner(_ scanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            recognize(item, using: scanner)
        }

        func dataScanner(_ scanner: DataScannerViewController,
                         becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            guard !delivered else { return }
            delivered = true
            onUnavailable()
        }

        private func recognize(_ item: RecognizedItem, using scanner: DataScannerViewController) {
            guard !delivered, case .barcode(let barcode) = item, let payload = barcode.payloadStringValue,
                  let code = FoodCatalog.barcode(payload, isUPCE: barcode.observation.symbology == .upce) else { return }
            delivered = true
            scanner.stopScanning()
            onCode(code)
        }
    }
}

final class FoodCameraController: UIViewController {
    let scanner: DataScannerViewController
    private let onUnavailable: () -> Void

    init(scanner: DataScannerViewController, onUnavailable: @escaping () -> Void) {
        self.scanner = scanner
        self.onUnavailable = onUnavailable
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { return nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(scanner)
        scanner.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scanner.view)
        NSLayoutConstraint.activate([
            scanner.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scanner.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scanner.view.topAnchor.constraint(equalTo: view.topAnchor),
            scanner.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        scanner.didMove(toParent: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        do {
            try scanner.startScanning()
        } catch {
            onUnavailable()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        scanner.stopScanning()
    }
}
