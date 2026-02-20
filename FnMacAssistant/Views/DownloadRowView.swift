//
//  DownloadRowView.swift
//  FnMacAssistant
//
//  Created by Isacucho on 06/11/25.
//

import SwiftUI

struct DownloadRowView: View {
    @ObservedObject var item: DownloadItem
    var manager: DownloadManager

    var body: some View {
        HStack {
            // File info and progress
            VStack(alignment: .leading, spacing: 4) {
                Text(item.fileName)
                    .font(.headline)
                    .lineLimit(1)

                ProgressView(value: item.progress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 200)

                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            // Action buttons
            HStack(spacing: 12) {
                switch item.state {
                case .downloading:
                    Button {
                        manager.pauseOrResume(item)
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                    }
                    .buttonStyle(.borderless)

                case .paused:
                    Button {
                        manager.pauseOrResume(item)
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderless)

                case .failed:
                    Button {
                        manager.startDownload(from: item.url)
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)

                case .finished:
                    if let path = item.localFileURL {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([path])
                        } label: {
                            Label("Show in Finder", systemImage: "magnifyingglass")
                        }
                        .buttonStyle(.borderless)
                    }

                default:
                    EmptyView()
                }

                // Cancel button
                if item.state == .downloading || item.state == .paused {
                    Button(role: .destructive) {
                        manager.cancelCurrentDownload()
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Status text 
private extension DownloadRowView {
    var statusText: String {
        switch item.state {
        case .downloading:
            let receivedMB = Double(item.totalBytesWritten) / 1_000_000
            let totalMB = Double(item.totalBytesExpected) / 1_000_000
            return String(format: "Downloading: %.1f / %.1f MB", receivedMB, totalMB)

        case .paused:
            return "Paused"

        case .finished:
            if let path = item.localFileURL {
                return "Saved to: \(path.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))"
            } else {
                return "Completed"
            }

        case .failed:
            return "Failed – \(item.errorMessage ?? "")"

        case .cancelled:
            return "Cancelled"

        default:
            return "Waiting"
        }
    }
}
