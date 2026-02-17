//
//  PatchView.swift
//  FnMacAssistant
//
//  Created by Isacucho on 10/11/25.
//

import SwiftUI

struct PatchView: View {
    @StateObject private var patchManager = PatchManager.shared
    @AppStorage("enableInGameDownloadFolder") private var enableInGameDownloadFolder = false
    @State private var showInGameDownloadInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 42, height: 42)
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .foregroundColor(.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Fortnite Mac Patcher")
                        .font(.largeTitle)
                        .bold()
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if patchManager.patchCompleted {
                    Text("Patched")
                        .font(.caption2)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.green.opacity(0.15))
                        .foregroundColor(.green)
                        .clipShape(Capsule())
                } else if patchManager.isPatching {
                    Text("Working…")
                        .font(.caption2)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundColor(.accentColor)
                        .clipShape(Capsule())
                }
            }

            Text("""
This patch adds the required entitlements to Fortnite’s embedded provisioning file.
FnMacAssistant will open Fortnite, wait a few seconds, then apply the patch.
""")
            .font(.system(size: 14))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            glassSection {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Button {
                            patchManager.startPatch()
                        } label: {
                            HStack(spacing: 8) {
                                if patchManager.isPatching {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                } else {
                                    Image(systemName: patchManager.patchCompleted ? "checkmark.circle.fill" : "bolt.fill")
                                }
                                Text(patchManager.patchCompleted ? "Patch Applied" : "Apply Patch")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                        }
                        .prominentActionButton()
                        .disabled(patchManager.isPatching)

                        Spacer()

                        HStack(spacing: 8) {
                            Toggle("Enable in-game download folder", isOn: $enableInGameDownloadFolder)
                                .onChange(of: enableInGameDownloadFolder) { _, enabled in
                                    if enabled {
                                        patchManager.prepareInGameDownloadFolder()
                                    } else {
                                        patchManager.removeInGameDownloadFolder()
                                    }
                                }
                                .toggleStyle(.switch)

                            Button {
                                showInGameDownloadInfo = true
                            } label: {
                                Image(systemName: "questionmark.circle")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                showInGameDownloadInfo = hovering
                            }
                            .popover(isPresented: $showInGameDownloadInfo, arrowEdge: .top) {
                                Text("""
In-game downloads may not work as expected. You might need to use the app’s update helper or game assets downloader to get the files. This can also accumulate data if downloads fail.
""")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(width: 320)
                                .padding(12)
                            }
                        }

                        if patchManager.patchCompleted {
                            Button {
                                launchFortniteViaShell()
                            } label: {
                                Label("Open Fortnite", systemImage: "gamecontroller.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 12)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            glassSection {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Console Output")
                        .font(.headline)

                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(patchManager.logMessages.joined(separator: "\n"))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .padding(8)
                                .textSelection(.enabled)
                                .id("consoleText")

                            Color.clear
                                .frame(height: 1)
                                .id("consoleBottom")
                        }
                        .onChange(of: patchManager.logMessages.count) {
                            withAnimation {
                                proxy.scrollTo("consoleBottom", anchor: .bottom)
                            }
                        }
                        .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.25))
                        )
                        .frame(maxHeight: .infinity)
                    }
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private extension PatchView {
    var statusText: String {
        if patchManager.isPatching {
            return "Applying patch…"
        }
        if patchManager.patchCompleted {
            return "Ready to launch"
        }
        return "Ready"
    }
}

// MARK: - helpers

private func launchFortniteViaShell() {
    DispatchQueue.global(qos: .userInitiated).async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["/Applications/Fortnite.app"]

        do { try process.run() } catch { }
    }
}

private extension PatchView {
    @ViewBuilder
    func glassSection<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.1))
            )
    }
}
