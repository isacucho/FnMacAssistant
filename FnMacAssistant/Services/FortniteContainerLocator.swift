//
//  FortniteContainerLocator.swift
//  FnMacAssistant
//
//  Created by Isacucho on 14/11/25.
//

import Foundation
import AppKit
import Combine   

final class FortniteContainerLocator: ObservableObject {
    static let requestAutoDetectionNotification = Notification.Name("FnMacAssistantRequestContainerAutoDetection")
    static let resumeUpdateAssistantNotification = Notification.Name("FnMacAssistantResumeUpdateAssistant")
    static let resumeGameAssetsDownloadNotification = Notification.Name("FnMacAssistantResumeGameAssetsDownload")
    static let requestAutoDetectionWorkflowKey = "workflow"

    static let containerAccessGuidance = """
Grant Full Disk Access to FnMacAssistant.

If you prefer not to, go to Settings > Fortnite Container and select it manually.
"""

    static let containerAccessFailureMessage = """
FnMacAssistant couldn't access Fortnite's container.
\(containerAccessGuidance)
"""

    struct ContainerCandidate: Identifiable, Hashable {
        let path: String
        let dataSize: UInt64
        let modified: Date

        var id: String { path }
    }

    struct LocateResult {
        let selected: ContainerCandidate
        let additional: [ContainerCandidate]
    }

    struct DetectionOutcome {
        let allCandidates: [ContainerCandidate]
        let selected: ContainerCandidate?
        let additional: [ContainerCandidate]
        let ambiguousCandidates: [ContainerCandidate]
        let suggestedCandidate: ContainerCandidate?
        let needsPatchPrompt: Bool
        let allTiny: Bool
        let accessDenied: Bool
    }

    static let shared = FortniteContainerLocator()

    @Published var cachedPath: String? {
        didSet {
            if let path = cachedPath {
                UserDefaults.standard.set(path, forKey: "FortniteContainerPath")
            } else {
                UserDefaults.standard.removeObject(forKey: "FortniteContainerPath")
            }
        }
    }

    private init() {
        // Load cache from UserDefaults
        cachedPath = UserDefaults.standard.string(forKey: "FortniteContainerPath")
    }

    // MARK: - Public API

    func getContainerPath() -> String? {
        if let cached = cachedPath, !cached.isEmpty {
            return cached
        }

        let found = locateContainer()
        cachedPath = found
        return found
    }

    func resetContainer() {
        cachedPath = nil
    }

    func manuallySetContainer(path: String) {
        cachedPath = path
    }

    // MARK: - Automatic detection

    func locateContainer() -> String? {
        locateContainerWithDetails()?.selected.path
    }

    func locateContainerWithDetails() -> LocateResult? {
        let outcome = detectContainerOutcome()
        guard let selected = outcome.selected else {
            return nil
        }

        let additional = outcome.additional
        return LocateResult(selected: selected, additional: additional)
    }

    func detectContainerOutcome() -> DetectionOutcome {
        let candidates = deduplicatedCandidates(findContainerCandidates())
        let tinyThresholdBytes: UInt64 = 5 * 1024 * 1024
        let allTiny = !candidates.isEmpty && candidates.allSatisfy { $0.dataSize < tinyThresholdBytes }

        guard !candidates.isEmpty else {
            return DetectionOutcome(
                allCandidates: [],
                selected: nil,
                additional: [],
                ambiguousCandidates: [],
                suggestedCandidate: nil,
                needsPatchPrompt: false,
                allTiny: false,
                accessDenied: !canAccessContainersDirectory()
            )
        }

        let inspections = candidates.map { inspectContainer($0) }
        let withFortniteGame = inspections.filter(\.hasFortniteGameFolder)
        if withFortniteGame.count == 1, let selected = withFortniteGame.first?.candidate {
            return outcomeSelecting(selected, from: candidates, allTiny: allTiny)
        }

        let logCandidates = withFortniteGame.filter(\.hasLogs)
        if logCandidates.count == 1, let selected = logCandidates.first?.candidate {
            return outcomeSelecting(selected, from: candidates, allTiny: allTiny)
        }

        if logCandidates.count > 1 {
            let persistentCandidates = logCandidates.filter(\.hasPersistentDownloadContent)
            if persistentCandidates.count == 1, let selected = persistentCandidates.first?.candidate {
                return outcomeSelecting(selected, from: candidates, allTiny: allTiny)
            }
            if persistentCandidates.count > 1 {
                let ambiguous = persistentCandidates.map(\.candidate)
                return DetectionOutcome(
                    allCandidates: candidates,
                    selected: nil,
                    additional: [],
                    ambiguousCandidates: ambiguous,
                    suggestedCandidate: ambiguous.first,
                    needsPatchPrompt: false,
                    allTiny: allTiny,
                    accessDenied: false
                )
            }
        }

        return DetectionOutcome(
            allCandidates: candidates,
            selected: nil,
            additional: [],
            ambiguousCandidates: [],
            suggestedCandidate: nil,
            needsPatchPrompt: true,
            allTiny: allTiny,
            accessDenied: false
        )
    }

