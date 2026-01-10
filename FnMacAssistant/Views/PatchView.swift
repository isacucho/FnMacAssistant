//
//  PatchView.swift
//  FnMacAssistant
//
//  Created by Isacucho on 10/11/25.
//

import SwiftUI

struct PatchView: View {
    @StateObject private var patchManager = PatchManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {

            // MARK: - Title
            Text("Fortnite Mac Patcher")
                .font(.largeTitle)
                .bold()

            // MARK: - Description
            Text("""
To run Fortnite on macOS, the game requires special entitlements.
This patch adds those entitlements to the embedded.mobileprovision file,
allowing Fortnite to launch correctly.

The patch will open Fortnite automatically. Once it crashes,
the patch will be applied.
""")
            .font(.system(size: 15))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            // MARK: - Patch + Open Fortnite Buttons
            HStack(spacing: 12) {

                // PATCH BUTTON
                Button {
                    patchManager.startPatch()
                } label: {
                    ZStack {
                        Text("Apply Patch")
                            .font(.system(size: 15, weight: .semibold))
                            .opacity(0)

                        if patchManager.isPatching {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else if patchManager.patchCompleted {
                            Text("Patch Applied")
                                .font(.system(size: 15, weight: .semibold))
                        } else {
                            Text("Apply Patch")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .padding(.vertical, 8)
                    .frame(width: 140)
                }
                .buttonStyle(.borderedProminent)
                .disabled(patchManager.isPatching)

                if patchManager.patchCompleted {
                    Button {
                        launchFortniteViaShell()
                    } label: {
                        Text("Open Fortnite")
                            .font(.system(size: 15, weight: .semibold))
                            .padding(.vertical, 8)
                            .frame(width: 140)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.top, 4)

            // MARK: - Console Log
            VStack(alignment: .leading, spacing: 6) {
                Text("Console Output")
                    .font(.headline)

                ScrollViewReader { proxy in
                    ScrollView {
                        Text(patchManager.logMessages.joined(separator: "\n"))
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(8)
                            .textSelection(.enabled)   // ← allows full multiline selection
                            .id("consoleText")

                        Color.clear
                            .frame(height: 1)
                            .id("consoleBottom")
                    }
                    .onChange(of: patchManager.logMessages.count) {
                        withAnimation {
                            proxy.scrollTo("consoleBottom", anchor: .bottom)
                        }
                    }
                    .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.3))
                    )
                    .frame(minHeight: 180, maxHeight: 220)
                }
            }

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - helpers

private func launchFortniteViaShell() {
    DispatchQueue.global(qos: .userInitiated).async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["/Applications/Fortnite.app"]

        do { try process.run() } catch { }
    }
}
