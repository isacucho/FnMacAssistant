//
//  PatchManager.swift
//  FnMacAssistant
//
//  Created by Isacucho on 11/11/25.
//

import Foundation
import Combine
import AppKit

final class PatchManager: ObservableObject {
    static let shared = PatchManager()
    
    @MainActor @Published var patchAttempts = 0
    @MainActor @Published var isPatching = false
    @MainActor @Published var patchCompleted = false
    @MainActor @Published var logMessages: [String] = []
    
    private let fortniteAppPath = "/Applications/Fortnite.app"
    private let altFortniteAppPath = "/Applications/Fortnite-1.app"
    private let legacyFortniteAppPath = "/Applications/FortniteClient-IOS-Shipping.app"
    private let iOSFolderPath = "/Applications/iOS"
    private let iOSLegacyFortniteAppPath = "/Applications/iOS/FortniteClient-IOS-Shipping.app"
    
    private init() {}
    
    // MARK: - Public Entry Point
    @MainActor
    func startPatch() {
        // Allow re-patching attempts even if already completed in this session
        patchAttempts += 1
        if patchAttempts >= 3 {
            showRepeatedPatchWarning()
            patchAttempts = 0
            return
        }
        
        Task.detached(priority: .userInitiated) {
            await self.runPatch()
        }
    }
    // MARK: - Patch Steps
    private func runPatch() async {
        log("Starting patch process...")
        setState(isPatching: true, completed: false)

        normalizeFortniteAppName()
        
        guard FileManager.default.fileExists(atPath: fortniteAppPath) else {
            log("Fortnite is not installed. Please sideload it first.")
            finish(false)
            return
        }
        
        log("Launching Fortnite...")
        let launched = await runShellLaunch()
        guard launched else {
            log("Failed to launch Fortnite. Try opening it manually at least once.")
            finish(false)
            return
        }

        log("Waiting for gatekeeper to verify the application...")
        let start = Date()
        var wasRunning = false
        while Date().timeIntervalSince(start) < 7 {
            if isFortniteRunning() {
                wasRunning = true
            } else if wasRunning {
                log("Adding entitlements to embedded.mobileprovision...")
                break
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        
        log("Applying patch...")
        let result = await applyProvisionPatch()
        switch result {
        case .success:
            if UserDefaults.standard.bool(forKey: "enableInGameDownloadFolder") {
                updateBackgroundHttpFolder()
            }
            log("Patch successfully applied. You can now open Fortnite.")
            finish(true)
        case .alreadyApplied:
            if UserDefaults.standard.bool(forKey: "enableInGameDownloadFolder") {
                updateBackgroundHttpFolder()
            }
            log("Patch was already applied. No changes were made.")
            finish(false)
        case .failed:
            log("Failed to apply patch. If this happened due to permissions, grant Full Disk Access to FnMacAssistant and try again.")
            await promptFullDiskAccess()
            finish(false)
        }
    }

    // MARK: - In-Game Download Folder
    @MainActor
    func prepareInGameDownloadFolder() {
        updateBackgroundHttpFolder()
    }

    @MainActor
    func removeInGameDownloadFolder() {
        guard let containerPath = FortniteContainerLocator.shared.getContainerPath() else {
            log("Could not locate Fortnite container. BackgroundHttp cleanup skipped.")
            return
        }

        let backgroundHttpURL = URL(fileURLWithPath: containerPath)
            .appendingPathComponent("Data/Documents/FortniteGame/PersistentDownloadDir/BackgroundHttp", isDirectory: true)

        let fm = FileManager.default

        guard fm.fileExists(atPath: backgroundHttpURL.path) else { return }

        do {
            let contents = try fm.contentsOfDirectory(at: backgroundHttpURL, includingPropertiesForKeys: [.isDirectoryKey])
            for item in contents where item.lastPathComponent.hasPrefix("++") {
                try fm.removeItem(at: item)
            }
            log("BackgroundHttp folder cleaned.")
        } catch {
            log("Failed to clean BackgroundHttp folder: \(error.localizedDescription)")
        }
    }

    // MARK: - Normalize App Name
    private func normalizeFortniteAppName() {
        let fm = FileManager.default
        if fm.fileExists(atPath: iOSFolderPath) && fm.fileExists(atPath: iOSLegacyFortniteAppPath) {
            if fm.fileExists(atPath: legacyFortniteAppPath) {
                log("Found iOS Fortnite bundle, but one already exists in Applications root.")
            } else {
                do {
                    try fm.moveItem(atPath: iOSLegacyFortniteAppPath, toPath: legacyFortniteAppPath)
                    log("Moved FortniteClient-IOS-Shipping.app from /Applications/iOS to /Applications.")
                } catch {
                    log("Failed to move FortniteClient-IOS-Shipping.app from iOS folder. \(error.localizedDescription)")
                }
            }
        }

        let altExists = fm.fileExists(atPath: altFortniteAppPath)
        let legacyExists = fm.fileExists(atPath: legacyFortniteAppPath)
        guard altExists || legacyExists else { return }

        let preferredPath = altExists ? altFortniteAppPath : legacyFortniteAppPath

        if fm.fileExists(atPath: fortniteAppPath) {
            do {
                try fm.removeItem(atPath: fortniteAppPath)
            } catch {
                log("Failed to remove existing Fortnite.app. \(error.localizedDescription)")
                return
            }
        }

        do {
            try fm.moveItem(atPath: preferredPath, toPath: fortniteAppPath)
            log("Renamed Fortnite's bundle to Fortnite.app")
        } catch {
            log("Failed to rename Fortnite app. \(error.localizedDescription)")
        }
    }
    
    // MARK: - Launch via shell
    private func runShellLaunch() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = ["/Applications/Fortnite.app"]
                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    // MARK: - Patch embedded.mobileprovision
    private func applyProvisionPatch() async -> PatchResult {
        let provisionPath = fortniteAppPath + "/Wrapper/FortniteClient-IOS-Shipping.app/embedded.mobileprovision"
        guard FileManager.default.fileExists(atPath: provisionPath) else {
            log("Could not find the embedded provisioning file.")
            return .failed
        }
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("FnMacAssistant-cache", isDirectory: true)
        let tempURL = tempDir.appendingPathComponent("embedded.mobileprovision")
        
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try FileManager.default.removeItem(at: tempURL)
            }
            try FileManager.default.copyItem(atPath: provisionPath, toPath: tempURL.path)
        } catch {
            log("Unable to copy provisioning file.")
            return .failed
        }
        
        do {
            var data = try Data(contentsOf: tempURL)
            guard let xmlStart = data.range(of: Data("<?xml".utf8))?.lowerBound,
                  let xmlEnd = data.lastRange(of: Data("</plist>".utf8))?.upperBound else {
                log("Could not locate the XML section in the provisioning file.")
                return .failed
            }
            
            let xmlData = data.subdata(in: xmlStart..<xmlEnd)
            guard var xml = String(data: xmlData, encoding: .utf8) else {
                log("Unable to read provisioning XML.")
                return .failed
            }

            let keyA = "com.apple.developer.kernel.extended-virtual-addressing"
            let keyB = "com.apple.developer.kernel.increased-memory-limit"
            if xml.contains(keyA) && xml.contains(keyB) {
                return .alreadyApplied
            }
            
            let patch = """
                <key>com.apple.developer.kernel.extended-virtual-addressing</key>
                <true/>
                <key>com.apple.developer.kernel.increased-memory-limit</key>
                <true/>
            """
            
            if let entKey = xml.range(of: "<key>Entitlements</key>"),
               let dictOpen = xml.range(of: "<dict>", range: entKey.upperBound..<xml.endIndex),
               let dictClose = xml.range(of: "</dict>", range: dictOpen.upperBound..<xml.endIndex) {
                xml.insert(contentsOf: patch, at: dictClose.lowerBound)
            } else {
                log("Could not find the entitlements section.")
                return .failed
            }
            
            let newXML = xml.data(using: .utf8)!
            data.replaceSubrange(xmlStart..<xmlEnd, with: newXML)
            try data.write(to: tempURL, options: .atomic)
        } catch {
            log("Failed to modify provisioning file.")
            return .failed
        }
        
        log("Replacing provisioning file...")
        let success = await moveFileWithShell(from: tempURL.path, to: provisionPath)
        if !success {
            log("Failed to replace provisioning file. Check if FnMacAssistant has Full Disk Access.")
        }
        return success ? .success : .failed
    }

