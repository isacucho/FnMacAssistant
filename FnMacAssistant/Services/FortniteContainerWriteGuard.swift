//
//  FortniteContainerWriteGuard.swift
//  FnMacAssistant
//
//  Created by Isacucho on 20/02/26.
//

import Foundation
import AppKit

enum FortniteContainerWriteGuard {
    static func confirmCanModifyContainer() -> Bool {
        if Thread.isMainThread {
            return confirmCanModifyContainerOnMainThread()
        }

        var allowed = false
        DispatchQueue.main.sync {
            allowed = confirmCanModifyContainerOnMainThread()
        }
        return allowed
    }

    private static func confirmCanModifyContainerOnMainThread() -> Bool {
        guard isFortniteRunning() else { return true }

        let alert = NSAlert()
        alert.messageText = "Fortnite Is Running"
        alert.informativeText = """
        FnMacAssistant needs to modify files inside Fortnite's container.
        Close Fortnite before continuing.
        """
        alert.addButton(withTitle: "Close Fortnite")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return false }

        terminateFortnite()
        waitForFortniteToClose(timeout: 5)
        return !isFortniteRunning()
    }

    static func isFortniteRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            ($0.bundleIdentifier?.contains("Fortnite") ?? false)
            || ($0.localizedName?.lowercased().contains("fortnite") ?? false)
        }
    }

    // Strict check for the game app itself. This avoids treating helper
    // processes as blockers for UI prompts that only care about Fortnite.app.
    static func isMainFortniteAppRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains(where: isMainFortniteApplication(_:))
    }

    static func terminateFortnite() {
        let running = NSWorkspace.shared.runningApplications.filter {
            ($0.bundleIdentifier?.contains("Fortnite") ?? false)
            || ($0.localizedName?.lowercased().contains("fortnite") ?? false)
        }
        for app in running {
            _ = app.forceTerminate()
        }
    }

    private static func waitForFortniteToClose(timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while isFortniteRunning() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
    }

    private static func isMainFortniteApplication(_ app: NSRunningApplication) -> Bool {
        if let bundleIdentifier = app.bundleIdentifier?.lowercased() {
            if bundleIdentifier == "com.epicgames.fortnitegame" || bundleIdentifier == "com.epicgames.fortnite" {
                return true
            }
        }

        if let bundlePath = app.bundleURL?.path.lowercased(), bundlePath.hasSuffix("/fortnite.app") {
            return true
        }

        if let executableURL = app.executableURL {
            let executablePath = executableURL.path.lowercased()
            if executablePath.contains("/fortnite.app/") {
                return true
            }
            if executablePath.contains("/fortniteclient-ios-shipping.app/")
                || executableURL.lastPathComponent.lowercased() == "fortniteclient-ios-shipping" {
                return true
            }
        }

        return false
    }
}
