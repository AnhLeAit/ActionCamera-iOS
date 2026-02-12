# ActionCamera

This is a simple iOS app that captures short video clips (up to 10 seconds), applies a customizable text overlay with animation, and saves the result to the photo library.

## Demo

| App Demo | Exported Video with Overlay |
| :---: | :---: |
| [Demo-ActionCamera.mp4](Demo/Demo-ActionCamera.mp4) | [overlay.MOV](Demo/overlay_85CF669E-BE8A-4CFB-9135-AC5AC1B0F594.MOV) |

## Architecture

**MVVM** with SwiftUI, Combine, and Swift 6 strict concurrency:

```
ActionCamera/
├── App/                  # App entry point, root ContentView
├── Camera/               # AVFoundation service layer
│   ├── CameraManager     # AVCaptureSession setup, recording, camera switching
│   └── CameraPreviewView # UIViewRepresentable for live preview
├── Export/               # Video processing pipeline
│   ├── VideoExporter     # AVMutableComposition + overlay compositing
│   └── PhotoLibrarySaver # PHPhotoLibrary save helper
├── Models/               # Data models
│   └── OverlayPosition   # Enum for top/center/bottom placement
├── ViewModels/           # MVVM view models
│   ├── CameraViewModel   # Camera state, recording timer, permission checks
│   └── PreviewViewModel  # Export flow, overlay config, photo library permission
└── Views/                # SwiftUI views (thin, declarative)
    ├── CameraView        # Live camera preview + record controls
    ├── PreviewView       # Video playback + overlay settings + export
    └── VideoPlayerView   # AVPlayerViewController wrapper with auto-loop
```

## Key Decisions

### Concurrency Model
- **`@MainActor`** isolation on ViewModels and CameraManager ensures all UI state mutations happen on the main thread
- **`nonisolated(unsafe)`** used for `AVCaptureSession` since it must be accessed from both main and background threads (session start/stop runs on a dedicated serial queue)
- **`nonisolated static`** functions for heavy export work (`buildAndExport`, `createOverlayLayer`) to keep video processing off the main actor
- **`@Sendable`** closures for cross-isolation-boundary callbacks
- **`@preconcurrency import AVFoundation`** to silence Sendable conformance warnings on AVFoundation types
- Full **Swift 6 strict concurrency** compliance — zero warnings

### AVFoundation Approach
- **`AVCaptureMovieFileOutput`** for recording with built-in `maxRecordedDuration` for the 10-second limit (auto-stop handled at the framework level)
- **`AVMutableComposition` + `AVMutableVideoComposition`** with Core Animation layers for the text overlay — this allows fade-in and slide animations via `CABasicAnimation`
- **`AVVideoCompositionCoreAnimationTool`** bridges Core Animation into the video render pipeline
- **iOS 18 `export(to:as:)` API** used instead of the deprecated `exportAsynchronously` for cleaner async/await integration

### Overlay System
- **Multiline text support**: Uses `NSString.boundingRect` to dynamically calculate text height for multi-line overlays, with `CATextLayer.isWrapped = true`
- Combined **fade-in** (opacity 0→1 over 0.8s) and **slide-in** (position offset over 0.6s with easeOut) for a polished entrance
- **AccentColor** background with 70% opacity for brand-consistent overlay styling
- Animation direction adapts to overlay position (slides down from top, up from bottom)
- **Live preview** on the video player before export — overlay scales proportionally to match the actual video content area using aspect ratio detection

### Permission Handling
- **Camera/Microphone**: Checked before recording starts — shows alert with "Open Settings" button if denied
- **Photo Library**: Checked before export begins — prevents wasted export time when save will fail
- Both permission alerts offer direct navigation to iOS Settings for easy re-authorization

### Video Player
- **Auto-play with infinite looping** via `NotificationCenter` observer on `AVPlayerItemDidPlayToEndTime`
- Playback controls visible for user pause/play interaction
- Proper cleanup on dismissal — player paused, current item replaced with nil, observers removed

## Trade-offs

- **`AVAssetExportPresetHighestQuality`**: Prioritizes quality over file size/speed. For production, might offer quality options
- **Timer-based recording countdown**: Uses `Timer` with 0.1s intervals for the UI counter. For frame-accurate timing, could use `CMSampleBuffer` timestamps instead
- **No video trimming**: If the user records 10 seconds but only wants 5, they can't trim. Would add a timeline scrubber with more time
- **Overlay preview approximation**: The SwiftUI overlay preview uses `GeometryReader` with aspect ratio calculation to match the export, but slight differences may occur due to font rendering differences between SwiftUI `Text` and `CATextLayer`
- **Permission change causes app restart**: When the user changes Photo Library permission in iOS Settings, the system terminates and restarts the app. This means the recorded video and any edited overlay text are lost. This is an iOS-level behavior that cannot be prevented. With more time, the workaround would be to persist the recorded video path and overlay settings (text, position) to disk so they can be restored on relaunch
- **Portrait mode only**: The app only supports portrait orientation. Landscape mode is not supported

## What I'd Do With More Time

- Video trimming UI before export
- Custom fonts, colors, and text size options for overlay
- Multiple overlay layers (image watermarks, logos)
- Undo/redo for overlay changes
- Export quality/format options (MOV, MP4)
- Proper dependency injection instead of creating services inline
- Localization support
- Haptic feedback on record start/stop
- Unit tests and UI tests — this is a small, simple sample project so test coverage can be added with more time
- And more...

## App Icon

The app icon was generated using the prompt: *"Generate random iOS app icon for Action Camera app with size 1024x1024 in png"*, then refined using Apple's Icon Composer tool to quickly apply the default icon style.

## Requirements

- iOS 18.0+
- Xcode 16.0+
- Swift 6.0
- Physical device recommended (camera not available in Simulator)
