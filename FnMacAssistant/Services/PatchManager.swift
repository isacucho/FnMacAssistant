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
    
    private init() {}
    
    // MARK: - Public Entry Point
    @MainActor
    func startPatch() {
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
        
        guard FileManager.default.fileExists(atPath: fortniteAppPath) else {
            log("Fortnite is not installed. Please sideload it first.")
            finish(false)
            return
        }
        
        log("Launching Fortnite to verify installation...")
        let launched = await runShellLaunch()
        guard launched else {
            log("Failed to launch Fortnite. Try opening it manually once.")
            finish(false)
            return
        }
        
        log("Waiting for Fortnite to start...")
        var started = false
        for _ in 0..<35 {
            if isFortniteRunning() { started = true; break }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        
        guard started else {
            log("Patch cancelled: Fortnite is already patched, or macOS blocked it from running.")
            log("Go to System Settings → Privacy & Security and click 'Open Anyway' to allow Fortnite to run.")
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?General") {
                NSWorkspace.shared.open(url)
            }
            finish(false)
            return
        }
        
        log("Fortnite launched. Monitoring process...")
        
        var lifetimeSeconds = 0
        while isFortniteRunning() {
            try? await Task.sleep(nanoseconds: 500_000_000)
            lifetimeSeconds += 1
            if lifetimeSeconds > 60 { break }
        }
        
        if lifetimeSeconds > 20 {
            log("Patch cancelled: Fortnite is already patched or the sideload method used does not require patching.")
            finish(false)
            return
        }
        
        log("Fortnite closed — proceeding with patching...")
        
        log("Applying patch...")
        let success = await applyProvisionPatch()
        if success {
            log("Patch successfully applied. You can now open Fortnite.")
        } else {
            log("Failed to apply patch. If this happened due to permissions, grant Full Disk Access to FnMacAssistant and try again.")
            await promptFullDiskAccess()
        }
        
        finish(success)
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
    private func applyProvisionPatch() async -> Bool {
        let provisionPath = fortniteAppPath + "/Wrapper/FortniteClient-IOS-Shipping.app/embedded.mobileprovision"
        guard FileManager.default.fileExists(atPath: provisionPath) else {
            log("Could not find the embedded provisioning file.")
            return false
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
            return false
        }
        
        do {
            var data = try Data(contentsOf: tempURL)
            guard let xmlStart = data.range(of: Data("<?xml".utf8))?.lowerBound,
                  let xmlEnd = data.lastRange(of: Data("</plist>".utf8))?.upperBound else {
                log("Could not locate the XML section in the provisioning file.")
                return false
            }
            
            let xmlData = data.subdata(in: xmlStart..<xmlEnd)
            guard var xml = String(data: xmlData, encoding: .utf8) else {
                log("Unable to read provisioning XML.")
                return false
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
                return false
            }
            
            let newXML = xml.data(using: .utf8)!
            data.replaceSubrange(xmlStart..<xmlEnd, with: newXML)
            try data.write(to: tempURL, options: .atomic)
        } catch {
            log("Failed to modify provisioning file.")
            return false
        }
        
        log("Replacing provisioning file...")
        let success = await moveFileWithShell(from: tempURL.path, to: provisionPath)
        if !success {
            log("Failed to replace provisioning file. Check if FnMacAssistant has Full Disk Access.")
        }
        return success
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
