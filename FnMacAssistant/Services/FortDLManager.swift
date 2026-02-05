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
        return Double(downloadedBytes) / Double(totalBytes)
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
            "-o", outputDir
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
        downloadedBytes = 0
        totalBytes = 0
        didNotifyForCurrentDownload = false
        
        clearFortDLCache()
        runFortDL(arguments: args)
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

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let str = String(decoding: data, as: UTF8.self)

            Task { @MainActor in
                self.log(str)
                self.parseProgress(from: str)
            }
            process.terminationHandler = { _ in
                Task { @MainActor in
                    self.clearFortDLCache()
                }
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

        // PROGRESS_BYTES <downloaded> <total>
        if str.hasPrefix("PROGRESS_BYTES") {
            let parts = str.split(separator: " ")
            if parts.count == 3,
               let downloaded = UInt64(parts[1]),
               let total = UInt64(parts[2]) {

                downloadedBytes = downloaded
                totalBytes = total
                isDownloading = true
                isInstalling = false
                isDone = false
            }
        }

        if str.contains("Extracting files") {
            isDownloading = false
            isInstalling = true
        }

        if str.contains("Done:") {
            isDownloading = false
            isInstalling = false
            isDone = true
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
    private func parseProgress(from output: String) {
        let lines = output.split(separator: "\n")

        for line in lines {
            let text = String(line)

            // ---- DOWNLOAD PROGRESS ----
            if text.hasPrefix("PROGRESS ") {
                // Format: PROGRESS <downloaded> <total>
                let parts = text.split(separator: " ")
                guard parts.count == 3,
                      let downloaded = UInt64(parts[1]),
                      let total = UInt64(parts[2])
                else { continue }

                if !isDownloading {
                    isDownloading = true
                    isInstalling = false
                    isDone = false
                    downloadStartDate = Date()
                }

                downloadedBytes = downloaded
                totalBytes = total
            }

            // ---- INSTALL PHASE ----
            else if text.contains("Extracting files") {
                isDownloading = false
                isInstalling = true
            }

            // ---- DONE ----
            else if text.hasPrefix("Done:") {
                isDownloading = false
                isInstalling = false
                isDone = true
                notifyIfNeeded()
            }
        }
    }
    
    // MARK: - fort-dl Cache

    private var fortDLCacheURL: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("FnMacAssistant-cache", isDirectory: true)
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

            // Fallback hard kill after short delay
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
