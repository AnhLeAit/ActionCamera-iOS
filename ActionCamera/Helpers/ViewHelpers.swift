//
//  ViewHelpers.swift
//  ActionCamera
//
//  Created by Anh Le on 12/2/26.
//  Copyright © 2026 Anh Le. Licensed under the MIT License.
//
import SwiftUI

struct GlassProminentButtonStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .buttonStyle(.glassProminent)
        } else {
            content
                .buttonStyle(.borderedProminent)
        }
    }
}

struct GlassButtonStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .buttonStyle(.glass)
        } else {
            content
                .buttonStyle(.bordered)
        }
    }
}

extension View {
    func applyGlassProminentButtonStyle() -> some View {
        self.modifier(GlassProminentButtonStyleModifier())
    }

    func applyGlassButtonStyle() -> some View {
        self.modifier(GlassButtonStyleModifier())
    }
}
