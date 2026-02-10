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
    @ObservedObject private var updateChecker = UpdateChecker.shared
    @AppStorage("suppressUpdatePopupVersion") private var suppressUpdatePopupVersion = ""
    @AppStorage("suppressPrereleasePopupVersion") private var suppressPrereleasePopupVersion = ""
    @State private var startupSheet: StartupSheet?

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
        .sheet(item: $startupSheet) { sheet in
            switch sheet {
            case .update:
                UpdatePromptSheet(
                    title: "Update Available",
                    message: updateMessage,
                    suppressLabel: "Do not show again",
                    suppressValue: updateSuppressBinding,
                    primaryTitle: "Open Releases",
                    primaryAction: openReleasesPage,
                    secondaryTitle: "Later",
                    onDismiss: { startupSheet = nil }
                )
            case .prerelease:
                UpdatePromptSheet(
                    title: "Pre-release Build",
                    message: prereleaseMessage,
                    suppressLabel: "Do not show again",
                    suppressValue: prereleaseSuppressBinding,
                    primaryTitle: "Open Discord",
                    primaryAction: openDiscord,
                    secondaryTitle: "Close",
                    onDismiss: { startupSheet = nil }
                )
            }
        }
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
        .task {
            await updateChecker.checkForUpdates()
            if updateChecker.isUpdateAvailable {
                if updateChecker.isBetaWithStableSameVersion {
                    if !isUpdateSuppressedForLatest {
                        startupSheet = .update
                    }
                } else if !isUpdateSuppressedForLatest {
                    startupSheet = .update
                }
            } else if updateChecker.isBetaBuild && !isPrereleaseSuppressedForCurrent {
                startupSheet = .prerelease
            }
        }
    }

    private var updateMessage: String {
        if updateChecker.isBetaWithStableSameVersion {
            return "A stable build of your current version is available. Please update to improve stability."
        }
        if let latest = updateChecker.latestVersion {
            return "A new version (\(latest)) is available. Please update to avoid issues."
        }
        return "A new version is available. Please update to avoid issues."
    }

    private var prereleaseMessage: String {
        "You're running a pre-release build. You might encounter issues. If you find any, please report them in the testers channel on the Discord."
    }

    private var isUpdateSuppressedForLatest: Bool {
        guard let latest = updateChecker.latestVersion else { return false }
        return suppressUpdatePopupVersion == updateSuppressionKey(latestVersion: latest)
    }

    private var isPrereleaseSuppressedForCurrent: Bool {
        suppressPrereleasePopupVersion == updateChecker.currentVersion
    }

    private var updateSuppressBinding: Binding<Bool> {
        Binding(
            get: { isUpdateSuppressedForLatest },
            set: { isOn in
                if isOn, let latest = updateChecker.latestVersion {
                    suppressUpdatePopupVersion = updateSuppressionKey(latestVersion: latest)
                } else {
                    suppressUpdatePopupVersion = ""
                }
            }
        )
    }

    private func updateSuppressionKey(latestVersion: String) -> String {
        if updateChecker.isBetaWithStableSameVersion {
            return "\(latestVersion)|\(updateChecker.currentVersion)"
        }
        return latestVersion
    }

    private var prereleaseSuppressBinding: Binding<Bool> {
        Binding(
            get: { isPrereleaseSuppressedForCurrent },
            set: { isOn in
                if isOn {
                    suppressPrereleasePopupVersion = updateChecker.currentVersion
                } else {
                    suppressPrereleasePopupVersion = ""
                }
            }
        )
    }

    private func openReleasesPage() {
        if let url = URL(string: "https://github.com/isacucho/FnMacAssistant/releases/latest") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openDiscord() {
        if let url = URL(string: "https://discord.gg/nfEBGJBfHD") {
            NSWorkspace.shared.open(url)
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

private enum StartupSheet: String, Identifiable {
    case update
    case prerelease

    var id: String { rawValue }
}

private struct UpdatePromptSheet: View {
    let title: String
    let message: String
    let suppressLabel: String
    @Binding var suppressValue: Bool
    let primaryTitle: String
    let primaryAction: () -> Void
    let secondaryTitle: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2)
                .bold()

            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            Toggle(suppressLabel, isOn: $suppressValue)
                .toggleStyle(.checkbox)

            HStack {
                Spacer()
                Button(primaryTitle) {
                    primaryAction()
                    onDismiss()
                }
                Button(secondaryTitle) {
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
