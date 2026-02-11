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
    @State private var showStorageAlert = false
    @State private var storageAlertMessage = ""
    @State private var didAutoScrollToDownload = false
    private let downloadSpacerID = "DOWNLOAD_SPACER"

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: 20) {
                    headerSection

                glassSection {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Latest Version")
                                .font(.headline)
                            Spacer()
                            Text(shownVersion ?? (ipaFetcher.isLoading ? "Fetching…" : "N/A"))
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Picker("Select IPA:", selection: $ipaFetcher.selectedIPA) {
                                ForEach(ipaFetcher.availableIPAs) { ipa in
                                    Text(ipa.name).tag(Optional(ipa))
                                }
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .pickerStyle(.menu)
                            .frame(minWidth: 260)

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

                        if let pathLabel = downloadPathLabel {
                            Text("Current download path: \(pathLabel)")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                    .onAppear {
                        Task { await refreshIPAs() }
                    }

                    if let ipa = ipaFetcher.selectedIPA {
                        glassSection {
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
                                .padding(.trailing, 6)
                            }
                            .scrollIndicators(.visible)
                            .frame(maxHeight: 240)
                        }
                    } else {
                        Text("No IPA selected")
                            .foregroundColor(.secondary)
                    }

                    if let ipa = ipaFetcher.selectedIPA {
                        Button {
                            Task { await handleDownloadRequest(for: ipa) }
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

                    if hasActiveDownload {
                        Spacer()
                            .frame(height: downloadBubbleHeight + 24)
                            .id(downloadSpacerID)
                    }
                    }
                    .padding(24)
                    .onChange(of: hasActiveDownload) { active in
                        guard active else {
                            didAutoScrollToDownload = false
                            return
                        }
                        if !didAutoScrollToDownload {
                            DispatchQueue.main.async {
                                withAnimation(.easeOut(duration: 0.35)) {
                                    proxy.scrollTo(downloadSpacerID, anchor: .bottom)
                                }
                            }
                            didAutoScrollToDownload = true
                        }
                    }
                }
            }

            if let active = downloadManager.downloads.first {
                downloadBubble(for: active)
                    .padding()
            }
        }
        .alert("Replace Current Download?", isPresented: $showCancelPrompt) {
            Button("Cancel Current & Download", role: .destructive) {
                downloadManager.cancelCurrentDownload()
                if let ipa = ipaFetcher.selectedIPA,
                   let url = URL(string: ipa.download_url) {
                    downloadManager.startDownload(from: url)
                }
            }
            Button("Keep Current", role: .cancel) {}
        } message: {
            Text("Starting a new download will cancel the current one.")
        }
        .alert("Not Enough Storage", isPresented: $showStorageAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(storageAlertMessage)
        }
    }

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 42, height: 42)
                Image(systemName: "square.and.arrow.down.fill")
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("IPA Downloads")
                    .font(.largeTitle)
                    .bold()
                Text(ipaFetcher.isLoading ? "Loading releases…" : "Ready")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Helpers

    private func refreshIPAs() async {
        await ipaFetcher.fetchAvailableIPAs()
        shownVersion = ipaFetcher.latestReleaseTag ?? "N/A"
    }

    private func handleDownloadRequest(for ipa: IPAFetcher.IPAInfo) async {
        guard let url = URL(string: ipa.download_url) else { return }

        if let requiredBytes = await remoteFileSizeBytes(for: url),
           let availableBytes = availableDiskSpaceBytes(for: downloadFolderURL) {
            let requiredWithBuffer = applyStorageBuffer(to: Int64(requiredBytes))
            if requiredWithBuffer > availableBytes {
            storageAlertMessage = storageMessage(
                required: requiredWithBuffer,
                available: availableBytes
            )
            showStorageAlert = true
            return
            }
        }

        if let active = downloadManager.downloads.first,
           active.state != .finished {
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

    private var downloadFolderURL: URL? {
        downloadManager.defaultDownloadFolder ??
            FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }

    private func availableDiskSpaceBytes(for url: URL?) -> Int64? {
        guard let url else { return nil }
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let capacity = values.volumeAvailableCapacityForImportantUsage {
            return capacity
        }
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
           let capacity = values.volumeAvailableCapacity {
            return Int64(capacity)
        }
        return nil
    }

    private func remoteFileSizeBytes(for url: URL) async -> Int64? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue("FnMacAssistant/2.0 (macOS)", forHTTPHeaderField: "User-Agent")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse,
               let length = http.value(forHTTPHeaderField: "Content-Length"),
               let bytes = Int64(length) {
                return bytes
            }
        } catch {
            return nil
        }
        return nil
    }

    private func storageMessage(required: Int64, available: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .decimal
        let requiredLabel = formatter.string(fromByteCount: required)
        let availableLabel = formatter.string(fromByteCount: available)
        return "Required: \(requiredLabel). Available: \(availableLabel). Please free up space and try again."
    }

    private func applyStorageBuffer(to bytes: Int64) -> Int64 {
        Int64(ceil(Double(bytes) * 1.05))
    }

    private var downloadPathLabel: String? {
        guard let url = downloadFolderURL else { return nil }
        return url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private var hasActiveDownload: Bool {
        downloadManager.downloads.first != nil
    }

    private var downloadBubbleHeight: CGFloat {
        110
    }

    @ViewBuilder
    private func downloadBubble(for active: DownloadItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(active.fileName)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                if active.state == .finished {
                    Text("Completed")
                        .font(.caption2)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.green.opacity(0.15))
                        .foregroundColor(.green)
                        .clipShape(Capsule())
                } else if active.state == .paused {
                    Text("Paused")
                        .font(.caption2)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.orange.opacity(0.15))
                        .foregroundColor(.orange)
                        .clipShape(Capsule())
                } else {
                    Text("Downloading")
                        .font(.caption2)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundColor(.accentColor)
                        .clipShape(Capsule())
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: active.progress)
                    .progressViewStyle(.linear)

                let downloaded = formatBytes(active.totalBytesWritten)
                let total = formatBytes(active.totalBytesExpected)

                if active.state == .finished {
                    Text("Download complete")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                } else {
                    Text("\(downloaded) / \(total) downloaded")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack {
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
                Spacer()
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 8)
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

    @ViewBuilder
    private func glassSection<Content: View>(
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
