//
//  UpdateAssistantManager.swift
//  FnMacAssistant
//
//  Created by Isacucho on 14/02/26.
//

import Foundation
import AppKit
import Combine

final class UpdateAssistantManager: NSObject, ObservableObject, URLSessionDataDelegate {
    static let shared = UpdateAssistantManager()
    private static let showConsoleDefaultsKey = "updateAssistantShowConsole"

    @Published var isDownloading = false
    @Published var isTracking = false
    @Published var isDone = false
    @Published var isPaused = false
    @Published var statusMessage: String = "Ready"
    @Published var logOutput: String = ""
    @Published var showConsole: Bool = {
        let defaults = UserDefaults.standard
        let key = "updateAssistantShowConsole"
        if defaults.object(forKey: key) == nil {
            return false
        }
        return defaults.bool(forKey: key)
    }() {
        didSet {
            UserDefaults.standard.set(showConsole, forKey: Self.showConsoleDefaultsKey)
        }
    }

    @Published var downloadedBytes: Int64 = 0
    @Published var totalBytes: Int64 = 0

    private let chunkDownloadDirRelative = "PersistentDownloadDir/ChunkDownload"
    private let fortniteGameRelative = "Data/Documents/FortniteGame"
    private let logRelativePath = "Data/Documents/FortniteGame/Saved/Logs/FortniteGame.log"
    private let stagedDownloadsFolderName = "staged-downloads"
    private let fortniteDefaultTagsPath =
        "/Applications/Fortnite.app/Wrapper/FortniteClient-IOS-Shipping.app/cookeddata/fortnitegame/content/defaulttags"

    private var assistantTask: Task<Void, Never>?
    private var logLines: [String] = []
    private var logBuffer: String = ""
    private var logHandle: FileHandle?
    private var logOffset: UInt64 = 0

    private let stateQueue = DispatchQueue(label: "UpdateAssistantManager.state")
    private var downloadState: DownloadState?
    private var downloadContinuation: CheckedContinuation<Void, Error>?
    private var downloadSession: URLSession?
    private var downloadTask: URLSessionDataTask?
    private var batchDownloadedPaths: [String] = []
    private var batchTargetDirs: Set<String> = []
    private let stagedDownloadsQueue = DispatchQueue(label: "UpdateAssistantManager.stagedDownloads")
    private var pendingStagedDownloads: [StagedDownload] = []
    private var didNotifyForCurrentRun = false
    private var defaultTagPlaceholderIndex: [String: String]?

    private struct DownloadState {
        var tempURL: URL
        var destURL: URL
        var fileHandle: FileHandle
        var expectedBytes: Int64
        var downloadedBytes: Int64
        var startDate: Date
        var lastLogUpdate: Date
        var baseDownloadedBytes: Int64
    }

