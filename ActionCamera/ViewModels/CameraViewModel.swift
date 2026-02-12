import AVFoundation
import Combine
import SwiftUI

@MainActor
final class CameraViewModel: ObservableObject {
    // MARK: - Published State

    @Published var isRecording = false
    @Published var recordingTime: TimeInterval = 0
    @Published var error: CameraError?
    @Published var currentCameraPosition: AVCaptureDevice.Position = .back
    @Published var recordedVideoURL: URL?
    @Published var showPreview = false

    // MARK: - Properties

    let cameraManager = CameraManager()
    private var recordingTimer: Timer?
    private let maxRecordingDuration: TimeInterval = 10
    private var cancellables = Set<AnyCancellable>()

    var session: AVCaptureSession { cameraManager.session }

    // MARK: - Errors

    enum CameraError: LocalizedError, Equatable {
        case cameraUnavailable
        case permissionDenied
        case setupFailed(String)
        case recordingFailed(String)

        var errorDescription: String? {
            switch self {
            case .cameraUnavailable:
                return "Camera is not available on this device."
            case .permissionDenied:
                return "Camera or microphone permission was denied. Please enable it in Settings."
            case .setupFailed(let reason):
                return "Camera setup failed: \(reason)"
            case .recordingFailed(let reason):
                return "Recording failed: \(reason)"
            }
        }
    }

    // MARK: - Setup

    private var isSetUp = false

    func setup() async {
        guard !isSetUp else { return }
        isSetUp = true
        do {
            try await cameraManager.requestPermissionsAndSetup()
        } catch let err as CameraManager.CameraError {
            switch err {
            case .permissionDenied:
                error = .permissionDenied
            case .cameraUnavailable:
                error = .cameraUnavailable
            case .setupFailed(let reason):
                error = .setupFailed(reason)
            default:
                error = .setupFailed(err.localizedDescription)
            }
        } catch {
            self.error = .setupFailed(error.localizedDescription)
        }
    }

    // MARK: - Camera Switching

    func switchCamera() {
        guard !isRecording else { return }
        cameraManager.switchCamera()
        currentCameraPosition = cameraManager.currentPosition
    }

    // MARK: - Recording

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        guard cameraStatus == .authorized, micStatus == .authorized else {
            error = .permissionDenied
            return
        }

        cameraManager.startRecording { [weak self] result in
            Task { @MainActor [weak self] in
                self?.handleRecordingResult(result)
            }
        }
        isRecording = true
        startTimer()
    }

    private func stopRecording() {
        cameraManager.stopRecording()
    }

    private func handleRecordingResult(_ result: Result<URL, CameraManager.CameraError>) {
        isRecording = false
        stopTimer()

        switch result {
        case .success(let url):
            recordedVideoURL = url
            showPreview = true
        case .failure(let err):
            error = .recordingFailed(err.localizedDescription)
        }
    }

    // MARK: - Timer

    private func startTimer() {
        recordingTime = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.recordingTime += 0.1
                if self.recordingTime >= self.maxRecordingDuration {
                    self.recordingTimer?.invalidate()
                }
            }
        }
    }

    private func stopTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingTime = 0
    }

    // MARK: - Cleanup

    func clearRecording() {
        if let url = recordedVideoURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordedVideoURL = nil
        showPreview = false
    }

    func stopSession() {
        cameraManager.stopSession()
    }

    func dismissError() {
        error = nil
    }

    func formatTime(_ time: TimeInterval) -> String {
        let seconds = Int(time) % 60
        let tenths = Int(time * 10) % 10
        return String(format: "00:%02d.%d", seconds, tenths)
    }
}
