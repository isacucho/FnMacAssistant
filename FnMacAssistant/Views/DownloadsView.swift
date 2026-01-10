//
//  DownloadsView.swift
//  FnMacAssistant
//
//  Created by Isacucho on 06/11/25.
//

import SwiftUI

struct DownloadsView: View {
    @ObservedObject var downloadManager = DownloadManager.shared
    @StateObject private var ipaFetcher = IPAFetcher.shared

    @State private var shownVersion: String? = nil
    @State private var showCancelPrompt = false

    var body: some View {
        ZStack(alignment: .bottom) {

            // MARK: - Main Content
            VStack(alignment: .leading, spacing: 20) {

                // MARK: Header
                HStack {
                    Text("Available IPAs")
                        .font(.largeTitle)
                        .bold()

                    Spacer()

                    if ipaFetcher.isLoading {
                        ProgressView().scaleEffect(0.9)
                    } else {
                        Button {
                            Task { await refreshIPAs() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                // MARK: Version Banner
                HStack {
                    Text("Latest Version: \(shownVersion ?? (ipaFetcher.isLoading ? "Fetching…" : "N/A"))")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(
                            LinearGradient(
                                colors: [.blue.opacity(0.85), .purple.opacity(0.85)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(radius: 4, y: 2)

                    Spacer()
                }
                .padding(.bottom, 6)

                // MARK: IPA Picker
                HStack {
                    Picker("Select IPA:", selection: $ipaFetcher.selectedIPA) {
                        ForEach(ipaFetcher.availableIPAs) { ipa in
                            Text(ipa.name).tag(Optional(ipa))
                        }
                    }
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .pickerStyle(.menu)
                    .frame(minWidth: 260)
                }
                .onAppear {
                    Task { await refreshIPAs() }
                }

                // MARK: Selected IPA Info
                if let ipa = ipaFetcher.selectedIPA {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(ipa.name)
                                .font(.title3)
                                .bold()

                            Text(ipaInfo(for: ipa.name))
                                .font(.system(size: 15))
                                .foregroundColor(.primary)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 80)
                    }
                } else {
                    Text("No IPA selected")
                        .foregroundColor(.secondary)
                }

                // MARK: Active Download Bubble
                if let active = downloadManager.downloads.first {
                    VStack(alignment: .leading, spacing: 10) {

                        HStack {
                            Text("Downloading \(active.fileName)")
                                .font(.headline)
                                .lineLimit(1)

                            Spacer()

                            if active.state == .finished {
                                Button(role: .destructive) {
                                    withAnimation {
                                        downloadManager.clearDownloads()
                                    }
                                } label: {
                                    Label("Clear", systemImage: "trash.fill")
                                }
                                .buttonStyle(.bordered)
                            } else {
                                Button {
                                    downloadManager.pauseOrResume(active)
                                } label: {
                                    Label(
                                        active.state == .paused ? "Resume" : "Pause",
                                        systemImage: active.state == .paused ? "play.fill" : "pause.fill"
                                    )
                                }
                                .buttonStyle(.bordered)

                                Button(role: .destructive) {
                                    withAnimation {
                                        downloadManager.cancelCurrentDownload()
                                        downloadManager.clearDownloads()
                                    }
                                } label: {
                                    Label("Cancel", systemImage: "xmark.circle.fill")
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: active.progress)
                                .progressViewStyle(.linear)

                            let downloaded = formatBytes(active.totalBytesWritten)
                            let total = formatBytes(active.totalBytesExpected)

                            if active.state == .finished {
                                Text("✅ Download Complete")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.green)
                            } else {
                                Text("\(downloaded) / \(total) downloaded")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(radius: 3, y: 2)
                }

                Spacer(minLength: 20)
            }
            .padding(24)

            // MARK: Download Button
            if let ipa = ipaFetcher.selectedIPA {
                Button {
                    handleDownloadRequest(for: ipa)
                } label: {
                    Label("Download", systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .alert("Cancel Current Download?", isPresented: $showCancelPrompt) {
            Button("Cancel", role: .destructive) {
                downloadManager.cancelCurrentDownload()
                if let ipa = ipaFetcher.selectedIPA,
                   let url = URL(string: ipa.download_url) {
                    downloadManager.startDownload(from: url)
                }
            }
            Button("Keep Current", role: .cancel) {}
        } message: {
            Text("Another download is already in progress.")
        }
    }

    // MARK: - Helpers

    private func refreshIPAs() async {
        await ipaFetcher.fetchAvailableIPAs()
        shownVersion = ipaFetcher.latestReleaseTag ?? "N/A"
    }

    private func handleDownloadRequest(for ipa: IPAFetcher.IPAInfo) {
        guard let url = URL(string: ipa.download_url) else { return }

        if downloadManager.isDownloading {
            showCancelPrompt = true
        } else {
            downloadManager.startDownload(from: url)
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .decimal
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - IPA Descriptions

    private func ipaInfo(for ipaName: String) -> AttributedString {
        let lower = ipaName.lowercased()
        var text = AttributedString()

        if lower.contains("clean") {
            text = AttributedString("""
Clean Build

Unmodified IPA file, straight from source.
""")
        } else if lower.contains("tweak") {
            text = AttributedString("""
Tweak Build

Includes the following regular tweaks:
• Removed device restriction
• Allows editing files from the Files app
• macOS Fullscreen Patch

Plus the following gameplay enhancements by rt2746:
• Toggle pointer locking with Left Option key
• Unlocks 120 FPS option
• Unlocks graphic preset selection
• Custom options menu (press P)
• Mouse interaction with mobile UI
• Directory access support (made by VictorWads)

""")

            var disclaimer = AttributedString(
                "Disclaimer: Use FnMacTweak at your own risk. We are not responsible for any damages or incidents caused by this tweak, including bans."
            )
            disclaimer.font = .system(size: 13, weight: .bold)
            disclaimer.foregroundColor = .red

            text += disclaimer

        } else if lower.contains("fortnite") {
            text = AttributedString("""
Regular Build

Includes the following tweaks:
• Removed device restriction
• Allows editing files from the Files app
• macOS Fullscreen Patch
""")
        } else {
            text = AttributedString("""
Unknown Build

This IPA isn't recognized by FnMacAssistant.
For more info, visit:
https://discord.gg/nfEBGJBfHD
""")
        }

        return text
    }
}
