//
//  FileHelper.swift
//  FnMacAssistant
//
//  Created by Isacucho on 06/11/25.
//

import Foundation

struct FileHelper {
    static func fnMacAssistantDownloadFolder() -> URL {
        let fm = FileManager.default
        let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let folder = downloads.appendingPathComponent("FnMacAssistant")
        if !fm.fileExists(atPath: folder.path) {
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }
}

enum AppTempDirectory {
    static let settingsKey = "appTempFolderPath"
    private static let legacyUpdateAssistantKey = "updateAssistantTempFolderPath"

    static func rootURL() -> URL {
        let defaults = UserDefaults.standard

        if let customPath = defaults.string(forKey: settingsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !customPath.isEmpty {
            return URL(fileURLWithPath: customPath, isDirectory: true)
        }

        // Backward compatibility: preserve previously configured Update Assistant temp path.
        if let legacyPath = defaults.string(forKey: legacyUpdateAssistantKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !legacyPath.isEmpty {
            return URL(fileURLWithPath: legacyPath, isDirectory: true)
        }

        return FileManager.default.temporaryDirectory
            .appendingPathComponent("FnMacAssistant-cache", isDirectory: true)
    }

    static func subdirectory(_ name: String) -> URL {
        rootURL().appendingPathComponent(name, isDirectory: true)
    }
}
