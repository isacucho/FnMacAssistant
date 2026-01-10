//
//  FortniteContainerLocator.swift
//  FnMacAssistant
//
//  Created by Isacucho on 14/11/25.
//

import Foundation
import AppKit
import Combine   

final class FortniteContainerLocator: ObservableObject {
    static let shared = FortniteContainerLocator()

    @Published var cachedPath: String? {
        didSet {
            if let path = cachedPath {
                UserDefaults.standard.set(path, forKey: "FortniteContainerPath")
            } else {
                UserDefaults.standard.removeObject(forKey: "FortniteContainerPath")
            }
        }
    }

    private init() {
        // Load cache from UserDefaults
        cachedPath = UserDefaults.standard.string(forKey: "FortniteContainerPath")
    }

    // MARK: - Public API

    func getContainerPath() -> String? {
        // Return cached value if available
        if let cached = cachedPath, !cached.isEmpty {
            return cached
        }

        // Otherwise, locate and cache automatically
        let found = locateContainer()
        cachedPath = found
        return found
    }

    func resetContainer() {
        cachedPath = nil
    }

    func manuallySetContainer(path: String) {
        cachedPath = path
    }

    // MARK: - Automatic detection

    func locateContainer() -> String? {
        let containersURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers")

        guard let containerDirs = try? FileManager.default.contentsOfDirectory(
            at: containersURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: .skipsHiddenFiles
        ) else {
            return nil
        }

        var candidates: [(url: URL, modified: Date)] = []

        for dir in containerDirs {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                continue
            }

            let metadataPlist = dir.appendingPathComponent(".com.apple.containermanagerd.metadata.plist")
            guard FileManager.default.fileExists(atPath: metadataPlist.path) else {
                continue
            }

            if metadataContainsFortnite(at: metadataPlist) {
                let modDate = (try? dir.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                candidates.append((dir, modDate))
            }
        }

        return candidates.sorted { $0.modified > $1.modified }.first?.url.path
    }

    private func metadataContainsFortnite(at url: URL) -> Bool {
        guard let dict = NSDictionary(contentsOf: url) as? [String: Any] else {
            return false
        }
        return dictContainsFortnite(dict)
    }

    private func dictContainsFortnite(_ dict: [String: Any]) -> Bool {
        for (_, value) in dict {
            if let str = value as? String,
               str.localizedCaseInsensitiveContains("FortniteGame") {
                return true
            }
            if let arr = value as? [Any],
               arrayContainsFortnite(arr) {
                return true
            }
            if let inner = value as? [String: Any],
               dictContainsFortnite(inner) {
                return true
            }
        }
        return false
    }

    private func arrayContainsFortnite(_ arr: [Any]) -> Bool {
        for value in arr {
            if let str = value as? String,
               str.localizedCaseInsensitiveContains("FortniteGame") {
                return true
            }
            if let dict = value as? [String: Any],
               dictContainsFortnite(dict) {
                return true
            }
            if let innerArr = value as? [Any],
               arrayContainsFortnite(innerArr) {
                return true
            }
        }
        return false
    }

    // MARK: - File picker for manual selection
    func pickContainerManually(completion: @escaping (String?) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Select Fortnite Container Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        panel.begin { response in
            if response == .OK, let url = panel.url {
                completion(url.path)
            } else {
                completion(nil)
            }
        }
    }
}
