//
//  UpdateAssistantView.swift
//  FnMacAssistant
//
//  Created by Isacucho on 12/02/26.
//

import SwiftUI

struct UpdateAssistantView: View {
    @ObservedObject private var manager = UpdateAssistantManager.shared

    @State private var consoleUserScrolledAway = false
    @State private var consoleViewportHeight: CGFloat = 0
    @State private var showStartPrompt = false
    @State private var dontShowStartPrompt = false
    @AppStorage("updateAssistantSuppressStartPrompt") private var suppressStartPrompt = false
    @State private var showHowItWorks = false

    private let bottomSpacerID = "UPDATE_BOTTOM_SPACER"

    private var showsProgressBar: Bool {
        manager.isDownloading || manager.isDone
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerSection
                        quickActionsCard

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .center, spacing: 12) {
                                if manager.isRunning {
                                    Button("Stop") {
                                        if manager.isDownloading {
                                            manager.requestCancelDownload()
                                        } else {
                                            manager.stop()
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                } else {
                                    Button("Start Update") {
                                        if suppressStartPrompt {
                                            manager.start()
                                        } else {
                                            dontShowStartPrompt = false
                                            showStartPrompt = true
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.large)
                                    .font(.system(size: 20, weight: .semibold))
                                }

                                Spacer()

                                Toggle("Show console logs", isOn: $manager.showConsole)
                            }

                            if manager.showConsole {
                                consoleView
                            }
                        }

                        if showsProgressBar {
                            Spacer()
                                .frame(height: progressBarHeight + 24)
                                .id(bottomSpacerID)
                        }
                    }
                    .padding(24)
                }

                if showsProgressBar {
                    progressBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onChange(of: showsProgressBar) { _, showing in
                guard showing else { return }
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.35)) {
                        proxy.scrollTo(bottomSpacerID, anchor: .bottom)
                    }
                }
            }
        }
        .sheet(isPresented: $showStartPrompt) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Start Update?")
                    .font(.title2)
                    .bold()

                Text("""
This will open Fortnite and begin the download assistant.

If you are updating the base game, do not touch anything while the process runs.
If you are installing a game mode, open your desired game mode and click Download. The assistant will continue automatically.
When the download is finished, you will see a Download button with no update size in Fortnite. Click it to complete installation.
""")
                .font(.system(size: 13))
                .foregroundColor(.secondary)

                Toggle("Do not show again", isOn: $dontShowStartPrompt)
                    .toggleStyle(.checkbox)

                HStack {
                    Spacer()
                    Button("Cancel") {
                        showStartPrompt = false
                    }
                    Button("Start") {
                        suppressStartPrompt = dontShowStartPrompt
                        manager.start()
                        showStartPrompt = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 420)
        }
    }

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 42, height: 42)
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Update Assistant")
                    .font(.largeTitle)
                    .bold()
                Text("Created by Altermine")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                showHowItWorks = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                showHowItWorks = hovering
            }
            .popover(isPresented: $showHowItWorks, arrowEdge: .top) {
                howItWorksPopover
                    .frame(width: 320)
                    .padding(12)
            }
        }
    }

    private var quickActionsCard: some View {
        glassSection {
            VStack(alignment: .leading, spacing: 12) {
                Text("Overview")
                    .font(.headline)

                Text("This assistant watches Fortnite’s download log, captures requested chunks, and downloads them directly into your game data folder.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    Text("What to do")
                        .font(.subheadline.weight(.semibold))
                    Text("Base game update: click Start Update and do not touch anything until the assistant finishes.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Game mode install: click Start Update, go to your desired game mode in Fortnite, then click Download. The rest proceeds automatically. When done, you will see a Download button with no download size insde Fortnite. Click it to complete installation.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if manager.isRunning {
                    Text("Fortnite will open automatically.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func stepRow(index: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(index)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 22, height: 22)
                .foregroundColor(.accentColor)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))

            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var howItWorksPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How it works")
                .font(.headline)

            stepRow(index: "1", text: "Click Start Update.")
            stepRow(index: "2", text: "Base game update: do not touch anything while it runs.")
            stepRow(index: "3", text: "Game mode install: open your desired game mode and click Download. When finished, click the Download button with no download size inside Fortnite to complete installation.")

            Divider()
        }
        .padding(4)
    }

    // MARK: - Console View

    private var consoleView: some View {
        GeometryReader { viewportProxy in
            let height = viewportProxy.size.height
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(manager.logOutput)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .textSelection(.enabled)
                            .padding(8)

                        GeometryReader { bottomProxy in
                            Color.clear
                                .preference(
                                    key: UpdateConsoleBottomOffsetKey.self,
                                    value: bottomProxy.frame(in: .named("updateConsoleScroll")).maxY
                                )
                        }
                        .frame(height: 1)
                        .id("consoleBottom")
                    }
                }
                .coordinateSpace(name: "updateConsoleScroll")
                .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3))
                )
                .onChange(of: manager.logOutput) {
                    if !consoleUserScrolledAway {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("consoleBottom", anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    consoleViewportHeight = height
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("consoleBottom", anchor: .bottom)
                    }
                }
                .onPreferenceChange(UpdateConsoleBottomOffsetKey.self) { bottomY in
                    consoleViewportHeight = height
                    let atBottom = bottomY <= height + 8
                    consoleUserScrolledAway = !atBottom
                }
            }
        }
        .frame(minHeight: 160, maxHeight: 220)
    }

    // MARK: - Sticky Progress Bar

    private var progressBar: some View {
        VStack(spacing: 8) {
            ProgressView(value: manager.downloadProgress)
                .progressViewStyle(.linear)

            HStack {
                if manager.isDownloading {
                    Text("Downloading (\(manager.downloadProgressLabel))")
                } else if manager.isDone {
                    Text("Done")
                }

                Spacer()

                    if manager.isDownloading {
                        HStack(spacing: 8) {
                            Text(manager.downloadPercentageLabel)

                            if manager.isPaused {
                                Button("Resume") {
                                    manager.resume()
                                }
                                .buttonStyle(.bordered)
                            } else {
                                Button("Pause") {
                                    manager.pause()
                                }
                                .buttonStyle(.bordered)
                            }

                            Button("Cancel") {
                                manager.requestCancelDownload()
                            }
                            .buttonStyle(.bordered)
                        }
                    } else if manager.isDone {
                    HStack(spacing: 8) {
                        Button {
                            openFortnite()
                        } label: {
                            Label("Open Fortnite", systemImage: "gamecontroller.fill")
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive) {
                            manager.stop()
                        } label: {
                            Label("Close", systemImage: "xmark.circle.fill")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.1))
        )
        .padding()
        .shadow(radius: 8)
    }

    private var progressBarHeight: CGFloat {
        80
    }

    private func openFortnite() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["/Applications/Fortnite.app"]
        try? process.run()
    }

    // MARK: - Glass Section

    private func glassSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(.ultraThickMaterial, for: .window)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.1))
            )
    }
}

private struct UpdateConsoleBottomOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
