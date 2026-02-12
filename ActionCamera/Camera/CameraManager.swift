import UIKit
@preconcurrency import AVFoundation

/// Service layer for AVFoundation camera operations.
/// Isolated to @MainActor since AVCaptureSession configuration must happen on a consistent thread.
@MainActor
final class CameraManager: NSObject {
    // MARK: - Properties

    nonisolated(unsafe) let session = AVCaptureSession()
    private(set) var currentPosition: AVCaptureDevice.Position = .back
    private var videoOutput: AVCaptureMovieFileOutput?
    private var recordingCompletion: (@Sendable (Result<URL, CameraError>) -> Void)?
    private let sessionQueue = DispatchQueue(label: "com.actioncamera.session")

    // MARK: - Errors

    enum CameraError: Error, LocalizedError, Sendable {
        case cameraUnavailable
        case permissionDenied
        case setupFailed(String)
        case recordingFailed(String)

        var errorDescription: String? {
            switch self {
            case .cameraUnavailable:
                return "Camera is not available on this device."
            case .permissionDenied:
                return "Camera or microphone permission was denied."
            case .setupFailed(let reason):
                return "Camera setup failed: \(reason)"
            case .recordingFailed(let reason):
                return "Recording failed: \(reason)"
            }
        }
    }

    // MARK: - Setup

    func requestPermissionsAndSetup() async throws {
        let cameraGranted = await Self.requestPermission(for: .video)
        guard cameraGranted else { throw CameraError.permissionDenied }

        let micGranted = await Self.requestPermission(for: .audio)
        guard micGranted else { throw CameraError.permissionDenied }

        configureSession()
    }

    private static func requestPermission(for mediaType: AVMediaType) async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: mediaType)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: mediaType)
        default:
            return false
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .high

        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        // Video input
        guard let videoDevice = Self.camera(for: currentPosition) else {
            session.commitConfiguration()
            return
        }

        do {
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
            }
        } catch {
            session.commitConfiguration()
            return
        }

        // Audio input
        if let audioDevice = AVCaptureDevice.default(for: .audio) {
            if let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
               session.canAddInput(audioInput) {
                session.addInput(audioInput)
            }
        }

        // Movie output
        let movieOutput = AVCaptureMovieFileOutput()
        movieOutput.maxRecordedDuration = CMTime(seconds: 10, preferredTimescale: 600)
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
            videoOutput = movieOutput
        }

        session.commitConfiguration()

        sessionQueue.async { [session] in
            session.startRunning()
        }
    }

    private static func camera(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: position
        ).devices.first
    }

    // MARK: - Camera Switching

    func switchCamera() {
        let newPosition: AVCaptureDevice.Position = (currentPosition == .back) ? .front : .back
        guard let newDevice = Self.camera(for: newPosition) else { return }

        session.beginConfiguration()

        if let currentInput = session.inputs
            .compactMap({ $0 as? AVCaptureDeviceInput })
            .first(where: { $0.device.hasMediaType(.video) }) {
            session.removeInput(currentInput)
        }

        if let newInput = try? AVCaptureDeviceInput(device: newDevice),
           session.canAddInput(newInput) {
            session.addInput(newInput)
            currentPosition = newPosition
        }

        session.commitConfiguration()
    }

    // MARK: - Recording

    func startRecording(completion: @escaping @Sendable (Result<URL, CameraError>) -> Void) {
        guard let output = videoOutput else { return }

        recordingCompletion = completion

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        output.startRecording(to: tempURL, recordingDelegate: self)
    }

    func stopRecording() {
        videoOutput?.stopRecording()
    }

    func stopSession() {
        sessionQueue.async { [session] in
            session.stopRunning()
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        // Recording started — ViewModel handles UI state via its own timer
    }

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let completion = self.recordingCompletion
            self.recordingCompletion = nil

            if let error {
                let nsError = error as NSError
                if nsError.domain == AVFoundationErrorDomain,
                   nsError.code == AVError.maximumDurationReached.rawValue {
                    completion?(.success(outputFileURL))
                } else {
                    completion?(.failure(.recordingFailed(error.localizedDescription)))
                }
            } else {
                completion?(.success(outputFileURL))
            }
        }
    }
}
