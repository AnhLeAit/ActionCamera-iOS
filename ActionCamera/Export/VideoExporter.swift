import AVFoundation
import UIKit

@MainActor
final class VideoExporter: ObservableObject {
    // MARK: - Published State

    @Published var progress: Float = 0
    @Published var isExporting = false

    private var exportSession: AVAssetExportSession?
    private var progressTimer: Timer?

    // MARK: - Errors

    enum ExportError: Error, LocalizedError, Sendable {
        case compositionFailed(String)
        case exportFailed(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .compositionFailed(let reason):
                return "Failed to create composition: \(reason)"
            case .exportFailed(let reason):
                return "Export failed: \(reason)"
            case .cancelled:
                return "Export was cancelled."
            }
        }
    }

    // MARK: - Export with Overlay

    func exportWithOverlay(
        sourceURL: URL,
        overlayText: String,
        position: OverlayPosition,
        completion: @escaping @Sendable (Result<URL, ExportError>) -> Void
    ) {
        isExporting = true
        progress = 0

        let asset = AVURLAsset(url: sourceURL)
        let text = overlayText
        let pos = position

        // Create a sendable progress handler that captures no mutable state
        let progressHandler: @Sendable (Float) -> Void = { [weak self] value in
            Task { @MainActor in
                self?.progress = value
            }
        }

        let finishHandler: @Sendable (Bool) -> Void = { [weak self] _ in
            Task { @MainActor in
                self?.isExporting = false
            }
        }

        Task.detached {
            do {
                let result = try await Self.buildAndExport(
                    asset: asset,
                    overlayText: text,
                    position: pos,
                    onProgress: progressHandler
                )
                finishHandler(true)
                completion(.success(result))
            } catch let error as ExportError {
                finishHandler(false)
                completion(.failure(error))
            } catch {
                finishHandler(false)
                completion(.failure(.exportFailed(error.localizedDescription)))
            }
        }
    }

    // MARK: - Build Composition and Export (background)

    private nonisolated static func buildAndExport(
        asset: AVURLAsset,
        overlayText: String,
        position: OverlayPosition,
        onProgress: @escaping @Sendable (Float) -> Void
    ) async throws -> URL {
        let duration = try await asset.load(.duration)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw ExportError.compositionFailed("No video track found")
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let transformedSize = naturalSize.applying(preferredTransform)
        let videoSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))

        // Build composition
        let composition = AVMutableComposition()

        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ExportError.compositionFailed("Could not add video track")
        }

        let timeRange = CMTimeRange(start: .zero, duration: duration)
        try compositionVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)
        compositionVideoTrack.preferredTransform = preferredTransform

        // Audio
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if let audioTrack = audioTracks.first,
           let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try compositionAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
        }

        // Video composition with overlay
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = videoSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = timeRange

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        layerInstruction.setTransform(preferredTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        // Core Animation overlay layers
        let overlayLayer = Self.createOverlayLayer(
            text: overlayText,
            position: position,
            videoSize: videoSize
        )

        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: videoSize)

        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: videoSize)
        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(overlayLayer)

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        // Export
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("overlay_\(UUID().uuidString)")
            .appendingPathExtension("mov")

        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw ExportError.exportFailed("Could not create export session")
        }

        session.videoComposition = videoComposition

        // Track progress using a timer on a background queue
        nonisolated(unsafe) let exportSession = session
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler {
            onProgress(exportSession.progress)
        }
        timer.resume()

        do {
            try await session.export(to: outputURL, as: .mov)
            timer.cancel()
            return outputURL
        } catch {
            timer.cancel()
            if Task.isCancelled {
                throw ExportError.cancelled
            }
            throw ExportError.exportFailed(error.localizedDescription)
        }
    }

    // MARK: - Create Overlay Layer

    private nonisolated static func createOverlayLayer(
        text: String,
        position: OverlayPosition,
        videoSize: CGSize
    ) -> CALayer {
        let overlayLayer = CALayer()
        overlayLayer.frame = CGRect(origin: .zero, size: videoSize)

        let fontSize: CGFloat = videoSize.width * 0.05
        let font = UIFont.systemFont(ofSize: fontSize, weight: .bold)

        let textLayer = CATextLayer()
        textLayer.string = text
        textLayer.fontSize = fontSize
        textLayer.font = font
        textLayer.foregroundColor = UIColor.white.cgColor
        textLayer.shadowColor = UIColor.black.cgColor
        textLayer.shadowOffset = CGSize(width: 2, height: -2)
        textLayer.shadowOpacity = 0.8
        textLayer.shadowRadius = 4
        textLayer.alignmentMode = .center
        textLayer.contentsScale = UITraitCollection.current.displayScale
        textLayer.isWrapped = true
        textLayer.truncationMode = .end

        // Measure actual text height for multiline support
        let maxTextWidth = videoSize.width * 0.8
        let textBounds = (text as NSString).boundingRect(
            with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        let actualTextHeight = ceil(textBounds.height)
        let padding: CGFloat = videoSize.height * 0.05
        let bgWidth = maxTextWidth + 24
        let bgHeight = actualTextHeight + 24
        let bgX = (videoSize.width - bgWidth) / 2

        let yPosition: CGFloat
        switch position {
        case .top:
            yPosition = videoSize.height - padding - bgHeight
        case .center:
            yPosition = (videoSize.height - bgHeight) / 2
        case .bottom:
            yPosition = padding
        }

        // Background
        let backgroundLayer = CALayer()
        let accentColor = UIColor(named: "AccentColor") ?? UIColor(red: 0.686, green: 0.290, blue: 0.878, alpha: 1.0)
        backgroundLayer.backgroundColor = accentColor.withAlphaComponent(0.7).cgColor
        backgroundLayer.cornerRadius = 8
        backgroundLayer.frame = CGRect(x: bgX, y: yPosition, width: bgWidth, height: bgHeight)

        // Text — vertically centered inside background
        let textY = yPosition + (bgHeight - actualTextHeight) / 2
        textLayer.frame = CGRect(
            x: bgX,
            y: textY,
            width: bgWidth,
            height: actualTextHeight
        )

        overlayLayer.addSublayer(backgroundLayer)
        overlayLayer.addSublayer(textLayer)

        // Fade-in animation
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0.0
        fadeIn.toValue = 1.0
        fadeIn.beginTime = AVCoreAnimationBeginTimeAtZero
        fadeIn.duration = 0.8
        fadeIn.fillMode = .forwards
        fadeIn.isRemovedOnCompletion = false

        backgroundLayer.add(fadeIn, forKey: "fadeIn")
        textLayer.add(fadeIn, forKey: "fadeIn")

        // Slide-in animation
        let bgFinalY = yPosition + bgHeight / 2
        let slideOffset: CGFloat = position == .bottom ? -30 : 30

        let bgSlide = CABasicAnimation(keyPath: "position.y")
        bgSlide.fromValue = bgFinalY + slideOffset
        bgSlide.toValue = bgFinalY
        bgSlide.beginTime = AVCoreAnimationBeginTimeAtZero
        bgSlide.duration = 0.6
        bgSlide.timingFunction = CAMediaTimingFunction(name: .easeOut)
        bgSlide.fillMode = .forwards
        bgSlide.isRemovedOnCompletion = false
        backgroundLayer.add(bgSlide, forKey: "slideIn")

        let textFinalY = textY + actualTextHeight / 2
        let textSlide = CABasicAnimation(keyPath: "position.y")
        textSlide.fromValue = textFinalY + slideOffset
        textSlide.toValue = textFinalY
        textSlide.beginTime = AVCoreAnimationBeginTimeAtZero
        textSlide.duration = 0.6
        textSlide.timingFunction = CAMediaTimingFunction(name: .easeOut)
        textSlide.fillMode = .forwards
        textSlide.isRemovedOnCompletion = false
        textLayer.add(textSlide, forKey: "slideIn")

        return overlayLayer
    }
}
