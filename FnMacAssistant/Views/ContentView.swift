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
                case .updateAssistant:
                    UpdateAssistantView()
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
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var fortDLManager = FortDLManager.shared
    @ObservedObject private var updateAssistant = UpdateAssistantManager.shared

    @State private var lastIpaFinishedID: UUID?
    @State private var lastAssetsFinished: Bool = false

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
                    label: "Update Assistant",
                    systemImage: "arrow.triangle.2.circlepath",
                    isSelected: selection == .updateAssistant
                ) { selection = .updateAssistant }
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
            .focusSection()
            
            Spacer()

            if hasAnyDownloadSummary {
                VStack(alignment: .leading, spacing: 10) {
                    if selection != .downloads, let active = downloadManager.downloads.first {
                        downloadSummaryCard(
                            title: "IPA Download",
                            subtitle: active.fileName,
                            progress: active.progress,
                            progressLabel: ipaProgressText(for: active),
                            stateLabel: ipaStateLabel(for: active),
                            showClear: active.state == .finished,
                            showCancel: active.state != .finished,
                            onClear: {
                                downloadManager.clearDownloads()
                            },
                            onCancel: {
                                downloadManager.cancelCurrentDownload()
                                downloadManager.clearDownloads()
                            }
                        )
                    }

                    if selection != .gameAssets,
                       (fortDLManager.isDownloading || fortDLManager.isInstalling || fortDLManager.isDone) {
                        downloadSummaryCard(
                            title: "Game Assets",
                            subtitle: assetsSubtitle,
                            progress: fortDLManager.downloadProgress,
                            progressLabel: assetsProgressText,
                            stateLabel: assetsStateLabel,
                            showClear: fortDLManager.isDone,
                            showCancel: fortDLManager.isDownloading,
                            onClear: {
                                fortDLManager.clearCompletedDownload()
                            },
                            onCancel: {
                                fortDLManager.cancelDownload()
                            }
                        )
                    }

                    if selection != .updateAssistant,
                       (updateAssistant.isDownloading || updateAssistant.isDone) {
                        downloadSummaryCard(
                            title: "Update Assistant",
                            subtitle: updateAssistant.statusMessage,
                            progress: updateAssistant.downloadProgress,
                            progressLabel: updateAssistantProgressText,
                            stateLabel: updateAssistantStateLabel,
                            showClear: updateAssistant.isDone,
                            showCancel: updateAssistant.isDownloading,
                            onClear: {
                                updateAssistant.stop()
                            },
                            onCancel: {
                                updateAssistant.stop()
                            }
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
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
    }

    private var hasAnyDownloadSummary: Bool {
        let hasIPADownload = selection != .downloads && downloadManager.downloads.first != nil
        let hasAssetsDownload = selection != .gameAssets &&
            (fortDLManager.isDownloading || fortDLManager.isInstalling || fortDLManager.isDone)
        let hasUpdateAssistant = selection != .updateAssistant &&
            (updateAssistant.isDownloading || updateAssistant.isDone)
        return hasIPADownload || hasAssetsDownload || hasUpdateAssistant
    }

    private var assetsSubtitle: String {
        if fortDLManager.downloadAllAssets {
            return "All assets"
        }

        let assetsCount = fortDLManager.selectedAssets.count
        let layersCount = fortDLManager.selectedLayers.count

        if layersCount == 1, let layerName = fortDLManager.selectedLayers.first,
           isFullLayerSelected(layerName: layerName) {
            return layerName
        }
        if assetsCount == 1, let name = fortDLManager.selectedAssets.first {
            return name
        }
        if assetsCount > 1 {
            return "Multiple tags"
        }
        if layersCount == 1, let name = fortDLManager.selectedLayers.first {
            return name
        }
        if layersCount > 1 {
            return "Multiple layers"
        }

        return "Game assets"
    }

    private func isFullLayerSelected(layerName: String) -> Bool {
        guard let layer = fortDLManager.layers.first(where: { $0.name == layerName }) else {
            return false
        }
        let assetNames = Set(layer.assets.map(\.name))
        return !assetNames.isEmpty && assetNames.isSubset(of: fortDLManager.selectedAssets)
    }

    private func ipaProgressText(for active: DownloadItem) -> String {
        if active.state == .finished {
            return "Done"
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .decimal

        let downloaded = formatter.string(fromByteCount: active.totalBytesWritten)
        let total = formatter.string(fromByteCount: active.totalBytesExpected)
        return "\(downloaded) / \(total)"
    }

    private func ipaStateLabel(for active: DownloadItem) -> String {
        switch active.state {
        case .paused:
            return "Paused"
        case .finished:
            return "Done"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        default:
            return String(format: "%.1f%%", active.progress * 100)
        }
    }

    private var assetsProgressText: String {
        if fortDLManager.isInstalling {
            return "Installing…"
        }
        if fortDLManager.isDone {
            return "Done"
        }
        return fortDLManager.downloadProgressLabel
    }

    private var assetsStateLabel: String {
        if fortDLManager.isInstalling {
            return "Installing"
        }
        if fortDLManager.isDone {
            return "Done"
        }
        return fortDLManager.downloadPercentageLabel
    }

    private var updateAssistantProgressText: String {
        if updateAssistant.isDone {
            return "Done"
        }
        return updateAssistant.downloadProgressLabel
    }

    private var updateAssistantStateLabel: String {
        if updateAssistant.isDone {
            return "Done"
        }
        return updateAssistant.downloadPercentageLabel
    }

    private func scheduleIpaAutoClear() {
        guard let active = downloadManager.downloads.first else { return }
        if lastIpaFinishedID == active.id { return }
        lastIpaFinishedID = active.id

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if downloadManager.downloads.first?.id == active.id,
               downloadManager.downloads.first?.state == .finished {
                downloadManager.clearDownloads()
            }
        }
    }

    @ViewBuilder
    private func downloadSummaryCard(
        title: String,
        subtitle: String,
        progress: Double,
        progressLabel: String,
        stateLabel: String,
        showClear: Bool,
        showCancel: Bool,
        onClear: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(stateLabel)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)

            ProgressView(value: progress)
                .progressViewStyle(.linear)

            HStack {
                Text(progressLabel)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Spacer()

                if showCancel {
                    Button("Cancel") {
                        onCancel()
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.bordered)
                }

                if showClear {
                    Button("Clear") {
                        onClear()
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.1))
        )
    }
}

// MARK: - Sidebar Button 
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
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .background(RoundedRectangle(cornerRadius: 8).foregroundStyle(backgroundColor))
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
    case updateAssistant
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
