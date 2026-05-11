//
//  IPAFetcher.swift
//  FnMacAssistant
//
//  Created by Isacucho on 06/11/25.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class IPAFetcher: ObservableObject {
    static let shared = IPAFetcher()
    private static let minimumSupportedMacOSVersion = MacOSVersion("15.1")!

    // MARK: - Models

    struct IPAInfo: Identifiable, Decodable, Hashable {
        let name: String
        let download_url: String
        let description: String?
        var id: String { download_url }
    }

    struct MacOSSupportStatus: Equatable {
        enum Reason: Equatable {
            case belowMinimum
            case aboveMaximum
        }

        let currentVersion: String
        let minimumVersion: String
        let maximumVersion: String?
        let reason: Reason

        var title: String {
            "Unsupported macOS Version"
        }

        var message: String {
            switch reason {
            case .belowMinimum:
                return "FnMacAssistant requires macOS \(minimumVersion) or later. You are currently on macOS \(currentVersion). Some features may not work correctly."
            case .aboveMaximum:
                if let maximumVersion {
                    return "FnMacAssistant currently supports macOS versions up to \(maximumVersion). You are currently on macOS \(currentVersion), which is newer than the latest supported version. Some features may not work correctly."
                }
                return "You are currently on macOS \(currentVersion). Some features may not work correctly."
            }
        }
    }

    private struct RemoteListEntry: Decodable {
        let name: String?
        let download_url: String?
        let description: String?
        let max_version: String?
        let max_supported_macos: String?
    }

    private struct RemotePayload: Decodable {
        let ipas: [RemoteListEntry]
        let max_version: String?
        let max_supported_macos: String?
    }

    // MARK: - Published State

    @Published var availableIPAs: [IPAInfo] = []
    @Published var selectedIPA: IPAInfo? {
        didSet {
            if let selectedIPA {
                UserDefaults.standard.set(selectedIPA.id, forKey: selectedIPAIDDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: selectedIPAIDDefaultsKey)
            }
        }
    }
    @Published var isLoading: Bool = false
    @Published var latestReleaseTag: String? = nil
    @Published private(set) var maximumSupportedMacOSVersion: String? = nil
    @Published private(set) var macOSSupportStatus: MacOSSupportStatus? = nil

    // MARK: - Remote Source Configuration

    private let ipaListURL = "https://gitlab.com/-/snippets/5991232/raw/main/fortnite.json"
    private let selectedIPAIDDefaultsKey = "selectedIPAID"
    private let cachedIPAListDataDefaultsKey = "cachedIPAListData"

    // MARK: - Init

    private init() {}

    // MARK: - Public API

    func fetchAvailableIPAs() async {
        let preferredSelectionID = selectedIPA?.id
            ?? UserDefaults.standard.string(forKey: selectedIPAIDDefaultsKey)
        isLoading = true
        updateMacOSSupportStatus()

        guard let payload = await fetchFromJSONSource(ipaListURL) ?? fetchCachedJSONSource() else {
            isLoading = false
            return
        }

        let ipaList = payload.ipas
        availableIPAs = ipaList
        maximumSupportedMacOSVersion = payload.maximumSupportedMacOSVersion
        updateMacOSSupportStatus()

        if let preferredSelectionID,
           let matched = ipaList.first(where: { $0.id == preferredSelectionID }) {
            selectedIPA = matched
        } else {
            selectedIPA = ipaList.first
        }

        if let first = ipaList.first,
           let version = extractVersion(from: first.name) {
            latestReleaseTag = version
        } else {
            latestReleaseTag = "Unknown"
        }

        isLoading = false
    }

    // MARK: - JSON Fetch (cache disabled)

    private func fetchFromJSONSource(_ urlString: String) async -> (ipas: [IPAInfo], maximumSupportedMacOSVersion: String?)? {
        guard let baseURL = URL(string: urlString),
              let url = cacheBustedURL(from: baseURL) else { return nil }

        do {
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("FnMacAssistant/2.0 (macOS)", forHTTPHeaderField: "User-Agent")
            request.setValue("no-cache, no-store, must-revalidate", forHTTPHeaderField: "Cache-Control")
            request.setValue("no-cache", forHTTPHeaderField: "Pragma")
            request.setValue("0", forHTTPHeaderField: "Expires")
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

            let config = URLSessionConfiguration.ephemeral
            config.urlCache = nil
            config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData

            let session = URLSession(configuration: config)
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                print("❌ IPA JSON fetch failed:", (response as? HTTPURLResponse)?.statusCode ?? -1)
                return nil
            }

            print("Raw JSON:", String(data: data, encoding: .utf8) ?? "Invalid JSON")
            let payload = try decodePayload(from: data)
            UserDefaults.standard.set(data, forKey: cachedIPAListDataDefaultsKey)
            return payload

        } catch {
            print("IPA JSON error:", error)
            return nil
        }
    }

    private func cacheBustedURL(from baseURL: URL) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL
        }

        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "_fnmac_ts" }
        queryItems.append(URLQueryItem(name: "_fnmac_ts", value: String(Int(Date().timeIntervalSince1970))))
        components.queryItems = queryItems
        return components.url
    }

    private func fetchCachedJSONSource() -> (ipas: [IPAInfo], maximumSupportedMacOSVersion: String?)? {
        guard let data = UserDefaults.standard.data(forKey: cachedIPAListDataDefaultsKey) else {
            return nil
        }

        do {
            let payload = try decodePayload(from: data)
            print("Using cached IPA JSON")
            return payload
        } catch {
            print("Cached IPA JSON error:", error)
            return nil
        }
    }

    private func decodePayload(from data: Data) throws -> (ipas: [IPAInfo], maximumSupportedMacOSVersion: String?) {
        let decoder = JSONDecoder()

        if let wrappedPayload = try? decoder.decode(RemotePayload.self, from: data) {
            let ipas = wrappedPayload.ipas.compactMap { entry -> IPAInfo? in
                guard let name = entry.name,
                      let downloadURL = entry.download_url else {
                    return nil
                }
                return IPAInfo(name: name, download_url: downloadURL, description: entry.description)
            }
            let maximumSupportedMacOSVersion = firstNonEmptyVersion(
                wrappedPayload.max_supported_macos,
                wrappedPayload.max_version
            )

            print("\(ipas.count) IPAs found")
            if let maximumSupportedMacOSVersion {
                print("Max supported macOS from remote source:", maximumSupportedMacOSVersion)
            }

            return (ipas: ipas, maximumSupportedMacOSVersion: maximumSupportedMacOSVersion)
        }

        let decoded = try decoder.decode([RemoteListEntry].self, from: data)
        let ipas = decoded.compactMap { entry -> IPAInfo? in
            guard let name = entry.name,
                  let downloadURL = entry.download_url else {
                return nil
            }
            return IPAInfo(name: name, download_url: downloadURL, description: entry.description)
        }
        let maximumSupportedMacOSVersion = decoded
            .compactMap { $0.max_supported_macos ?? $0.max_version }
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })

        print("\(ipas.count) IPAs found")
        if let maximumSupportedMacOSVersion {
            print("Max supported macOS from remote source:", maximumSupportedMacOSVersion)
        }

        return (ipas: ipas, maximumSupportedMacOSVersion: maximumSupportedMacOSVersion)
    }

    private func firstNonEmptyVersion(_ candidates: String?...) -> String? {
        candidates.first(where: {
            guard let value = $0 else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) ?? nil
    }

    private func updateMacOSSupportStatus() {
        let currentVersion = MacOSVersion.current
        let minimumVersion = Self.minimumSupportedMacOSVersion
        let maximumVersion = maximumSupportedMacOSVersion.flatMap(MacOSVersion.init(_:))

        if currentVersion < minimumVersion {
            macOSSupportStatus = MacOSSupportStatus(
                currentVersion: currentVersion.displayString,
                minimumVersion: minimumVersion.displayString,
                maximumVersion: maximumVersion?.displayString,
                reason: .belowMinimum
            )
            return
        }

        if let maximumVersion, currentVersion > maximumVersion {
            macOSSupportStatus = MacOSSupportStatus(
                currentVersion: currentVersion.displayString,
                minimumVersion: minimumVersion.displayString,
                maximumVersion: maximumVersion.displayString,
                reason: .aboveMaximum
            )
            return
        }

        macOSSupportStatus = nil
    }
}

