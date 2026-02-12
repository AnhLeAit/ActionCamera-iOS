//
//  VideoPlayerView.swift
//  ActionCamera
//
//  Created by Anh Le on 12/2/26.
//  Copyright © 2026 Anh Le. Licensed under the MIT License.
//

import SwiftUI
import AVKit

struct VideoPlayerView: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        let player = AVPlayer(url: url)
        controller.player = player
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect

        // Loop infinitely
        let observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }
        context.coordinator.loopObserver = observer

        player.play()
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        let currentAsset = uiViewController.player?.currentItem?.asset as? AVURLAsset
        if currentAsset?.url != url {
            // Clean up old observer
            if let observer = context.coordinator.loopObserver {
                NotificationCenter.default.removeObserver(observer)
            }

            let player = AVPlayer(url: url)
            uiViewController.player = player

            let observer = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { _ in
                player.seek(to: .zero)
                player.play()
            }
            context.coordinator.loopObserver = observer

            player.play()
        }
    }

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Coordinator) {
        // Stop playback and release player
        uiViewController.player?.pause()
        uiViewController.player?.replaceCurrentItem(with: nil)
        uiViewController.player = nil

        // Remove loop observer
        if let observer = coordinator.loopObserver {
            NotificationCenter.default.removeObserver(observer)
            coordinator.loopObserver = nil
        }
    }

    // MARK: - Coordinator

    final class Coordinator {
        var loopObserver: NSObjectProtocol?
    }
}
