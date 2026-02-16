//
//  SettingsView.swift
//  FnMacAssistant
//
//  Created by Isacucho on 06/11/25.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var downloadManager = DownloadManager.shared
    @StateObject private var containerLocator = FortniteContainerLocator.shared
    @State private var showResetConfirm = false
    @State private var showFullDiskAlert = false
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @ObservedObject private var updateChecker = UpdateChecker.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {

                headerSection

                Text("Manage downloads, container location, and notifications.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 16) {

                    // MARK: - Download Settings
                    Text("Download Settings")
                        .font(.headline)

                    glassSection {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Download Location")
                                .font(.headline)

                            if let folder = downloadManager.defaultDownloadFolder {
                                Text(
                                    "Current folder: " +
                                    folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
                                )
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                            } else {
                                Text("No folder selected — using ~/Downloads")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }

                            HStack(spacing: 12) {
                                Button("Change Folder…") {
                                    let panel = NSOpenPanel()
                                    panel.title = "Select Download Location"
                                    panel.message = "Choose where you want to save downloaded files."
                                    panel.canChooseDirectories = true
                                    panel.canChooseFiles = false
                                    panel.allowsMultipleSelection = false
                                    panel.prompt = "Select"

                                    if panel.runModal() == .OK, let url = panel.url {
                                        downloadManager.setDownloadFolder(url)
                                    }
                                }

                                Button("Reset to Default") {
                                    downloadManager.resetDownloadFolder()
                                }
                            }
                        }
                    }
                }

                // MARK: - Fortnite Container
                glassSection {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Fortnite Container")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Detected Path:")
                                .font(.subheadline)

                            Text(containerLocator.cachedPath ?? "Not set")
                                .font(.system(size: 13, weight: .regular, design: .monospaced))
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Divider()

                        HStack(spacing: 12) {

                            Button("Find Automatically") {
                                if let found = containerLocator.locateContainer() {
                                    containerLocator.cachedPath = found
                                } else {
                                    showFullDiskAlert = true
                                }
                            }

                            Button("Select Manually…") {
                                let panel = NSOpenPanel()
                                panel.title = "Select Fortnite Container Folder"
                                panel.canChooseDirectories = true
                                panel.canChooseFiles = false
                                panel.allowsMultipleSelection = false
                                panel.directoryURL = FileManager.default
                                    .homeDirectoryForCurrentUser
                                    .appendingPathComponent("Library/Containers")

                                panel.begin { response in
                                    if response == .OK, let url = panel.url {
                                        containerLocator.manuallySetContainer(path: url.path)
                                    }
                                }
                            }

                            Button(role: .destructive) {
                                containerLocator.resetContainer()
                            } label: {
                                Text("Reset")
                            }
                            Spacer()
                            Button("Show in Finder") {
                                if let path = containerLocator.getContainerPath() {
                                    let url = URL(fileURLWithPath: path, isDirectory: true)
                                    if !NSWorkspace.shared.openFile(path, withApplication: "Finder") {
                                        NSWorkspace.shared.activateFileViewerSelecting([url])
                                    }
                                }
                            }
                            .disabled(containerLocator.getContainerPath() == nil)
                        }
                    }
                }

                // MARK: - Notifications
                glassSection {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Notifications")
                            .font(.headline)

                        Text("""
FnMacAssistant uses notifications to let you know when game assets finish installing.
You can disable them at any time.
""")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)

                        Toggle("Enable notifications", isOn: $notificationsEnabled)
                            .onChange(of: notificationsEnabled) { _, enabled in
                                if enabled {
                                    NotificationHelper.shared.requestAuthorization()
                                }
                            }
                    }
                }

                // MARK: - Updates
                glassSection {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Updates")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Current version: \(updateChecker.currentVersion)")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)

                            if let latest = updateChecker.latestVersion {
                                Text("Latest version: \(latest)")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                        }

                        if updateChecker.isUpdateAvailable, let latest = updateChecker.latestVersion {
                            Text("A new version (\(latest)) is available.")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.orange)
                        } else if updateChecker.isBetaBuild {
                            Text("You're on a pre-release build.")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.orange)
                        } else if updateChecker.latestVersion != nil {
                            Text("You're up to date.")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }

                        if let lastChecked = updateChecker.lastChecked {
                            Text("Last checked: \(lastChecked.formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }

                        if let error = updateChecker.errorMessage {
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }

                        HStack(spacing: 12) {
                            Button(updateChecker.isChecking ? "Checking…" : "Check for Updates") {
                                Task { await updateChecker.checkForUpdates(force: true) }
                            }
                            .disabled(updateChecker.isChecking)

                            if updateChecker.isUpdateAvailable {
                                Button("Open Releases") {
                                    openReleasesPage()
                                }
                            }
                        }
                    }
                }

                Divider()

                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        showResetConfirm = true
                    } label: {
                        Text("Reset All Settings")
                            .foregroundColor(.red)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
            .padding(24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .alert("Reset All Settings?", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                resetAllSettings()
            }
        } message: {
            Text("This will reset download location, container path, manual manifest settings, and warning preferences.")
        }
        .alert("Full Disk Access Needed", isPresented: $showFullDiskAlert) {
            Button("Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("""
FnMacAssistant needs Full Disk Access to locate Fortnite's container.

Open System Settings > Privacy & Security > Full Disk Access, then add and enable FnMacAssistant.
""")
        }
        .task {
            await updateChecker.checkForUpdates()
        }
    }

    // MARK: - Glass Section Builder
    @ViewBuilder
    private func glassSection<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(.ultraThickMaterial, for: .window)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1))
            )
    }

    private func resetAllSettings() {
        downloadManager.resetDownloadFolder()
        containerLocator.resetContainer()

        let fortDL = FortDLManager.shared
        fortDL.useManualManifest = false
        fortDL.manualManifestID = ""
        fortDL.setManualManifestEnabled(false)

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "defaultDownloadFolderPath")
        defaults.removeObject(forKey: "FortniteContainerPath")
        defaults.removeObject(forKey: "fortdlManualManifestID")
        defaults.removeObject(forKey: "notificationsEnabled")
        defaults.removeObject(forKey: "brCosmeticsWarningDisabled")
        defaults.removeObject(forKey: "brCosmeticsWarnedBattleRoyale")
        defaults.removeObject(forKey: "brCosmeticsWarnedRocketRacing")
        defaults.removeObject(forKey: "brCosmeticsWarnedCreative")
        defaults.removeObject(forKey: "brCosmeticsWarnedFestival")
    }

    private func openReleasesPage() {
        if let url = URL(string: "https://github.com/isacucho/FnMacAssistant/releases/latest") {
            NSWorkspace.shared.open(url)
        }
    }

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 42, height: 42)
                Image(systemName: "gearshape.fill")
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Settings")
                    .font(.largeTitle)
                    .bold()
                Text("Customize preferences")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}
