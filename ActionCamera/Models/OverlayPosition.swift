//
//  OverlayPosition.swift
//  ActionCamera
//
//  Created by Anh Le on 12/2/26.
//  Copyright © 2026 Anh Le. Licensed under the MIT License.
//

import Foundation

enum OverlayPosition: String, CaseIterable, Identifiable {
    case top
    case center
    case bottom

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }
}
