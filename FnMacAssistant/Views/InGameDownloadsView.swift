//
//  InGameDownloadsView.swift
//  FnMacAssistant
//
//  Created by Isacucho on 13/11/25.
//

import SwiftUI

struct InGameDownloadsView: View {
    @StateObject private var tracker = InGameDownloadTracker.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                Text("In-Game Downloads")
                    .font(.largeTitle).bold()

                Text("""
Fortnite sometimes downloads game assets or game modes in the background. \
This tool monitors those internal downloads and helps you restart Fortnite at the right moment.
""")
                .font(.system(size: 15))
                .foregroundColor(.secondary)

                // Bubble 1 – REAL FILE DOWNLOADS
                InGameDownloadRowView(
                    title: "Download Game Files",
                    description: tracker.fileStatusMessage,
                    progress: tracker.filesProgress,
                    isActive: tracker.isDownloadingFiles,
                    resetAction: { tracker.resetDownload() },
                    startAction: { tracker.startGameFilesDownload() },
                    cancelAction: { tracker.requestCancelDownload() }
                    
                )
                .frame(maxWidth: .infinity)

                // Bubble 2 – placeholder (future)
                InGameDownloadRowView(
                    title: "Download Game Mode",
                    description: "Coming soon: tracking per-mode downloads (BR, ZB, STW…).",
                    progress: tracker.modeProgress,
                    isActive: tracker.isDownloadingMode,
                    resetAction: {},
                    startAction: { tracker.startGameModeDownload() },
                    cancelAction: { tracker.requestCancelDownload() }
                    
                )
                .frame(maxWidth: .infinity)

                Spacer()
            }
            .padding()
        }
    }
}