// MARK: - Version extractor

private func extractVersion(from ipaName: String) -> String? {
    let pattern = #"\d+\.\d+(?:\.\d+)?"#
    let regex = try? NSRegularExpression(pattern: pattern)
    let range = NSRange(ipaName.startIndex..<ipaName.endIndex, in: ipaName)

    guard let match = regex?.firstMatch(in: ipaName, range: range),
          let swiftRange = Range(match.range, in: ipaName) else {
        return nil
    }

    return String(ipaName[swiftRange])
}

private struct MacOSVersion: Comparable {
    enum PreReleaseKind: Int, Comparable {
        case beta
        case rc

        static func < (lhs: PreReleaseKind, rhs: PreReleaseKind) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    struct PreRelease: Comparable {
        let kind: PreReleaseKind
        let number: Int

        static func < (lhs: PreRelease, rhs: PreRelease) -> Bool {
            if lhs.kind != rhs.kind {
                return lhs.kind < rhs.kind
            }
            return lhs.number < rhs.number
        }
    }

    let major: Int
    let minor: Int
    let patch: Int
    let preRelease: PreRelease?

    init?(_ rawValue: String) {
        let source = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "beta", with: "b")
            .replacingOccurrences(of: " ", with: "")

        let pattern = #"^(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:(b|rc)(\d*))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        guard let match = regex.firstMatch(in: source, options: [], range: range) else { return nil }

