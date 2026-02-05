//
//  ContentView.swift
//  FnMacAssistant
//
//  Created by Isacucho on 06/11/25.
//

import SwiftUI

struct ContentView: View {
    @State private var selection: SidebarSection = .downloads
    @State private var isSidebarVisible: Bool = true

    var body: some View {
        HStack(spacing: 0) {
            if isSidebarVisible {
                SidebarView(selection: $selection)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .zIndex(1)
            }

            Divider()

            ZStack {
                switch selection {
                case .downloads:
                    DownloadsView(downloadManager: DownloadManager.shared)
                case .patch:
                    PatchView()
                case .gameAssets:
                    GameAssetsView()
                case .faq:
                    FAQView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.ultraThinMaterial)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isSidebarVisible.toggle()
                    }
                }) {
                    Image(systemName: "sidebar.left")
                }
                .help(isSidebarVisible ? "Hide Sidebar" : "Show Sidebar")
            }
        }
    }
}

// MARK: - Sidebar View
struct SidebarView: View {
    @Binding var selection: SidebarSection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FnMacAssistant")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal, 16)
                .padding(.top, 20)

            VStack(alignment: .leading, spacing: 6) {
                SidebarButton(
                    label: "IPA Downloads",
                    systemImage: "square.and.arrow.down",
                    isSelected: selection == .downloads
                ) { selection = .downloads }

                SidebarButton(
                    label: "Patch",
                    systemImage: "wrench.and.screwdriver.fill",
                    isSelected: selection == .patch
                ) { selection = .patch }
                
                SidebarButton(
                    label: "Game Assets",
                    systemImage: "shippingbox.fill",
                    isSelected: selection == .gameAssets
                ) { selection = .gameAssets }
                SidebarButton(
                    label: "FAQ",
                    systemImage: "questionmark.circle.fill",
                    isSelected: selection == .faq
                ) { selection = .faq }
                
                SidebarButton(
                    label: "Settings",
                    systemImage: "gearshape.fill",
                    isSelected: selection == .settings
                ) { selection = .settings }
            }
            .padding(.top, 10)
            .padding(.horizontal, 8)

            Spacer()
        }
        .frame(width: 200)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.1), Color.black.opacity(0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
            .blur(radius: 10)
        )
        .overlay(Divider(), alignment: .trailing)
    }
}

// MARK: - Sidebar Button (modern hover + select style)
struct SidebarButton: View {
    let label: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 20)
                Text(label)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.25)
        } else if isHovered {
            return Color.primary.opacity(0.08)
        } else {
            return Color.clear
        }
    }
}

// MARK: - Sidebar Section Enum
enum SidebarSection {
    case downloads
    case patch
    case gameAssets
    case faq
    case settings
}
