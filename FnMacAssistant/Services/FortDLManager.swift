//
//  FortDLManager.swift
//  FnMacAssistant
//
//  Created by Isacucho on 11/01/26.
//

import Foundation
import Combine

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

    private init() {
        loadManifest()
        fetchAvailableLayers()
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
            manifestID = URL(fileURLWithPath: manifestPath)
                .deletingPathExtension()
                .lastPathComponent
        }

        log("✔ Manifest ID: \(manifestID ?? "unknown")")
    }

    // MARK: - Fetch layers / assets

    func fetchAvailableLayers() {
        guard let manifestID else { return }

        resetSelections()
        logOutput = ""

        let process = Process()
        process.executableURL = fortDLURL()
        process.arguments = [
            "--manifest-id", manifestID,
            "--list-tags"
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
        process.executableURL = fortDLURL()
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let str = String(decoding: data, as: UTF8.self)
            Task { @MainActor in self.log(str) }
        }

        try? process.run()
    }

    private func fortDLURL() -> URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/fort-dl")
    }

    private func log(_ str: String) {
        logOutput += str + "\n"
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
}
