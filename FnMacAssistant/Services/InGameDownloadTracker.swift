//
//  InGameDownloadTracker.swift
//  FnMacAssistant
//
//  Created by Isacucho on 13/11/25.
//

import Foundation
import Combine
import AppKit

@MainActor
final class InGameDownloadTracker: ObservableObject {
    static let shared = InGameDownloadTracker()

    // UI State
    @Published var filesProgress: Double = 0
    @Published var isDownloadingFiles = false
    @Published var fileStatusMessage: String = "Idle"

    // Mode downloads
    @Published var modeProgress: Double = 0
    @Published var isDownloadingMode = false
    private var downloadStarted = false

    // Internals
    private var ignoreNextWarning = false
    private var task: Task<Void, Never>?
    private let jsonRelativePath = "data/documents/FortniteGame/PersistentDownloadDir/InstallBundleManagerReportCache.json"
    private let libraryRelativePath = "data/Library/Caches/com.apple.nsurlsessiond"
    private let chunkDownloadPath = "data/documents/FortniteGame/PersistentDownloadDir/ChunkDownload"

    private var cumulativeDownloaded: UInt64 = 0
    private var librarySizeAtFinishTrigger: UInt64 = 0

    // Control flags
    private var allowFortniteToRun = true

    // Stuck detection
    private var lastProgressValue: UInt64 = 0
    private var lastProgressDate = Date()

    // Pending completion
    private var pendingFinish = false
    private var pendingFinishStart: Date?

    private init() {}

    // MARK: - PUBLIC

    func startGameFilesDownload() {
        guard !isDownloadingFiles else { return }
        if let container = FortniteContainerLocator.shared.getContainerPath() {
            let libraryPath = URL(fileURLWithPath: container).appendingPathComponent(libraryRelativePath).path
            let chunkDownloadFullPath = URL(fileURLWithPath: container)
                .appendingPathComponent(chunkDownloadPath).path
            // (as you requested: not deleted, unchanged, but harmless)
        }

        isDownloadingFiles = true
        filesProgress = 0
        fileStatusMessage = "Starting…"

        cumulativeDownloaded = 0
        librarySizeAtFinishTrigger = 0

        allowFortniteToRun = false
        lastProgressValue = 0
        lastProgressDate = Date()

        pendingFinish = false
        pendingFinishStart = nil

        task = Task.detached { [weak self] in
            await self?.runGameFilesFlow()
        }
    }

    func startGameModeDownload() {
        guard !isDownloadingMode else { return }
        isDownloadingMode = true
        modeProgress = 0
        Task { @MainActor in
            for i in 0...100 {
                try? await Task.sleep(nanoseconds: 12_000_000)
                modeProgress = Double(i) / 100.0
            }
            isDownloadingMode = false
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isDownloadingFiles = false
        fileStatusMessage = "Stopped"

        cumulativeDownloaded = 0
        librarySizeAtFinishTrigger = 0
        allowFortniteToRun = true

        pendingFinish = false
        pendingFinishStart = nil
    }

    @MainActor
    func resetDownload() {
        let alert = NSAlert()
        alert.messageText = "Reset in-game download?"
        alert.informativeText =
        """
        Only reset the in-game download if Fortnite gave you a connection error \
        after the download was marked complete.

        This will erase Fortnite’s download progress file and force Fortnite to \
        rebuild it on next launch.
        """
        alert.alertStyle = .critical

        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Reset Download")
        alert.buttons[1].hasDestructiveAction = true

        let response = alert.runModal()
        if response != .alertSecondButtonReturn { return }

        guard let container = FortniteContainerLocator.shared.getContainerPath() else { return }
        let jsonPath = URL(fileURLWithPath: container)
            .appendingPathComponent(jsonRelativePath).path

        try? FileManager.default.removeItem(atPath: jsonPath)

        self.filesProgress = 0
        self.fileStatusMessage = "Download reset. You can now re-start the download."
        self.isDownloadingFiles = false
        self.cumulativeDownloaded = 0
        self.pendingFinish = false
        self.pendingFinishStart = nil
    }

    func requestCancelDownload() {
        Task { @MainActor in
            let alert = NSAlert()
            alert.messageText = "Cancel internal download?"
            alert.informativeText = "Canceling the internal download may leave Fortnite in an unstable state. Are you sure you want to cancel?"
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Back")
            alert.addButton(withTitle: "Cancel Download")
            alert.buttons[1].hasDestructiveAction = true

            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                self.stop()
            }
        }
    }

    // MARK: - MAIN LOGIC