        func capture(_ index: Int) -> String? {
            let captureRange = match.range(at: index)
            guard captureRange.location != NSNotFound,
                  let swiftRange = Range(captureRange, in: source) else {
                return nil
            }
            return String(source[swiftRange])
        }

        guard let majorString = capture(1),
              let major = Int(majorString) else {
            return nil
        }

        self.major = major
        self.minor = Int(capture(2) ?? "") ?? 0
        self.patch = Int(capture(3) ?? "") ?? 0

        if let preReleaseKindString = capture(4) {
            let kind: PreReleaseKind
            switch preReleaseKindString {
            case "b":
                kind = .beta
            case "rc":
                kind = .rc
            default:
                return nil
            }
            let number = Int(capture(5) ?? "") ?? 0
            self.preRelease = PreRelease(kind: kind, number: number)
        } else {
            self.preRelease = nil
        }
    }

    static var current: MacOSVersion {
        let processVersion = ProcessInfo.processInfo.operatingSystemVersion
        let baseVersion = "\(processVersion.majorVersion).\(processVersion.minorVersion).\(processVersion.patchVersion)"
        let extraVersion = currentVersionExtra()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return MacOSVersion(baseVersion + extraVersion) ?? MacOSVersion(baseVersion) ?? MacOSVersion("0")!
    }

    var displayString: String {
        var value = "\(major).\(minor)"
        if patch != 0 || preRelease != nil {
            value += ".\(patch)"
        }
        if let preRelease {
            switch preRelease.kind {
            case .beta:
                value += "b"
            case .rc:
                value += "rc"
            }
            if preRelease.number > 0 {
                value += "\(preRelease.number)"
            }
        }
        return value
    }

    static func < (lhs: MacOSVersion, rhs: MacOSVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        switch (lhs.preRelease, rhs.preRelease) {
        case let (lhs?, rhs?):
            return lhs < rhs
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return false
        }
    }

    private static func currentVersionExtra() -> String? {
        guard let dictionary = NSDictionary(contentsOfFile: "/System/Library/CoreServices/SystemVersion.plist"),
              let value = dictionary["ProductVersionExtra"] as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }
}
