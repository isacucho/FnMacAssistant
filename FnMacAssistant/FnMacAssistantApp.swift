//
//  FnMacAssistantApp.swift
//  FnMacAssistant
//
//  Created by Isacucho on 06/11/25.
//

import SwiftUI

@main
struct FnMacAssistantApp: App {
    @StateObject private var downloadManager = DownloadManager()
    private let windowSize = CGSize(width: 900, height: 510)

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(downloadManager)
                .frame(minWidth: windowSize.width, minHeight: windowSize.height)
        }
        .defaultSize(width: windowSize.width, height: windowSize.height)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
        }
    }
}

private struct LegacyProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let large: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white.opacity(isEnabled ? 1 : 0.7))
            .padding(.horizontal, large ? 16 : 12)
            .padding(.vertical, large ? 10 : 8)
            .background(
                RoundedRectangle(cornerRadius: large ? 12 : 10, style: .continuous)
                    .fill(
                        Color.accentColor.opacity(
                            isEnabled
                            ? (configuration.isPressed ? 0.72 : 0.9)
                            : 0.35
                        )
                    )
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct ProminentActionButtonModifier: ViewModifier {
    let large: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        content
            .buttonStyle(LegacyProminentButtonStyle(large: large))
    }
}

extension View {
    func prominentActionButton(large: Bool = false) -> some View {
        modifier(ProminentActionButtonModifier(large: large))
    }
}
