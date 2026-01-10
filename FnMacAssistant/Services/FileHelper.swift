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
