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

    // MARK: - Models

    struct IPAInfo: Identifiable, Decodable, Hashable {
        let name: String
        let download_url: String
        var id: String { download_url }
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

    // MARK: - Gist Configuration

    private let gistID = "fb6a16acae4e592603540249cbb7e08d"
    private let gistFileName = "list.json"
    private let selectedIPAIDDefaultsKey = "selectedIPAID"

    // MARK: - Init

    private init() {}

    // MARK: - Public API

    func fetchAvailableIPAs() async {
        let preferredSelectionID = selectedIPA?.id
            ?? UserDefaults.standard.string(forKey: selectedIPAIDDefaultsKey)
        isLoading = true

        guard let rawURL = await fetchLatestGistRawURL(),
              let ipaList = await fetchFromJSONSource(rawURL) else {
            isLoading = false
            return
        }

        availableIPAs = ipaList
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

    // MARK: - GitHub Gist API

    private func fetchLatestGistRawURL() async -> String? {
        let apiURL = URL(string: "https://api.github.com/gists/\(gistID)")!

        do {
            var request = URLRequest(url: apiURL)
            request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            request.setValue("FnMacAssistant/2.0 (macOS)", forHTTPHeaderField: "User-Agent")
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

            let config = URLSessionConfiguration.ephemeral
            config.urlCache = nil

            let session = URLSession(configuration: config)
            let (data, _) = try await session.data(for: request)

            struct GistResponse: Decodable {
                struct File: Decodable {
                    let raw_url: String
                }
                let files: [String: File]
            }

            let gist = try JSONDecoder().decode(GistResponse.self, from: data)

            guard let rawURL = gist.files[gistFileName]?.raw_url else {
                print("list.json not found in gist")
                return nil
            }

            print("Latest Gist raw URL:", rawURL)
            return rawURL

        } catch {
            print("Failed to fetch Gist metadata:", error)
            return nil
        }
    }

    // MARK: - JSON Fetch (cache disabled)

    private func fetchFromJSONSource(_ urlString: String) async -> [IPAInfo]? {
        guard let url = URL(string: urlString) else { return nil }

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

            let decoded = try JSONDecoder().decode([IPAInfo].self, from: data)
            print("\(decoded.count) IPAs found")
            return decoded

        } catch {
            print("IPA JSON error:", error)
            return nil
        }
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
