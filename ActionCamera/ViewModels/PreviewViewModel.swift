import AVFoundation
import Combine
import Photos
import SwiftUI

@MainActor
final class PreviewViewModel: ObservableObject {
    // MARK: - Published State

    @Published var overlayText = "Our Action Camera"
    @Published var overlayPosition: OverlayPosition = .top
    @Published var isExporting = false
    @Published var exportProgress: Float = 0
    @Published var exportedURL: URL?
    @Published var isSaved = false
    @Published var error: ExportError?
    @Published var videoAspectRatio: CGFloat?

    // MARK: - Properties

    let videoURL: URL
    private let exporter = VideoExporter()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Errors

    enum ExportError: LocalizedError, Equatable {
        case exportFailed(String)
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .exportFailed(let reason):
                return "Export failed: \(reason)"
            case .saveFailed(let reason):
                return "Save failed: \(reason)"
            }
        }
    }

    // MARK: - Init

    init(videoURL: URL) {
        self.videoURL = videoURL
        observeExporter()
        loadVideoAspectRatio()
    }

    private func loadVideoAspectRatio() {
        Task {
            let asset = AVURLAsset(url: videoURL)
            guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return }
            let size = try? await track.load(.naturalSize)
            let transform = try? await track.load(.preferredTransform)
            if let size, let transform {
                let transformed = size.applying(transform)
                let w = abs(transformed.width)
                let h = abs(transformed.height)
                if h > 0 {
                    self.videoAspectRatio = w / h
                }
            }
        }
    }

    private func observeExporter() {
        exporter.$progress
            .receive(on: DispatchQueue.main)
            .assign(to: &$exportProgress)

        exporter.$isExporting
            .receive(on: DispatchQueue.main)
            .assign(to: &$isExporting)
    }

    // MARK: - Export & Save

    func exportAndSave() {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .denied || status == .restricted {
            error = .saveFailed("Photo library access was denied. Please enable it in Settings.")
            return
        }

        exporter.exportWithOverlay(
            sourceURL: videoURL,
            overlayText: overlayText,
            position: overlayPosition
        ) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .success(let url):
                    self.exportedURL = url
                    await self.saveToPhotoLibrary(url: url)
                case .failure(let err):
                    self.error = .exportFailed(err.localizedDescription)
                }
            }
        }
    }

    private func saveToPhotoLibrary(url: URL) async {
        do {
            try await PhotoLibrarySaver.save(videoAt: url)
            isSaved = true
        } catch {
            self.error = .saveFailed(error.localizedDescription)
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        try? FileManager.default.removeItem(at: videoURL)
        if let exported = exportedURL {
            try? FileManager.default.removeItem(at: exported)
        }
    }

    func dismissError() {
        error = nil
    }
}