    @MainActor
    func performVerifyContainerCheck() async -> DetectionOutcome {
        let before = deduplicatedCandidates(findContainerCandidates())
        let previousLogDates = Dictionary(uniqueKeysWithValues: before.map { ($0.path, logsDirectoryModifiedDate(for: $0)) })

        openFortnite()
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        terminateFortnite()
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        let outcome = detectContainerOutcome()
        let updatedLogCandidates = outcome.allCandidates.filter { candidate in
            let currentLogDate = logsDirectoryModifiedDate(for: candidate)
            guard let priorLogDate = previousLogDates[candidate.path] else {
                return currentLogDate != .distantPast
            }
            return currentLogDate > priorLogDate
        }

        if let selected = updatedLogCandidates.sorted(by: logsModifiedSort).first {
            return outcomeSelecting(selected, from: outcome.allCandidates, allTiny: outcome.allTiny)
        }

        let candidatesWithLogs = outcome.allCandidates.filter {
            logsDirectoryModifiedDate(for: $0) != .distantPast
        }
        if let selected = candidatesWithLogs.sorted(by: logsModifiedSort).first {
            return outcomeSelecting(selected, from: outcome.allCandidates, allTiny: outcome.allTiny)
        }

        return outcome
    }

    @MainActor
    func restoreContainersAndRegenerate() async -> DetectionOutcome {
        let existing = deduplicatedCandidates(findContainerCandidates())
        do {
            try deleteContainers(paths: existing.map(\.path))
        } catch {
            return detectContainerOutcome()
        }

        openFortnite()
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        terminateFortnite()
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        return detectContainerOutcome()
    }

    func deleteContainers(paths: [String]) throws {
        for path in Set(paths) {
            try FileManager.default.removeItem(atPath: path)
        }
    }

    private func findContainerCandidates() -> [ContainerCandidate] {
        let containersURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers")

        guard let containerDirs = try? FileManager.default.contentsOfDirectory(
            at: containersURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        var candidates: [ContainerCandidate] = []

        for dir in containerDirs {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                continue
            }

            let metadataPlist = dir.appendingPathComponent(".com.apple.containermanagerd.metadata.plist")
            guard FileManager.default.fileExists(atPath: metadataPlist.path) else {
                continue
            }

            if metadataContainsFortnite(at: metadataPlist) {
                let modDate = (try? dir.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let dataSize = fortniteDataSize(in: dir)
                candidates.append(
                    ContainerCandidate(
                        path: dir.path,
                        dataSize: dataSize,
                        modified: modDate
                    )
                )
            }
        }

        return candidates.sorted(by: candidateSort)
    }

    private func deduplicatedCandidates(_ candidates: [ContainerCandidate]) -> [ContainerCandidate] {
        var bestByPath: [String: ContainerCandidate] = [:]

        for candidate in candidates {
            guard let existing = bestByPath[candidate.path] else {
                bestByPath[candidate.path] = candidate
                continue
            }

            if candidateSort(candidate, existing) {
                bestByPath[candidate.path] = candidate
            }
        }

        return bestByPath.values.sorted(by: candidateSort)
    }

    func canAccessContainersDirectory() -> Bool {
        let containersURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers")
        return (try? FileManager.default.contentsOfDirectory(
            at: containersURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )) != nil
    }

    private func inspectContainer(_ candidate: ContainerCandidate) -> ContainerInspection {
        let rootURL = URL(fileURLWithPath: candidate.path, isDirectory: true)
        let fortniteGameURL = rootURL
            .appendingPathComponent("Data/Documents/FortniteGame", isDirectory: true)
        let logsURL = fortniteGameURL
            .appendingPathComponent("Saved/Logs", isDirectory: true)
        let persistentDownloadDirURL = fortniteGameURL
            .appendingPathComponent("PersistentDownloadDir", isDirectory: true)

        return ContainerInspection(
            candidate: candidate,
            hasFortniteGameFolder: directoryExists(at: fortniteGameURL),
            hasLogs: directoryContainsFiles(at: logsURL),
            hasPersistentDownloadContent: directoryContainsAnything(at: persistentDownloadDirURL)
        )
    }

    private func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func directoryContainsFiles(at url: URL) -> Bool {
        guard directoryExists(at: url),
              let contents = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
              ) else {
            return false
        }

        return contents.contains { item in
            let values = try? item.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile == true
        }
    }

