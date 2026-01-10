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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {

                // MARK: - Title
                Text("Settings")
                    .font(.largeTitle)
                    .bold()
                    .padding(.horizontal, 8)

                VStack(alignment: .leading, spacing: 16) {

                    // MARK: - Download Settings
                    Text("Download Settings")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 4)

                    // ===== Download Folder Section =====
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
                                    NSSound.beep()
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
                        }
                    }
                }
            }
            .padding(24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Glass Section Builder
    @ViewBuilder
    private func glassSection<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1))
            )
    }
}
