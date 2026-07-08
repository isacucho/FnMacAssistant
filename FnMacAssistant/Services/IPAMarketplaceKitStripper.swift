//
//  IPAMarketplaceKitStripper.swift
//  FnMacAssistant
//
//  Created by Aarav Chourishi on 08/07/26.
//

import Foundation

/// Removes Epic's `MarketplaceKitWrapper.framework` from a downloaded Fortnite IPA so
/// the app stops crashing on macOS 27.
///
/// Background: recent Fortnite iOS builds ship an Epic-authored framework
/// `MarketplaceKitWrapper.framework` (`com.epicgames.MarketplaceKitWrapper`) that wraps
/// Apple's `MarketplaceKit.AppDistributor` API. On macOS 27 (Tahoe beta) Apple's API
/// returns nil for a sideloaded app, and Epic's `AppDistributorWrapper.getCurrent`
/// Swift closure dereferences that nil — `EXC_BAD_ACCESS @ 0x0` ~2s after launch
/// (Thread … Crashed: `MarketplaceKitWrapper … AppDistributorWrapper.getCurrent`).
///
/// The framework is weak-linked and Epic's own binary degrades gracefully when it is
/// absent ("MarketplaceKitWrapper framework not available, marketplace features will be
/// disabled"), so removing it from the IPA *before* sideloading prevents the crash with
/// no functional loss: sideloaded clients never use Apple's marketplace in-app purchase
/// (Epic uses its own payment).
///
/// Why this must happen pre-sign in the IPA rather than as a post-install patch:
/// modifying the framework binary after signing invalidates its code signature and amfid
/// kills the app on launch, and the iOS-on-Mac runtime re-overlays the framework from the
/// bundle so it can't be deleted post-install. Stripping the IPA before the user sideloads
/// (and Sideloadly re-signs) is the only place it works.
enum IPAMarketplaceKitStripper {

    /// Strips `MarketplaceKitWrapper.framework` from the IPA at `ipaURL` when the host is
    /// macOS 27 or newer. Returns `true` if the framework was removed, `false` if no strip
    /// was needed (older macOS, or framework already absent — `zip -d` is a no-op then).
    /// - Throws: `StripperError` if `zip` is missing or reports a real failure.
    static func stripIfNeeded(at ipaURL: URL) throws -> Bool {
        guard hostNeedsStrip() else { return false }
        try removeMarketplaceKitWrapper(from: ipaURL)
        return true
    }

    private static func hostNeedsStrip() -> Bool {
        // Crash confirmed on macOS 27.0 beta. Stripping is harmless on other versions,
        // but we gate on 27+ to leave working 26.x setups untouched.
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
    }

    private static func removeMarketplaceKitWrapper(from ipaURL: URL) throws {
        guard FileManager.default.fileExists(atPath: "/usr/bin/zip") else {
            throw StripperError.zipUnavailable
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        // `*` matches across path separators, so this pair covers every file under the
        // framework dir (incl. SC_Info/ and _CodeSignature/) regardless of the inner
        // app's bundle name. `zip -d` exits 0 with "Nothing to do!" and leaves the archive
        // untouched when no entries match, so it's a safe no-op if the framework is gone.
        process.arguments = [
            "-d", ipaURL.path,
            "Payload/*/Frameworks/MarketplaceKitWrapper.framework/*",
            "Payload/*/Frameworks/MarketplaceKitWrapper.framework"
        ]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
        } catch {
            throw StripperError.launchFailed(error)
        }

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw StripperError.zipFailed(
                status: process.terminationStatus,
                details: String(
                    data: output.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
        }
    }

    enum StripperError: LocalizedError {
        case zipUnavailable
        case launchFailed(Error)
        case zipFailed(status: Int32, details: String)

        var errorDescription: String? {
            switch self {
            case .zipUnavailable:
                return "/usr/bin/zip is not available; cannot strip MarketplaceKitWrapper."
            case .launchFailed(let error):
                return "Failed to run zip: \(error.localizedDescription)"
            case .zipFailed(let status, let details):
                return "zip exited with status \(status)" + (details.isEmpty ? "" : ": \(details)")
            }
        }
    }
}