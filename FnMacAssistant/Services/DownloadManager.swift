//
//  DownloadManager.swift
//  FnMacAssistant
//
//  Created by Isacucho on 06/11/25.
//

import Foundation
import Combine
import SwiftUI

final class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    @Published private(set) var downloads: [DownloadItem] = []
    @Published var defaultDownloadFolder: URL? = nil

    @AppStorage("defaultDownloadFolderPath") var defaultDownloadFolderPath: String?

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private var taskToItem: [Int: DownloadItem] = [:]

    override init() {
        super.init()
        restoreSavedFolder()
    }

    // MARK: - Folder persistence
    private func restoreSavedFolder() {
        if let path = defaultDownloadFolderPath {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                defaultDownloadFolder = url
                return
            }
        }
        defaultDownloadFolder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }

    func setDownloadFolder(_ url: URL) {
        defaultDownloadFolder = url
        defaultDownloadFolderPath = url.path
    }

    func resetDownloadFolder() {
        defaultDownloadFolder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        defaultDownloadFolderPath = nil
    }

    // MARK: - Start Download
    func startDownload(from url: URL) {
        guard let folder = defaultDownloadFolder ??
                FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            print("No valid folder available for download")
            return
        }

        let item = DownloadItem(url: url)
        DispatchQueue.main.async {
            self.downloads = [item] // ensure only one active
        }

        var request = URLRequest(url: url)
        request.setValue("FnMacAssistant/2.0 (macOS)", forHTTPHeaderField: "User-Agent")

        let task = session.downloadTask(with: request)
        item.state = .downloading
        item.taskIdentifier = task.taskIdentifier
        item.localFileURL = folder.appendingPathComponent(item.fileName)
        taskToItem[task.taskIdentifier] = item

        DispatchQueue.main.async {
            self.downloads = [item]
        }

        task.resume()
    }

    // MARK: - Pause / Resume / Cancel
    func pause(_ item: DownloadItem) {
        guard item.state == .downloading, let id = item.taskIdentifier else { return }
        session.getAllTasks { tasks in
            guard let task = tasks.first(where: { $0.taskIdentifier == id }) as? URLSessionDownloadTask else { return }
            task.cancel { resumeDataOrNil in
                DispatchQueue.main.async {
                    item.resumeData = resumeDataOrNil
                    item.state = .paused
                    item.taskIdentifier = nil
                    self.objectWillChange.send()
                }
            }
        }
    }

    func resume(_ item: DownloadItem) {
        if let resume = item.resumeData {
            let task = self.session.downloadTask(withResumeData: resume)
            item.state = .downloading
            item.resumeData = nil
            item.taskIdentifier = task.taskIdentifier
            self.taskToItem[task.taskIdentifier] = item
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
            task.resume()
        } else {
            startDownload(from: item.url)
        }
    }

    func pauseOrResume(_ item: DownloadItem) {
        if item.state == .downloading {
            pause(item)
        } else if item.state == .paused {
            resume(item)
        }
    }

    func cancel(_ item: DownloadItem) {
        guard let id = item.taskIdentifier else {
            DispatchQueue.main.async {
                item.state = .cancelled
                self.objectWillChange.send()
            }
            return
        }

        session.getAllTasks { tasks in
            if let task = tasks.first(where: { $0.taskIdentifier == id }) {
                task.cancel()
            }
            DispatchQueue.main.async {
                item.state = .cancelled
                item.taskIdentifier = nil
                self.objectWillChange.send()
            }
        }
    }

    func cancelCurrentDownload() {
        guard let current = downloads.first else { return }
        cancel(current)
    }
    
    func clearDownloads() {
        DispatchQueue.main.async {
            self.downloads.removeAll()
        }
    }
    
    var isDownloading: Bool {
        downloads.contains(where: { $0.state == .downloading })
    }
}

// MARK: - URLSessionDownloadDelegate
extension DownloadManager: URLSessionDownloadDelegate {

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {

        guard let item = taskToItem[downloadTask.taskIdentifier] else { return }

        let targetFolder = self.defaultDownloadFolder ??
            FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!

        let dest = targetFolder.appendingPathComponent(item.fileName)

        do {
            let fm = FileManager.default

            if !fm.fileExists(atPath: targetFolder.path) {
                try fm.createDirectory(at: targetFolder, withIntermediateDirectories: true)
            }

            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }

            try fm.moveItem(at: location, to: dest)

            DispatchQueue.main.async {
                item.localFileURL = dest
                item.state = .finished
                item.progress = 1.0
                item.totalBytesWritten = downloadTask.countOfBytesReceived
                item.totalBytesExpected = downloadTask.countOfBytesExpectedToReceive
                item.taskIdentifier = nil
                self.objectWillChange.send()
                print("✅ Download finished and moved to: \(dest.path)")
            }

        } catch {
            DispatchQueue.main.async {
                item.errorMessage = "Failed to save file: \(error.localizedDescription)"
                item.state = .failed
                item.taskIdentifier = nil
                self.objectWillChange.send()
                print("❌ Error moving file: \(error)")
            }
        }

        taskToItem[downloadTask.taskIdentifier] = nil
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let item = taskToItem[downloadTask.taskIdentifier] else { return }

        DispatchQueue.main.async {
            item.totalBytesWritten = totalBytesWritten
            item.totalBytesExpected = totalBytesExpectedToWrite
            item.progress = totalBytesExpectedToWrite > 0
                ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
                : 0
            self.objectWillChange.send()
        }
    }
}
