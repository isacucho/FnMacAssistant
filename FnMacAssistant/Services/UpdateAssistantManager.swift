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
    private let tempFolderName = "update-assistant"

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
    private var didNotifyForCurrentRun = false
    private var fortniteReopenMonitorTimer: Timer?
    private var suppressFortniteReopenWarningUntil: Date = .distantPast
    private var fortniteReopenPromptInFlight = false
    private var allowFortniteWhileDownloading = false

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

    func start() {
        guard !isTracking else { return }
        guard let container = FortniteContainerLocator.shared.getContainerPath() else {
            appendLog("ERROR: Fortnite container not found. Set it in Settings first.")
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
        fortniteReopenPromptInFlight = false
        allowFortniteWhileDownloading = false
        suppressFortniteReopenWarningUntil = .distantPast
        didNotifyForCurrentRun = false
        batchTargetDirs.removeAll()
        batchDownloadedPaths.removeAll()
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
                  "Update Assistant will close Fortnite as soon as it detects the download link.\n")

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
                        suppressFortniteReopenWarningUntil = Date().addingTimeInterval(6)
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
                    allowFortniteWhileDownloading = false
                    DispatchQueue.main.async {
                        self.isDownloading = true
                        self.startFortniteReopenMonitor()
                    }

                    var baseDownloaded: Int64 = 0

                    for task in filtered {
                        if Task.isCancelled { break }
                        var completed = false
                        var attempt = 0
                        while !Task.isCancelled, !completed {
                            do {
                                let destURL = URL(fileURLWithPath: task.fullPath)
                                try await downloadFile(
                                    from: task.url,
                                    to: destURL,
                                    expectedSize: task.size,
                                    baseDownloadedBytes: baseDownloaded
                                )
                                completed = true
                                baseDownloaded += task.size
                                self.batchDownloadedPaths.append(task.fullPath)
                                self.batchTargetDirs.insert((task.fullPath as NSString).deletingLastPathComponent)
                                writeOptionalLanguagePlaceholderCopyIfNeeded(for: task)
                                appendLog("Saving to: \(task.relativePath)")
                            } catch {
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
                        appendLog("\n")
                    }

                    if Task.isCancelled {
                        appendLog("\nAborted")
                        finalize(success: false)
                        return
                    }

                    DispatchQueue.main.async {
                        self.downloadedBytes = baseDownloaded
                    }
                    appendLog("Downloaded a total of \(formatSize(bytes: baseDownloaded)).")

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

        appendLog("\nAborted")
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
                    task.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func ensureTempDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FnMacAssistant-cache", isDirectory: true)
            .appendingPathComponent(tempFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
        return tempDir
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
        fortniteReopenPromptInFlight = false
        allowFortniteWhileDownloading = false
        suppressFortniteReopenWarningUntil = .distantPast

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
        fortniteReopenPromptInFlight = false
        allowFortniteWhileDownloading = false
        suppressFortniteReopenWarningUntil = .distantPast
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

    @MainActor
    private func startFortniteReopenMonitor() {
        stopFortniteReopenMonitor()
        fortniteReopenMonitorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard self.isDownloading else { return }
            guard !self.allowFortniteWhileDownloading else { return }
            guard Date() >= self.suppressFortniteReopenWarningUntil else { return }
            guard self.isFortniteRunning() else { return }
            guard !self.fortniteReopenPromptInFlight else { return }

            self.fortniteReopenPromptInFlight = true
            self.appendLog("Fortnite was opened during download. Closing it to protect the download.")
            self.terminateFortnite()

            Task {
                let action = await self.promptFortniteOpenedDuringDownloadAction()
                switch action {
                case .cancelDownload:
                    self.appendLog("Download cancelled because Fortnite was opened during download.")
                    self.stopInternal(deleteDownloaded: false)
                case .ignoreAndOpen:
                    self.appendLog("Continuing after warning. Opening Fortnite may break the download.")
                    self.openFortnite()
                    self.allowFortniteWhileDownloading = true
                case .closeWarning:
                    self.appendLog("Continuing download with Fortnite closed.")
                    self.suppressFortniteReopenWarningUntil = Date().addingTimeInterval(2)
                }
                self.fortniteReopenPromptInFlight = false
            }
        }
    }

    private func stopFortniteReopenMonitor() {
        fortniteReopenMonitorTimer?.invalidate()
        fortniteReopenMonitorTimer = nil
    }

    private enum FortniteOpenedDuringDownloadAction {
        case cancelDownload
        case ignoreAndOpen
        case closeWarning
    }

    private func promptFortniteOpenedDuringDownloadAction() async -> FortniteOpenedDuringDownloadAction {
        await MainActor.run {
            let alert = NSAlert()
            alert.messageText = "Fortnite Opened During Download"
            alert.informativeText = """
            Opening Fortnite while Update Assistant is downloading can break the download.
            """
            alert.addButton(withTitle: "Cancel Download")
            alert.addButton(withTitle: "Ignore and Open Fortnite")
            alert.addButton(withTitle: "Dismiss")
            // Keep "Dismiss" as default even though it is the last (bottom) button.
            alert.buttons[0].keyEquivalent = ""
            alert.buttons[1].keyEquivalent = ""
            alert.buttons[2].keyEquivalent = "\r"
            alert.buttons[2].keyEquivalentModifierMask = []

            var escPressed = false
            let escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let isEscape = event.keyCode == 53 || event.charactersIgnoringModifiers == "\u{1b}"
                guard isEscape else { return event }
                escPressed = true
                NSApp.abortModal()
                return nil
            }

            let response = alert.runModal()
            if let escMonitor {
                NSEvent.removeMonitor(escMonitor)
            }
            if escPressed {
                return .closeWarning
            }
            if response == .alertFirstButtonReturn {
                return .cancelDownload
            }
            if response == .alertSecondButtonReturn {
                return .ignoreAndOpen
            }
            return .closeWarning
        }
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
                self.replaceLog("Downloaded \(self.formatSize(bytes: state.downloadedBytes))\(speedLabel)")
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
        guard path.contains("/defaulttags/") else {
            return filename
        }

        let targetLower = target.lowercased()
        let languagePattern = #"^lang\.([a-z]{2}(?:-[a-z0-9]{2,3})?)(?:optional)?$"#
        let languageRegex = try? NSRegularExpression(pattern: languagePattern, options: [])
        let targetRange = NSRange(location: 0, length: targetLower.utf16.count)
        let languageCode: String? = {
            guard let languageRegex,
                  let match = languageRegex.firstMatch(in: targetLower, options: [], range: targetRange),
                  let codeRange = Range(match.range(at: 1), in: targetLower) else { return nil }
            return String(targetLower[codeRange])
        }()

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

        let lowerPath = path.lowercased()
        let shouldRewrite =
            lowerPath.hasSuffix("tagplaceholder_fnone.txt")
            || lowerPath.contains("/tagplaceholder_lang.")

        guard shouldRewrite else {
            return filename
        }

        let base = (path as NSString).deletingLastPathComponent
        let newName: String
        if let languageCode {
            newName = "tagplaceholder_lang\(languageCode).txt"
        } else {
            newName = "tagplaceholder_\(normalized).txt"
        }
        return (base as NSString).appendingPathComponent(newName)
    }

    private func writeOptionalLanguagePlaceholderCopyIfNeeded(for task: DownloadTask) {
        let targetLower = task.target.lowercased()
        let languagePattern = #"^lang\.([a-z]{2}(?:-[a-z0-9]{2,3})?)optional$"#
        guard let languageRegex = try? NSRegularExpression(pattern: languagePattern, options: []) else { return }
        let range = NSRange(location: 0, length: targetLower.utf16.count)
        guard let match = languageRegex.firstMatch(in: targetLower, options: [], range: range),
              let languageRange = Range(match.range(at: 1), in: targetLower) else { return }

        let sourcePath = task.fullPath.replacingOccurrences(of: "\\", with: "/")
        let sourceLower = sourcePath.lowercased()
        guard sourceLower.contains("/defaulttags/"),
              sourceLower.hasSuffix(".txt") else { return }

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
            batchDownloadedPaths.append(optionalPath)
            appendLog("Saving to: \((task.relativePath as NSString).deletingLastPathComponent)/\(optionalName)")
        } catch {
            appendLog("WARNING: Failed to duplicate optional language placeholder: \(error.localizedDescription)")
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