    private func directoryContainsAnything(at url: URL) -> Bool {
        guard directoryExists(at: url),
              let contents = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              ) else {
            return false
        }

        return !contents.isEmpty
    }

    private func logsDirectoryModifiedDate(for candidate: ContainerCandidate) -> Date {
        let logsURL = URL(fileURLWithPath: candidate.path, isDirectory: true)
            .appendingPathComponent("Data/Documents/FortniteGame/Saved/Logs", isDirectory: true)

        guard directoryExists(at: logsURL) else {
            return .distantPast
        }

        return (try? logsURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    func logsDirectoryModifiedDate(forPath path: String) -> Date? {
        let logsURL = URL(fileURLWithPath: path, isDirectory: true)
            .appendingPathComponent("Data/Documents/FortniteGame/Saved/Logs", isDirectory: true)

        guard directoryExists(at: logsURL) else {
            return nil
        }

        return try? logsURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func outcomeSelecting(
        _ selected: ContainerCandidate,
        from allCandidates: [ContainerCandidate],
        allTiny: Bool
    ) -> DetectionOutcome {
        let additional = allCandidates.filter { $0.path != selected.path }
        return DetectionOutcome(
            allCandidates: allCandidates,
            selected: selected,
            additional: additional,
            ambiguousCandidates: [],
            suggestedCandidate: selected,
            needsPatchPrompt: false,
            allTiny: allTiny,
            accessDenied: false
        )
    }

    private func candidateSort(_ lhs: ContainerCandidate, _ rhs: ContainerCandidate) -> Bool {
        if lhs.dataSize == rhs.dataSize {
            return lhs.modified > rhs.modified
        }
        return lhs.dataSize > rhs.dataSize
    }

    private func logsModifiedSort(_ lhs: ContainerCandidate, _ rhs: ContainerCandidate) -> Bool {
        let lhsLogsDate = logsDirectoryModifiedDate(for: lhs)
        let rhsLogsDate = logsDirectoryModifiedDate(for: rhs)

        if lhsLogsDate == rhsLogsDate {
            return candidateSort(lhs, rhs)
        }
        return lhsLogsDate > rhsLogsDate
    }

    @MainActor
    private func openFortnite() {
        let url = URL(fileURLWithPath: "/Applications/Fortnite.app", isDirectory: true)
        NSWorkspace.shared.open(url)
    }

    @MainActor
    private func terminateFortnite() {
        let runningApps = NSWorkspace.shared.runningApplications
        for app in runningApps {
            if let executablePath = app.executableURL?.path.lowercased(),
               executablePath.contains("/fortnite.app/") || executablePath.contains("/fortniteclient-ios-shipping.app/") {
                app.forceTerminate()
                continue
            }

            if app.localizedName?.lowercased().contains("fortnite") == true {
                app.forceTerminate()
            }
        }
    }

    private func fortniteDataSize(in containerURL: URL) -> UInt64 {
        let fortniteGamePath = containerURL
            .appendingPathComponent("Data/Documents/FortniteGame", isDirectory: true)

        return directorySize(at: fortniteGamePath)
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
            } else if let fileSize = values.fileSize {
                total += UInt64(fileSize)
            }
        }

        return total
    }

    private func metadataContainsFortnite(at url: URL) -> Bool {
        guard let dict = NSDictionary(contentsOf: url) as? [String: Any] else {
            return false
        }
        return dictContainsFortnite(dict)
    }

    private func dictContainsFortnite(_ dict: [String: Any]) -> Bool {
        for (_, value) in dict {
            if let str = value as? String,
               str.localizedCaseInsensitiveContains("FortniteGame") {
                return true
            }
            if let arr = value as? [Any],
               arrayContainsFortnite(arr) {
                return true
            }
            if let inner = value as? [String: Any],
               dictContainsFortnite(inner) {
                return true
            }
        }
        return false
    }

    private func arrayContainsFortnite(_ arr: [Any]) -> Bool {
        for value in arr {
            if let str = value as? String,
               str.localizedCaseInsensitiveContains("FortniteGame") {
                return true
            }
            if let dict = value as? [String: Any],
               dictContainsFortnite(dict) {
                return true
            }
            if let innerArr = value as? [Any],
               arrayContainsFortnite(innerArr) {
                return true
            }
        }
        return false
    }

    // MARK: - File picker for manual selection
    func pickContainerManually(completion: @escaping (String?) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Select Fortnite Container Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        panel.begin { response in
            if response == .OK, let url = panel.url {
                completion(url.path)
            } else {
                completion(nil)
            }
        }
    }
}

private struct ContainerInspection {
    let candidate: FortniteContainerLocator.ContainerCandidate
    let hasFortniteGameFolder: Bool
    let hasLogs: Bool
    let hasPersistentDownloadContent: Bool
}
