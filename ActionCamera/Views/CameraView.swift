import SwiftUI
import AVFoundation

struct CameraView: View {
    @StateObject private var viewModel = CameraViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                CameraPreviewView(session: viewModel.session)
                    .ignoresSafeArea()

                VStack {
                    topBar
                    Spacer()
                    bottomBar
                }
                .padding()
            }
            .task {
                await viewModel.setup()
            }
            .onChange(of: viewModel.error) { _, newValue in
                // Error alert is driven by the binding below
            }
            .alert("Error", isPresented: showErrorBinding) {
                if viewModel.error == .permissionDenied {
                    Button("Open Settings") {
                        viewModel.dismissError()
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    Button("Cancel", role: .cancel) {
                        viewModel.dismissError()
                    }
                } else {
                    Button("OK") { viewModel.dismissError() }
                }
            } message: {
                Text(viewModel.error?.localizedDescription ?? "An unknown error occurred.")
            }
            .navigationDestination(isPresented: $viewModel.showPreview) {
                PreviewView(videoURL: viewModel.recordedVideoURL ?? URL(fileURLWithPath: "")) {
                    viewModel.clearRecording()
                }
            }
        }
    }

    private var showErrorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.dismissError() } }
        )
    }

    // MARK: - Top Bar

    private var topBar: some View {
        VStack(spacing: 6) {
            Text(viewModel.isRecording ? "Recording" : "Action Camera")
                .font(.headline.weight(.bold))
                .foregroundStyle(viewModel.isRecording ? .red : .white)
                .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 2)

            if viewModel.isRecording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(.red)
                        .frame(width: 10, height: 10)

                    Text(viewModel.formatTime(viewModel.recordingTime))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .padding(.top, 50)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 20) {
            if viewModel.isRecording {
                ProgressView(value: viewModel.recordingTime, total: 10)
                    .tint(.red)
                    .scaleEffect(y: 2)
                    .padding(.horizontal)
            }

            ZStack {
                // Record button — always centered
                Button {
                    viewModel.toggleRecording()
                } label: {
                    ZStack {
                        Circle()
                            .strokeBorder(.white, lineWidth: 4)
                            .frame(width: 72, height: 72)

                        if viewModel.isRecording {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.red)
                                .frame(width: 28, height: 28)
                        } else {
                            Circle()
                                .fill(.red)
                                .frame(width: 60, height: 60)
                        }
                    }
                }

                // Switch camera — bottom right
                if !viewModel.isRecording {
                    HStack {
                        Spacer()
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                viewModel.switchCamera()
                            }
                        } label: {
                            Image(systemName: "camera.rotate.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .padding(12)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                    }
                }
            }
        }
        .padding(.bottom, 30)
    }

}