    // MARK: - BackgroundHttp Folder Update
    private func updateBackgroundHttpFolder() {
        guard let containerPath = FortniteContainerLocator.shared.getContainerPath() else {
            log("Could not locate Fortnite container. BackgroundHttp update skipped.")
            return
        }

        let backgroundHttpURL = URL(fileURLWithPath: containerPath)
            .appendingPathComponent("Data/Documents/FortniteGame/PersistentDownloadDir/BackgroundHttp", isDirectory: true)

        guard let buildVersion = readCloudBuildVersion(),
              let folderName = buildFolderName(from: buildVersion)
        else {
            log("Could not determine build version for BackgroundHttp update.")
            return
        }

        let fm = FileManager.default

        do {
            try fm.createDirectory(at: backgroundHttpURL, withIntermediateDirectories: true)
            let contents = try fm.contentsOfDirectory(at: backgroundHttpURL, includingPropertiesForKeys: [.isDirectoryKey])
            for item in contents where item.lastPathComponent.hasPrefix("++") {
                try fm.removeItem(at: item)
            }

            let newFolderURL = backgroundHttpURL.appendingPathComponent(folderName, isDirectory: true)
            if !fm.fileExists(atPath: newFolderURL.path) {
                try fm.createDirectory(at: newFolderURL, withIntermediateDirectories: true)
            }

            log("BackgroundHttp folder set to \(folderName)")
        } catch {
            log("Failed to update BackgroundHttp folder: \(error.localizedDescription)")
        }
    }

