//
//  ContentView.swift
//  FnMacAssistant
//
//  Created by Isacucho on 06/11/25.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var selection: SidebarSection = .home
    @AppStorage("startupSidebarSection") private var startupSidebarSectionRaw = SidebarSection.home.rawValue
    @State private var isSidebarVisible: Bool = true
    @ObservedObject private var sparkleUpdater = SparkleUpdaterService.shared
    @ObservedObject private var dataManager = DataManagementManager.shared
    @ObservedObject private var patchManager = PatchManager.shared
    @ObservedObject private var containerLocator = FortniteContainerLocator.shared
    @ObservedObject private var ipaFetcher = IPAFetcher.shared
    @AppStorage("suppressPrereleasePopupVersion") private var suppressPrereleasePopupVersion = ""
    @State private var startupSheet: StartupSheet?
    @State private var didPresentUnsupportedMacOSSheet = false
    @State private var showExternalDriveWarning = false
    @State private var showDataPathResetPrompt = false
    @State private var startupIssuePath = ""
    @State private var showStartupOperationError = false
    @State private var startupOperationErrorMessage = ""
    @State private var acknowledgedExternalDisconnectPath: String?
    @State private var showStartupFullDiskAlert = false
    @State private var showStartupDuplicateContainersSheet = false
    @State private var startupSelectedContainer: FortniteContainerLocator.ContainerCandidate?
    @State private var startupExtraContainers: [FortniteContainerLocator.ContainerCandidate] = []
    @State private var startupSelectedExtraContainerPaths: Set<String> = []
    @State private var startupContainerWasVerified = false
    @State private var showStartupPatchFortniteAlert = false
    @State private var showStartupAmbiguousContainerSheet = false
    @State private var startupAmbiguousCandidates: [FortniteContainerLocator.ContainerCandidate] = []
    @State private var startupSuggestedContainer: FortniteContainerLocator.ContainerCandidate?
    @State private var startupAmbiguousAllTiny = false
    @State private var startupContainerActionInProgress = false
    @State private var startupContainerActionMessage = ""
    @State private var startupContainerDeleteErrorMessage: String?
    @State private var pendingContainerWorkflow: PendingContainerWorkflow?

    private enum PendingContainerWorkflow: String {
        case updateAssistantStart
        case gameAssetsDownload
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    colorScheme == .dark
                    ? Color.black.opacity(0.16)
                    : Color.white.opacity(0.42),
                    colorScheme == .dark
                    ? Color.black.opacity(0.06)
                    : Color.white.opacity(0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blur(radius: 12)

            HStack(spacing: 0) {
                if isSidebarVisible {
                    SidebarView(selection: $selection)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                        .zIndex(1)
                }

                Divider()

                ZStack {
                    switch selection {
                    case .home:
                        HomeView(selection: $selection)
                    case .downloads:
                        DownloadsView(downloadManager: DownloadManager.shared)
                    case .patch:
                        PatchView()
                    case .gameAssets:
                        GameAssetsView()
                    case .dataManagement:
                        DataManagementView()
                    case .updateAssistant:
                        UpdateAssistantView()
                    case .faq:
                        FAQView()
                    case .settings:
                        SettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .containerBackground(
            colorScheme == .dark ? .ultraThickMaterial : .regularMaterial,
            for: .window
        )
        .sheet(item: $startupSheet) { sheet in
            switch sheet {
            case .prerelease:
                UpdatePromptSheet(
                    title: "Pre-release Build",
                    message: prereleaseMessage,
                    suppressLabel: "Do not show again",
                    suppressValue: prereleaseSuppressBinding,
                    primaryTitle: "Open Discord",
                    primaryAction: openDiscord,
                    secondaryTitle: "Close",
                    onDismiss: { startupSheet = nil }
                )
            case .unsupportedMacOS:
                StartupNoticeSheet(
                    title: ipaFetcher.macOSSupportStatus?.title ?? "Unsupported macOS Version",
                    message: ipaFetcher.macOSSupportStatus?.message ?? "This macOS version is not currently supported.",
                    primaryTitle: "Close",
                    onDismiss: {
                        didPresentUnsupportedMacOSSheet = true
                        startupSheet = nil
                    }
                )
            }
        }
        .alert("External Drive Not Connected", isPresented: $showExternalDriveWarning) {
            Button("Check Again") {
                performStartupDataPathCheck(forceReopenAlert: true)
            }
            Button("Ignore", role: .cancel) {
                acknowledgedExternalDisconnectPath = startupIssuePath
            }
        } message: {
            Text("Connect the external drive where your game data is located, then reopen FnMacAssistant.\n\nExpected path:\n\(startupIssuePath)")
        }
        .alert("Game Data Not Found", isPresented: $showDataPathResetPrompt) {
            Button("Keep Current Path", role: .cancel) {}
            Button("Reset to Container", role: .destructive) {
                Task {
                    do {
                        try await dataManager.resetDataLocationToContainer()
                    } catch {
                        startupOperationErrorMessage = error.localizedDescription
                        showStartupOperationError = true
                    }
                }
            }
        } message: {
            Text("Game data was not found at the selected path:\n\(startupIssuePath)\n\nDo you want to reset the download path to the original container?")
        }
        .alert("Operation Failed", isPresented: $showStartupOperationError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(startupOperationErrorMessage)
        }
        .alert("Full Disk Access Needed", isPresented: $showStartupFullDiskAlert) {
            Button("Open Privacy & Security") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
                    NSWorkspace.shared.open(url)
                } else if let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
                    NSWorkspace.shared.open(fallback)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(FortniteContainerLocator.containerAccessFailureMessage)
        }
        .alert("Patch Fortnite First", isPresented: $showStartupPatchFortniteAlert) {
            Button("Retry Search") {
                Task {
                    await performStartupContainerDetectionIfNeeded(force: true)
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Fortnite containers were found, but none contained enough data to identify the correct one. Patch Fortnite, then retry the container search.")
        }
        .alert("Container Action Failed", isPresented: Binding(
            get: { startupContainerDeleteErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    startupContainerDeleteErrorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(startupContainerDeleteErrorMessage ?? "Container action failed.")
        }
        .sheet(isPresented: $showStartupDuplicateContainersSheet) {
            duplicateContainersSheet
        }
        .sheet(isPresented: $showStartupAmbiguousContainerSheet) {
            ambiguousContainersSheet
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isSidebarVisible.toggle()
                    }
                }) {
                    Image(systemName: "sidebar.left")
                }
                .help(isSidebarVisible ? "Hide Sidebar" : "Show Sidebar")
            }
        }
        .onChange(of: containerLocator.cachedPath) { _, newValue in
            if newValue != nil {
                showStartupDuplicateContainersSheet = false
                showStartupAmbiguousContainerSheet = false
                showStartupPatchFortniteAlert = false
            }
        }
        .onChange(of: patchManager.patchCompleted) { _, completed in
            guard completed, containerLocator.cachedPath == nil else { return }
            Task {
                await performStartupContainerDetectionIfNeeded(force: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: FortniteContainerLocator.requestAutoDetectionNotification)) { notification in
            if let workflowRaw = notification.userInfo?[FortniteContainerLocator.requestAutoDetectionWorkflowKey] as? String,
               let workflow = PendingContainerWorkflow(rawValue: workflowRaw) {
                pendingContainerWorkflow = workflow
            }
            Task {
                await performStartupContainerDetectionIfNeeded(force: true)
            }
        }
        .task {
            if let startupSection = SidebarSection(rawValue: startupSidebarSectionRaw) {
                selection = startupSection
            } else {
                selection = .home
                startupSidebarSectionRaw = SidebarSection.home.rawValue
            }

            await ipaFetcher.fetchAvailableIPAs()
            if sparkleUpdater.isPrereleaseBuild && !isPrereleaseSuppressedForCurrent {
                startupSheet = .prerelease
            }
            queueUnsupportedMacOSSheetIfNeeded()

            await performStartupContainerDetectionIfNeeded()
            performStartupDataPathCheck()
            await monitorExternalDriveDisconnects()
        }
        .onChange(of: startupSheet) { _, newValue in
            if newValue == nil {
                queueUnsupportedMacOSSheetIfNeeded()
            }
        }
    }

    private var prereleaseMessage: String {
        "You're running a pre-release build. You might encounter issues. If you find any, please report them in the testers channel on the Discord."
    }

    private var isPrereleaseSuppressedForCurrent: Bool {
        suppressPrereleasePopupVersion == sparkleUpdater.currentVersion
    }

    private var prereleaseSuppressBinding: Binding<Bool> {
        Binding(
            get: { isPrereleaseSuppressedForCurrent },
            set: { isOn in
                if isOn {
                    suppressPrereleasePopupVersion = sparkleUpdater.currentVersion
                } else {
                    suppressPrereleasePopupVersion = ""
                }
            }
        )
    }

    private func queueUnsupportedMacOSSheetIfNeeded() {
        guard ipaFetcher.macOSSupportStatus != nil else {
            return
        }
        guard !didPresentUnsupportedMacOSSheet else { return }

        if startupSheet == nil {
            startupSheet = .unsupportedMacOS
        }
    }

    private func openDiscord() {
        if let url = URL(string: "https://discord.gg/nfEBGJBfHD") {
            NSWorkspace.shared.open(url)
        }
    }

    private func performStartupDataPathCheck(forceReopenAlert: Bool = false) {
        dataManager.refreshCurrentDataLocation()
        guard let issue = dataManager.detectStartupDataPathIssue() else {
            showExternalDriveWarning = false
            showDataPathResetPrompt = false
            acknowledgedExternalDisconnectPath = nil
            return
        }

        switch issue {
        case .externalDriveDisconnected(let path):
            startupIssuePath = path
            showDataPathResetPrompt = false
            acknowledgedExternalDisconnectPath = nil
            if forceReopenAlert {
                showExternalDriveWarning = false
                DispatchQueue.main.async {
                    showExternalDriveWarning = true
                }
            } else {
                showExternalDriveWarning = true
            }
        case .dataNotFound(let path):
            startupIssuePath = path
            showExternalDriveWarning = false
            showDataPathResetPrompt = true
        }
    }

    @MainActor
    private func monitorExternalDriveDisconnects() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            dataManager.refreshCurrentDataLocation()
            let issue = dataManager.detectStartupDataPathIssue()

            guard case .externalDriveDisconnected(let path) = issue else {
                if issue == nil {
                    acknowledgedExternalDisconnectPath = nil
                }
                continue
            }

            guard acknowledgedExternalDisconnectPath != path else { continue }
            guard !showExternalDriveWarning else { continue }

            startupIssuePath = path
            showDataPathResetPrompt = false
            showExternalDriveWarning = true
        }
    }

    @MainActor
    private func performStartupContainerDetectionIfNeeded(force: Bool = false) async {
        guard force || containerLocator.cachedPath == nil else { return }

        let outcome = containerLocator.detectContainerOutcome()
        handleStartupContainerOutcome(outcome)
    }

    @MainActor
    private func handleStartupContainerOutcome(
        _ outcome: FortniteContainerLocator.DetectionOutcome,
        verifiedSelection: Bool = false
    ) {
        showStartupPatchFortniteAlert = false
        showStartupFullDiskAlert = false

        if outcome.accessDenied {
            startupContainerWasVerified = false
            showStartupFullDiskAlert = true
            return
        }

        if let selected = outcome.selected {
            showStartupAmbiguousContainerSheet = false
            containerLocator.cachedPath = selected.path
            resumePendingContainerWorkflowIfNeeded()
            if !outcome.additional.isEmpty {
                presentStartupDuplicateContainers(
                    selected: selected,
                    extras: outcome.additional,
                    verifiedSelection: verifiedSelection
                )
            } else {
                startupContainerWasVerified = false
            }
            return
        }

        if !outcome.ambiguousCandidates.isEmpty {
            startupContainerWasVerified = false
            showStartupDuplicateContainersSheet = false
            startupAmbiguousCandidates = outcome.ambiguousCandidates
            startupSuggestedContainer = outcome.allTiny ? nil : outcome.suggestedCandidate
            startupAmbiguousAllTiny = outcome.allTiny
            showStartupAmbiguousContainerSheet = true
            return
        }

        if outcome.needsPatchPrompt {
            startupContainerWasVerified = false
            showStartupAmbiguousContainerSheet = false
            showStartupDuplicateContainersSheet = false
            showStartupPatchFortniteAlert = true
        }
    }

    @MainActor
    private func useSuggestedStartupContainer() {
        guard let suggested = startupSuggestedContainer else { return }
        containerLocator.cachedPath = suggested.path
        resumePendingContainerWorkflowIfNeeded()
        let extras = startupAmbiguousCandidates.filter { $0.path != suggested.path }
        showStartupAmbiguousContainerSheet = false
        if !extras.isEmpty {
            presentStartupDuplicateContainers(
                selected: suggested,
                extras: extras,
                verifiedSelection: false
            )
        } else {
            startupContainerWasVerified = false
        }
    }

    @MainActor
    private func presentStartupDuplicateContainers(
        selected: FortniteContainerLocator.ContainerCandidate,
        extras: [FortniteContainerLocator.ContainerCandidate],
        verifiedSelection: Bool
    ) {
        startupContainerWasVerified = verifiedSelection
        startupSelectedContainer = selected
        startupExtraContainers = extras
        startupSelectedExtraContainerPaths = Set(extras.map(\.path))
        DispatchQueue.main.async {
            showStartupDuplicateContainersSheet = true
        }
    }

    @MainActor
    private func resumePendingContainerWorkflowIfNeeded() {
        guard let workflow = pendingContainerWorkflow else { return }
        pendingContainerWorkflow = nil

        switch workflow {
        case .updateAssistantStart:
            NotificationCenter.default.post(
                name: FortniteContainerLocator.resumeUpdateAssistantNotification,
                object: nil
            )
        case .gameAssetsDownload:
            NotificationCenter.default.post(
                name: FortniteContainerLocator.resumeGameAssetsDownloadNotification,
                object: nil
            )
        }
    }

    @MainActor
    private func deleteStartupDuplicateContainers() {
        do {
            try containerLocator.deleteContainers(paths: Array(startupSelectedExtraContainerPaths))
            startupExtraContainers.removeAll { startupSelectedExtraContainerPaths.contains($0.path) }
            startupSelectedExtraContainerPaths.removeAll()
            showStartupDuplicateContainersSheet = false
        } catch {
            startupContainerDeleteErrorMessage = error.localizedDescription
        }
    }

    private var duplicateContainersSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Multiple Fortnite Containers Found")
                .font(.title3.weight(.semibold))

            Text(startupContainerWasVerified
                 ? "Container verified. Would you like to delete the other detected containers?"
                 : "FnMacAssistant selected a container automatically. Do you want to delete the other detected containers?")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let selected = startupSelectedContainer {
                containerCard(
                    title: "Selected container (kept):",
                    candidate: selected
                )
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(startupExtraContainers) { candidate in
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(isOn: Binding(
                                get: { startupSelectedExtraContainerPaths.contains(candidate.path) },
                                set: { isOn in
                                    if isOn {
                                        startupSelectedExtraContainerPaths.insert(candidate.path)
                                    } else {
                                        startupSelectedExtraContainerPaths.remove(candidate.path)
                                    }
                                }
                            )) {
                                Text(candidate.path)
                                    .font(.system(size: 12, design: .monospaced))
                                    .textSelection(.enabled)
                            }

                            HStack(spacing: 14) {
                                Text("Logs modified: \(formatLogsDate(candidate: candidate))")
                                Text("Size: \(formatBytes(candidate.dataSize))")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
            .frame(maxHeight: 280)

            HStack {
                Button("Keep All") {
                    showStartupDuplicateContainersSheet = false
                }

                Spacer()

                Button("Delete Selected", role: .destructive) {
                    deleteStartupDuplicateContainers()
                }
                .disabled(startupSelectedExtraContainerPaths.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 640)
    }

    private var ambiguousContainersSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Multiple Fortnite Containers Found")
                .font(.title3.weight(.semibold))

            Text("Multiple Fortnite containers were found. FnMacAssistant automatically determined the selected container to be the correct one. Would you like to verify the container, restore your Fortnite containers, or continue with selected?")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Verify Container will automatically open and then close Fortnite to see which container was modified.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if startupContainerActionInProgress {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)

                    Text(startupContainerActionMessage.isEmpty ? "Checking containers..." : startupContainerActionMessage)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 2)
            }

            if let suggested = startupSuggestedContainer {
                containerCard(
                    title: "Automatically determined container:",
                    candidate: suggested
                )
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if startupSuggestedContainer != nil {
                        Text("Other detected containers:")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)
                    }

                    ForEach(startupAmbiguousCandidates.filter { candidate in
                        candidate.path != startupSuggestedContainer?.path
                    }) { candidate in
                        containerCard(title: nil, candidate: candidate)
                    }
                }
            }
            .frame(maxHeight: 260)

            HStack {
                Button("Restore Containers", role: .destructive) {
                    Task {
                        startupContainerActionInProgress = true
                        startupContainerActionMessage = "Restoring containers. Fortnite will regenerate a fresh one."
                        let outcome = await containerLocator.restoreContainersAndRegenerate()
                        startupContainerActionInProgress = false
                        startupContainerActionMessage = ""
                        showStartupAmbiguousContainerSheet = false
                        handleStartupContainerOutcome(outcome)
                    }
                }
                .disabled(startupContainerActionInProgress)
                .foregroundColor(.red)

                Spacer()

                if !startupAmbiguousAllTiny, startupSuggestedContainer != nil {
                    Button("Continue with Selected") {
                        useSuggestedStartupContainer()
                    }
                    .disabled(startupContainerActionInProgress)
                }

                Button("Verify Container") {
                    Task {
                        startupContainerActionInProgress = true
                        startupContainerActionMessage = "Verifying container. Fortnite will open and close automatically."
                        let outcome = await containerLocator.performVerifyContainerCheck()
                        startupContainerActionInProgress = false
                        startupContainerActionMessage = ""
                        handleStartupContainerOutcome(outcome, verifiedSelection: true)
                    }
                }
                .disabled(startupContainerActionInProgress)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 680)
    }

    @ViewBuilder
    private func containerCard(
        title: String?,
        candidate: FortniteContainerLocator.ContainerCandidate
    ) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                if let title {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                }

                Text(candidate.path)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.75))
                    .textSelection(.enabled)

                HStack(spacing: 14) {
                    Text("Logs modified: \(formatLogsDate(candidate: candidate))")
                    Text("Size: \(formatBytes(candidate.dataSize))")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func formatDate(_ date: Date) -> String {
        if date == .distantPast {
            return "Unknown"
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func formatLogsDate(candidate: FortniteContainerLocator.ContainerCandidate) -> String {
        if let date = containerLocator.logsDirectoryModifiedDate(forPath: candidate.path) {
            return formatDate(date)
        }
        return formatDate(candidate.modified)
    }
}

// MARK: - Sidebar View
struct SidebarView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: SidebarSection
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var fortDLManager = FortDLManager.shared
    @ObservedObject private var updateAssistantManager = UpdateAssistantManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FnMacAssistant")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal, 16)
                .padding(.top, 20)

            VStack(alignment: .leading, spacing: 6) {
                SidebarButton(
                    label: "Home",
                    systemImage: "house.fill",
                    isSelected: selection == .home
                ) { selection = .home }

                SidebarButton(
                    label: "IPA Downloads",
                    systemImage: "square.and.arrow.down",
                    isSelected: selection == .downloads
                ) { selection = .downloads }

                SidebarButton(
                    label: "Patch",
                    systemImage: "wrench.and.screwdriver.fill",
                    isSelected: selection == .patch
                ) { selection = .patch }
                
                SidebarButton(
                    label: "Update Assistant",
                    systemImage: "arrow.triangle.2.circlepath",
                    isSelected: selection == .updateAssistant
                ) { selection = .updateAssistant }

                SidebarButton(
                    label: "Game Assets",
                    systemImage: "shippingbox.fill",
                    isSelected: selection == .gameAssets
                ) { selection = .gameAssets }

                SidebarButton(
                    label: "Data Manager",
                    systemImage: "externaldrive.fill.badge.minus",
                    isSelected: selection == .dataManagement
                ) { selection = .dataManagement }
                SidebarButton(
                    label: "FAQ",
                    systemImage: "questionmark.circle.fill",
                    isSelected: selection == .faq
                ) { selection = .faq }
                
                SidebarButton(
                    label: "Settings",
                    systemImage: "gearshape.fill",
                    isSelected: selection == .settings
                ) { selection = .settings }
            }
            .padding(.top, 10)
            .padding(.horizontal, 8)
            .focusSection()
            
            Spacer()

            if hasAnyDownloadSummary {
                VStack(alignment: .leading, spacing: 10) {
                    if selection != .downloads, let active = downloadManager.downloads.first {
                        downloadSummaryCard(
                            title: "IPA Download",
                            subtitle: active.fileName,
                            progress: active.progress,
                            progressLabel: ipaProgressText(for: active),
                            stateLabel: ipaStateLabel(for: active),
                            showClear: active.state == .finished,
                            showCancel: active.state != .finished,
                            onOpen: {
                                selection = .downloads
                            },
                            onClear: {
                                downloadManager.clearDownloads()
                            },
                            onCancel: {
                                downloadManager.cancelCurrentDownload()
                                downloadManager.clearDownloads()
                            }
                        )
                    }

                    if selection != .gameAssets,
                       (fortDLManager.isDownloading || fortDLManager.isInstalling || fortDLManager.isDone) {
                        downloadSummaryCard(
                            title: "Game Assets",
                            subtitle: assetsSubtitle,
                            progress: fortDLManager.downloadProgress,
                            progressLabel: assetsProgressText,
                            stateLabel: assetsStateLabel,
                            showClear: fortDLManager.isDone,
                            showCancel: fortDLManager.isDownloading,
                            onOpen: {
                                selection = .gameAssets
                            },
                            onClear: {
                                fortDLManager.clearCompletedDownload()
                            },
                            onCancel: {
                                fortDLManager.cancelDownload()
                            }
                        )
                    }

                    if selection != .updateAssistant,
                       (updateAssistantManager.isDownloading || updateAssistantManager.isDone) {
                        downloadSummaryCard(
                            title: "Update Assistant",
                            subtitle: updateAssistantManager.statusMessage,
                            progress: updateAssistantManager.downloadProgress,
                            progressLabel: updateAssistantProgressText,
                            stateLabel: updateAssistantStateLabel,
                            showClear: updateAssistantManager.isDone,
                            showCancel: updateAssistantManager.isDownloading,
                            onOpen: {
                                selection = .updateAssistant
                            },
                            onClear: {
                                updateAssistantManager.stop()
                            },
                            onCancel: {
                                updateAssistantManager.stop()
                            }
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
        }
        .frame(width: 200)
    }

    private var hasAnyDownloadSummary: Bool {
        let hasIPADownload = selection != .downloads && downloadManager.downloads.first != nil
        let hasAssetsDownload = selection != .gameAssets &&
            (fortDLManager.isDownloading || fortDLManager.isInstalling || fortDLManager.isDone)
        let hasUpdateAssistant = selection != .updateAssistant &&
            (updateAssistantManager.isDownloading || updateAssistantManager.isDone)
        return hasIPADownload || hasAssetsDownload || hasUpdateAssistant
    }

    private var assetsSubtitle: String {
        if fortDLManager.downloadAllAssets {
            return "All assets"
        }

        let assetsCount = fortDLManager.selectedAssets.count
        let layersCount = fortDLManager.selectedLayers.count

        if layersCount == 1, let layerName = fortDLManager.selectedLayers.first,
           isFullLayerSelected(layerName: layerName) {
            return layerName
        }
        if assetsCount == 1, let name = fortDLManager.selectedAssets.first {
            return name
        }
        if assetsCount > 1 {
            return "Multiple tags"
        }
        if layersCount == 1, let name = fortDLManager.selectedLayers.first {
            return name
        }
        if layersCount > 1 {
            return "Multiple layers"
        }

        return "Game assets"
    }

    private func isFullLayerSelected(layerName: String) -> Bool {
        guard let layer = fortDLManager.layers.first(where: { $0.name == layerName }) else {
            return false
        }
        let assetNames = Set(layer.assets.map(\.name))
        return !assetNames.isEmpty && assetNames.isSubset(of: fortDLManager.selectedAssets)
    }

    private func ipaProgressText(for active: DownloadItem) -> String {
        if active.state == .finished {
            return "Done"
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .decimal

        let downloaded = formatter.string(fromByteCount: active.totalBytesWritten)
        let total = formatter.string(fromByteCount: active.totalBytesExpected)
        return "\(downloaded) / \(total)"
    }

    private func ipaStateLabel(for active: DownloadItem) -> String {
        switch active.state {
        case .paused:
            return "Paused"
        case .finished:
            return "Done"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        default:
            return String(format: "%.1f%%", active.progress * 100)
        }
    }

    private var assetsProgressText: String {
        if fortDLManager.isInstalling {
            return "Installing…"
        }
        if fortDLManager.isDone {
            return "Done"
        }
        return fortDLManager.downloadProgressLabel
    }

    private var assetsStateLabel: String {
        if fortDLManager.isInstalling {
            return "Installing"
        }
        if fortDLManager.isDone {
            return "Done"
        }
        return fortDLManager.downloadPercentageLabel
    }

    private var updateAssistantProgressText: String {
        if updateAssistantManager.isDone {
            return "Done"
        }
        return updateAssistantManager.downloadProgressLabel
    }

    private var updateAssistantStateLabel: String {
        if updateAssistantManager.isDone {
            return "Done"
        }
        return updateAssistantManager.downloadPercentageLabel
    }

    @ViewBuilder
    private func downloadSummaryCard(
        title: String,
        subtitle: String,
        progress: Double,
        progressLabel: String,
        stateLabel: String,
        showClear: Bool,
        showCancel: Bool,
        onOpen: @escaping () -> Void,
        onClear: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(stateLabel)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)

            ProgressView(value: progress)
                .progressViewStyle(.linear)

            HStack {
                Text(progressLabel)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Spacer()

                if showCancel {
                    Button("Cancel") {
                        onCancel()
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.bordered)
                }

                if showClear {
                    Button("Clear") {
                        onClear()
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(8)
        .containerBackground(
            colorScheme == .dark ? .ultraThickMaterial : .regularMaterial,
            for: .window
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.1))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onOpen()
        }
    }
}

// MARK: - Sidebar Button 
struct SidebarButton: View {
    let label: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 20)
                Text(label)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .background(RoundedRectangle(cornerRadius: 8).foregroundStyle(backgroundColor))
            .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.25)
        } else if isHovered {
            return Color.primary.opacity(0.08)
        } else {
            return Color.clear
        }
    }
}

