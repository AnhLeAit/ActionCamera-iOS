//
//  PhotoLibrarySaver.swift
//  ActionCamera
//
//  Created by Anh Le on 12/2/26.
//  Copyright © 2026 Anh Le. Licensed under the MIT License.
//

import Photos
import UIKit

enum PhotoLibrarySaver {
    enum SaveError: LocalizedError {
        case permissionDenied
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Photo library access was denied. Please enable it in Settings."
            case .saveFailed(let reason):
                return "Failed to save video: \(reason)"
            }
        }
    }

    static func save(videoAt url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw SaveError.permissionDenied
        }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }
}