    private func readCloudBuildVersion() -> String? {
        let cloudJSON =
        "/Applications/Fortnite.app/Wrapper/FortniteClient-IOS-Shipping.app/Cloud/cloudcontent.json"

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: cloudJSON)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        return json["BuildVersion"] as? String
    }

    private func buildFolderName(from buildVersion: String) -> String? {
        let pattern = "^(.*-)(\\d+(?:\\.\\d+){1,2})"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(buildVersion.startIndex..<buildVersion.endIndex, in: buildVersion)
        guard let match = regex.firstMatch(in: buildVersion, range: range),
              let prefixRange = Range(match.range(at: 1), in: buildVersion),
              let versionRange = Range(match.range(at: 2), in: buildVersion)
        else { return nil }

        let prefix = String(buildVersion[prefixRange])
        var version = String(buildVersion[versionRange])
        let parts = version.split(separator: ".").map(String.init)
        if parts.count >= 3, parts.last == "1" {
            version = parts.dropLast().joined(separator: ".")
        }

        return prefix + version
    }
    
    // MARK: - Shell Move Helper
    private func moveFileWithShell(from: String, to: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["bash", "-c", "mv -f '\(from)' '\(to)'"]
                
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: false)
                    return
                }
                
                DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
                    if process.isRunning {
                        process.terminate()
                        continuation.resume(returning: false)
                    }
                }
                
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus == 0)
            }
        }
    }
    
    // MARK: - Terminate Fortnite
    private func terminateFortnite() {
        for app in NSWorkspace.shared.runningApplications where app.localizedName?.lowercased().contains("fortnite") == true {
            app.terminate()
        }
    }
    
    // MARK: - Prompt for Full Disk Access
    @MainActor
    private func promptFullDiskAccess() async {
        let alert = NSAlert()
        alert.messageText = "Full Disk Access Required"
        alert.informativeText = """
        FnMacAssistant needs Full Disk Access to modify Fortnite's internal files.
        To grant access, open System Settings → Privacy & Security → Full Disk Access,
        and enable FnMacAssistant.
        """
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    // MARK: - Process Detection
    private func isFortniteRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.localizedName?.lowercased().contains("fortnite") ?? false
        }
    }
    
    // MARK: - Helpers
    @MainActor
    private func setState(isPatching: Bool, completed: Bool) {
        self.isPatching = isPatching
        self.patchCompleted = completed
    }
    
    @MainActor
    private func finish(_ success: Bool) {
        isPatching = false
        patchCompleted = success
    }
    
    @MainActor
    private func log(_ message: String) {
        self.logMessages.append(message)
        print(message)
    }
    
    
    @MainActor
    private func showRepeatedPatchWarning() {
        let alert = NSAlert()
        alert.messageText = "Patch Attempted Multiple Times"
        alert.informativeText = """
    It looks like you've attempted to patch Fortnite several times.
    
    If patching does not seem to work, it might be because macOS blocked Fortnite from launching.
    Please open System Settings → Privacy & Security and press “Open Anyway”.
    """
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?General") {
                NSWorkspace.shared.open(url)
            }
        }
    }

}

private enum PatchResult {
    case success
    case alreadyApplied
    case failed
}