    private func runGameFilesFlow() async {
        guard let container = FortniteContainerLocator.shared.getContainerPath() else {
            await setError("Container not found.")
            allowFortniteToRun = true
            return
        }

        let jsonPath = URL(fileURLWithPath: container).appendingPathComponent(jsonRelativePath).path
        let libraryPath = URL(fileURLWithPath: container).appendingPathComponent(libraryRelativePath).path

        // ✔ FIXED: missing chunkDownloadFullPath
        let chunkDownloadFullPath = URL(fileURLWithPath: container)
            .appendingPathComponent(chunkDownloadPath).path

        await updateStatus("Launching Fortnite…")
        _ = await openFortnite()

        await updateStatus("Waiting for Fortnite to start download…")
        let jsonReady = await waitForJSONChange(jsonPath, timeout: 40)
        if !jsonReady {
            allowFortniteToRun = true
            await setError("No download detected.")
            return
        }

        terminateFortnite()
        downloadStarted = true
        await updateStatus("Do not re-open Fortnite — it will be re-opened automatically when done.")
        try? await Task.sleep(nanoseconds: 300_000_000)

        guard let totalBytesInitial = getTotalDownloadBytes(fromJSON: jsonPath),
              totalBytesInitial > 0 else {
            await showAlreadyDownloadedPopup()
            allowFortniteToRun = true
            await MainActor.run {
                self.fileStatusMessage = "All game files are already downloaded."
                self.filesProgress = 1.0
                self.isDownloadingFiles = false
            }
            return
        }

        await updateStatus("Total download: \(format(bytes: totalBytesInitial))")

        let pollIntervalNanos = UInt64(0.5 * 1_000_000_000)
        var lastLibrarySize: UInt64 = folderSize(at: libraryPath)

        while !Task.isCancelled {

            if shouldRecoverFromStuck() {
                ignoreNextWarning = true
                _ = await openFortniteSilently()
                terminateFortnite()
                lastProgressDate = Date()
            }

            if !allowFortniteToRun && downloadStarted {
                let running = NSWorkspace.shared.runningApplications.contains {
                    ($0.bundleIdentifier?.contains("Fortnite") ?? false)
                    || ($0.localizedName?.lowercased().contains("fortnite") ?? false)
                }
                if running {
                    if ignoreNextWarning == true {
                        terminateFortnite()
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        ignoreNextWarning = false
                    } else {
                        terminateFortnite()
                        await MainActor.run { self.showWarningPopup() }
                    }
                }
            }

            try? await Task.sleep(nanoseconds: pollIntervalNanos)

            let currentDownloadedJSON = getDownloadedBytes(fromJSON: jsonPath) ?? 0

            let librarySize = folderSize(at: libraryPath)
            let chunkSize = folderSize(at: chunkDownloadFullPath)

            // ✔ FIXED: combined size now works
            let combinedSize = librarySize + chunkSize

            let realDownloaded = max(currentDownloadedJSON, combinedSize, cumulativeDownloaded)
            cumulativeDownloaded = realDownloaded

            if realDownloaded > lastProgressValue {
                lastProgressValue = realDownloaded
                lastProgressDate = Date()
            }

            if !pendingFinish {
                await MainActor.run {
                    filesProgress = min(1, Double(realDownloaded) / Double(totalBytesInitial))
                    fileStatusMessage =
                        "Downloading — \(format(bytes: realDownloaded)) / \(format(bytes: totalBytesInitial))"
                }

                if realDownloaded >= totalBytesInitial {
                    pendingFinish = true
                    pendingFinishStart = Date()
                    librarySizeAtFinishTrigger = librarySize

                    await MainActor.run {
                        self.filesProgress = 1.0
                        self.fileStatusMessage = "Finishing download…"
                    }
                    lastLibrarySize = librarySize
                    continue
                }
            }

            else {

                if librarySize > lastLibrarySize {
                    pendingFinishStart = Date()
                    await MainActor.run {
                        self.fileStatusMessage = "Finishing download…"
                        self.filesProgress = 1.0
                    }
                    lastLibrarySize = librarySize
                    continue
                }

                if librarySize < lastLibrarySize {
                    await MainActor.run {
                        self.filesProgress = 1.0
                        self.fileStatusMessage = "Download Complete"
                        self.isDownloadingFiles = false
                    }
                    allowFortniteToRun = true
                    _ = await openFortnite()
                    return
                }

                if let start = pendingFinishStart,
                   Date().timeIntervalSince(start) > 5 {

                    allowFortniteToRun = true
                    await MainActor.run {
                        self.filesProgress = 1.0
                        self.fileStatusMessage = "Download Complete"
                        self.isDownloadingFiles = false
                    }

                    _ = await openFortnite()
                    return
                }

                lastLibrarySize = librarySize
                continue
            }

            if librarySize < lastLibrarySize && lastLibrarySize > 0 {

                await MainActor.run {
                    self.fileStatusMessage = "Finishing download…"
                    self.filesProgress = 0.99
                }

                try? await Task.sleep(nanoseconds: 1_000_000_000)

                await MainActor.run {
                    self.filesProgress = 1.0
                    self.fileStatusMessage = "Finalizing…"
                    self.isDownloadingFiles = false
                }

                allowFortniteToRun = true
                _ = await openFortnite()
                return
            }

            lastLibrarySize = librarySize
        }

        allowFortniteToRun = true
        pendingFinish = false
    }