    var downloadProgress: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(downloadedBytes) / Double(totalBytes))
    }

    var downloadProgressLabel: String {
        let downloaded = ByteCountFormatter.string(fromByteCount: downloadedBytes, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        return "\(downloaded) / \(total)"
    }

    var downloadPercentageLabel: String {
        String(format: "%.1f%%", downloadProgress * 100)
    }

    var isRunning: Bool {
        isTracking || isDownloading
    }

    static func configuredTempDirectoryURL() -> URL {
        AppTempDirectory.subdirectory("update-assistant")
    }

    func start() {
        guard !isTracking else { return }
        guard let container = FortniteContainerLocator.shared.getContainerPath() else {
            appendLog("ERROR: \(FortniteContainerLocator.containerAccessFailureMessage)")
            return
        }

        resetStateForStart()
        assistantTask = Task.detached { [weak self] in
            await self?.runAssistant(containerPath: container)
        }
    }

    func stop() {
        stopInternal(deleteDownloaded: false)
    }

    func requestCancelDownload() {
        Task { @MainActor in
            let alert = NSAlert()
            alert.messageText = "Cancel download?"
            alert.informativeText = "You can stop and keep downloaded files, or stop and delete downloaded files from this session."
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Keep Downloading")
            alert.addButton(withTitle: "Stop Without Deleting")
            alert.addButton(withTitle: "Delete & Stop")
            alert.buttons[2].hasDestructiveAction = true

            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                stopInternal(deleteDownloaded: false)
            } else if response == .alertThirdButtonReturn {
                stopInternal(deleteDownloaded: true)
            }
        }
    }

    func pause() {
        stateQueue.async {
            guard let task = self.downloadTask, self.isDownloading, !self.isPaused else { return }
            task.suspend()
            DispatchQueue.main.async {
                self.isPaused = true
                self.statusMessage = "Paused"
                self.appendLog("Download paused.")
                print("[UpdateAssistant] Download paused.")
            }
        }
    }

    func resume() {
        stateQueue.async {
            guard let task = self.downloadTask, self.isDownloading, self.isPaused else { return }
            task.resume()
            DispatchQueue.main.async {
                self.isPaused = false
                self.statusMessage = "Downloading…"
                self.appendLog("Download resumed.")
                print("[UpdateAssistant] Download resumed.")
            }
        }
    }

    func reset() {
        DispatchQueue.main.async {
            self.isDownloading = false
            self.isTracking = false
            self.isDone = false
            self.isPaused = false
            self.statusMessage = "Idle"
            self.downloadedBytes = 0
            self.totalBytes = 0
        }
    }

    private func resetStateForStart() {
        DispatchQueue.main.async {
            self.isDownloading = false
            self.isTracking = true
            self.isDone = false
            self.isPaused = false
            self.statusMessage = "Launching Fortnite…"
            self.downloadedBytes = 0
            self.totalBytes = 0
            self.logLines.removeAll()
            self.logOutput = ""
        }
        stopFortniteReopenMonitor()
        didNotifyForCurrentRun = false
        batchTargetDirs.removeAll()
        batchDownloadedPaths.removeAll()
        clearPendingStagedDownloads()
        if let tempDir = try? ensureTempDirectory() {
            let stagedRoot = tempDir.appendingPathComponent(stagedDownloadsFolderName, isDirectory: true)
            try? FileManager.default.removeItem(at: stagedRoot)
        }
    }

    private func runAssistant(containerPath: String) async {
        let fortniteGamePath = URL(fileURLWithPath: containerPath)
            .appendingPathComponent(fortniteGameRelative).path
        let logPath = URL(fileURLWithPath: containerPath)
            .appendingPathComponent(logRelativePath).path

        appendLog("Starting with container root:\n\(containerPath)\n")

        let wasRunning = isFortniteRunning()
        if !wasRunning {
            updateStatus("Launching Fortnite…")
            openFortnite()
            updateStatus("Waiting for Fortnite log reset…")
        } else {
            updateStatus("Fortnite is already open. Scanning current log…")
            appendLog("Fortnite is already open. Scanning current log for ongoing downloads.")
        }

        if !wasRunning {
            let resetDetected = await waitForLogReset(logPath: logPath)
            if !resetDetected {
                appendLog("WARNING: Log reset not detected. Continuing with current log.")
            } else {
                appendLog("Log reset detected. Starting tracking.")
            }
        }

        // If Fortnite is already open, include existing log content so ongoing downloads are picked up.
        prepareLogReader(logPath: logPath, skipExisting: false)

        updateStatus("Waiting for download link…")
        appendLog("If you are updating a game mode, click the Download button in Fortnite.\n" +
                  "Update Assistant will close Fortnite as soon as it detects the download link.\n" +
                  "Do not open Fortnite while download/apply is running.\n")

        let requestRegex = try? NSRegularExpression(
            pattern: "LogFortInstallBundleManager: Display: InstallBundleSourceBPS: Requesting Chunk [^\\s]* from CDN for Request (\\S*) \\[(\\d+)/(\\d+)\\]: (\\d+) (https://.*) \\[(ChunkDb|Direct Install)\\]$",
            options: [.anchorsMatchLines]
        )

        guard let requestRegex else {
            appendLog("ERROR: Failed to compile regex patterns.")
            finalize(success: false)
            return
        }

        var downloadConfig: String?
        var lastTaskDetectedAt = Date()
        var didCloseFortnite = false

        var pendingTasks: [DownloadTask] = []
        var pendingKeySet: Set<String> = []
        var lastLinkDetected: Date?
        var chunkProgressByTarget: [String: (expected: Int, observed: Set<Int>)] = [:]
        let incompleteChunkWaitTimeout: TimeInterval = 5
        let bundleDetectionWaitSeconds: TimeInterval = 3

        while !Task.isCancelled {
            if Task.isCancelled { break }

            let newLines = readNewLogLines(logPath: logPath)

            for line in newLines {
                let nsLine = line as NSString
                let fullRange = NSRange(location: 0, length: nsLine.length)
                guard let match = requestRegex.firstMatch(in: line, options: [], range: fullRange) else { continue }

                let target = nsLine.substring(with: match.range(at: 1))
                let currentPartStr = nsLine.substring(with: match.range(at: 2))
                let totalPartsStr = nsLine.substring(with: match.range(at: 3))
                let sizeStr = nsLine.substring(with: match.range(at: 4))
                let urlStr = nsLine.substring(with: match.range(at: 5))
                let typeStr = nsLine.substring(with: match.range(at: 6))
                let isDirect = (typeStr == "Direct Install")

                guard let size = Int64(sizeStr),
                      let url = URL(string: urlStr) else {
                    replaceLog("ERROR: Invalid download task data, skipping.")
                    continue
                }

                if !isDirect,
                   let currentPart = Int(currentPartStr),
                   let totalParts = Int(totalPartsStr) {
                    var progress = chunkProgressByTarget[target] ?? (expected: totalParts, observed: [])
                    progress.expected = max(progress.expected, totalParts)
                    progress.observed.insert(currentPart)
                    chunkProgressByTarget[target] = progress
                }

                var filename = url.lastPathComponent
                var fileSize = size
                let targetPath = (chunkDownloadDirRelative as NSString).appendingPathComponent(target)
                var relativePath = (targetPath as NSString).appendingPathComponent(filename)
                var fullPath = (fortniteGamePath as NSString).appendingPathComponent(relativePath)

                appendLog("[\(typeStr)] Task found with URL:")
                appendLog(urlStr)
                appendLog("")

                if isDirect {
                    if downloadConfig == nil {
                        if let pathFromLog = findDownloadConfigPath(logPath: logPath) {
                            downloadConfig = try? String(contentsOfFile: pathFromLog, encoding: .utf8)
                        }
                        if downloadConfig == nil {
                            appendLog("\n--------------\nERROR: Could not find download config file in the Fortnite log.")
                            finalize(success: false)
                            return
                        }
                    }

                    let urlPath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    if let directInfo = parseDirectInstallConfig(
                        configText: downloadConfig,
                        target: target,
                        urlPath: urlPath
                    ) {
                        filename = adjustPlaceholderFilenameIfNeeded(
                            directInfo.filename,
                            target: target
                        )
                        fileSize = directInfo.size
                        relativePath = (targetPath as NSString).appendingPathComponent(filename)
                        fullPath = (fortniteGamePath as NSString).appendingPathComponent(relativePath)
                    } else {
                        replaceLog("ERROR: Can't find the URL '\(urlPath)' in download config.")
                        appendLog("Skipping the task.")
                        continue
                    }
                }

                let key = "\(urlStr)|\(relativePath)"
                if !pendingKeySet.contains(key) {
                    pendingKeySet.insert(key)
                    pendingTasks.append(
                        DownloadTask(
                            url: url,
                            relativePath: relativePath,
                            fullPath: fullPath,
                            size: fileSize,
                            isDirect: isDirect,
                            target: target
                        )
                    )
                }
                lastLinkDetected = Date()
                lastTaskDetectedAt = Date()
            }

            let idleSeconds = Int(Date().timeIntervalSince(lastTaskDetectedAt))
            if idleSeconds >= 120 && pendingTasks.isEmpty && lastLinkDetected == nil {
                replaceLog("No tasks found for \(idleSeconds) seconds. Fortnite must have updated!")
                appendLog("If it didn't, restart Fortnite before starting Update Assistant again.")
                finalize(success: true)
                return
            }

            if let lastLink = lastLinkDetected {
                let elapsed = Date().timeIntervalSince(lastLink)
                if elapsed >= bundleDetectionWaitSeconds, !pendingTasks.isEmpty {
                    let incompleteTargets = chunkProgressByTarget
                        .filter { $0.value.expected > 0 && $0.value.observed.count < $0.value.expected }
                    if !incompleteTargets.isEmpty && elapsed < incompleteChunkWaitTimeout {
                        let summary = incompleteTargets
                            .map { "\($0.key): \($0.value.observed.count)/\($0.value.expected)" }
                            .sorted()
                            .joined(separator: ", ")
                        replaceLog("Waiting for remaining chunk requests before closing Fortnite... \(summary)")
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        continue
                    }

                    replaceLog("Batch complete. Preparing downloads…")

                    if !didCloseFortnite {
                        appendLog("Closing Fortnite…")
                        terminateFortnite()
                        terminateUserNSURLSessiond()
                        clearNSURLSessionDownloadsCache(containerPath: containerPath)
                        didCloseFortnite = true
                    }

                    let hasDirectInstall = pendingTasks.contains(where: { $0.isDirect })
                    let hasChunkDb = pendingTasks.contains(where: { !$0.isDirect })
                    if hasDirectInstall && hasChunkDb {
                        appendLog("Mixed batch detected (Direct Install + ChunkDb). Downloading both entry types.")
                    } else if hasDirectInstall {
                        appendLog("Direct Install entries detected. Downloading Direct Install entries.")
                    } else {
                        appendLog("ChunkDb entries detected. Downloading ChunkDb entries.")
                    }

                    let filtered = pendingTasks.filter { !fileExists($0.fullPath, size: $0.size) }
                    pendingTasks.removeAll()
                    pendingKeySet.removeAll()
                    chunkProgressByTarget.removeAll()
                    lastLinkDetected = nil

                    if filtered.isEmpty {
                        appendLog("All files already downloaded. Waiting for more links…")
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        continue
                    }

                    let totalBytes = filtered.reduce(Int64(0)) { $0 + $1.size }
                    updateProgressForBatch(totalBytes: totalBytes)
                    DispatchQueue.main.async {
                        self.isDownloading = true
                    }

                    var baseDownloaded: Int64 = 0
                    clearPendingStagedDownloads()

                    for task in filtered {
                        if Task.isCancelled { break }
                        var completed = false
                        var attempt = 0
                        while !Task.isCancelled, !completed {
                            do {
                                let destURL = stagedDownloadURL(for: task.relativePath)
                                try await downloadFile(
                                    from: task.url,
                                    to: destURL,
                                    expectedSize: task.size,
                                    baseDownloadedBytes: baseDownloaded
                                )
                                completed = true
                                baseDownloaded += task.size
                                addPendingStagedDownload(
                                    StagedDownload(
                                        stagedURL: destURL,
                                        destinationPath: task.fullPath,
                                        relativePath: task.relativePath
                                    )
                                )
                                if let optionalStaged = writeOptionalLanguagePlaceholderCopyIfNeeded(for: task, stagedURL: destURL) {
                                    addPendingStagedDownload(optionalStaged)
                                }
                            } catch {
                                if Task.isCancelled || isCancellationError(error) {
                                    break
                                }
                                attempt += 1
                                let isRetryable = shouldRetryDownload(error)
                                replaceLog("DOWNLOAD ERROR: \(error.localizedDescription)")
                                if isNetworkConnectionLostError(error) {
                                    let networkMessage = "Network connection lost. Waiting to retry download."
                                    appendLog(networkMessage)
                                    print("[UpdateAssistant] \(networkMessage)")
                                }
                                if !Task.isCancelled {
                                    let retryMessage = isRetryable
                                        ? "Retrying (\(attempt)) after temporary interruption…"
                                        : "Retrying (\(attempt)) after error…"
                                    appendLog(retryMessage)
                                    print("[UpdateAssistant] \(retryMessage)")
                                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                                }
                            }
                        }
                    }

                    if Task.isCancelled {
                        appendLog("Download cancelled.")
                        finalize(success: false)
                        return
                    }

                    DispatchQueue.main.async {
                        self.downloadedBytes = baseDownloaded
                    }
                    appendLog("Downloaded a total of \(formatSize(bytes: baseDownloaded)).")

                    updateStatus("Waiting for Fortnite to close…")
                    if !(await waitForWriteAccessBeforeApplying()) {
                        appendLog("Update assistant stopped before applying files.")
                        finalize(success: false)
                        return
                    }

                    updateStatus("Applying update…")
                    do {
                        try applyStagedDownloads(consumePendingStagedDownloads())
                    } catch {
                        appendLog("ERROR: Failed to apply staged files: \(error.localizedDescription)")
                        finalize(success: false)
                        return
                    }

                    finalize(success: true)
                    return
                } else {
                    replaceLog("No tasks found, waiting... \(idleSeconds)")
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            } else {
                replaceLog("No tasks found, waiting... \(idleSeconds)")
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }

        appendLog("Download cancelled.")
        finalize(success: false)
    }

    private func updateProgressForBatch(totalBytes: Int64) {
        DispatchQueue.main.async {
            self.downloadedBytes = 0
            self.totalBytes = max(totalBytes, 0)
            self.statusMessage = "Downloading…"
        }
    }

    private func fileExists(_ path: String, size: Int64) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path),
              let attrs = try? fm.attributesOfItem(atPath: path),
              let fileSize = attrs[.size] as? NSNumber else { return false }
        return fileSize.int64Value == size
    }

    private func downloadFile(from url: URL, to destURL: URL, expectedSize: Int64, baseDownloadedBytes: Int64) async throws {
        try await withCheckedThrowingContinuation { continuation in
            stateQueue.async {
                do {
                    let tempDir = try self.ensureTempDirectory()
                    let tempURL = tempDir.appendingPathComponent(UUID().uuidString)
                    FileManager.default.createFile(atPath: tempURL.path, contents: nil)
                    let fileHandle = try FileHandle(forWritingTo: tempURL)
                    let state = DownloadState(
                        tempURL: tempURL,
                        destURL: destURL,
                        fileHandle: fileHandle,
                        expectedBytes: expectedSize,
                        downloadedBytes: 0,
                        startDate: Date(),
                        lastLogUpdate: Date.distantPast,
                        baseDownloadedBytes: baseDownloadedBytes
                    )
                    self.downloadState = state
                    self.downloadContinuation = continuation

                    let config = URLSessionConfiguration.default
                    let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
                    self.downloadSession = session
                    var request = URLRequest(url: url)
                    request.setValue("FnMacAssistant/2.0 (macOS)", forHTTPHeaderField: "User-Agent")
                    let task = session.dataTask(with: request)
                    self.downloadTask = task
                    self.appendLog("Downloading: \(destURL.path)")
                    task.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func ensureTempDirectory() throws -> URL {
        let tempDir = Self.configuredTempDirectoryURL()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
        return tempDir
    }

    private func stagedDownloadURL(for relativePath: String) -> URL {
        let sanitized = relativePath.replacingOccurrences(of: "\\", with: "/")
        let root = (try? ensureTempDirectory()) ?? Self.configuredTempDirectoryURL()
        return root
            .appendingPathComponent(stagedDownloadsFolderName, isDirectory: true)
            .appendingPathComponent(sanitized)
    }

    private func waitForWriteAccessBeforeApplying() async -> Bool {
        guard isFortniteRunning() else { return true }
        appendLog("Fortnite is running. Close it to continue applying files.")
        return await MainActor.run {
            FortniteContainerWriteGuard.confirmCanModifyContainer()
        }
    }

    private func applyStagedDownloads(_ stagedDownloads: [StagedDownload]) throws {
        let fm = FileManager.default
        for staged in stagedDownloads {
            if Task.isCancelled {
                throw CancellationError()
            }

            let destinationURL = URL(fileURLWithPath: staged.destinationPath)
            try fm.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }
            try fm.moveItem(at: staged.stagedURL, to: destinationURL)
            batchDownloadedPaths.append(destinationURL.path)
            batchTargetDirs.insert(destinationURL.deletingLastPathComponent().path)
            appendLog("Moved to final location: \(destinationURL.path)")
        }

        if let tempDir = try? ensureTempDirectory() {
            let stagedRoot = tempDir.appendingPathComponent(stagedDownloadsFolderName, isDirectory: true)
            try? fm.removeItem(at: stagedRoot)
        }
    }

    private func cancelActiveDownload() {
        stateQueue.async {
            self.cancelActiveDownloadLocked(resumeError: CancellationError())
        }
    }

    private func cancelActiveDownloadLocked(resumeError: Error?) {
        self.downloadTask?.cancel()
        self.downloadTask = nil

        if let state = self.downloadState {
            try? state.fileHandle.close()
            try? FileManager.default.removeItem(at: state.tempURL)
        }
        self.downloadState = nil

        self.downloadSession?.invalidateAndCancel()
        self.downloadSession = nil

        if let continuation = self.downloadContinuation {
            self.downloadContinuation = nil
            if let resumeError {
                continuation.resume(throwing: resumeError)
            } else {
                continuation.resume()
            }
        }
    }

    private func stopInternal(deleteDownloaded: Bool) {
        assistantTask?.cancel()
        assistantTask = nil
        cancelActiveDownload()
        stopFortniteReopenMonitor()

        if !deleteDownloaded {
            let stagedDownloads = consumePendingStagedDownloads()
            if !stagedDownloads.isEmpty {
                if FortniteContainerWriteGuard.confirmCanModifyContainer() {
                    do {
                        try applyStagedDownloads(stagedDownloads)
                        appendLog("Stopped. Moved \(stagedDownloads.count) staged file(s) to final location.")
                    } catch {
                        appendLog("WARNING: Failed to move staged files on stop: \(error.localizedDescription)")
                    }
                } else {
                    appendLog("Stopped without deleting, but could not move staged files because Fortnite is running.")
                }
            }
        }

        if deleteDownloaded {
            let paths = batchDownloadedPaths
            batchDownloadedPaths.removeAll()
            for path in paths {
                try? FileManager.default.removeItem(atPath: path)
            }

            let dirs = batchTargetDirs
            batchTargetDirs.removeAll()
            for dir in dirs {
                try? FileManager.default.removeItem(atPath: dir)
            }

            if let tempDir = try? ensureTempDirectory() {
                let stagedRoot = tempDir.appendingPathComponent(stagedDownloadsFolderName, isDirectory: true)
                try? FileManager.default.removeItem(at: stagedRoot)
            }
            clearPendingStagedDownloads()
        }

        DispatchQueue.main.async {
            self.isDownloading = false
            self.isTracking = false
            self.isDone = false
            self.isPaused = false
            self.statusMessage = "Stopped"
            self.downloadedBytes = 0
            self.totalBytes = 0
        }
    }

    private func finalize(success: Bool) {
        stopFortniteReopenMonitor()
        DispatchQueue.main.async {
            self.isDownloading = false
            self.isTracking = false
            self.isDone = success
            self.isPaused = false
            self.statusMessage = success ? "Done" : "Stopped"
        }
        if success {
            notifyIfNeeded()
        }
    }

    private func updateStatus(_ message: String) {
        DispatchQueue.main.async {
            self.statusMessage = message
        }
    }

    private func notifyIfNeeded() {
        guard !didNotifyForCurrentRun else { return }
        didNotifyForCurrentRun = true
        let enabled = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
        guard enabled else { return }
        NotificationHelper.shared.post(
            title: "Update Assistant finished",
            body: "Update downloads are complete. You can open Fortnite now."
        )
    }

    private func appendLog(_ message: String) {
        DispatchQueue.main.async {
            self.logLines.append(message)
            self.logOutput = self.logLines.joined(separator: "\n")
        }
    }

    private func replaceLog(_ message: String) {
        DispatchQueue.main.async {
            if self.logLines.isEmpty {
                self.logLines.append(message)
            } else {
                self.logLines[self.logLines.count - 1] = message
            }
            self.logOutput = self.logLines.joined(separator: "\n")
        }
    }

    private func openFortnite() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["/Applications/Fortnite.app"]
        try? process.run()
    }

    private func stopFortniteReopenMonitor() {
        // Reopen monitoring disabled: we now warn once and guard writes right before apply.
    }

    private func isFortniteRunning() -> Bool {
        FortniteContainerWriteGuard.isFortniteRunning()
    }

    private func waitForLogReset(logPath: String) async -> Bool {
        let timeoutSeconds = 40
        let pollNanos = UInt64(500_000_000)

        let initialContent = (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? ""
        let initialLength = initialContent.count

        for _ in 0..<(timeoutSeconds * 2) {
            if Task.isCancelled { return false }
            let content = (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? ""
            if content.count < initialLength || !content.hasPrefix(initialContent) {
                return true
            }
            try? await Task.sleep(nanoseconds: pollNanos)
        }
        return false
    }

    private func readNewLogLines(logPath: String) -> [String] {
        let url = URL(fileURLWithPath: logPath)

        if logHandle == nil {
            logHandle = try? FileHandle(forReadingFrom: url)
            logBuffer = ""
        }

        guard let handle = logHandle else { return [] }

        if let size = (try? FileManager.default.attributesOfItem(atPath: logPath)[.size]) as? NSNumber {
            let fileSize = size.uint64Value
            if fileSize < logOffset {
                logOffset = 0
                logBuffer = ""
                try? handle.seek(toOffset: 0)
            }
        }

        try? handle.seek(toOffset: logOffset)
        let data = try? handle.readToEnd()
        let newData = data ?? Data()
        if newData.isEmpty {
            return []
        }

        logOffset += UInt64(newData.count)
        if let chunk = String(data: newData, encoding: .utf8) {
            logBuffer.append(chunk)
        }

        var lines: [String] = []
        let parts = logBuffer.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline })
        if parts.count > 1 {
            for idx in 0..<(parts.count - 1) {
                lines.append(String(parts[idx]))
            }
            logBuffer = String(parts.last ?? "")
        }

        return lines
    }

    private func prepareLogReader(logPath: String, skipExisting: Bool) {
        logHandle = nil
        logOffset = 0
        logBuffer = ""
        if skipExisting {
            if let size = (try? FileManager.default.attributesOfItem(atPath: logPath)[.size]) as? NSNumber {
                logOffset = size.uint64Value
            }
        }
    }

    private func findDownloadConfigPath(logPath: String) -> String? {
        guard let content = try? String(contentsOfFile: logPath, encoding: .utf8) else {
            return nil
        }
        let nsLog = content as NSString
        let range = NSRange(location: 0, length: nsLog.length)
        let pattern = "LogFortInstallBundleManager: Display: InstallBundleSourceBPS: " +
            "(?:Found and loaded download config file from|Loaded download config file from HTTP request - file:)" +
            ".*?FortniteGame/(.*?Full.ini)$"
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines, .dotMatchesLineSeparators]),
           let match = regex.firstMatch(in: content, options: [], range: range) {
            let relPath = nsLog.substring(with: match.range(at: 1))
            let base = URL(fileURLWithPath: logPath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            return base.appendingPathComponent(relPath).path
        }
        return nil
    }

    private func terminateFortnite() {
        FortniteContainerWriteGuard.terminateFortnite()
    }

    private func terminateUserNSURLSessiond() {
        let uid = getuid()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-ax", "-o", "pid,uid,comm"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            appendLog("WARNING: Failed to query running processes: \(error.localizedDescription)")
            return
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)

        for line in output.split(separator: "\n").dropFirst() {
            let parts = line.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count >= 3,
                  let pid = Int32(parts[0]),
                  let procUID = Int(parts[1]) else { continue }

            let command = String(parts[2])
            guard procUID == uid else { continue }
            guard command.contains("nsurlsessiond") else { continue }

            if kill(pid, SIGTERM) == 0 {
                appendLog("Stopped downloader process: \(command) (pid \(pid))")
            } else {
                appendLog("WARNING: Failed to stop downloader process \(pid).")
            }
        }
    }

    private func clearNSURLSessionDownloadsCache(containerPath: String) {
        let fm = FileManager.default
        let downloadsURL = URL(fileURLWithPath: containerPath)
            .appendingPathComponent("Data/Library/Caches/com.apple.nsurlsessiond/Downloads", isDirectory: true)

        guard fm.fileExists(atPath: downloadsURL.path) else {
            appendLog("NSURLSession downloads cache folder not found. Skipping cleanup.")
            return
        }

        do {
            let contents = try fm.contentsOfDirectory(
                at: downloadsURL,
                includingPropertiesForKeys: nil,
                options: []
            )
            for item in contents {
                try fm.removeItem(at: item)
            }
            appendLog("Cleared NSURLSession downloads cache.")
        } catch {
            appendLog("WARNING: Failed to clear NSURLSession downloads cache: \(error.localizedDescription)")
        }
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        stateQueue.async {
            if var state = self.downloadState {
                let expected = response.expectedContentLength
                if expected > 0 {
                    state.expectedBytes = expected
                }
                self.downloadState = state
            }
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        stateQueue.async {
            guard var state = self.downloadState else { return }
            do {
                try state.fileHandle.write(contentsOf: data)
            } catch {
                return
            }

            state.downloadedBytes += Int64(data.count)
            let now = Date()
            let elapsed = now.timeIntervalSince(state.startDate)

            if now.timeIntervalSince(state.lastLogUpdate) >= 0.5 {
                let speed = elapsed > 0 ? self.formatSpeed(bytesPerSec: Double(state.downloadedBytes) / elapsed) : ""
                let sizeLabel = self.formatSizeProgress(downloaded: state.downloadedBytes, total: state.expectedBytes)
                let speedLabel = speed.isEmpty ? "" : " at \(speed)"
                DispatchQueue.main.async {
                    self.downloadedBytes = state.baseDownloadedBytes + state.downloadedBytes
                    self.replaceLog("Downloading: \(sizeLabel)\(speedLabel)")
                }
                state.lastLogUpdate = now
            }

            self.downloadState = state
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        stateQueue.async {
            guard let state = self.downloadState else { return }
            do {
                try state.fileHandle.close()
            } catch {}

            if let error = error {
                try? FileManager.default.removeItem(at: state.tempURL)
                self.downloadState = nil
                self.downloadTask = nil
                self.downloadSession?.invalidateAndCancel()
                self.downloadSession = nil

                if let continuation = self.downloadContinuation {
                    self.downloadContinuation = nil
                    continuation.resume(throwing: error)
                }
                return
            }

            do {
                try FileManager.default.createDirectory(
                    at: state.destURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                if FileManager.default.fileExists(atPath: state.destURL.path) {
                    try FileManager.default.removeItem(at: state.destURL)
                }
                try FileManager.default.moveItem(at: state.tempURL, to: state.destURL)
            } catch {
                try? FileManager.default.removeItem(at: state.tempURL)
                self.downloadState = nil
                self.downloadTask = nil
                self.downloadSession?.invalidateAndCancel()
                self.downloadSession = nil
                if let continuation = self.downloadContinuation {
                    self.downloadContinuation = nil
                    continuation.resume(throwing: error)
                }
                return
            }

            self.downloadState = nil
            self.downloadTask = nil
            self.downloadSession?.invalidateAndCancel()
            self.downloadSession = nil

            DispatchQueue.main.async {
                self.downloadedBytes = state.baseDownloadedBytes + state.downloadedBytes
                let speed = self.formatSpeed(bytesPerSec: self.elapsedSpeed(bytes: state.downloadedBytes, since: state.startDate))
                let speedLabel = speed.isEmpty ? "" : " at \(speed)"
                self.appendLog("Downloaded \(self.formatSize(bytes: state.downloadedBytes))\(speedLabel) to temp: \(state.destURL.path)")
            }

            if let continuation = self.downloadContinuation {
                self.downloadContinuation = nil
                continuation.resume()
            }
        }
    }

    private func elapsedSpeed(bytes: Int64, since date: Date) -> Double {
        let elapsed = Date().timeIntervalSince(date)
        guard elapsed > 0 else { return 0 }
        return Double(bytes) / elapsed
    }

    private func formatSpeed(bytesPerSec: Double) -> String {
        var value = bytesPerSec
        for unit in ["B/s", "KB/s", "MB/s", "GB/s", "TB/s"] {
            if value < 1024 {
                return String(format: "%.2f %@", value, unit)
            }
            value /= 1024
        }
        return String(format: "%.2f PB/s", value)
    }

    private func formatSize(bytes: Int64) -> String {
        var value = Double(bytes)
        for unit in ["B", "KB", "MB", "GB", "TB"] {
            if value < 1024 {
                return String(format: "%.2f %@", value, unit)
            }
            value /= 1024
        }
        return String(format: "%.2f PB", value)
    }

    private func formatSizeProgress(downloaded: Int64, total: Int64) -> String {
        if total > 0 {
            let percent = Int((Double(downloaded) / Double(total)) * 100)
            return "\(percent)% — \(formatSize(bytes: downloaded)) of \(formatSize(bytes: total))"
        }
        return formatSize(bytes: downloaded)
    }

    private func clearPendingStagedDownloads() {
        stagedDownloadsQueue.sync {
            pendingStagedDownloads.removeAll()
        }
    }

    private func addPendingStagedDownload(_ stagedDownload: StagedDownload) {
        stagedDownloadsQueue.sync {
            pendingStagedDownloads.append(stagedDownload)
        }
    }

    private func consumePendingStagedDownloads() -> [StagedDownload] {
        stagedDownloadsQueue.sync {
            let stagedDownloads = pendingStagedDownloads
            pendingStagedDownloads.removeAll()
            return stagedDownloads
        }
    }

    private func shouldRetryDownload(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }

        switch nsError.code {
        case NSURLErrorCancelled,
             NSURLErrorTimedOut,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorNotConnectedToInternet,
             NSURLErrorCannotConnectToHost,
             NSURLErrorCannotFindHost,
             NSURLErrorDNSLookupFailed,
             NSURLErrorDataNotAllowed,
             NSURLErrorInternationalRoamingOff,
             NSURLErrorCallIsActive,
             NSURLErrorCannotLoadFromNetwork:
            return true
        default:
            return false
        }
    }

    private func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private func isNetworkConnectionLostError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        return nsError.code == NSURLErrorNetworkConnectionLost || nsError.code == NSURLErrorNotConnectedToInternet
    }

    private func parseDirectInstallConfig(
        configText: String?,
        target: String,
        urlPath: String
    ) -> (filename: String, size: Int64)? {
        guard let configText else { return nil }

        let candidates = [
            urlPath,
            "/" + urlPath
        ]

        for rawLine in configText.split(whereSeparator: { $0.isNewline }) {
            let line = String(rawLine)
            guard line.contains("DirectFile=\"") else { continue }

            guard let startRange = line.range(of: "DirectFile=\"") else { continue }
            let afterStart = line[startRange.upperBound...]
            guard let endRange = afterStart.range(of: "\"") else { continue }
            let payload = String(afterStart[..<endRange.lowerBound])

            for candidate in candidates {
                guard payload.hasPrefix(candidate + ",") else { continue }
                let parts = payload.split(separator: ",", omittingEmptySubsequences: false)
                if parts.count >= 4 {
                    let filename = String(parts[1])
                    let sizeStr = String(parts[3])
                    if let size = Int64(sizeStr) {
                        return (filename, size)
                    }
                    if let size = Int64(parts[2]) {
                        return (filename, size)
                    }
                }
            }
        }

        return nil
    }

    private func adjustPlaceholderFilenameIfNeeded(_ filename: String, target: String) -> String {
        let path = filename.replacingOccurrences(of: "\\", with: "/")
        let lowerPath = path.lowercased()
        guard lowerPath.contains("/defaulttags/") else {
            return filename
        }

        let shouldRewrite =
            lowerPath.contains("tagplaceholder")
            && lowerPath.hasSuffix(".txt")

        guard shouldRewrite else {
            return filename
        }

        let base = (path as NSString).deletingLastPathComponent
        let candidates = placeholderCandidates(for: target)
        let index = loadDefaultTagPlaceholderIndex()
        let newName =
            candidates.lazy.compactMap { index[$0.lowercased()] }.first
            ?? candidates.first
            ?? (path as NSString).lastPathComponent
        return (base as NSString).appendingPathComponent(newName)
    }

    private func loadDefaultTagPlaceholderIndex() -> [String: String] {
        if let defaultTagPlaceholderIndex {
            return defaultTagPlaceholderIndex
        }

        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: fortniteDefaultTagsPath)) ?? []
        var index: [String: String] = [:]
        for name in names {
            let lower = name.lowercased()
            guard lower.hasPrefix("tagplaceholder"), lower.hasSuffix(".txt") else { continue }
            index[lower] = name
        }

        defaultTagPlaceholderIndex = index
        return index
    }

    private func placeholderCandidates(for target: String) -> [String] {
        let targetLower = target.lowercased()
        let languagePattern = #"^lang\.([a-z]{2}(?:-[a-z0-9]{2,3})?)(optional)?$"#
        let languageRegex = try? NSRegularExpression(pattern: languagePattern, options: [])
        let targetRange = NSRange(location: 0, length: targetLower.utf16.count)

        if let languageRegex,
           let match = languageRegex.firstMatch(in: targetLower, options: [], range: targetRange),
           let codeRange = Range(match.range(at: 1), in: targetLower) {
            let languageCode = String(targetLower[codeRange])
            let isOptional = match.range(at: 2).location != NSNotFound
            if isOptional {
                return [
                    "tagplaceholder_lang\(languageCode)optional.txt",
                    "tagplaceholder_lang\(languageCode).txt"
                ]
            }
            return [
                "tagplaceholder_lang\(languageCode).txt",
                "tagplaceholder_lang\(languageCode)optional.txt"
            ]
        }

        let isOptionalTarget = targetLower.contains("optional")
        var normalized = targetLower
            .replacingOccurrences(of: "optional", with: "")
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")

        while normalized.contains("__") {
            normalized = normalized.replacingOccurrences(of: "__", with: "_")
        }
        normalized = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "_"))

        if normalized.hasPrefix("gfp"), !normalized.hasPrefix("gfp_"), normalized.count > 3 {
            normalized = "gfp_" + String(normalized.dropFirst(3))
        }

        if normalized == "gfp_brcosmeticsinstallondemand" {
            normalized = "gfp_brcosmeticsondemandiad"
        }

        if isOptionalTarget {
            return [
                "tagplaceholder_\(normalized)optional.txt",
                "tagplaceholder_\(normalized).txt"
            ]
        }

        return [
            "tagplaceholder_\(normalized).txt",
            "tagplaceholder_\(normalized)optional.txt"
        ]
    }

    private func writeOptionalLanguagePlaceholderCopyIfNeeded(for task: DownloadTask, stagedURL: URL) -> StagedDownload? {
        let targetLower = task.target.lowercased()
        let languagePattern = #"^lang\.([a-z]{2}(?:-[a-z0-9]{2,3})?)optional$"#
        guard let languageRegex = try? NSRegularExpression(pattern: languagePattern, options: []) else { return nil }
        let range = NSRange(location: 0, length: targetLower.utf16.count)
        guard let match = languageRegex.firstMatch(in: targetLower, options: [], range: range),
              let languageRange = Range(match.range(at: 1), in: targetLower) else { return nil }

        let sourcePath = stagedURL.path.replacingOccurrences(of: "\\", with: "/")
        let sourceLower = sourcePath.lowercased()
        guard sourceLower.contains("/defaulttags/"),
              sourceLower.hasSuffix(".txt") else { return nil }

        let languageCode = String(targetLower[languageRange])
        let optionalName = "tagplaceholder_lang\(languageCode)optional.txt"
        let optionalPath = ((sourcePath as NSString).deletingLastPathComponent as NSString)
            .appendingPathComponent(optionalName)

        let fm = FileManager.default
        if fm.fileExists(atPath: optionalPath) {
            try? fm.removeItem(atPath: optionalPath)
        }

        do {
            try fm.copyItem(atPath: sourcePath, toPath: optionalPath)
            let relativeOptionalPath = ((task.relativePath as NSString).deletingLastPathComponent as NSString)
                .appendingPathComponent(optionalName)
            let destinationPath = ((task.fullPath as NSString).deletingLastPathComponent as NSString)
                .appendingPathComponent(optionalName)
            return StagedDownload(
                stagedURL: URL(fileURLWithPath: optionalPath),
                destinationPath: destinationPath,
                relativePath: relativeOptionalPath
            )
        } catch {
            appendLog("WARNING: Failed to duplicate optional language placeholder: \(error.localizedDescription)")
            return nil
        }
    }
}

private struct DownloadTask {
    let url: URL
    let relativePath: String
    let fullPath: String
    let size: Int64
    let isDirect: Bool
    let target: String
}

private struct StagedDownload {
    let stagedURL: URL
    let destinationPath: String
    let relativePath: String
}
