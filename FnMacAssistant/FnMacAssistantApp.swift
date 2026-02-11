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
    private let windowSize = CGSize(width: 900, height: 510)

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(downloadManager)
                .frame(minWidth: windowSize.width, minHeight: windowSize.height)
        }
        .defaultSize(width: windowSize.width, height: windowSize.height)
        .windowResizability(.contentMinSize)
        .commands {
        }
    }
}