    private func shouldRecoverFromStuck() -> Bool {
        Date().timeIntervalSince(lastProgressDate) >= 15
    }

    @MainActor
    private func showWarningPopup() {
        let alert = NSAlert()
        alert.messageText = "Fortnite is downloading"
        alert.informativeText =
        "Please do NOT open Fortnite during the in-game download. It will reopen automatically when the download is finished."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        _ = alert.runModal()
    }

    @MainActor
    private func showAlreadyDownloadedPopup() {
        let alert = NSAlert()
        alert.messageText = "All Files Already Downloaded"
        alert.informativeText =
        "Fortnite has no missing files. Everything is already downloaded.\n\nDo you want to open Fortnite now?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Fortnite")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            _ = Task { await openFortnite() }
        }
    }

    private func openFortnite() async -> Bool {
        return await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                p.arguments = ["/Applications/Fortnite.app"]
                do {
                    try p.run()
                    cont.resume(returning: true)
                } catch {
                    cont.resume(returning: false)
                }
            }
        }
    }

    private func openFortniteSilently() async -> Bool {
        return await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                p.arguments = ["-g", "/Applications/Fortnite.app"]
                do {
                    try p.run()
                    cont.resume(returning: true)
                } catch {
                    cont.resume(returning: false)
                }
            }
        }
    }

    private func terminateFortnite() {
        for app in NSWorkspace.shared.runningApplications where
            (app.bundleIdentifier?.contains("Fortnite") ?? false)
            || (app.localizedName?.lowercased().contains("fortnite") ?? false)
        {
            app.terminate()
        }
    }

    private func waitForJSONChange(_ path: String, timeout: TimeInterval) async -> Bool {
        let start = Date()
        var lastMod = fileMod(path)

        while Date().timeIntervalSince(start) < timeout && !Task.isCancelled {
            if FileManager.default.fileExists(atPath: path) {
                let mod = fileMod(path)
                if mod != lastMod {
                    return true
                }
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        return false
    }

    private func fileMod(_ path: String) -> Date? {
        (try? FileManager.default
            .attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? nil
    }

    private func getTotalDownloadBytes(fromJSON path: String) -> UInt64? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return sumKeyRecursive(obj, key: "DownloadSize")
    }

    private func getDownloadedBytes(fromJSON path: String) -> UInt64? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return sumKeyRecursive(obj, key: "DownloadedSize")
    }

    private func sumKeyRecursive(_ node: Any, key: String) -> UInt64 {
        var total: UInt64 = 0
        if let dict = node as? [String: Any] {
            for (k, v) in dict {
                if k.lowercased() == key.lowercased() {
                    if let n = v as? NSNumber { total += n.uint64Value }
                    else if let s = v as? String, let n = UInt64(s) { total += n }
                }
                total += sumKeyRecursive(v, key: key)
            }
        } else if let arr = node as? [Any] {
            for item in arr {
                total += sumKeyRecursive(item, key: key)
            }
        }
        return total
    }

    private func folderSize(at path: String) -> UInt64 {
        var result: UInt64 = 0
        guard let enumr = FileManager.default.enumerator(atPath: path) else { return 0 }

        for case let file as String in enumr {
            let full = (path as NSString).appendingPathComponent(file)
            if let attr = try? FileManager.default.attributesOfItem(atPath: full),
               let bytes = attr[.size] as? UInt64 {
                result += bytes
            }
        }
        return result
    }

    private func updateStatus(_ str: String) async {
        await MainActor.run { self.fileStatusMessage = str }
    }

    private func setError(_ msg: String) async {
        await MainActor.run {
            self.fileStatusMessage = msg
            self.filesProgress = 0
            self.isDownloadingFiles = false
            self.allowFortniteToRun = true
        }
    }

    private func format(bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
