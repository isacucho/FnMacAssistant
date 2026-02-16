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
        if let cached = cachedPath, !cached.isEmpty {
            return cached
        }

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

        var candidates: [(url: URL, dataSize: UInt64, modified: Date)] = []

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
                let dataSize = fortniteDataSize(in: dir)
                candidates.append((dir, dataSize, modDate))
            }
        }

        return candidates.sorted {
            if $0.dataSize == $1.dataSize {
                return $0.modified > $1.modified
            }
            return $0.dataSize > $1.dataSize
        }.first?.url.path
    }

    private func fortniteDataSize(in containerURL: URL) -> UInt64 {
        let fortniteGamePath = containerURL
            .appendingPathComponent("Data/Documents/FortniteGame", isDirectory: true)

        return directorySize(at: fortniteGamePath)
    }

    private func directorySize(at url: URL) -> UInt64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return 0
        }

        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]),
                  values.isRegularFile == true else {
                continue
            }

            if let allocated = values.totalFileAllocatedSize {
                total += UInt64(allocated)
            } else if let fileSize = values.fileSize {
                total += UInt64(fileSize)
            }
        }

        return total
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
