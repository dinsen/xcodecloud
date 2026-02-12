import Foundation
import Observation

enum BuildMonitoringMode: String, CaseIterable, Sendable {
    case singleApp
    case allApps

    nonisolated var title: String {
        switch self {
        case .singleApp: return "Single App"
        case .allApps: return "All Apps"
        }
    }
}

@MainActor
@Observable
final class BuildFeedStore {
    private enum DefaultsKey {
        static let selectedAppID = "selectedAppID"
        static let selectedAppName = "selectedAppDisplayName"
        static let selectedAppBundleID = "selectedAppBundleID"
        static let monitoringMode = "monitoringMode"
    }

    private(set) var credentials: AppStoreConnectCredentials?
    private(set) var availableApps: [ASCAppSummary] = []
    private(set) var selectedApp: ASCAppSummary?
    private(set) var monitoringMode: BuildMonitoringMode = .singleApp
    private(set) var buildRuns: [BuildRunSummary] = []
    private(set) var isLoadingApps = false
    private(set) var isLoadingBuildRuns = false
    private(set) var errorMessage: String?
    private(set) var appSelectionMessage: String?
    private(set) var lastUpdated: Date?
    private(set) var hasLoadedInitialState = false

    var hasCompleteCredentials: Bool {
        credentials?.isComplete ?? false
    }

    var isMonitoringAllApps: Bool {
        monitoringMode == .allApps
    }

    var monitoredAppDescription: String {
        if monitoringMode == .allApps {
            return "All apps"
        }

        return selectedApp?.displayName ?? "Not selected"
    }

