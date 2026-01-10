//
//  FnMacAssistantApp.swift
//  FnMacAssistant
//
//  Created by Isacucho on 06/11/25.
//

import SwiftUI

@main
struct FnMacAssistantApp: App {
    @StateObject private var downloadManager = DownloadManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(downloadManager)
                .frame(minWidth: 700, minHeight: 420)
        }
        .commands {
            // Optional: menu commands (future)
        }
    }
}
