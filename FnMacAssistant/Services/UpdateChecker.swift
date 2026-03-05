//
//  UpdateChecker.swift
//  FnMacAssistant
//
//  Created by Isacucho on 02/10/26.
//

import Foundation
import Combine
import Sparkle

final class SparkleUpdaterService: NSObject, ObservableObject {
    static let shared = SparkleUpdaterService()

    enum UpdateChannel: String, CaseIterable, Identifiable {
        case stable
        case beta

        var id: String { rawValue }

        var title: String {
            switch self {
            case .stable: return "Stable"
            case .beta: return "Beta"
            }
        }
    }

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var automaticallyDownloadsUpdates = false
    @Published private(set) var selectedChannel: UpdateChannel

    let updaterController: SPUStandardUpdaterController
    private let updaterDelegateProxy: SparkleChannelDelegate
    private let selectedChannelKey = "sparkle.selectedChannel"
    private let defaultsInitializedKey = "sparkle.defaultsInitialized"

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
    }

    var currentBuildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    var currentVersionWithBuild: String {
        "\(currentVersion) (\(currentBuildNumber))"
    }

    var isPrereleaseBuild: Bool {
        Self.detectPrereleaseBuild()
    }

    private override init() {
        let defaults = UserDefaults.standard
        let isFirstLaunchDefaultsInit = !defaults.bool(forKey: defaultsInitializedKey)

        let initialChannel: UpdateChannel
        if isFirstLaunchDefaultsInit {
            initialChannel = Self.detectPrereleaseBuild() ? .beta : .stable
            defaults.set(initialChannel.rawValue, forKey: selectedChannelKey)
        } else {
            let stored = defaults.string(forKey: selectedChannelKey)
            initialChannel = UpdateChannel(rawValue: stored ?? "") ?? .stable
        }

        selectedChannel = initialChannel
        updaterDelegateProxy = SparkleChannelDelegate(channel: initialChannel)
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: updaterDelegateProxy,
            userDriverDelegate: nil
        )
        super.init()

        if isFirstLaunchDefaultsInit {
            updaterController.updater.automaticallyDownloadsUpdates = true
            defaults.set(true, forKey: defaultsInitializedKey)
        }

        bindUpdaterState()
        refreshState()
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        updaterController.updater.automaticallyChecksForUpdates = enabled
        refreshState()
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        updaterController.updater.automaticallyDownloadsUpdates = enabled
        refreshState()
    }

    func setChannel(_ channel: UpdateChannel) {
        guard channel != selectedChannel else { return }
        selectedChannel = channel
        updaterDelegateProxy.channel = channel
        UserDefaults.standard.set(channel.rawValue, forKey: selectedChannelKey)
        updaterController.updater.resetUpdateCycleAfterShortDelay()
    }

    private func bindUpdaterState() {
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
            .store(in: &cancellables)
    }

    private func refreshState() {
        canCheckForUpdates = updaterController.updater.canCheckForUpdates
        automaticallyChecksForUpdates = updaterController.updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updaterController.updater.automaticallyDownloadsUpdates
    }

    private static func detectPrereleaseBuild() -> Bool {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        return version.contains("-") || version.rangeOfCharacter(from: .letters) != nil
    }

    private var cancellables = Set<AnyCancellable>()
}

private final class SparkleChannelDelegate: NSObject, SPUUpdaterDelegate {
    var channel: SparkleUpdaterService.UpdateChannel

    init(channel: SparkleUpdaterService.UpdateChannel) {
        self.channel = channel
        super.init()
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        channel == .beta ? ["beta"] : []
    }
}
