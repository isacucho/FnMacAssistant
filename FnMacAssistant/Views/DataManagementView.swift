//
//  DataManagementView.swift
//  FnMacAssistant
//
//  Created by Isacucho on 02/21/26.
//


import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DataManagementView: View {
    @StateObject private var manager = DataManagementManager.shared

    @State private var showDeleteSelectionAlert = false
    @State private var showDeleteGameDataAlert = false
    @State private var showOperationErrorAlert = false
    @State private var operationErrorMessage = ""
    @State private var showIndividualBundles = false
    @State private var expandedSubsections: Set<DataManagementSubsection> = []
    @State private var showFortniteAccessChecklist = false
    @State private var didConfirmFortniteAccess = false
    @State private var pendingMoveTargetURL: URL?
    @State private var showArchiveCreatedAlert = false
    @State private var archiveCreatedMessage = ""
    @State private var showDeleteImportedArchiveAlert = false
    @State private var importedSourceURLToDelete: URL?
    @State private var importedSourceIsDirectory = false
    @State private var showMoveProgressPopup = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection

                if let path = manager.currentContainerPath {
                    Text("Container: \(path)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                } else {
                    Text("Fortnite container not set. Choose it in Settings first.")
                        .font(.system(size: 13))
                        .foregroundColor(.orange)
                }

                subsectionAccordion

                if !manager.statusMessage.isEmpty {
                    Text(manager.statusMessage)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            manager.refreshAll()
        }
        .onChange(of: manager.isMovingData) { _, _ in
            syncMoveProgressPopupVisibility()
        }
        .onChange(of: manager.movingToExternalDrive) { _, _ in
            syncMoveProgressPopupVisibility()
        }
        .alert("Delete Selected Items?", isPresented: $showDeleteSelectionAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                performDeleteSelected()
            }
        } message: {
            Text("This will permanently delete \(manager.selectedCount) selected item(s).")
        }
        .alert("Delete Fortnite App and Data?", isPresented: $showDeleteGameDataAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                performDeleteGameAndData()
            }
        } message: {
            Text("This will permanently delete /Applications/Fortnite.app and the selected Fortnite container.")
        }
        .alert("Operation Failed", isPresented: $showOperationErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(operationErrorMessage)
        }
        .alert("Archive Created", isPresented: $showArchiveCreatedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(archiveCreatedMessage)
        }
        .alert("Import Completed", isPresented: $showDeleteImportedArchiveAlert) {
            Button("Keep", role: .cancel) {
                importedSourceURLToDelete = nil
                importedSourceIsDirectory = false
            }
            Button("Delete", role: .destructive) {
                deleteImportedSourceIfNeeded()
            }
        } message: {
            if let url = importedSourceURLToDelete {
                Text("Would you like to delete the archive?\n\(url.path)")
            } else {
                Text("Would you like to delete the archive?")
            }
        }
        .sheet(isPresented: $showFortniteAccessChecklist) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Grant Fortnite Access First")
                    .font(.title3.weight(.semibold))

                Text("""
Before moving data, do this in Fortnite:
1. Open Fortnite.
2. Press 'P'.
3. Go to the tab with the 🔗 icon.
4. Click 'Select Fortnite Data Folder'.
5. Select the target folder you picked.
Then return here and continue.
""")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Toggle("I have given Fortnite access to the target folder", isOn: $didConfirmFortniteAccess)
                    .toggleStyle(.checkbox)

                HStack {
                    Button("Cancel") {
                        showFortniteAccessChecklist = false
                        pendingMoveTargetURL = nil
                        didConfirmFortniteAccess = false
                    }

                    Spacer()

                    Button("Continue") {
                        guard let target = pendingMoveTargetURL else { return }
                        showFortniteAccessChecklist = false
                        didConfirmFortniteAccess = false
                        pendingMoveTargetURL = nil
                        Task { await performMove(to: target) }
                    }
                    .prominentActionButton()
                    .disabled(!didConfirmFortniteAccess)
                }
            }
            .padding(20)
            .frame(width: 480)
        }
        .sheet(isPresented: $showMoveProgressPopup) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Transferring Files to External Drive")
                    .font(.title3.weight(.semibold))

                ProgressView(value: min(1, max(0, manager.moveProgress)))
                    .progressViewStyle(.linear)

                HStack {
                    Text(manager.isCancellingMove ? "Cancelling" : (manager.moveProgressLabel.isEmpty ? "Starting transfer..." : manager.moveProgressLabel))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int((manager.moveProgress * 100).rounded()))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text("Current file")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                Text(manager.isCancellingMove ? "Cancelling..." : (manager.moveCurrentFilePath.isEmpty ? "Preparing..." : manager.moveCurrentFilePath))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)

                HStack {
                    Spacer()
                    Button(manager.isCancellingMove ? "Cancelling..." : "Cancel Transfer", role: .destructive) {
                        manager.requestCancelMove()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!manager.isMovingData || manager.isCancellingMove)
                }
            }
            .padding(20)
            .frame(width: 560)
            .interactiveDismissDisabled(manager.isMovingData)
        }
    }

    private var subsectionAccordion: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(DataManagementSubsection.allCases) { subsection in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(subsection.title)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: expandedSubsections.contains(subsection) ? "chevron.down" : "chevron.right")
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toggleSubsection(subsection)
                    }

                    if expandedSubsections.contains(subsection) {
                        Divider()
                        subsectionContent(for: subsection)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.1))
                )
                .contentShape(RoundedRectangle(cornerRadius: 14))
                .onTapGesture {
                    guard !expandedSubsections.contains(subsection) else { return }
                    toggleSubsection(subsection)
                }
            }
        }
    }

    @ViewBuilder
    private func subsectionContent(for subsection: DataManagementSubsection) -> some View {
        switch subsection {
        case .gamemodeCleanup:
            deleteBundlesContent
        case .dataLocation:
            dataLocationContent
        case .deleteGameData:
            deleteEverythingContent
        }
    }

    private var deleteBundlesContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Manage Installed Bundles")
                .font(.headline)

            if manager.categories.isEmpty && manager.customMaps.isEmpty {
                Text("No installed bundles found in InstalledBundles or GameCustom/InstalledBundles.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Toggle("Show individual bundles", isOn: $showIndividualBundles)

            if showIndividualBundles {
                let columns = categoryMasonryColumns(categories: manager.categories, columnCount: 2)

                HStack(alignment: .top, spacing: 10) {
                    ForEach(columns.indices, id: \.self) { columnIndex in
                        VStack(spacing: 10) {
                            ForEach(columns[columnIndex]) { category in
                                categoryCard(category: category, showItems: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            } else {
                let columns = [GridItem(.adaptive(minimum: 220), spacing: 10, alignment: .top)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ForEach(manager.categories) { category in
                        categoryCard(category: category, showItems: false)
                    }
                }
            }

            if !manager.customMaps.isEmpty {
                Divider()

                Text("UEFN / Additional Maps")
                    .font(.subheadline.weight(.semibold))

                ForEach(manager.customMaps) { map in
                    Toggle(isOn: Binding(
                        get: { manager.selectedCustomMapPaths.contains(map.path) },
                        set: { selected in
                            if selected {
                                manager.selectedCustomMapPaths.insert(map.path)
                            } else {
                                manager.selectedCustomMapPaths.remove(map.path)
                            }
                        }
                    )) {
                        HStack {
                            Text(map.name)
                                .font(.system(size: 12))
                            Spacer()
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }

            HStack(spacing: 10) {
                Button("Refresh") {
                    manager.refreshAll()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(role: .destructive) {
                    showDeleteSelectionAlert = true
                } label: {
                    Text("Delete Selected")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(!manager.hasSelection)
            }

            Divider()

            HStack(spacing: 10) {
                Button("Import Archive") {
                    importArchive()
                }
                .buttonStyle(.bordered)
                .disabled(manager.isArchiveOperationInProgress)

                Button("Create Archive of Selected") {
                    createArchiveOfSelected()
                }
                .buttonStyle(.bordered)
                .disabled(!manager.hasSelection || manager.isArchiveOperationInProgress)

                Spacer()
            }

            if manager.isArchiveOperationInProgress {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: min(1, max(0, manager.archiveProgress)))
                        .progressViewStyle(.linear)

                    HStack {
                        Text(manager.archiveProgressLabel.isEmpty ? "Working with archive..." : manager.archiveProgressLabel)
                        Spacer()
                        Text(manager.archivePercentageLabel)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
        }
    }

    private var dataLocationContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Change Game Files Location")
                .font(.headline)

            Text("Current path: \(manager.currentFortniteGamePath.isEmpty ? "Not available" : manager.currentFortniteGamePath)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .textSelection(.enabled)

            if let redirectedStatusText {
                Text(redirectedStatusText)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Text("Important: You must have the tweak installed so Fortnite can access your custom game-data location.")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.orange)

            Text("Before moving files: open Fortnite, press 'P', navigate to the tab labed 🔗, click on the 'Select Fortnite data Folder' button, select the same folder, then return here.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Select Folder and Move") {
                    selectCustomDataFolderAndMove()
                }
                .prominentActionButton()
                .disabled(manager.currentContainerPath == nil || manager.isMovingData)

                Button("Reset to Container") {
                    resetDataLocation()
                }
                .buttonStyle(.bordered)
                .disabled(manager.currentContainerPath == nil || manager.isMovingData)

                Spacer()
            }

        }
    }

    private var deleteEverythingContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Delete Game and Data")
                .font(.headline)

            Text("Deletes /Applications/Fortnite.app and your selected Fortnite container.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Button(role: .destructive) {
                showDeleteGameDataAlert = true
            } label: {
                Text("Delete Fortnite and all data")
                    .foregroundColor(.red)
            }
            .buttonStyle(.bordered)
            .disabled(manager.currentContainerPath == nil)
        }
    }

    private var redirectedStatusText: String? {
        guard manager.isUsingSymlink, !manager.currentFortniteGamePath.isEmpty else { return nil }
        let targetURL = URL(fileURLWithPath: manager.currentFortniteGamePath, isDirectory: true)
        if manager.isExternalVolume(targetURL) {
            return "External drive selected. Make sure the drive is plugged in and detected by MacOS before continuing."
        }
        return "Custom path selected"
    }

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 42, height: 42)
                Image(systemName: "externaldrive.fill.badge.minus")
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Data Management")
                    .font(.largeTitle)
                    .bold()
                Text("Manage installed bundles and storage path")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }

    private func selectCustomDataFolderAndMove() {
        let panel = NSOpenPanel()
        panel.title = "Select Target Folder"
        panel.message = "Choose an empty folder (or one containing only FortniteGame)."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            pendingMoveTargetURL = url
            didConfirmFortniteAccess = false
            showFortniteAccessChecklist = true
        }
    }

    private func performMove(to url: URL) async {
        do {
            try await manager.moveFortniteGame(to: url)
        } catch {
            present(error)
        }
    }

    private func performDeleteSelected() {
        do {
            try manager.deleteSelected()
        } catch {
            present(error)
        }
    }

    private func resetDataLocation() {
        do {
            try manager.resetDataLocationToContainer()
        } catch {
            present(error)
        }
    }

    private func performDeleteGameAndData() {
        do {
            try manager.deleteGameAndData()
        } catch {
            present(error)
        }
    }

    private func createArchiveOfSelected() {
        guard manager.currentContainerPath != nil else {
            present(DataManagementError.containerNotFound)
            return
        }

        let panel = NSSavePanel()
        panel.title = "Save Bundle Archive"
        panel.message = "Creates a sanitized archive from PersistentDownloadDir."
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.nameFieldStringValue = manager.defaultArchiveFilename()
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return
        }

        Task {
            do {
                try await manager.createSelectedBundlesArchive(destinationURL: destinationURL)
                archiveCreatedMessage = destinationURL.path
                showArchiveCreatedAlert = true
            } catch {
                present(error)
            }
        }
    }

    private func importArchive() {
        guard manager.currentContainerPath != nil else {
            present(DataManagementError.containerNotFound)
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Select Archive to Import"
        panel.message = "Select a ZIP archive or a folder named PersistentDownloadDir."
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.zip, .folder]
        panel.prompt = "Import"

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }

        Task {
            do {
                let values = try selectedURL.resourceValues(forKeys: [.isDirectoryKey])
                if values.isDirectory == true {
                    try await manager.importPersistentDownloadDirFolder(from: selectedURL)
                    importedSourceURLToDelete = selectedURL
                    importedSourceIsDirectory = true
                    showDeleteImportedArchiveAlert = true
                } else {
                    try await manager.importArchive(from: selectedURL)
                    importedSourceURLToDelete = selectedURL
                    importedSourceIsDirectory = false
                    showDeleteImportedArchiveAlert = true
                }
            } catch {
                present(error)
            }
        }
    }

    private func deleteImportedSourceIfNeeded() {
        guard let sourceURL = importedSourceURLToDelete else { return }
        do {
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                try FileManager.default.removeItem(at: sourceURL)
                let noun = importedSourceIsDirectory ? "Folder" : "Archive"
                manager.statusMessage = "\(noun) imported and deleted: \(sourceURL.path)"
            }
            importedSourceURLToDelete = nil
            importedSourceIsDirectory = false
        } catch {
            importedSourceURLToDelete = nil
            importedSourceIsDirectory = false
            present(error)
        }
    }

    private func present(_ error: Error) {
        operationErrorMessage = error.localizedDescription
        showOperationErrorAlert = true
    }

    private func toggleSubsection(_ subsection: DataManagementSubsection) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedSubsections.contains(subsection) {
                expandedSubsections.remove(subsection)
            } else {
                expandedSubsections.insert(subsection)
            }
        }
    }

    private func syncMoveProgressPopupVisibility() {
        let shouldShow = manager.isMovingData && manager.movingToExternalDrive
        if shouldShow != showMoveProgressPopup {
            showMoveProgressPopup = shouldShow
        }
    }

    @ViewBuilder
    private func categoryCard(category: DataManagementManager.BundleCategory, showItems: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { manager.isEntireCategorySelected(category) },
                set: { selected in manager.setCategory(category, selected: selected) }
            )) {
                HStack {
                    Text(category.title)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: Int64(category.totalSizeBytes), countStyle: .file))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.checkbox)

            if showItems {
                Divider()

                ForEach(category.items) { item in
                    Toggle(isOn: Binding(
                        get: { manager.selectedBundlePaths.contains(item.path) },
                        set: { selected in
                            if selected {
                                manager.selectedBundlePaths.insert(item.path)
                            } else {
                                manager.selectedBundlePaths.remove(item.path)
                            }
                        }
                    )) {
                        HStack {
                            Text(item.name)
                                .font(.system(size: 12, design: .monospaced))
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: Int64(item.sizeBytes), countStyle: .file))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func categoryMasonryColumns(
        categories: [DataManagementManager.BundleCategory],
        columnCount: Int
    ) -> [[DataManagementManager.BundleCategory]] {
        var columns = Array(repeating: [DataManagementManager.BundleCategory](), count: columnCount)
        var heights = Array(repeating: CGFloat(0), count: columnCount)

        for category in categories {
            let estimatedHeight = 74 + CGFloat(category.items.count) * 24
            if let index = heights.enumerated().min(by: { $0.element < $1.element })?.offset {
                columns[index].append(category)
                heights[index] += estimatedHeight
            }
        }

        return columns
    }
}

private enum DataManagementSubsection: String, CaseIterable, Identifiable {
    case gamemodeCleanup
    case dataLocation
    case deleteGameData

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gamemodeCleanup:
            return "Data Manager"
        case .dataLocation:
            return "Data Location"
        case .deleteGameData:
            return "Delete Fortnite"
        }
    }
}
