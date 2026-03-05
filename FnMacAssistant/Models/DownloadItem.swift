//
//  DownloadItem.swift
//  FnMacAssistant
//
//  Created by Isacucho on 06/11/25.
//

import Foundation
import Combine

enum DownloadState: String, Codable {
    case idle
    case downloading
    case paused
    case finished
    case failed
    case cancelled
}

final class DownloadItem: ObservableObject, Identifiable {
    let id = UUID()
    let url: URL
    @Published var progress: Double = 0.0        
    @Published var state: DownloadState = .idle
    @Published var totalBytesWritten: Int64 = 0
    @Published var totalBytesExpected: Int64 = NSURLSessionTransferSizeUnknown
    @Published var localFileURL: URL? = nil
    @Published var errorMessage: String? = nil
    @Published var isPaused: Bool = false

    // Internal resume data for pause/resume
    var resumeData: Data? = nil
    var taskIdentifier: Int? = nil

    init(url: URL) {
        self.url = url
    }

    var fileName: String {
        url.lastPathComponent.isEmpty ? "download-\(id).bin" : url.lastPathComponent
    }
}