    var workflowSections: [WorkflowBuildSection] {
        let grouped = Dictionary(grouping: buildRuns, by: { $0.workflowName })

        return grouped
            .map { key, runs in
                WorkflowBuildSection(
                    workflowName: key,
                    runs: runs.sorted(by: Self.sortRuns)
                )
            }
            .sorted {
                let lhsPriority = $0.runs.first?.status.priority ?? Int.max
                let rhsPriority = $1.runs.first?.status.priority ?? Int.max

                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }

                let lhsNewest = $0.runs.first?.number ?? 0
                let rhsNewest = $1.runs.first?.number ?? 0
                return lhsNewest > rhsNewest
            }
    }

    var appSections: [AppBuildSection] {
        let grouped = Dictionary(grouping: buildRuns, by: { $0.app?.id ?? "unknown" })

        return grouped
            .compactMap { _, runs in
                guard let app = runs.first?.app else { return nil }
                return AppBuildSection(
                    app: app,
                    runs: runs.sorted(by: Self.sortRuns)
                )
            }
            .sorted {
                let lhsPriority = $0.runs.first?.status.priority ?? Int.max
                let rhsPriority = $1.runs.first?.status.priority ?? Int.max

                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }

                return $0.app.name.localizedCaseInsensitiveCompare($1.app.name) == .orderedAscending
            }
    }

    var overallStatus: BuildStatus {
        guard !buildRuns.isEmpty else { return .unknown }
        return buildRuns.min(by: { $0.status.priority < $1.status.priority })?.status ?? .unknown
    }

    var menuBarSymbolName: String {
        overallStatus.symbolName
    }

    private let credentialsStore: CredentialsStore
    private let apiClient: any AppStoreConnectAPI
    private let userDefaults: UserDefaults

    private var autoRefreshTask: Task<Void, Never>?

    init(
        credentialsStore: CredentialsStore,
        apiClient: any AppStoreConnectAPI,
        userDefaults: UserDefaults
    ) {
        self.credentialsStore = credentialsStore
        self.apiClient = apiClient
        self.userDefaults = userDefaults

        reloadCredentials()
        loadSelectedAppFromDefaults()
        loadMonitoringModeFromDefaults()

        _ = NotificationCenter.default.addObserver(
            forName: .appStoreConnectCredentialsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadCredentials()
                await self?.reloadAfterCredentialUpdate()
            }
        }
    }

    convenience init() {
        self.init(
            credentialsStore: KeychainCredentialsStore(),
            apiClient: AppStoreConnectClient(),
            userDefaults: .standard
        )
    }

    func loadInitialState() async {
        guard !hasLoadedInitialState else { return }
        hasLoadedInitialState = true

        guard hasCompleteCredentials else {
            errorMessage = "Credentials are missing."
            return
        }

        await loadApps()

        if monitoringMode == .allApps || selectedApp != nil {
            await refreshBuildRuns()
        }
    }

    func reloadCredentials() {
        credentials = credentialsStore.loadCredentials()
    }

    func loadApps() async {
        guard hasCompleteCredentials, let credentials else {
            availableApps = []
            selectedApp = nil
            appSelectionMessage = "Add credentials first."
            clearSelectedAppDefaults()
            return
        }

        isLoadingApps = true
        defer { isLoadingApps = false }

        do {
            let apps = try await apiClient.fetchApps(credentials: credentials)
            availableApps = apps
            appSelectionMessage = nil

            if let selectedID = selectedApp?.id,
               let refreshedSelected = apps.first(where: { $0.id == selectedID }) {
                selectedApp = refreshedSelected
                persistSelectedApp(refreshedSelected)
            } else if let storedID = userDefaults.string(forKey: DefaultsKey.selectedAppID),
                      let storedSelection = apps.first(where: { $0.id == storedID }) {
                selectedApp = storedSelection
                persistSelectedApp(storedSelection)
            } else if selectedApp == nil {
                clearSelectedAppDefaults()
            }

            if monitoringMode == .allApps {
                appSelectionMessage = nil
            }
        } catch {
            appSelectionMessage = sanitizedMessage(for: error)
        }
    }

    func setMonitoringMode(_ mode: BuildMonitoringMode) async {
        monitoringMode = mode
        persistMonitoringMode(mode)

        if mode == .singleApp, selectedApp == nil, let first = availableApps.first {
            selectedApp = first
            persistSelectedApp(first)
        }

        await refreshBuildRuns()
    }

    func selectApp(_ app: ASCAppSummary) async {
        selectedApp = app
        monitoringMode = .singleApp
        persistSelectedApp(app)
        persistMonitoringMode(.singleApp)
        errorMessage = nil
        await refreshBuildRuns()
    }

    func clearSelectedApp() {
        selectedApp = nil
        buildRuns = []
        clearSelectedAppDefaults()
    }

    func refreshBuildRuns() async {
        guard hasCompleteCredentials, let credentials else {
            errorMessage = "Credentials are missing."
            buildRuns = []
            return
        }

        isLoadingBuildRuns = true
        defer { isLoadingBuildRuns = false }

        do {
            let runs: [BuildRunSummary]

            if monitoringMode == .allApps {
                if availableApps.isEmpty {
                    await loadApps()
                }

                let appsToMonitor = availableApps
                guard !appsToMonitor.isEmpty else {
                    errorMessage = "No apps are available for these credentials."
                    buildRuns = []
                    return
                }

                var mergedRuns: [BuildRunSummary] = []
                var partialErrors: [String] = []

                for app in appsToMonitor {
                    do {
                        let appRuns = try await apiClient.fetchLatestBuildRuns(
                            credentials: credentials,
                            appID: app.id,
                            limit: 6
                        )
                        mergedRuns.append(contentsOf: appRuns.map { $0.withApp(app) })
                    } catch {
                        partialErrors.append("\(app.name): \(sanitizedMessage(for: error))")
                    }
                }

                runs = mergedRuns.sorted(by: Self.sortRuns)

                if !partialErrors.isEmpty {
                    errorMessage = "Some apps could not be refreshed."
                } else {
                    errorMessage = nil
                }
            } else {
                guard let selectedApp else {
                    errorMessage = "Select an app in Settings to load build runs."
                    buildRuns = []
                    return
                }

                runs = try await apiClient.fetchLatestBuildRuns(
                    credentials: credentials,
                    appID: selectedApp.id,
                    limit: 20
                )
                .map { $0.withApp(selectedApp) }

                errorMessage = nil
            }

            buildRuns = runs
            lastUpdated = Date()
        } catch {
            errorMessage = sanitizedMessage(for: error)
        }
    }

    func configureAutoRefresh(enabled: Bool, intervalSeconds: TimeInterval) {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil

        guard enabled else { return }

        let interval = max(15, intervalSeconds)

        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                let nanoseconds = UInt64(interval * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)

                guard !Task.isCancelled else { return }
                await self?.refreshBuildRuns()
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    private func reloadAfterCredentialUpdate() async {
        if !hasCompleteCredentials {
            availableApps = []
            selectedApp = nil
            buildRuns = []
            clearSelectedAppDefaults()
            errorMessage = "Credentials are missing."
            stopAutoRefresh()
            return
        }

        await loadApps()

        if monitoringMode == .allApps || selectedApp != nil {
            await refreshBuildRuns()
        }
    }

    private func persistSelectedApp(_ app: ASCAppSummary) {
        userDefaults.set(app.id, forKey: DefaultsKey.selectedAppID)
        userDefaults.set(app.name, forKey: DefaultsKey.selectedAppName)
        userDefaults.set(app.bundleID, forKey: DefaultsKey.selectedAppBundleID)
    }

    private func persistMonitoringMode(_ mode: BuildMonitoringMode) {
        userDefaults.set(mode.rawValue, forKey: DefaultsKey.monitoringMode)
    }

    private func loadSelectedAppFromDefaults() {
        guard let id = userDefaults.string(forKey: DefaultsKey.selectedAppID),
              let name = userDefaults.string(forKey: DefaultsKey.selectedAppName),
              let bundleID = userDefaults.string(forKey: DefaultsKey.selectedAppBundleID) else {
            selectedApp = nil
            return
        }

        selectedApp = ASCAppSummary(id: id, name: name, bundleID: bundleID)
    }

    private func clearSelectedAppDefaults() {
        userDefaults.removeObject(forKey: DefaultsKey.selectedAppID)
        userDefaults.removeObject(forKey: DefaultsKey.selectedAppName)
        userDefaults.removeObject(forKey: DefaultsKey.selectedAppBundleID)
    }

    private func loadMonitoringModeFromDefaults() {
        guard let rawValue = userDefaults.string(forKey: DefaultsKey.monitoringMode),
              let mode = BuildMonitoringMode(rawValue: rawValue) else {
            monitoringMode = .singleApp
            return
        }

        monitoringMode = mode
    }

    private func sanitizedMessage(for error: Error) -> String {
        if let known = error as? AppStoreConnectClientError {
            return known.localizedDescription
        }

        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }

        return "Something went wrong while loading from App Store Connect."
    }

    private static func sortRuns(lhs: BuildRunSummary, rhs: BuildRunSummary) -> Bool {
        if let lhsNumber = lhs.number, let rhsNumber = rhs.number {
            return lhsNumber > rhsNumber
        }

        let lhsDate = lhs.timestamp ?? .distantPast
        let rhsDate = rhs.timestamp ?? .distantPast
        return lhsDate > rhsDate
    }
}
