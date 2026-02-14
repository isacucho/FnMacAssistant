//
//  FortDLManager.swift
//  FnMacAssistant
//
//  Created by Isacucho on 11/01/26.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class FortDLManager: ObservableObject {
    static let shared = FortDLManager()

    // MARK: - Models

    struct Asset: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let size: UInt64
    }

    struct Layer: Identifiable {
        let id = UUID()
        let name: String
        let totalSize: String
        let assets: [Asset]
    }

    // MARK: - State
    
    @Published var isDownloading = false
    @Published var downloadedBytes: UInt64 = 0
    @Published var totalBytes: UInt64 = 0

    @Published var manifestID: String?
    @Published var buildVersion: String?
    @Published var layers: [Layer] = []
    @Published var totalDownloadSize: String?

    @Published var selectedLayers: Set<String> = []
    @Published var selectedAssets: Set<String> = []

    @Published var logOutput: String = ""

    // UI flags
    @Published var showAssets = false
    @Published var showConsole = false
    @Published var downloadAllAssets = false
    
    @Published var isInstalling = false
    @Published var isDone = false
    
    private var activeProcess: Process?
    private var didNotifyForCurrentDownload = false
    private var wasCancelled = false
    private var cacheMonitorTimer: Timer?
    private var lastDownloadArguments: [String]?
    private var autoResumeTimer: Timer?
    private var stallCheckTimer: Timer?
    private var lastProgressBytes: UInt64 = 0
    private var lastProgressDate: Date?

    private var cancellables: Set<AnyCancellable> = []


    @Published var downloadStartDate: Date?
    @Published var useManualManifest: Bool = false
    @Published var manualManifestID: String = ""

    @AppStorage("fortdlManualManifestID") private var storedManualManifestID = ""

    private var autoManifestID: String?

    private init() {
        manualManifestID = storedManualManifestID

        $manualManifestID
            .sink { [weak self] value in
                self?.storedManualManifestID = value
                Task { @MainActor in
                    self?.updateManifestID()
                }
            }
            .store(in: &cancellables)

        loadManifest()
        fetchAvailableLayers()
    }
    
    var downloadProgress: Double {
        if isDone { return 1 }
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(downloadedBytes) / Double(totalBytes))
    }

    var downloadProgressLabel: String {
        let downloaded = ByteCountFormatter.string(
            fromByteCount: Int64(downloadedBytes),
            countStyle: .file
        )
        let total = ByteCountFormatter.string(
            fromByteCount: Int64(totalBytes),
            countStyle: .file
        )
        return "\(downloaded) / \(total)"
    }
    
    

    var downloadedSizeLabel: String {
        ByteCountFormatter.string(
            fromByteCount: Int64(downloadedBytes),
            countStyle: .file
        )
    }

    var totalSizeLabel: String {
        ByteCountFormatter.string(
            fromByteCount: Int64(totalBytes),
            countStyle: .file
        )
    }

    // MARK: - Manifest

    func loadManifest() {
        let cloudJSON =
        "/Applications/Fortnite.app/Wrapper/FortniteClient-IOS-Shipping.app/Cloud/cloudcontent.json"

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: cloudJSON)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            log("❌ Failed to read cloudcontent.json")
            return
        }

        buildVersion = json["BuildVersion"] as? String

        if let manifestPath = json["ManifestPath"] as? String {
            autoManifestID = URL(fileURLWithPath: manifestPath)
                .deletingPathExtension()
                .lastPathComponent
        }

        updateManifestID()
        log("✔ Manifest ID: \(manifestID ?? "unknown")")
    }

    // MARK: - Fetch layers / assets

    func fetchAvailableLayers() {
        guard let manifestID else { return }

        resetSelections()
        logOutput = ""

        let process = Process()
        process.executableURL = fortDLURL()
        clearFortDLCache()

        process.arguments = [
            "--manifest-id", manifestID,
            "--list-tags",
            "-c", fortDLCacheURL.path
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        process.terminationHandler = { _ in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: data, as: UTF8.self)

            Task { @MainActor in
                self.logOutput = output
                self.parseOutput(output)
            }
        }

        try? process.run()
    }

    // MARK: - Download

    func download() {
        guard let manifestID,
              let container = FortniteContainerLocator.shared.getContainerPath()
        else { return }

        let outputDir =
        "\(container)/Data/Documents/FortniteGame/PersistentDownloadDir"

        var args = [
            "--manifest-id", manifestID,
            "-o", outputDir,
            "--download-only"
        ]
        
        args += ["-c", fortDLCacheURL.path]

        if downloadAllAssets {
            // everything
        } else if !selectedAssets.isEmpty {
            for asset in selectedAssets {
                args += ["--tag", asset]
            }
        } else {
            for layer in selectedLayers {
                args += ["--layer", layer]
            }
        }

        isDownloading = true
        isInstalling = false
        isDone = false
        downloadedBytes = 0
        totalBytes = selectedDownloadSizeBytes
        didNotifyForCurrentDownload = false
        wasCancelled = false
        
        clearFortDLCache()
        lastDownloadArguments = args
        runFortDL(arguments: args)
        startCacheMonitoring()
        scheduleStallCheck()
    }

    // MARK: - Parsing

    private func parseOutput(_ output: String) {
        if let line = output
            .split(separator: "\n")
            .first(where: { $0.contains("Total download size:") }) {

            totalDownloadSize = line
                .replacingOccurrences(of: "Total download size:", with: "")
                .trimmingCharacters(in: .whitespaces)
        }

        layers.removeAll()

        let blocks = output.components(separatedBy: "\n\n")

        for block in blocks {
            guard block.contains(":"),
                  !block.lowercased().hasPrefix("total download size")
            else { continue }

            let lines = block
                .split(separator: "\n")
                .map(String.init)

            let header = lines.first!
                .replacingOccurrences(of: ":", with: "")

            if header.hasPrefix("Available tags") { continue }

            let sizeLine = lines.last { $0.contains("Total:") } ?? ""
            let size = sizeLine
                .replacingOccurrences(of: "Total:", with: "")
                .trimmingCharacters(in: .whitespaces)

            let assets = lines
                .dropFirst()
                .filter { !$0.contains("Total:") }
                .compactMap { line -> Asset? in
                    let parts = line
                        .trimmingCharacters(in: .whitespaces)
                        .components(separatedBy: .whitespaces)
                        .filter { !$0.isEmpty }

                    guard parts.count >= 3 else { return nil }

                    let name = parts.first!
                    let sizeString = parts.suffix(2).joined(separator: " ")
                    let sizeBytes = Self.parseSizeToBytes(sizeString)

                    return Asset(name: name, size: sizeBytes)
                }

            layers.append(
                Layer(name: header, totalSize: size, assets: assets)
            )
        }
    }

    // MARK: - Process helpers

    private func runFortDL(arguments: [String]) {
        let process = Process()
        activeProcess = process
        process.executableURL = fortDLURL()
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let str = String(decoding: data, as: UTF8.self)

            guard let strongSelf = self else { return }
            Task { @MainActor in
                strongSelf.log(str)
            }
        }

        process.terminationHandler = { [weak self, handle] process in
            let remaining = handle.readDataToEndOfFile()
            guard let strongSelf = self else { return }
            Task { @MainActor in
                handle.readabilityHandler = nil
                if !remaining.isEmpty {
                    let str = String(decoding: remaining, as: UTF8.self)
                    strongSelf.log(str)
                }
                strongSelf.handleProcessTermination(process.terminationStatus)
            }
        }

        try? process.run()
    }

    private func fortDLURL() -> URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/fort-dl")
    }

    private func log(_ str: String) {
        logOutput += str + "\n"
        if str.contains("Populating ChunkDownload cache") {
            isDownloading = false
            isInstalling = true
        }

        if str.contains("Download complete (--download-only specified)") ||
            str.contains("Cleaning up cache directory") ||
            str.contains("Done:") {
            isDownloading = false
            isInstalling = false
            isDone = true
            stopCacheMonitoring()
            stopAutoResume()
            stopStallCheck()
            clearFortDLCache()
            notifyIfNeeded()
        }
    }
    
    

    var selectedDownloadSizeLabel: String {
        if downloadAllAssets {
            return totalDownloadSize ?? "—"
        }

        let totalBytes = layers
            .flatMap(\.assets)
            .filter { selectedAssets.contains($0.name) }
            .reduce(0) { $0 + $1.size }

        return ByteCountFormatter.string(
            fromByteCount: Int64(totalBytes),
            countStyle: .file
        )
    }

    var selectedDownloadSizeBytes: UInt64 {
        if downloadAllAssets {
            let totalBytes = layers
                .flatMap(\.assets)
                .reduce(0) { $0 + $1.size }
            return totalBytes
        }

        let totalBytes = layers
            .flatMap(\.assets)
            .filter { selectedAssets.contains($0.name) }
            .reduce(0) { $0 + $1.size }

        return totalBytes
    }

    private static func parseSizeToBytes(_ str: String) -> UInt64 {
        let parts = str.split(separator: " ")
        guard parts.count == 2,
              let value = Double(parts[0])
        else { return 0 }

        switch parts[1].uppercased() {
        case "KB": return UInt64(value * 1_024)
        case "MB": return UInt64(value * 1_024 * 1_024)
        case "GB": return UInt64(value * 1_024 * 1_024 * 1_024)
        default: return 0
        }
    }

    private func resetSelections() {
        selectedLayers.removeAll()
        selectedAssets.removeAll()
        layers.removeAll()
        totalDownloadSize = nil
    }
    private func handleProcessOutput(_ output: String) {
        log(output)

        for line in output.split(separator: "\n") {
            if line.hasPrefix("PROGRESS ") {
                let parts = line.split(separator: " ")
                guard parts.count == 3,
                      let downloaded = UInt64(parts[1]),
                      let total = UInt64(parts[2])
                else { continue }

                downloadedBytes = downloaded
                totalBytes = total
            }
        }
    }

    var downloadPercentageLabel: String {
        String(format: "%.1f%%", downloadProgress * 100)
    }

    var downloadETALabel: String {
        guard
            let start = downloadStartDate,
            downloadedBytes > 0,
            totalBytes > downloadedBytes
        else { return "—" }

        let elapsed = Date().timeIntervalSince(start)
        let speed = Double(downloadedBytes) / elapsed
        let remaining = Double(totalBytes - downloadedBytes) / speed

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated

        return formatter.string(from: remaining) ?? "—"
    }
    // MARK: - fort-dl Cache

    private var fortDLCacheURL: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("FnMacAssistant-cache", isDirectory: true)
            .appendingPathComponent("fort-dl", isDirectory: true)
    }

    private func clearFortDLCache() {
        let fm = FileManager.default

        if fm.fileExists(atPath: fortDLCacheURL.path) {
            do {
                try fm.removeItem(at: fortDLCacheURL)
            } catch {
                log("⚠️ Failed to remove fort-dl cache: \(error.localizedDescription)")
            }
        }

        do {
            try fm.createDirectory(
                at: fortDLCacheURL,
                withIntermediateDirectories: true
            )
        } catch {
            log("⚠️ Failed to create fort-dl cache: \(error.localizedDescription)")
        }
    }
    // MARK: - Cancel Download (Ctrl-C equivalent)

    func cancelDownload() {
        if let process = activeProcess {
            log("🛑 Download cancelled by user")

            // Send SIGINT (Ctrl-C)
            process.interrupt()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if process.isRunning {
                    process.terminate()
                }
            }
        }

        activeProcess = nil

        isDownloading = false
        isInstalling = false
        isDone = false
        didNotifyForCurrentDownload = false
        wasCancelled = true
        stopCacheMonitoring()
        stopAutoResume()
        stopStallCheck()

        downloadedBytes = 0
        totalBytes = 0

        clearFortDLCache()
    }

    func clearCompletedDownload() {
        guard isDone else { return }
        isDone = false
        isDownloading = false
        isInstalling = false
        downloadedBytes = 0
        totalBytes = 0
        downloadStartDate = nil
        wasCancelled = false
        stopCacheMonitoring()
        stopAutoResume()
        stopStallCheck()
    }

    @MainActor
    func resetDownloadStateIfIdle() {
        guard !isDownloading && !isInstalling else { return }
        isDone = false
        isDownloading = false
        isInstalling = false
        downloadedBytes = 0
        totalBytes = 0
        downloadStartDate = nil
        didNotifyForCurrentDownload = false
        wasCancelled = false
        stopCacheMonitoring()
        stopAutoResume()
        stopStallCheck()
    }

    private func startCacheMonitoring() {
        stopCacheMonitoring()
        downloadStartDate = Date()
        lastProgressBytes = 0
        lastProgressDate = Date()
        cacheMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let strongSelf = self else { return }
            Task { @MainActor in
                strongSelf.handleCacheMonitorTick()
            }
        }
    }

    private func handleProcessTermination(_ status: Int32) {
        activeProcess = nil

        if wasCancelled || isDone {
            return
        }

        if status != 0 || (isDownloading || isInstalling) {
            log("⚠️ Download interrupted. Attempting to resume every 5 seconds with the same command...")
            startAutoResume()
        }
    }

    private func startAutoResume() {
        autoResumeTimer?.invalidate()
        autoResumeTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let strongSelf = self else { return }
            Task { @MainActor in
                strongSelf.handleAutoResumeTick()
            }
        }
    }

    private func stopAutoResume() {
        autoResumeTimer?.invalidate()
        autoResumeTimer = nil
    }


    private func scheduleStallCheck() {
        stallCheckTimer?.invalidate()
        stallCheckTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let strongSelf = self else { return }
            Task { @MainActor in
                strongSelf.handleStallCheckTick()
            }
        }
    }

    private func stopStallCheck() {
        stallCheckTimer?.invalidate()
        stallCheckTimer = nil
    }

    @MainActor
    private func handleCacheMonitorTick() {
        guard isDownloading || isInstalling else { return }
        let bytes = cacheDirectorySize(at: fortDLCacheURL)
        if bytes > 0 {
            downloadedBytes = bytes
        }
        if totalBytes > 0,
           downloadedBytes >= totalBytes,
           !isDone {
            isDownloading = false
            isInstalling = true
        }
    }

    @MainActor
    private func handleAutoResumeTick() {
        guard activeProcess == nil else { return }
        guard let args = lastDownloadArguments else { return }

        log("🔄 Resuming download...")
        isDownloading = true
        isInstalling = false
        isDone = false
        wasCancelled = false
        runFortDL(arguments: args)
        startCacheMonitoring()
    }

    @MainActor
    private func handleStallCheckTick() {
        guard isDownloading else { return }

        if downloadedBytes != lastProgressBytes {
            lastProgressBytes = downloadedBytes
            lastProgressDate = Date()
            return
        }

        if let last = lastProgressDate, Date().timeIntervalSince(last) >= 10 {
            log("⚠️ Download stalled. Attempting to resume every 5 seconds with the same command...")
            activeProcess?.terminate()
            activeProcess = nil
            startAutoResume()
            lastProgressDate = Date()
        }
    }

    private func stopCacheMonitoring() {
        cacheMonitorTimer?.invalidate()
        cacheMonitorTimer = nil
    }

    private func cacheDirectorySize(at url: URL) -> UInt64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += UInt64(size)
            }
        }
        return total
    }

    private func notifyIfNeeded() {
        guard !didNotifyForCurrentDownload else { return }
        didNotifyForCurrentDownload = true
        let enabled = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
        guard enabled else { return }
        NotificationHelper.shared.post(
            title: "Game assets installed",
            body: "You can open Fortnite now."
        )
    }

    // MARK: - Manual Manifest

    func setManualManifestEnabled(_ enabled: Bool) {
        useManualManifest = enabled
        updateManifestID()
        fetchAvailableLayers()
    }

    func setManualManifestID(_ id: String) {
        manualManifestID = id
        updateManifestID()
    }

    func refreshManifest() {
        if useManualManifest, !manualManifestID.isEmpty {
            updateManifestID()
            fetchAvailableLayers()
        } else {
            loadManifest()
            fetchAvailableLayers()
        }
    }

    private func updateManifestID() {
        if useManualManifest, !manualManifestID.isEmpty {
            manifestID = manualManifestID
        } else {
            manifestID = autoManifestID
        }
    }
}
