//
//  GameAssetsView.swift
//  FnMacAssistant
//
//  Created by Isacucho on 11/01/26.
//

import SwiftUI

struct GameAssetsView: View {
    @ObservedObject private var manager = FortDLManager.shared
    @State private var didAutoScrollToProgress = false
    @State private var showBRCosmeticsWarning = false
    @State private var brCosmeticsWarningMessage = ""
    @State private var pendingWarningMode: BRCosmeticsMode? = nil
    @State private var dontShowBRCosmeticsAgain = false
    @State private var consoleUserScrolledAway = false
    @State private var consoleViewportHeight: CGFloat = 0
    @State private var showTagSelectionWarning = false

    @AppStorage("brCosmeticsWarningDisabled") private var brCosmeticsWarningDisabled = false
    @AppStorage("brCosmeticsWarnedBattleRoyale") private var brCosmeticsWarnedBattleRoyale = false
    @AppStorage("brCosmeticsWarnedRocketRacing") private var brCosmeticsWarnedRocketRacing = false
    @AppStorage("brCosmeticsWarnedCreative") private var brCosmeticsWarnedCreative = false
    @AppStorage("brCosmeticsWarnedFestival") private var brCosmeticsWarnedFestival = false

    private let bottomSpacerID = "BOTTOM_SPACER"
    private var showsProgressBar: Bool {
        manager.isDownloading || manager.isInstalling || manager.isDone
    }
    private let progressBarID = "PROGRESS_BAR"

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {

                // =====================
                // MAIN SCROLL CONTENT
                // =====================
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {

                        headerSection

                        Text("Download Fortnite game assets without launching the game.")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)

                        glassSection {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Build")
                                    Spacer()
                                    Text(manager.buildVersion ?? "Unknown")
                                        .fontWeight(.semibold)
                                }

                                HStack {
                                    Text("Manifest ID")
                                    Text(manager.manifestID ?? "Unknown")
                                        .font(.system(.body, design: .monospaced))
                                        .textSelection(.enabled)

                                    Spacer()

                                    Toggle("Manual", isOn: $manager.useManualManifest)
                                        .onChange(of: manager.useManualManifest) { enabled in
                                            manager.setManualManifestEnabled(enabled)
                                        }
                                    .toggleStyle(.switch)
                                }

                                if manager.useManualManifest {
                                    HStack(spacing: 10) {
                                        Text("Manual Manifest ID")
                                        TextField(
                                            "Enter manifest ID",
                                            text: $manager.manualManifestID
                                        )
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.body, design: .monospaced))
                                        .frame(minWidth: 240)
                                        .onChange(of: manager.manualManifestID) { value in
                                            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                                            if trimmed != value {
                                                manager.manualManifestID = trimmed
                                            }
                                        }
                                        .onSubmit {
                                            manager.refreshManifest()
                                        }

                                        Button("Load") {
                                            manager.refreshManifest()
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }

                                Divider()

                                Toggle(
                                    "Download all assets (\(manager.totalDownloadSize ?? "—"))",
                                    isOn: $manager.downloadAllAssets
                                )
                                .onChange(of: manager.downloadAllAssets) { enabled in
                                    if enabled {
                                        manager.selectedLayers = Set(manager.layers.map(\.name))
                                        manager.selectedAssets = Set(
                                            manager.layers.flatMap { $0.assets.map(\.name) }
                                        )
                                    } else {
                                        manager.selectedLayers.removeAll()
                                        manager.selectedAssets.removeAll()
                                    }
                                }

                        Toggle("Show individual tags", isOn: $manager.showAssets)
                            .onChange(of: manager.showAssets) { show in
                                if !show && hasPartialTagSelection() {
                                    showTagSelectionWarning = true
                                }
                            }
                            }
                        }

                        glassSection {
                            let columnCount = manager.showAssets ? 2 : 4
                            let columns = masonryColumns(
                                layers: manager.layers,
                                columnCount: columnCount
                            )

                            HStack(alignment: .top, spacing: 12) {
                                ForEach(columns.indices, id: \.self) { columnIndex in
                                    VStack(spacing: 12) {
                                        ForEach(columns[columnIndex]) { layer in
                                            LayerCard(layer: layer)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }

                            HStack {
                                Button("Download Selected Assets") {
                                    manager.download()
                                    didAutoScrollToProgress = false
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(
                                    !manager.downloadAllAssets &&
                                    manager.selectedLayers.isEmpty &&
                                    manager.selectedAssets.isEmpty
                                )

                                Spacer()

                                Text("Total download size: \(manager.selectedDownloadSizeLabel)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // MARK: Console Toggle + Output
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Show console", isOn: $manager.showConsole)

                            if manager.showConsole {
                                consoleView
                            }
                        }

                        // MARK: Anchor point for auto-scroll
                        Color.clear
                            .frame(height: 1)
                            .id(progressBarID)

                        // Bottom padding so content never hides behind progress bar
                        if showsProgressBar {
                            Spacer()
                                .frame(height: progressBarHeight + 24)
                                .id(bottomSpacerID)
                        }
                    }
                    .padding()
                }

                // =====================
                // STICKY PROGRESS BAR
                // =====================
                if showsProgressBar {
                    progressBar
                }
            }
            // =====================
            // AUTO-SCROLL ON START
            // =====================
            .onChange(of: showsProgressBar) { showing in
                guard showing else { return }

                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.35)) {
                        proxy.scrollTo(bottomSpacerID, anchor: .bottom)
                    }
                }
            }
        }
        .sheet(isPresented: $showBRCosmeticsWarning, onDismiss: {
            finalizeBRCosmeticsWarning()
        }) {
            VStack(alignment: .leading, spacing: 16) {
                Text("BRCosmetics Required")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(brCosmeticsWarningMessage)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("Don’t show again", isOn: $dontShowBRCosmeticsAgain)

                HStack {
                    Spacer()
                    Button("OK") {
                        showBRCosmeticsWarning = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
            .frame(minWidth: 420)
        }
        .alert("Individual Tags Selected", isPresented: $showTagSelectionWarning) {
            Button("Deselect Tags", role: .destructive) {
                manager.selectedAssets.removeAll()
            }
            Button("Keep Selected", role: .cancel) {}
        } message: {
            Text("You have individual tags selected. Do you want to clear them or keep them selected?")
        }
    }

    // MARK: - Sticky Progress Bar View

    private var progressBar: some View {
        VStack(spacing: 8) {
            ProgressView(value: manager.downloadProgress)
                .progressViewStyle(.linear)

            HStack {
                if manager.isDownloading {
                    Text("Downloading (\(manager.downloadProgressLabel))")
                } else if manager.isInstalling {
                    Text("Installing…")
                } else if manager.isDone {
                    Text("Done")
                }

                Spacer()

                if manager.isDownloading {
                    HStack(spacing: 8) {
                        Text(manager.downloadPercentageLabel)

                        Button {
                            manager.cancelDownload()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Cancel download")
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
                            manager.clearCompletedDownload()
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
                                    key: ConsoleBottomOffsetKey.self,
                                    value: bottomProxy.frame(in: .named("consoleScroll")).maxY
                                )
                        }
                        .frame(height: 1)
                        .id("consoleBottom")
                    }
                }
                .coordinateSpace(name: "consoleScroll")
                .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3))
                )
                .gesture(
                    DragGesture()
                        .onChanged { _ in
                            consoleUserScrolledAway = true
                        }
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
                .onPreferenceChange(ConsoleBottomOffsetKey.self) { bottomY in
                    consoleViewportHeight = height
                    if bottomY <= height + 8 {
                        consoleUserScrolledAway = false
                    }
                }
            }
        }
        .frame(minHeight: 160, maxHeight: 220)
    }

    // MARK: - Masonry layout (unchanged)

    private func masonryColumns(
        layers: [FortDLManager.Layer],
        columnCount: Int
    ) -> [[FortDLManager.Layer]] {

        var columns = Array(repeating: [FortDLManager.Layer](), count: columnCount)
        var heights = Array(repeating: CGFloat(0), count: columnCount)

        for layer in layers {
            let estimatedHeight: CGFloat =
                manager.showAssets
                ? 90 + CGFloat(layer.assets.count) * 22
                : 90

            if let index = heights.enumerated().min(by: { $0.element < $1.element })?.offset {
                columns[index].append(layer)
                heights[index] += estimatedHeight
            }
        }

        return columns
    }

    // MARK: - Layer Card (unchanged)

    @ViewBuilder
    private func LayerCard(layer: FortDLManager.Layer) -> some View {
        let layerSelected = manager.selectedLayers.contains(layer.name)

        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { layerSelected },
                set: { selected in
                    if selected {
                        manager.selectedLayers.insert(layer.name)
                        manager.selectedAssets.formUnion(layer.assets.map(\.name))
                        handleBRCosmeticsWarning(for: layer.name)
                    } else {
                        manager.selectedLayers.remove(layer.name)
                        manager.selectedAssets.subtract(layer.assets.map(\.name))
                    }
                }
            )) {
                VStack(alignment: .leading) {
                    Text(layer.name)
                        .font(manager.showAssets ? .body : .title3)
                        .fontWeight(.semibold)

                    Text(layer.totalSize)
                        .font(manager.showAssets ? .caption : .body)
                        .foregroundColor(.secondary)
                }
            }
            .disabled(manager.downloadAllAssets)

            if manager.showAssets {
                Divider()

                ForEach(layer.assets) { asset in
                    Toggle(isOn: Binding(
                        get: {
                            manager.selectedAssets.contains(asset.name)
                        },
                        set: { selected in
                            if selected {
                                manager.selectedAssets.insert(asset.name)
                            } else {
                                manager.selectedAssets.remove(asset.name)
                            }
                        }
                    )) {
                        HStack {
                            Text(asset.name)
                                .lineLimit(1)

                            Spacer()

                            Text(
                                ByteCountFormatter.string(
                                    fromByteCount: Int64(asset.size),
                                    countStyle: .file
                                )
                            )
                            .foregroundColor(.secondary)
                        }
                    }
                    .font(.caption)
                    .disabled(manager.downloadAllAssets || layerSelected)
                }
            }
        }
        .padding(manager.showAssets ? 16 : 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - BRCosmetics Warning

    private func handleBRCosmeticsWarning(for layerName: String) {
        guard !brCosmeticsWarningDisabled else { return }
        guard let mode = requiredBRCosmeticsMode(for: layerName) else { return }
        guard !isModeAlreadyWarned(mode) else { return }
        guard !isBRCosmeticsSelected() else { return }

        pendingWarningMode = mode
        dontShowBRCosmeticsAgain = false
        brCosmeticsWarningMessage =
        """
        This mode requires BRCosmetics. Please enable the cosmetics layer.

        You only need to install BRCosmetics once per update. If you already installed it with another game mode, you do not need to install it again.
        """
        showBRCosmeticsWarning = true
    }

    private func requiredBRCosmeticsMode(for layerName: String) -> BRCosmeticsMode? {
        let name = layerName.lowercased()
        if name.contains("battle-royale") {
            return .battleRoyale
        }
        if name.contains("rocket-racing") {
            return .rocketRacing
        }
        if name.contains("creative") {
            return .creative
        }
        if name.contains("festival") {
            return .festival
        }
        return nil
    }

    private func isBRCosmeticsSelected() -> Bool {
        if manager.selectedLayers.contains("cosmetics") {
            return true
        }
        return manager.selectedAssets.contains("GFP_BRCosmetics")
    }

    private func finalizeBRCosmeticsWarning() {
        guard let mode = pendingWarningMode else { return }

        if dontShowBRCosmeticsAgain {
            brCosmeticsWarningDisabled = true
        }

        markModeWarned(mode)
        pendingWarningMode = nil
    }

    private func isModeAlreadyWarned(_ mode: BRCosmeticsMode) -> Bool {
        switch mode {
        case .battleRoyale:
            return brCosmeticsWarnedBattleRoyale
        case .rocketRacing:
            return brCosmeticsWarnedRocketRacing
        case .creative:
            return brCosmeticsWarnedCreative
        case .festival:
            return brCosmeticsWarnedFestival
        }
    }

    private func markModeWarned(_ mode: BRCosmeticsMode) {
        switch mode {
        case .battleRoyale:
            brCosmeticsWarnedBattleRoyale = true
        case .rocketRacing:
            brCosmeticsWarnedRocketRacing = true
        case .creative:
            brCosmeticsWarnedCreative = true
        case .festival:
            brCosmeticsWarnedFestival = true
        }
    }

    private func hasPartialTagSelection() -> Bool {
        if manager.selectedAssets.isEmpty { return false }
        for layer in manager.layers {
            let layerAssets = Set(layer.assets.map(\.name))
            if manager.selectedAssets.isSubset(of: layerAssets)
                && manager.selectedLayers.contains(layer.name) {
                continue
            }
            if !layerAssets.isDisjoint(with: manager.selectedAssets) {
                return true
            }
        }
        return false
    }

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 42, height: 42)
                Image(systemName: "shippingbox.fill")
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Game Assets")
                    .font(.largeTitle)
                    .bold()
                Text(manager.isDownloading ? "Downloading…" : "Ready")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func glassSection<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.1))
            )
    }
}

// MARK: - BRCosmetics Warning Modes
private enum BRCosmeticsMode {
    case battleRoyale
    case rocketRacing
    case creative
    case festival
}

private struct ConsoleBottomOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
