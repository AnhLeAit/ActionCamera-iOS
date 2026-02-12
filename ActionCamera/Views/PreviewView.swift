import SwiftUI
import AVKit

struct PreviewView: View {
    @StateObject private var viewModel: PreviewViewModel
    private let onDismiss: () -> Void

    @State private var showEditSheet = false

    init(videoURL: URL, onDismiss: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: PreviewViewModel(videoURL: videoURL))
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(spacing: 0) {
            videoPlayer
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomBar
        }
        .background(Color.black)
        .navigationTitle("Preview")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(viewModel.isExporting)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !viewModel.isExporting {
                    Button("Retake") {
                        viewModel.cleanup()
                        onDismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            editSheet
        }
        .alert("Saved!", isPresented: $viewModel.isSaved) {
            Button("Done") {
                viewModel.cleanup()
                onDismiss()
            }
        } message: {
            Text("Video has been saved to your photo library.")
        }
        .alert("Error", isPresented: showErrorBinding) {
            if case .saveFailed = viewModel.error {
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
            Text(viewModel.error?.localizedDescription ?? "An error occurred.")
        }
    }

    private var showErrorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.dismissError() } }
        )
    }

    // MARK: - Video Player

    @ViewBuilder
    private var videoPlayer: some View {
        let url = viewModel.exportedURL ?? viewModel.videoURL
        ZStack {
            VideoPlayerView(url: url)

            // Live overlay text preview (only before export)
            if viewModel.exportedURL == nil, !viewModel.overlayText.isEmpty {
                overlayPreview
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .padding()
    }

    // MARK: - Overlay Preview

    private var overlayPreview: some View {
        GeometryReader { geo in
            // Calculate the actual video content rect within the player
            let videoSize = videoContentSize(in: geo.size)
            let offsetX = (geo.size.width - videoSize.width) / 2
            let offsetY = (geo.size.height - videoSize.height) / 2

            let fontSize = videoSize.width * 0.05
            let verticalPadding = videoSize.height * 0.05
            let labelWidth = videoSize.width * 0.8

            VStack {
                if viewModel.overlayPosition == .top {
                    overlayLabel(fontSize: fontSize, maxWidth: labelWidth)
                        .padding(.top, verticalPadding)
                    Spacer()
                } else if viewModel.overlayPosition == .center {
                    Spacer()
                    overlayLabel(fontSize: fontSize, maxWidth: labelWidth)
                    Spacer()
                } else {
                    Spacer()
                    overlayLabel(fontSize: fontSize, maxWidth: labelWidth)
                        .padding(.bottom, verticalPadding)
                }
            }
            .frame(width: videoSize.width, height: videoSize.height)
            .offset(x: offsetX, y: offsetY)
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.3), value: viewModel.overlayPosition)
        .animation(.easeInOut(duration: 0.3), value: viewModel.overlayText)
    }

    private func videoContentSize(in containerSize: CGSize) -> CGSize {
        guard let ratio = viewModel.videoAspectRatio, ratio > 0 else {
            return containerSize
        }
        let containerRatio = containerSize.width / containerSize.height
        if containerRatio > ratio {
            // Container is wider — height fills, width is fitted
            let height = containerSize.height
            let width = height * ratio
            return CGSize(width: width, height: height)
        } else {
            // Container is taller — width fills, height is fitted
            let width = containerSize.width
            let height = width / ratio
            return CGSize(width: width, height: height)
        }
    }

    private func overlayLabel(fontSize: CGFloat, maxWidth: CGFloat) -> some View {
        Text(viewModel.overlayText)
            .font(.system(size: fontSize, weight: .bold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .frame(maxWidth: maxWidth)
            .shadow(color: .black.opacity(0.8), radius: 4, x: 2, y: 2)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 12) {
            if viewModel.isExporting {
                exportProgressView
            } else {
                // Summary of current overlay settings
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Overlay Text")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(viewModel.overlayText.isEmpty ? "No overlay" : "\"\(viewModel.overlayText)\"")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2)
                        Text(viewModel.overlayPosition.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        showEditSheet = true
                    } label: {
                        Label("Edit", systemImage: "slider.horizontal.3")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor)
                }

                Button {
                    viewModel.exportAndSave()
                } label: {
                    Label("Export & Save", systemImage: "square.and.arrow.down")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(viewModel.overlayText.isEmpty)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Edit Sheet

    private var editSheet: some View {
        VStack(spacing: 0) {
            Text("Overlay Settings")
                .font(.headline)
                .padding(.top, 24)
                .padding(.bottom, 16)

            VStack(spacing: 24) {
                overlayControls
            }
            .padding(.horizontal)

            Spacer()

            Button {
                showEditSheet = false
            } label: {
                Text("Done")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Overlay Controls

    private var overlayControls: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Overlay Text")
                    .foregroundStyle(.secondary)
                    .font(.headline)

                TextEditor(text: $viewModel.overlayText)
                    .font(.body)
                    .frame(minHeight: 80, maxHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray6))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Position")
                    .foregroundStyle(.secondary)
                    .font(.headline)

                Picker("Position", selection: $viewModel.overlayPosition) {
                    ForEach(OverlayPosition.allCases) { pos in
                        Text(pos.displayName)
                            .font(.title3)
                            .tag(pos)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.extraLarge)
            }
        }
    }

    // MARK: - Export Progress

    private var exportProgressView: some View {
        VStack(spacing: 12) {
            Text("Exporting...")
                .font(.headline)

            ProgressView(value: viewModel.exportProgress)
                .tint(.blue)

            Text("\(Int(viewModel.exportProgress * 100))%")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}
