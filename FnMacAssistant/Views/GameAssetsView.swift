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

                        Text("Game Assets")
                            .font(.largeTitle)
                            .bold()

                        Text("Download Fortnite game assets without launching the game.")
                            .foregroundColor(.secondary)

                        Divider()

                        HStack {
                            Text("Build:")
                            Text(manager.buildVersion ?? "Unknown")
                                .fontWeight(.semibold)
                        }

                        HStack {
                            Text("Manifest ID:")
                            Text(manager.manifestID ?? "Unknown")
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
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

                        Divider()

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
}
