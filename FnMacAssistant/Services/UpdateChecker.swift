//
//  UpdateChecker.swift
//  FnMacAssistant
//
//  Created by Isacucho on 02/10/26.
//

import Foundation
import Combine

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published private(set) var isChecking = false
    @Published private(set) var latestVersion: String?
    @Published private(set) var lastChecked: Date?
    @Published private(set) var errorMessage: String?

    private let session: URLSession
    private let cacheExpiry: TimeInterval = 600
    private let releasesAPI = URL(string: "https://api.github.com/repos/isacucho/FnMacAssistant/releases/latest")!

    private let cacheLatestKey = "updateChecker.latestVersion"
    private let cacheCheckedKey = "updateChecker.lastChecked"
    private let cacheETagKey = "updateChecker.latestETag"

    private init(session: URLSession = .shared) {
        self.session = session
        self.latestVersion = UserDefaults.standard.string(forKey: cacheLatestKey)
        self.lastChecked = UserDefaults.standard.object(forKey: cacheCheckedKey) as? Date
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
    }

    var isUpdateAvailable: Bool {
        guard let latestVersion else { return false }
        let current = parseVersion(currentVersion)
        let latest = parseVersion(latestVersion)
        let numericCompare = compareNumeric(current.parts, latest.parts)

        if numericCompare == .orderedAscending {
            return true
        }
        if numericCompare == .orderedSame {
            if current.hasPrerelease && !latest.hasPrerelease {
                return true
            }
        }
        return false
    }

    var isBetaBuild: Bool {
        guard let latestVersion else {
            return parseVersion(currentVersion).hasPrerelease
        }
        let current = parseVersion(currentVersion)
        let latest = parseVersion(latestVersion)
        let numericCompare = compareNumeric(current.parts, latest.parts)
        return current.hasPrerelease || numericCompare == .orderedDescending
    }

    var isBetaWithStableSameVersion: Bool {
        guard let latestVersion else { return false }
        let current = parseVersion(currentVersion)
        let latest = parseVersion(latestVersion)
        let numericCompare = compareNumeric(current.parts, latest.parts)
        return current.hasPrerelease && !latest.hasPrerelease && numericCompare == .orderedSame
    }

    func checkForUpdates(force: Bool = false) async {
        if !force, let lastChecked, Date().timeIntervalSince(lastChecked) < cacheExpiry,
           latestVersion != nil {
            return
        }

        isChecking = true
        errorMessage = nil
        defer { isChecking = false }

        var request = URLRequest(url: releasesAPI)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        if let etag = UserDefaults.standard.string(forKey: cacheETagKey) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        do {
            let (data, response) = try await session.data(for: request)
            let httpResponse = response as? HTTPURLResponse

            if httpResponse?.statusCode == 304 {
                updateCacheTimestamps()
                return
            }

            guard httpResponse?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }

            if let etag = httpResponse?.allHeaderFields["ETag"] as? String {
                UserDefaults.standard.set(etag, forKey: cacheETagKey)
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let normalizedVersion = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            latestVersion = normalizedVersion
            updateCacheTimestamps()
            UserDefaults.standard.set(normalizedVersion, forKey: cacheLatestKey)
        } catch {
            errorMessage = "Failed to check for updates."
            if latestVersion == nil {
                latestVersion = UserDefaults.standard.string(forKey: cacheLatestKey)
            }
        }
    }

    private func updateCacheTimestamps() {
        let now = Date()
        lastChecked = now
        UserDefaults.standard.set(now, forKey: cacheCheckedKey)
    }

    private func parseVersion(_ value: String) -> (parts: [Int], hasPrerelease: Bool) {
        var numericParts: [Int] = []
        var currentNumber = ""
        var hasPrerelease = false
        var inPrerelease = false

        for char in value {
            if inPrerelease {
                continue
            }

            if char.isNumber {
                currentNumber.append(char)
            } else if char == "." {
                if !currentNumber.isEmpty {
                    numericParts.append(Int(currentNumber) ?? 0)
                    currentNumber = ""
                }
            } else {
                if !currentNumber.isEmpty {
                    numericParts.append(Int(currentNumber) ?? 0)
                    currentNumber = ""
                }
                hasPrerelease = true
                inPrerelease = true
            }
        }

        if !currentNumber.isEmpty {
            numericParts.append(Int(currentNumber) ?? 0)
        }

        if value.rangeOfCharacter(from: .letters) != nil {
            hasPrerelease = true
        }

        return (numericParts, hasPrerelease)
    }

    private func compareNumeric(_ lhsParts: [Int], _ rhsParts: [Int]) -> ComparisonResult {
        let maxCount = max(lhsParts.count, rhsParts.count)

        for index in 0..<maxCount {
            let left = index < lhsParts.count ? lhsParts[index] : 0
            let right = index < rhsParts.count ? rhsParts[index] : 0
            if left < right { return .orderedAscending }
            if left > right { return .orderedDescending }
        }

        return .orderedSame
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
    }
}
