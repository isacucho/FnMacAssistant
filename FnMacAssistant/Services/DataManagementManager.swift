//
//  DataManagementManager.swift
//  FnMacAssistant
//
//  Created by Isacucho on 02/21/26.
//


import Foundation
import SwiftUI
import Combine

@MainActor
final class DataManagementManager: ObservableObject {
    static let shared = DataManagementManager()

    private final class MoveCancellationState: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false

        func requestCancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }

        func isCancelled() -> Bool {
            lock.lock()
            let value = cancelled
            lock.unlock()
            return value
        }
    }

    struct BundleItem: Identifiable, Hashable {
        let id: String
        let name: String
        let path: String
        let createdAt: Date?
        let sizeBytes: UInt64
    }

    struct BundleCategory: Identifiable {
        let id: String
        let title: String
        let items: [BundleItem]

        var totalSizeBytes: UInt64 {
            items.reduce(0) { $0 + $1.sizeBytes }
        }
    }

    @Published var categories: [BundleCategory] = []
    @Published var customMaps: [BundleItem] = []

    @Published var selectedBundlePaths: Set<String> = []
    @Published var selectedCustomMapPaths: Set<String> = []

    @Published var currentContainerPath: String?
    @Published var currentFortniteGamePath: String = ""
    @Published var isUsingSymlink = false

    @Published var statusMessage: String = ""
    @Published var isMovingData = false
    @Published var moveProgress: Double = 0
    @Published var moveProgressLabel: String = ""
    @Published var moveCurrentFilePath: String = ""
    @Published var isCancellingMove = false
    @Published var movingToExternalDrive = false
    @Published var isCreatingArchive = false
    @Published var isImportingArchive = false
    @Published var archiveProgress: Double = 0
    @Published var archiveProgressLabel: String = ""

    private let layerDefinitions: [(name: String, tags: [String])] = [
        (
            "base-game",
            [
                "Startup",
                "FNOne",
                "Encrypted",
                "CosmeticPreInstall",
                "GFP_BlitzRoot",
                "GFP_BRCosmeticsInstallOnDemand",
                "GFP_BRCosmeticsInstallOnDemandFat_EnableIAD",
                "Lang.es-ES",
                "Lang.zh-CN",
                "Lang.es-419",
                "Lang.it",
                "StartupOptional",
                "FrontEndOptional",
                "DefaultGameplayChunkOptional",
                "FNOneOptional",
                "EncryptedOptional",
                "CosmeticPreInstallOptional"
            ]
        ),
        ("cosmetics", ["GFP_BRCosmetics"]),
        ("battle-royale", ["FortniteBR", "GFP_BRRoot"]),
        ("creative", ["GFP_CreativeRoot", "GFP_CreativeRootOptional"]),
        ("save-the-world", ["GFP_SaveTheWorldRoot", "GFP_SaveTheWorldRootOptional"]),
        ("rocket-racing", ["GFP_DelMarRoot", "GFP_DelMarRootOptional"]),
        ("lego", ["GFP_JunoRoot"]),
        ("festival", ["GFP_Sparks", "GFP_SparksOptional"]),
        (
            "optional/hd-textures",
            [
                "FortniteBROnDemandOptional",
                "GFP_BRCosmeticsInstallOnDemandFat_DisableIAD",
                "GFP_BaseInstallRootOptional",
                "GFP_BlitzRootOptional",
                "GFP_JunoRootOptional",
                "GFP_BRRootOptional",
                "GFP_BRCosmeticsOptional",
                "GFP_BRCosmeticsInstallOnDemandFat",
                "FortniteBROptional",
                "FortniteBROnDemand",
                "StartupOptional",
                "FrontEndOptional",
                "DefaultGameplayChunkOptional",
                "FNOneOptional",
                "EncryptedOptional",
                "CosmeticPreInstallOptional"
            ]
        ),
        ("daft-punk", ["GFP_StrideMiceRoot", "GFP_Sparks", "GFP_StrideMiceRootOptional"])
    ]

    private lazy var tagToCategory: [String: String] = {
        var mapping: [String: String] = [:]
        for layer in layerDefinitions {
            for tag in layer.tags {
                let canonical = canonicalBundleFolder(tag)
                if mapping[canonical] == nil {
                    mapping[canonical] = layer.name
                }
            }
        }
        return mapping
    }()

    private init() {
        refreshAll()
    }

    private var moveCancellationState: MoveCancellationState?

    var hasSelection: Bool {
        !selectedBundlePaths.isEmpty || !selectedCustomMapPaths.isEmpty
    }

    var selectedCount: Int {
        selectedBundlePaths.count + selectedCustomMapPaths.count
    }

    var archivePercentageLabel: String {
        let percentage = Int((archiveProgress * 100).rounded())
        return "\(max(0, min(100, percentage)))%"
    }

    var isArchiveOperationInProgress: Bool {
        isCreatingArchive || isImportingArchive
    }

    func defaultArchiveFilename() -> String {
        let version = detectedGameVersionForArchive()
        let selectionLabel = archiveSelectionLabel()
        return sanitizeArchiveFilename("\(version) archive (\(selectionLabel)).zip")
    }

    func refreshAll() {
        currentContainerPath = FortniteContainerLocator.shared.getContainerPath()
        refreshCurrentDataLocation()
        loadInstalledBundles()
        loadCustomMaps()
    }

    func refreshCurrentDataLocation() {
        guard let container = currentContainerPath ?? FortniteContainerLocator.shared.getContainerPath() else {
            currentFortniteGamePath = ""
            isUsingSymlink = false
            return
        }

        let sourceURL = containerFortniteGameURL(container: container)

        if isSymlink(at: sourceURL),
           let resolved = resolveSymlinkTarget(at: sourceURL) {
            currentFortniteGamePath = resolved.path
            isUsingSymlink = true
        } else {
            currentFortniteGamePath = sourceURL.path
            isUsingSymlink = false
        }
    }

    func deleteSelected() throws {
        guard FortniteContainerWriteGuard.confirmCanModifyContainer() else {
            throw DataManagementError.fortniteRunning
        }

        let fm = FileManager.default
        let allPaths = selectedBundlePaths.union(selectedCustomMapPaths)

        for path in allPaths {
            if fm.fileExists(atPath: path) {
                try fm.removeItem(atPath: path)
            }
        }

        selectedBundlePaths.removeAll()
        selectedCustomMapPaths.removeAll()
        refreshAll()
        statusMessage = "Deleted \(allPaths.count) selected item(s)."
    }

    func moveFortniteGame(to targetRoot: URL) async throws {
        guard FortniteContainerWriteGuard.confirmCanModifyContainer() else {
            throw DataManagementError.fortniteRunning
        }

        guard let container = currentContainerPath ?? FortniteContainerLocator.shared.getContainerPath() else {
            throw DataManagementError.containerNotFound
        }

        let sourceURL = containerFortniteGameURL(container: container)

        guard FileManager.default.fileExists(atPath: targetRoot.path) else {
            throw DataManagementError.targetNotFound
        }

        try validateTargetRoot(targetRoot)

        let targetURL = targetRoot.appendingPathComponent("FortniteGame", isDirectory: true)

        let sourceReal = sourceURL.resolvingSymlinksInPath().standardizedFileURL.path
        let targetReal = targetURL.resolvingSymlinksInPath().standardizedFileURL.path

        if sourceReal == targetReal {
            refreshCurrentDataLocation()
            statusMessage = "Game data is already using that path."
            return
        }

        if targetRoot.path.hasPrefix(sourceReal + "/") {
            throw DataManagementError.invalidTargetInsideSource
        }

        let fm = FileManager.default
        let isExternal = isExternalVolume(targetRoot)
        let cancellationState = MoveCancellationState()
        moveCancellationState = cancellationState
        movingToExternalDrive = isExternal
        isMovingData = isExternal
        moveProgress = 0
        moveProgressLabel = ""
        moveCurrentFilePath = ""
        isCancellingMove = false
        defer {
            isMovingData = false
            moveProgress = 0
            moveProgressLabel = ""
            moveCurrentFilePath = ""
            isCancellingMove = false
            movingToExternalDrive = false
            moveCancellationState = nil
        }

        if isSymlink(at: sourceURL) {
            let oldTarget = resolveSymlinkTarget(at: sourceURL)

            if !fm.fileExists(atPath: targetURL.path),
               let oldTarget,
               fm.fileExists(atPath: oldTarget.path) {
                if isExternal {
                    try await transferDirectoryWithProgress(from: oldTarget, to: targetURL, cancellationState: cancellationState)
                    try fm.removeItem(at: oldTarget)
                } else {
                    try fm.moveItem(at: oldTarget, to: targetURL)
                }
            }

            try fm.removeItem(at: sourceURL)
            try fm.createSymbolicLink(at: sourceURL, withDestinationURL: targetURL)
        } else {
            if !fm.fileExists(atPath: targetURL.path) {
                if fm.fileExists(atPath: sourceURL.path) {
                    if isExternal {
                        try await transferDirectoryWithProgress(from: sourceURL, to: targetURL, cancellationState: cancellationState)
                        try fm.removeItem(at: sourceURL)
                    } else {
                        try fm.moveItem(at: sourceURL, to: targetURL)
                    }
                } else {
                    try fm.createDirectory(at: targetURL, withIntermediateDirectories: true)
                }
            } else if fm.fileExists(atPath: sourceURL.path) {
                try fm.removeItem(at: sourceURL)
            }

            try fm.createSymbolicLink(at: sourceURL, withDestinationURL: targetURL)
        }

        refreshCurrentDataLocation()
        statusMessage = "Moved FortniteGame and linked container to custom path."
    }

    func requestCancelMove() {
        moveCancellationState?.requestCancel()
        guard isMovingData else { return }
        isCancellingMove = true
        moveProgress = 1
        moveProgressLabel = "Cancelling"
        moveCurrentFilePath = "Cancelling..."
    }

    func isExternalVolume(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.volumeIsInternalKey]),
              let isInternal = values.volumeIsInternal else {
            return false
        }
        return !isInternal
    }

    func resetDataLocationToContainer() throws {
        guard FortniteContainerWriteGuard.confirmCanModifyContainer() else {
            throw DataManagementError.fortniteRunning
        }

        guard let container = currentContainerPath ?? FortniteContainerLocator.shared.getContainerPath() else {
            throw DataManagementError.containerNotFound
        }

        let sourceURL = containerFortniteGameURL(container: container)

        guard isSymlink(at: sourceURL) else {
            throw DataManagementError.notUsingSymlink
        }

        guard let linkTarget = resolveSymlinkTarget(at: sourceURL) else {
            throw DataManagementError.invalidSymlink
        }

        let fm = FileManager.default
        try fm.removeItem(at: sourceURL)

        if fm.fileExists(atPath: linkTarget.path) {
            try fm.moveItem(at: linkTarget, to: sourceURL)
        } else {
            try fm.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        }

        refreshCurrentDataLocation()
        statusMessage = "Reset game data path to container."
    }

    func deleteGameAndData() throws {
        guard FortniteContainerWriteGuard.confirmCanModifyContainer() else {
            throw DataManagementError.fortniteRunning
        }

        let fm = FileManager.default
        let appPath = "/Applications/Fortnite.app"

        if fm.fileExists(atPath: appPath) {
            try fm.removeItem(atPath: appPath)
        }

        if let container = currentContainerPath ?? FortniteContainerLocator.shared.getContainerPath(),
           fm.fileExists(atPath: container) {
            try fm.removeItem(atPath: container)
            FortniteContainerLocator.shared.resetContainer()
            currentContainerPath = nil
        }

        selectedBundlePaths.removeAll()
        selectedCustomMapPaths.removeAll()
        refreshAll()
        statusMessage = "Deleted Fortnite app bundle and container."
    }

    func createSelectedBundlesArchive(destinationURL: URL) async throws {
        guard let container = currentContainerPath ?? FortniteContainerLocator.shared.getContainerPath() else {
            throw DataManagementError.containerNotFound
        }

        guard hasSelection else {
            throw DataManagementError.noBundlesSelected
        }

        let persistentURL = containerPersistentDownloadDirURL(container: container)
        guard FileManager.default.fileExists(atPath: persistentURL.path) else {
            throw DataManagementError.persistentDownloadDirNotFound
        }

        isCreatingArchive = true
        archiveProgress = 0
        archiveProgressLabel = "Preparing archive..."
        defer {
            isCreatingArchive = false
            archiveProgress = 0
            archiveProgressLabel = ""
        }

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("FnMacAssistantArchive-\(UUID().uuidString)", isDirectory: true)
        let stagedPersistentURL = tempRoot.appendingPathComponent("PersistentDownloadDir", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try await stagePersistentDownloadDirForArchive(from: persistentURL, to: stagedPersistentURL)

        archiveProgress = 0.12
        archiveProgressLabel = "Sanitizing archive contents..."
        try sanitizeChunkDownload(in: stagedPersistentURL)
        try filterInstalledBundles(in: stagedPersistentURL)

        archiveProgress = 0.13
        archiveProgressLabel = "Compressing archive..."
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try await zipDirectoryForArchive(source: stagedPersistentURL, destination: destinationURL)
        archiveProgress = 1
        archiveProgressLabel = "Archive complete."
        statusMessage = "Created archive at \(destinationURL.path)."
    }

    func importArchive(from archiveURL: URL) async throws {
        guard FortniteContainerWriteGuard.confirmCanModifyContainer() else {
            throw DataManagementError.fortniteRunning
        }

        guard let container = currentContainerPath ?? FortniteContainerLocator.shared.getContainerPath() else {
            throw DataManagementError.containerNotFound
        }

        guard FileManager.default.fileExists(atPath: archiveURL.path) else {
            throw DataManagementError.archiveImportFailed
        }

        guard Self.validateZipArchive(at: archiveURL) else {
            throw DataManagementError.invalidArchiveFile
        }

        let importRootURL: URL
        if !currentFortniteGamePath.isEmpty {
            importRootURL = URL(fileURLWithPath: currentFortniteGamePath, isDirectory: true)
        } else {
            importRootURL = containerFortniteGameURL(container: container)
        }

        let fm = FileManager.default
        try fm.createDirectory(at: importRootURL, withIntermediateDirectories: true)

        isImportingArchive = true
        archiveProgress = 0
        archiveProgressLabel = "Preparing import..."
        defer {
            isImportingArchive = false
            archiveProgress = 0
            archiveProgressLabel = ""
        }

        let allEntries = Self.zipArchiveEntryList(at: archiveURL)
        let fileEntries = allEntries.filter { !$0.hasSuffix("/") }
        let totalEntries = max(fileEntries.count, 1)
        var importedEntries = 0
        var seenEntries = Set<String>()
        var bufferedOutput = ""

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                process.arguments = ["-o", archiveURL.path, "-d", importRootURL.path]

                let outputPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = outputPipe

                outputPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                    bufferedOutput.append(chunk)

                    while let newline = bufferedOutput.firstIndex(of: "\n") {
                        let line = String(bufferedOutput[..<newline])
                        bufferedOutput.removeSubrange(...newline)

                        guard let entry = Self.parseUnzipProcessedEntry(line) else { continue }
                        guard !entry.hasSuffix("/") else { continue }
                        guard seenEntries.insert(entry).inserted else { continue }

                        importedEntries += 1
                        let phase = min(1, Double(importedEntries) / Double(totalEntries))
                        let overall = min(0.985, phase)
                        DispatchQueue.main.async {
                            self.archiveProgress = overall
                            self.archiveProgressLabel = "Importing archive... \(importedEntries)/\(totalEntries)"
                        }
                    }
                }

                do {
                    try process.run()
                } catch {
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: DataManagementError.archiveImportFailed)
                    return
                }

                process.waitUntilExit()
                outputPipe.fileHandleForReading.readabilityHandler = nil

                guard process.terminationStatus == 0 else {
                    continuation.resume(throwing: DataManagementError.archiveImportFailed)
                    return
                }

                continuation.resume()
            }
        }

        archiveProgress = 0.99
        archiveProgressLabel = "Refreshing bundles..."
        refreshAll()
        archiveProgress = 1
        archiveProgressLabel = "Import complete."
        statusMessage = "Imported archive into \(importRootURL.path)."
    }

    func importPersistentDownloadDirFolder(from sourceFolderURL: URL) async throws {
        guard FortniteContainerWriteGuard.confirmCanModifyContainer() else {
            throw DataManagementError.fortniteRunning
        }

        guard let container = currentContainerPath ?? FortniteContainerLocator.shared.getContainerPath() else {
            throw DataManagementError.containerNotFound
        }

        guard sourceFolderURL.lastPathComponent == "PersistentDownloadDir" else {
            throw DataManagementError.invalidImportFolder
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sourceFolderURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw DataManagementError.invalidImportFolder
        }

        let importRootURL: URL
        if !currentFortniteGamePath.isEmpty {
            importRootURL = URL(fileURLWithPath: currentFortniteGamePath, isDirectory: true)
        } else {
            importRootURL = containerFortniteGameURL(container: container)
        }

        let destinationPersistentURL = importRootURL.appendingPathComponent("PersistentDownloadDir", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: destinationPersistentURL, withIntermediateDirectories: true)

        let totalFiles = max(Self.regularFileCount(in: sourceFolderURL), 1)
        var importedFiles = 0

        isImportingArchive = true
        archiveProgress = 0
        archiveProgressLabel = "Preparing import..."
        defer {
            isImportingArchive = false
            archiveProgress = 0
            archiveProgressLabel = ""
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    guard let enumerator = fm.enumerator(
                        at: sourceFolderURL,
                        includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                        options: [.skipsHiddenFiles],
                        errorHandler: nil
                    ) else {
                        continuation.resume()
                        return
                    }

                    let sourceRootPath = sourceFolderURL.path
                    for case let itemURL as URL in enumerator {
                        let values = try itemURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
                        let relativePath = String(itemURL.path.dropFirst(sourceRootPath.count))
                            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                        guard !relativePath.isEmpty else { continue }

                        let destinationURL = destinationPersistentURL.appendingPathComponent(relativePath)

                        if values.isDirectory == true {
                            try fm.createDirectory(at: destinationURL, withIntermediateDirectories: true)
                            continue
                        }

                        guard values.isRegularFile == true else { continue }
                        try fm.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                        if fm.fileExists(atPath: destinationURL.path) {
                            try fm.removeItem(at: destinationURL)
                        }
                        _ = try Self.copyFileWithoutChunking(from: itemURL, to: destinationURL)

                        importedFiles += 1
                        let phase = min(1, Double(importedFiles) / Double(totalFiles))
                        let overall = min(0.985, phase)
                        DispatchQueue.main.async {
                            self.archiveProgress = overall
                            self.archiveProgressLabel = "Importing folder... \(importedFiles)/\(totalFiles)"
                        }
                    }

                    continuation.resume()
                } catch {
                    continuation.resume(throwing: DataManagementError.archiveImportFailed)
                }
            }
        }

        archiveProgress = 0.99
        archiveProgressLabel = "Refreshing bundles..."
        refreshAll()
        archiveProgress = 1
        archiveProgressLabel = "Import complete."
        statusMessage = "Imported PersistentDownloadDir into \(destinationPersistentURL.path)."
    }

    func isEntireCategorySelected(_ category: BundleCategory) -> Bool {
        guard !category.items.isEmpty else { return false }
        return category.items.allSatisfy { selectedBundlePaths.contains($0.path) }
    }

    func setCategory(_ category: BundleCategory, selected: Bool) {
        let paths = category.items.map(\.path)
        if selected {
            selectedBundlePaths.formUnion(paths)
        } else {
            selectedBundlePaths.subtract(paths)
        }
    }

    private func loadInstalledBundles() {
        guard let container = currentContainerPath ?? FortniteContainerLocator.shared.getContainerPath() else {
            categories = []
            return
        }

        let installedURL = containerPersistentDownloadDirURL(container: container)
            .appendingPathComponent("InstalledBundles", isDirectory: true)

        guard let folderURLs = directoryURLs(at: installedURL) else {
            categories = []
            return
        }

        var grouped: [String: [BundleItem]] = [:]

        for folderURL in folderURLs {
            let folderName = folderURL.lastPathComponent
            let canonicalName = canonicalBundleFolder(folderName)
            let categoryName: String
            if canonicalName.localizedCaseInsensitiveContains("delmar") {
                categoryName = "rocket-racing"
            } else {
                categoryName = tagToCategory[canonicalName] ?? "other"
            }
            let attributes = (try? FileManager.default.attributesOfItem(atPath: folderURL.path)) ?? [:]
            let createdAt = attributes[.creationDate] as? Date
            let size = directorySize(at: folderURL)

            let item = BundleItem(
                id: folderURL.path,
                name: folderName,
                path: folderURL.path,
                createdAt: createdAt,
                sizeBytes: size
            )

            grouped[categoryName, default: []].append(item)
        }

        let orderedNames = layerDefinitions.map(\.name) + ["other"]
        categories = orderedNames.compactMap { categoryName in
            guard let items = grouped[categoryName], !items.isEmpty else { return nil }
            let sorted = items.sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return BundleCategory(
                id: categoryName,
                title: displayName(for: categoryName),
                items: sorted
            )
        }

        let valid = Set(categories.flatMap { $0.items.map(\.path) })
        selectedBundlePaths = selectedBundlePaths.intersection(valid)
    }

    private func loadCustomMaps() {
        guard let container = currentContainerPath ?? FortniteContainerLocator.shared.getContainerPath() else {
            customMaps = []
            return
        }

        let customURL = containerPersistentDownloadDirURL(container: container)
            .appendingPathComponent("GameCustom/InstalledBundles", isDirectory: true)

        guard let folderURLs = directoryURLs(at: customURL) else {
            customMaps = []
            return
        }

        customMaps = folderURLs.compactMap { folderURL in
            let attributes = (try? FileManager.default.attributesOfItem(atPath: folderURL.path)) ?? [:]
            let createdAt = attributes[.creationDate] as? Date
            let size = directorySize(at: folderURL)

            let labelDate = createdAt?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown date"
            let labelSize = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)

            return BundleItem(
                id: folderURL.path,
                name: "\(labelDate) • \(labelSize)",
                path: folderURL.path,
                createdAt: createdAt,
                sizeBytes: size
            )
        }
        .sorted { lhs, rhs in
            let left = lhs.createdAt ?? .distantPast
            let right = rhs.createdAt ?? .distantPast
            return left > right
        }

        let valid = Set(customMaps.map(\.path))
        selectedCustomMapPaths = selectedCustomMapPaths.intersection(valid)
    }

    private func validateTargetRoot(_ targetRoot: URL) throws {
        let entries = try FileManager.default.contentsOfDirectory(
            at: targetRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        if entries.isEmpty {
            return
        }

        if entries.count == 1, entries.first?.lastPathComponent == "FortniteGame" {
            return
        }

        throw DataManagementError.targetMustBeEmpty
    }

    private func directoryURLs(at url: URL) -> [URL]? {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return urls.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    private func canonicalBundleFolder(_ tag: String) -> String {
        switch tag {
        case "GFP_BRCosmeticsInstallOnDemandFat_EnableIAD", "GFP_BRCosmeticsInstallOnDemandFat_DisableIAD":
            return "GFP_BRCosmeticsInstallOnDemandFat"
        default:
            return tag
        }
    }

    private func displayName(for categoryID: String) -> String {
        switch categoryID {
        case "base-game":
            return "Base Game"
        case "cosmetics":
            return "Cosmetics"
        case "battle-royale":
            return "Battle Royale"
        case "creative":
            return "Creative"
        case "save-the-world":
            return "Save the World"
        case "rocket-racing":
            return "Rocket Racing"
        case "lego":
            return "LEGO"
        case "festival":
            return "Festival"
        case "optional/hd-textures":
            return "Optional / HD Textures"
        case "daft-punk":
            return "Daft Punk"
        case "other":
            return "Other"
        default:
            return categoryID
        }
    }

    private func containerFortniteGameURL(container: String) -> URL {
        let root = URL(fileURLWithPath: container, isDirectory: true)
        let lower = root.appendingPathComponent("data/Documents/FortniteGame", isDirectory: true)
        if FileManager.default.fileExists(atPath: lower.path) || isSymlink(at: lower) {
            return lower
        }
        return root.appendingPathComponent("Data/Documents/FortniteGame", isDirectory: true)
    }

    private func containerPersistentDownloadDirURL(container: String) -> URL {
        containerFortniteGameURL(container: container)
            .appendingPathComponent("PersistentDownloadDir", isDirectory: true)
    }

    private func isSymlink(at url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]) else {
            return false
        }
        return values.isSymbolicLink == true
    }

    private func resolveSymlinkTarget(at url: URL) -> URL? {
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) else {
            return nil
        }

        if destination.hasPrefix("/") {
            return URL(fileURLWithPath: destination, isDirectory: true)
        }

        return url.deletingLastPathComponent()
            .appendingPathComponent(destination, isDirectory: true)
            .standardizedFileURL
    }

    private func directorySize(at url: URL) -> UInt64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return 0
        }

        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]),
                  values.isRegularFile == true else {
                continue
            }

            if let allocated = values.totalFileAllocatedSize {
                total += UInt64(allocated)
            } else if let size = values.fileSize {
                total += UInt64(size)
            }
        }

        return total
    }

    private func detectedGameVersionForArchive() -> String {
        if let version = gameVersionFromCloudContent() {
            return version
        }

        if let container = currentContainerPath ?? FortniteContainerLocator.shared.getContainerPath(),
           let version = gameVersionFromBackgroundHttp(container: container) {
            return version
        }

        return "unknown-version"
    }

    private func gameVersionFromCloudContent() -> String? {
        let cloudJSON = "/Applications/Fortnite.app/Wrapper/FortniteClient-IOS-Shipping.app/Cloud/cloudcontent.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: cloudJSON)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let buildVersion = json["BuildVersion"] as? String else {
            return nil
        }
        return extractNumericVersion(from: buildVersion)
    }

    private func gameVersionFromBackgroundHttp(container: String) -> String? {
        let backgroundHttpURL = containerPersistentDownloadDirURL(container: container)
            .appendingPathComponent("BackgroundHttp", isDirectory: true)

        guard let folders = directoryURLs(at: backgroundHttpURL), !folders.isEmpty else {
            return nil
        }

        let sortedNames = folders.map(\.lastPathComponent).sorted { $0.localizedStandardCompare($1) == .orderedDescending }
        for name in sortedNames {
            if let version = extractNumericVersion(from: name) {
                return version
            }
        }
        return nil
    }

    private func extractNumericVersion(from value: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "(\\d+(?:\\.\\d+)+)") else {
            return nil
        }
        let nsRange = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: nsRange),
              let range = Range(match.range(at: 1), in: value) else {
            return nil
        }
        return String(value[range])
    }

    private func archiveSelectionLabel() -> String {
        let fullySelectedCategories = categories
            .filter { isEntireCategorySelected($0) }
            .map(\.title)

        var components: [String] = []
        components.append(contentsOf: fullySelectedCategories)

        let pathsCoveredBySelectedCategories = Set(
            categories
                .filter { isEntireCategorySelected($0) }
                .flatMap { $0.items.map(\.path) }
        )

        let individuallySelectedBundleNames = selectedBundlePaths
            .subtracting(pathsCoveredBySelectedCategories)
            .map { URL(fileURLWithPath: $0).lastPathComponent }
            .sorted()

        let selectedCustomMapNames = selectedCustomMapPaths
            .map { URL(fileURLWithPath: $0).lastPathComponent }
            .sorted()

        components.append(contentsOf: individuallySelectedBundleNames)
        components.append(contentsOf: selectedCustomMapNames)

        if components.isEmpty {
            return "selected-bundles"
        }

        let joined = components.joined(separator: ", ")
        if joined.count <= 90 {
            return joined
        }

        return "\(components.prefix(3).joined(separator: ", ")) +\(components.count - 3) more"
    }

    private func sanitizeArchiveFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleanedScalars = value.unicodeScalars.map { invalid.contains($0) ? "-" : Character($0) }
        let cleaned = String(cleanedScalars)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.count <= 140 {
            return cleaned
        }

        let withoutZip = cleaned.hasSuffix(".zip") ? String(cleaned.dropLast(4)) : cleaned
        let prefix = withoutZip.prefix(136)
        return "\(prefix).zip"
    }

    private func sanitizeChunkDownload(in persistentURL: URL) throws {
        let fm = FileManager.default
        let candidates = ["chunkdownload", "ChunkDownload"]

        for name in candidates {
            let folderURL = persistentURL.appendingPathComponent(name, isDirectory: true)
            guard fm.fileExists(atPath: folderURL.path) else { continue }
            let contents = try fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            for item in contents {
                try fm.removeItem(at: item)
            }
        }
    }

    private func filterInstalledBundles(in persistentURL: URL) throws {
        let selectedBundleNames = Set(selectedBundlePaths.map { URL(fileURLWithPath: $0).lastPathComponent })
        let selectedCustomMapNames = Set(selectedCustomMapPaths.map { URL(fileURLWithPath: $0).lastPathComponent })

        let installedBundlesURL = persistentURL.appendingPathComponent("InstalledBundles", isDirectory: true)
        try filterDirectoryContents(at: installedBundlesURL, keepingDirectoriesNamed: selectedBundleNames)

        let gameCustomInstalledBundlesURL = persistentURL
            .appendingPathComponent("GameCustom", isDirectory: true)
            .appendingPathComponent("InstalledBundles", isDirectory: true)
        try filterDirectoryContents(at: gameCustomInstalledBundlesURL, keepingDirectoriesNamed: selectedCustomMapNames)
    }

    private func filterDirectoryContents(at directoryURL: URL, keepingDirectoriesNamed selectedNames: Set<String>) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directoryURL.path) else { return }

        let contents = try fm.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for itemURL in contents {
            let isDirectory = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDirectory, selectedNames.contains(itemURL.lastPathComponent) {
                continue
            }
            try fm.removeItem(at: itemURL)
        }
    }

    private struct ArchiveCopyTask {
        let source: URL
        let destination: URL
        let isDirectory: Bool
        let sizeBytes: UInt64
    }

    private func stagePersistentDownloadDirForArchive(from source: URL, to destination: URL) async throws {
        let fm = FileManager.default
        let selectedBundleNames = Set(selectedBundlePaths.map { URL(fileURLWithPath: $0).lastPathComponent })
        let selectedCustomMapNames = Set(selectedCustomMapPaths.map { URL(fileURLWithPath: $0).lastPathComponent })

        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        var tasks: [ArchiveCopyTask] = []

        func addTask(sourceURL: URL, destinationURL: URL) {
            let isDirectory = (try? sourceURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            let size = isDirectory ? directorySize(at: sourceURL) : fileSize(at: sourceURL)
            tasks.append(ArchiveCopyTask(
                source: sourceURL,
                destination: destinationURL,
                isDirectory: isDirectory,
                sizeBytes: size
            ))
        }

        let topLevelEntries = try fm.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for entry in topLevelEntries {
            let name = entry.lastPathComponent
            let lowercasedName = name.lowercased()
            let destinationEntry = destination.appendingPathComponent(name, isDirectory: true)

            if lowercasedName == "chunkdownload" {
                try fm.createDirectory(at: destinationEntry, withIntermediateDirectories: true)
                continue
            }

            if lowercasedName == "installedbundles" {
                try fm.createDirectory(at: destinationEntry, withIntermediateDirectories: true)
                let bundleDirectories = directoryURLs(at: entry) ?? []
                for bundleDirectory in bundleDirectories where selectedBundleNames.contains(bundleDirectory.lastPathComponent) {
                    let destinationBundle = destinationEntry.appendingPathComponent(bundleDirectory.lastPathComponent, isDirectory: true)
                    addTask(sourceURL: bundleDirectory, destinationURL: destinationBundle)
                }
                continue
            }

            if lowercasedName == "gamecustom" {
                try fm.createDirectory(at: destinationEntry, withIntermediateDirectories: true)
                let gameCustomEntries = try fm.contentsOfDirectory(
                    at: entry,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )

                for gameCustomEntry in gameCustomEntries {
                    let childName = gameCustomEntry.lastPathComponent
                    let destinationChild = destinationEntry.appendingPathComponent(childName, isDirectory: true)
                    if childName.lowercased() == "installedbundles" {
                        try fm.createDirectory(at: destinationChild, withIntermediateDirectories: true)
                        let mapDirectories = directoryURLs(at: gameCustomEntry) ?? []
                        for mapDirectory in mapDirectories where selectedCustomMapNames.contains(mapDirectory.lastPathComponent) {
                            let destinationMap = destinationChild.appendingPathComponent(mapDirectory.lastPathComponent, isDirectory: true)
                            addTask(sourceURL: mapDirectory, destinationURL: destinationMap)
                        }
                    } else {
                        addTask(sourceURL: gameCustomEntry, destinationURL: destinationChild)
                    }
                }
                continue
            }

            addTask(sourceURL: entry, destinationURL: destinationEntry)
        }

        let totalBytes = max(tasks.reduce(0) { $0 + $1.sizeBytes }, 1)
        var copiedBytes: UInt64 = 0
        for task in tasks {
            copiedBytes = try await copyArchiveTask(task, totalBytes: totalBytes, copiedBytes: copiedBytes)
        }
    }

    private func copyArchiveTask(
        _ task: ArchiveCopyTask,
        totalBytes: UInt64,
        copiedBytes: UInt64
    ) async throws -> UInt64 {
        if task.isDirectory {
            return try await copyDirectoryWithArchiveProgress(
                from: task.source,
                to: task.destination,
                totalBytes: totalBytes,
                copiedBytes: copiedBytes
            )
        }

        return try await copyFileWithArchiveProgress(
            from: task.source,
            to: task.destination,
            totalBytes: totalBytes,
            copiedBytes: copiedBytes
        )
    }

    private func copyDirectoryWithArchiveProgress(
        from source: URL,
        to destination: URL,
        totalBytes: UInt64,
        copiedBytes: UInt64
    ) async throws -> UInt64 {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt64, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    var localCopiedBytes = copiedBytes
                    try Self.copyDirectoryRecursivelyWithProgress(
                        from: source,
                        to: destination,
                        progress: { copied in
                            localCopiedBytes = copiedBytes + copied
                            let phaseProgress = min(1, Double(localCopiedBytes) / Double(totalBytes))
                            let scaledProgress = phaseProgress * 0.1
                            let copiedLabel = ByteCountFormatter.string(fromByteCount: Int64(localCopiedBytes), countStyle: .file)
                            let totalLabel = ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
                            DispatchQueue.main.async {
                                self.archiveProgress = scaledProgress
                                self.archiveProgressLabel = "Copying files \(copiedLabel) / \(totalLabel)"
                            }
                        }
                    )
                    continuation.resume(returning: localCopiedBytes)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func copyFileWithArchiveProgress(
        from source: URL,
        to destination: URL,
        totalBytes: UInt64,
        copiedBytes: UInt64
    ) async throws -> UInt64 {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt64, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    var localCopiedBytes = copiedBytes
                    let destinationParent = destination.deletingLastPathComponent()
                    try FileManager.default.createDirectory(at: destinationParent, withIntermediateDirectories: true)
                    let written = try Self.copyFileWithoutChunking(from: source, to: destination)
                    localCopiedBytes += written
                    let phaseProgress = min(1, Double(localCopiedBytes) / Double(totalBytes))
                    let scaledProgress = phaseProgress * 0.1
                    let copiedLabel = ByteCountFormatter.string(fromByteCount: Int64(localCopiedBytes), countStyle: .file)
                    let totalLabel = ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
                    DispatchQueue.main.async {
                        self.archiveProgress = scaledProgress
                        self.archiveProgressLabel = "Copying files \(copiedLabel) / \(totalLabel)"
                    }
                    continuation.resume(returning: localCopiedBytes)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func fileSize(at url: URL) -> UInt64 {
        let attributes = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let number = attributes[.size] as? NSNumber
        return number?.uint64Value ?? 0
    }

    private func zipDirectoryForArchive(source: URL, destination: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let fm = FileManager.default
                let tempZipURL = destination.deletingLastPathComponent()
                    .appendingPathComponent(".tmp-\(UUID().uuidString).zip", isDirectory: false)
                let sourceParent = source.deletingLastPathComponent()
                let sourceFolderName = source.lastPathComponent
                let (entrySizes, totalSourceBytesRaw) = Self.zipEntrySizeMap(for: source)
                let totalSourceBytes = max(totalSourceBytesRaw, 1)
                let formatter = ByteCountFormatter()
                formatter.countStyle = .file
                let zipDotSizeBytes: UInt64 = 4 * 1024 * 1024

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                process.currentDirectoryURL = sourceParent
                process.arguments = ["-r", "-y", "-dd", "-dg", "-ds", "4m", tempZipURL.path, sourceFolderName]

                let outputPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = outputPipe

                var dotBasedProcessedBytes: UInt64 = 0
                var entryBasedProcessedBytes: UInt64 = 0
                var seenEntries = Set<String>()
                var bufferedOutput = ""

                outputPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                    let dotCount = UInt64(chunk.reduce(into: 0) { count, character in
                        if character == "." { count += 1 }
                    })
                    if dotCount > 0 {
                        let increment = dotCount * zipDotSizeBytes
                        dotBasedProcessedBytes = min(totalSourceBytes, dotBasedProcessedBytes + increment)
                    }
                    bufferedOutput.append(chunk)

                    while let newline = bufferedOutput.firstIndex(of: "\n") {
                        let line = String(bufferedOutput[..<newline])
                        bufferedOutput.removeSubrange(...newline)

                        guard let entry = Self.parseZipAddedEntry(line) else { continue }
                        guard seenEntries.insert(entry).inserted else { continue }
                        if let size = entrySizes[entry] {
                            entryBasedProcessedBytes += size
                        }
                    }

                    let processedSourceBytes = max(dotBasedProcessedBytes, entryBasedProcessedBytes)
                    if processedSourceBytes > 0 {
                        let isFinalizingCompression = process.isRunning && processedSourceBytes >= totalSourceBytes
                        let displayedProcessedBytes: UInt64
                        if isFinalizingCompression && totalSourceBytes > 1 {
                            displayedProcessedBytes = totalSourceBytes - 1
                        } else {
                            displayedProcessedBytes = min(processedSourceBytes, totalSourceBytes)
                        }
                        let phase = min(1, Double(displayedProcessedBytes) / Double(totalSourceBytes))
                        let overall = 0.13 + (0.855 * phase)
                        let copiedLabel = formatter.string(fromByteCount: Int64(displayedProcessedBytes))
                        let totalLabel = formatter.string(fromByteCount: Int64(totalSourceBytes))
                        DispatchQueue.main.async {
                            self.archiveProgress = min(1, overall)
                            if isFinalizingCompression {
                                self.archiveProgressLabel = "Finalizing compression..."
                            } else {
                                self.archiveProgressLabel = "Compressing archive... \(copiedLabel) / \(totalLabel)"
                            }
                        }
                    }
                }

                do {
                    try process.run()
                } catch {
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    try? fm.removeItem(at: tempZipURL)
                    continuation.resume(throwing: DataManagementError.archiveCreationFailed)
                    return
                }

                while process.isRunning {
                    let archiveBytes = Self.fileSizeOnDisk(at: tempZipURL)
                    let fallbackPhase = min(0.985, Double(archiveBytes) / Double(totalSourceBytes))
                    let fallbackOverall = 0.13 + (0.855 * fallbackPhase)
                    DispatchQueue.main.async {
                        self.archiveProgress = max(self.archiveProgress, fallbackOverall)
                        if dotBasedProcessedBytes == 0 && entryBasedProcessedBytes == 0 {
                            self.archiveProgressLabel = "Compressing archive..."
                        }
                    }
                    Thread.sleep(forTimeInterval: 0.12)
                }
                process.waitUntilExit()

                outputPipe.fileHandleForReading.readabilityHandler = nil

                guard process.terminationStatus == 0 else {
                    try? fm.removeItem(at: tempZipURL)
                    continuation.resume(throwing: DataManagementError.archiveCreationFailed)
                    return
                }

                DispatchQueue.main.sync {
                    self.archiveProgress = max(self.archiveProgress, 0.987)
                    self.archiveProgressLabel = "Validating archive..."
                }
                guard Self.validateZipArchive(at: tempZipURL) else {
                    try? fm.removeItem(at: tempZipURL)
                    continuation.resume(throwing: DataManagementError.archiveValidationFailed)
                    return
                }

                DispatchQueue.main.sync {
                    self.archiveProgress = max(self.archiveProgress, 0.995)
                    self.archiveProgressLabel = "Finalizing archive..."
                }
                do {
                    if fm.fileExists(atPath: destination.path) {
                        try fm.removeItem(at: destination)
                    }
                    try fm.moveItem(at: tempZipURL, to: destination)
                } catch {
                    try? fm.removeItem(at: tempZipURL)
                    continuation.resume(throwing: DataManagementError.archiveCreationFailed)
                    return
                }

                continuation.resume()
            }
        }
    }

    private func transferDirectoryWithProgress(
        from sourceURL: URL,
        to targetURL: URL,
        cancellationState: MoveCancellationState
    ) async throws {
        let totalBytes = max(directorySize(at: sourceURL), 1)
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var createdPaths: [URL] = []
                do {
                    try Self.copyDirectoryRecursivelyWithProgress(
                        from: sourceURL,
                        to: targetURL,
                        progress: { copiedBytes in
                            let progress = min(1, Double(copiedBytes) / Double(totalBytes))
                            let copiedLabel = formatter.string(fromByteCount: Int64(copiedBytes))
                            let totalLabel = formatter.string(fromByteCount: Int64(totalBytes))
                            DispatchQueue.main.async {
                                guard !self.isCancellingMove else { return }
                                self.moveProgress = progress
                                self.moveProgressLabel = "\(copiedLabel) / \(totalLabel)"
                            }
                        },
                        currentItem: { relativePath in
                            DispatchQueue.main.async {
                                guard !self.isCancellingMove else { return }
                                self.moveCurrentFilePath = relativePath
                            }
                        },
                        shouldCancel: {
                            cancellationState.isCancelled()
                        },
                        onCreate: { createdURL in
                            createdPaths.append(createdURL)
                        }
                    )
                    continuation.resume()
                } catch {
                    if cancellationState.isCancelled() {
                        Self.cleanupCreatedPaths(createdPaths)
                        continuation.resume(throwing: DataManagementError.transferCancelled)
                        return
                    }
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    nonisolated private static func copyDirectoryRecursivelyWithProgress(
        from sourceURL: URL,
        to targetURL: URL,
        progress: @escaping @Sendable (UInt64) -> Void,
        currentItem: @escaping @Sendable (String) -> Void = { _ in },
        shouldCancel: @escaping @Sendable () -> Bool = { false },
        onCreate: @escaping @Sendable (URL) -> Void = { _ in }
    ) throws {
        let fm = FileManager.default
        let sourcePath = sourceURL.path

        let targetExisted = fm.fileExists(atPath: targetURL.path)
        try fm.createDirectory(at: targetURL, withIntermediateDirectories: true)
        if !targetExisted {
            onCreate(targetURL)
        }

        guard let enumerator = fm.enumerator(
            at: sourceURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return
        }

        var copiedBytes: UInt64 = 0

        for case let itemURL as URL in enumerator {
            if shouldCancel() {
                throw DataManagementError.transferCancelled
            }
            let relativePath = String(itemURL.path.dropFirst(sourcePath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let destinationURL = targetURL.appendingPathComponent(relativePath, isDirectory: false)
            let destinationParent = destinationURL.deletingLastPathComponent()

            let values = try itemURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])

            if values.isDirectory == true {
                let existed = fm.fileExists(atPath: destinationURL.path)
                try fm.createDirectory(at: destinationURL, withIntermediateDirectories: true)
                if !existed {
                    onCreate(destinationURL)
                }
                continue
            }

            try fm.createDirectory(at: destinationParent, withIntermediateDirectories: true)

            if values.isRegularFile == true {
                currentItem(relativePath)
                var lastReported: UInt64 = 0
                let written = try copyFileWithoutChunking(
                    from: itemURL,
                    to: destinationURL,
                    onProgress: { currentSize in
                        if currentSize > lastReported {
                            copiedBytes += (currentSize - lastReported)
                            lastReported = currentSize
                            progress(copiedBytes)
                        }
                    }
                )
                if written > lastReported {
                    copiedBytes += (written - lastReported)
                    progress(copiedBytes)
                }
                onCreate(destinationURL)
            } else {
                try fm.copyItem(at: itemURL, to: destinationURL)
                onCreate(destinationURL)
            }
        }
    }

    nonisolated private static func copyFileWithoutChunking(
        from sourceURL: URL,
        to destinationURL: URL,
        onProgress: @escaping @Sendable (UInt64) -> Void = { _ in }
    ) throws -> UInt64 {
        let fm = FileManager.default
        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }

        var copyError: Error?
        let copyQueue = DispatchQueue(label: "fnmacassistant.copyfile", qos: .userInitiated)
        let group = DispatchGroup()
        group.enter()
        copyQueue.async {
            defer { group.leave() }
            do {
                try fm.copyItem(at: sourceURL, to: destinationURL)
            } catch {
                copyError = error
            }
        }

        while group.wait(timeout: .now() + 0.08) == .timedOut {
            let currentSize = fileSizeOnDisk(at: destinationURL)
            onProgress(currentSize)
        }

        if let copyError {
            throw copyError
        }

        let attributes = try fm.attributesOfItem(atPath: sourceURL.path)
        try fm.setAttributes(attributes, ofItemAtPath: destinationURL.path)
        let number = attributes[.size] as? NSNumber
        let finalSize = number?.uint64Value ?? 0
        onProgress(finalSize)
        return finalSize
    }

    nonisolated private static func cleanupCreatedPaths(_ createdPaths: [URL]) {
        let fm = FileManager.default
        let sorted = createdPaths.sorted { $0.path.count > $1.path.count }
        for path in sorted where fm.fileExists(atPath: path.path) {
            try? fm.removeItem(at: path)
        }
    }

    nonisolated private static func fileSizeOnDisk(at url: URL) -> UInt64 {
        let attributes = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let number = attributes[.size] as? NSNumber
        return number?.uint64Value ?? 0
    }

    nonisolated private static func zipEntrySizeMap(for directory: URL) -> ([String: UInt64], UInt64) {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return ([:], 0)
        }

        let rootPath = directory.path
        let rootName = directory.lastPathComponent
        var entrySizes: [String: UInt64] = [:]
        var totalBytes: UInt64 = 0

        for case let itemURL as URL in enumerator {
            let values = (try? itemURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])) ?? URLResourceValues()
            guard values.isRegularFile == true else { continue }
            let relativePath = String(itemURL.path.dropFirst(rootPath.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !relativePath.isEmpty else { continue }
            let archivePath = "\(rootName)/\(relativePath)"
            let size = UInt64(max(values.fileSize ?? 0, 0))
            entrySizes[archivePath] = size
            totalBytes += size
        }
        return (entrySizes, totalBytes)
    }

    nonisolated private static func parseZipAddedEntry(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("adding: ") else { return nil }
        let payload = String(trimmed.dropFirst("adding: ".count))
        if let suffixRange = payload.range(of: " (") {
            return String(payload[..<suffixRange.lowerBound])
        }
        return payload.isEmpty ? nil : payload
    }

    nonisolated private static func parseUnzipProcessedEntry(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["inflating: ", "extracting: ", "creating: "]
        for prefix in prefixes where trimmed.hasPrefix(prefix) {
            return String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    nonisolated private static func zipArchiveEntryList(at archiveURL: URL) -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Z1", archiveURL.path]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return [] }
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            guard let text = String(data: data, encoding: .utf8) else { return [] }
            return text
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } catch {
            return []
        }
    }

    nonisolated private static func regularFileCount(in directory: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return 0
        }

        var total = 0
        for case let itemURL as URL in enumerator {
            let values = try? itemURL.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true {
                total += 1
            }
        }
        return total
    }

    nonisolated private static func validateZipArchive(at archiveURL: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-tqq", archiveURL.path]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

enum DataManagementError: LocalizedError {
    case containerNotFound
    case fortniteRunning
    case targetNotFound
    case targetMustBeEmpty
    case invalidTargetInsideSource
    case notUsingSymlink
    case invalidSymlink
    case transferCancelled
    case noBundlesSelected
    case persistentDownloadDirNotFound
    case archiveCreationFailed
    case archiveValidationFailed
    case invalidArchiveFile
    case archiveImportFailed
    case invalidImportFolder

    var errorDescription: String? {
        switch self {
        case .containerNotFound:
            return "Fortnite container not found. Set it first in Settings."
        case .fortniteRunning:
            return "Fortnite must be closed before modifying game data."
        case .targetNotFound:
            return "Selected target folder does not exist."
        case .targetMustBeEmpty:
            return "Selected folder must be empty or contain only a FortniteGame folder."
        case .invalidTargetInsideSource:
            return "Target folder cannot be inside the current FortniteGame folder."
        case .notUsingSymlink:
            return "Game data is already using the container path."
        case .invalidSymlink:
            return "Could not resolve current symlink target."
        case .transferCancelled:
            return "Transfer cancelled. Copied files were removed."
        case .noBundlesSelected:
            return "Select at least one bundle before creating an archive."
        case .persistentDownloadDirNotFound:
            return "PersistentDownloadDir was not found in the selected container."
        case .archiveCreationFailed:
            return "Could not create archive."
        case .archiveValidationFailed:
            return "Archive was created but failed integrity validation."
        case .invalidArchiveFile:
            return "Selected archive is invalid or corrupted."
        case .archiveImportFailed:
            return "Could not import archive."
        case .invalidImportFolder:
            return "Selected folder must be named 'PersistentDownloadDir'."
        }
    }
}