// MARK: - Sidebar Section Enum
enum SidebarSection: String, CaseIterable, Identifiable {
    case home
    case downloads
    case patch
    case gameAssets
    case dataManagement
    case updateAssistant
    case faq
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            return "Home"
        case .downloads:
            return "IPA Downloads"
        case .patch:
            return "Patch"
        case .gameAssets:
            return "Game Assets"
        case .dataManagement:
            return "Data Manager"
        case .updateAssistant:
            return "Update Assistant"
        case .faq:
            return "FAQ"
        case .settings:
            return "Settings"
        }
    }
}

private enum StartupSheet: String, Identifiable {
    case prerelease
    case unsupportedMacOS

    var id: String { rawValue }
}

private struct UpdatePromptSheet: View {
    let title: String
    let message: String
    let suppressLabel: String
    @Binding var suppressValue: Bool
    let primaryTitle: String
    let primaryAction: () -> Void
    let secondaryTitle: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2)
                .bold()

            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            Toggle(suppressLabel, isOn: $suppressValue)
                .toggleStyle(.checkbox)

            HStack {
                Spacer()
                Button(primaryTitle) {
                    primaryAction()
                    onDismiss()
                }
                Button(secondaryTitle) {
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

private struct StartupNoticeSheet: View {
    let title: String
    let message: String
    let primaryTitle: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2)
                .bold()

            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            HStack {
                Spacer()
                Button(primaryTitle) {
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 430)
    }
}
