import Foundation
import Observation
#if os(iOS)
import UIKit
#endif

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
        static let dashboardFilterAppID = "dashboardFilterAppID"
        static let liveStatusEnabled = "liveStatusEnabled"
        static let liveStatusEndpointURL = "liveStatusEndpointURL"
        static let liveStatusPollIntervalSeconds = "liveStatusPollIntervalSeconds"
    }

    private struct DeviceSubscription: Equatable {
        let appID: String
        let token: String
    }

    private(set) var credentials: AppStoreConnectCredentials?
    private(set) var availableApps: [ASCAppSummary] = []
    private(set) var selectedApp: ASCAppSummary?
    private(set) var monitoringMode: BuildMonitoringMode = .singleApp
    private(set) var dashboardFilterAppID: String?
    private(set) var buildRuns: [BuildRunSummary] = []
    private(set) var workflows: [CIWorkflowSummary] = []
    private(set) var compatibilityMatrix: CICompatibilityMatrix?
    private(set) var repositories: [CIRepositorySummary] = []
    private(set) var isLoadingApps = false
    private(set) var isLoadingBuildRuns = false
    private(set) var isLoadingWorkflows = false
    private(set) var isTriggeringBuild = false
    private(set) var isManagingWorkflows = false
    private(set) var isLoadingCompatibility = false
    private(set) var isLoadingRepositories = false
    private(set) var errorMessage: String?
    private(set) var appSelectionMessage: String?
    private(set) var buildTriggerMessage: String?
    private(set) var workflowManagementMessage: String?
    private(set) var compatibilityMessage: String?
    private(set) var repositoryMessage: String?
    private(set) var liveStatus: CIRunningBuildStatus?
    private(set) var liveStatusMessage: String?
    private(set) var isPollingLiveStatus = false
    private(set) var lastUpdated: Date?
    private(set) var hasLoadedInitialState = false

    var hasCompleteCredentials: Bool {
        credentials?.isComplete ?? false
    }

    var isMonitoringAllApps: Bool {
        dashboardFilterAppID == nil
    }

    var dashboardFilterApp: ASCAppSummary? {
        guard let dashboardFilterAppID else { return nil }
        return dashboardFilterOptions.first(where: { $0.id == dashboardFilterAppID })
    }

    var dashboardFilterOptions: [ASCAppSummary] {
        var appsByID: [String: ASCAppSummary] = [:]

        for app in availableApps {
            appsByID[app.id] = app
        }

        for app in buildRuns.compactMap(\.app) where appsByID[app.id] == nil {
            appsByID[app.id] = app
        }

        return appsByID.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var monitoredAppDescription: String {
        return selectedApp?.displayName ?? "Not selected"
    }

    var workflowSections: [WorkflowBuildSection] {
        let grouped = Dictionary(grouping: dashboardFilteredRuns, by: { $0.workflowName })

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
        let grouped = Dictionary(grouping: dashboardFilteredRuns, by: { $0.app?.id ?? "unknown" })

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

    var portfolioRunningBuilds: [BuildRunSummary] {
        dashboardFilteredRuns
            .filter { $0.status == .running }
            .sorted(by: Self.sortRunsByLastRun)
    }

    var portfolioFailedBuilds: [BuildRunSummary] {
        dashboardFilteredRuns
            .filter { $0.status == .failed }
            .sorted(by: Self.sortRunsByLastRun)
    }

    var portfolioSuccessfulBuilds: [BuildRunSummary] {
        Array(
            dashboardFilteredRuns
                .filter { $0.status == .succeeded }
                .sorted(by: Self.sortRunsByLastRun)
                .prefix(20)
        )
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
    private let liveStatusClient: any CIRunningBuildStatusAPI
    private let liveActivityManager: any BuildLiveActivityManaging
    private let liveStatusDeviceRegistrationClient: any LiveStatusDeviceRegistrationAPI
    private let userDefaults: UserDefaults

    private var autoRefreshTask: Task<Void, Never>?
    private var liveStatusTask: Task<Void, Never>?
    private var liveStatusEndpointURL: URL?
    private var latestRemoteDeviceToken: String?
    private var lastRegisteredDeviceSubscription: DeviceSubscription?
#if os(iOS)
    private var hasRequestedRemoteNotifications = false
#endif

    init(
        credentialsStore: CredentialsStore,
        apiClient: any AppStoreConnectAPI,
        liveStatusClient: any CIRunningBuildStatusAPI,
        liveActivityManager: any BuildLiveActivityManaging,
        liveStatusDeviceRegistrationClient: any LiveStatusDeviceRegistrationAPI,
        userDefaults: UserDefaults
    ) {
        self.credentialsStore = credentialsStore
        self.apiClient = apiClient
        self.liveStatusClient = liveStatusClient
        self.liveActivityManager = liveActivityManager
        self.liveStatusDeviceRegistrationClient = liveStatusDeviceRegistrationClient
        self.userDefaults = userDefaults

        reloadCredentials()
        loadSelectedAppFromDefaults()
        loadMonitoringModeFromDefaults()
        loadDashboardFilterAppFromDefaults()

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

#if os(iOS)
        _ = NotificationCenter.default.addObserver(
            forName: .didRegisterRemoteNotificationToken,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let token = notification.userInfo?["deviceToken"] as? String else { return }
            Task { @MainActor [weak self] in
                await self?.handleRemoteDeviceTokenUpdate(token)
            }
        }

        _ = NotificationCenter.default.addObserver(
            forName: .didFailToRegisterRemoteNotifications,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let error = notification.object as? Error else { return }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            Task { @MainActor [weak self] in
                self?.liveStatusMessage = message
            }
        }

        _ = NotificationCenter.default.addObserver(
            forName: .didReceiveLiveStatusWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.handleLiveStatusWakeNotification()
            }
        }
#endif

        bootstrapLiveStatusConfigurationFromDefaults()
    }

    convenience init() {
        self.init(
            credentialsStore: KeychainCredentialsStore(),
            apiClient: AppStoreConnectClient(),
            liveStatusClient: CIRunningBuildStatusClient(),
            liveActivityManager: BuildLiveActivityManager(),
            liveStatusDeviceRegistrationClient: LiveStatusDeviceRegistrationClient(),
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

        await refreshBuildRuns()

        await loadApps()
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

            if let dashboardFilterAppID,
               !apps.contains(where: { $0.id == dashboardFilterAppID }),
               !buildRuns.contains(where: { $0.app?.id == dashboardFilterAppID }) {
                setDashboardFilter(appID: nil)
            }

            await registerDeviceForWakeNotificationsIfNeeded()
        } catch {
            appSelectionMessage = sanitizedMessage(for: error)
        }
    }

    func setDashboardFilter(appID: String?) {
        guard dashboardFilterAppID != appID else { return }
        dashboardFilterAppID = appID
        persistDashboardFilterAppID(appID)
    }

    func setMonitoringMode(_ mode: BuildMonitoringMode) async {
        monitoringMode = mode
        persistMonitoringMode(mode)

        if mode == .singleApp, selectedApp == nil, let first = availableApps.first {
            selectedApp = first
            persistSelectedApp(first)
        } else if mode == .allApps {
            workflows = []
            repositories = []
        }

        await refreshBuildRuns()
        await registerDeviceForWakeNotificationsIfNeeded()
    }

    func selectApp(_ app: ASCAppSummary) async {
        selectedApp = app
        monitoringMode = .singleApp
        workflows = []
        repositories = []
        liveStatus = nil
        liveStatusMessage = nil
        persistSelectedApp(app)
        persistMonitoringMode(.singleApp)
        errorMessage = nil
        await refreshBuildRuns()
        await registerDeviceForWakeNotificationsIfNeeded()
    }

    func clearSelectedApp() {
        selectedApp = nil
        buildRuns = []
        workflows = []
        repositories = []
        liveStatus = nil
        liveStatusMessage = nil
        lastRegisteredDeviceSubscription = nil
        clearSelectedAppDefaults()
        Task { [weak self] in
            await self?.liveActivityManager.end()
        }
    }

    func loadWorkflows() async {
        guard hasCompleteCredentials, let credentials else {
            workflows = []
            buildTriggerMessage = "Credentials are missing."
            return
        }

        guard let selectedApp else {
            workflows = []
            buildTriggerMessage = "Select an app in Settings first."
            return
        }

        isLoadingWorkflows = true
        defer { isLoadingWorkflows = false }

        do {
            workflows = try await apiClient.fetchWorkflows(
                credentials: credentials,
                appID: selectedApp.id
            )
            let message = workflows.isEmpty ? "No workflows available for this app." : nil
            buildTriggerMessage = message
            workflowManagementMessage = message
        } catch {
            workflows = []
            let message = sanitizedMessage(for: error)
            buildTriggerMessage = message
            workflowManagementMessage = message
        }
    }

    func triggerBuild(workflowID: String, clean: Bool) async -> Bool {
        guard hasCompleteCredentials, let credentials else {
            buildTriggerMessage = "Credentials are missing."
            return false
        }

        guard let selectedApp else {
            buildTriggerMessage = "Select an app in Settings first."
            return false
        }

        isTriggeringBuild = true
        defer { isTriggeringBuild = false }

        do {
            try await apiClient.triggerBuild(
                credentials: credentials,
                appID: selectedApp.id,
                workflowID: workflowID,
                clean: clean
            )
            buildTriggerMessage = "Build queued."
            await refreshBuildRuns()
            return true
        } catch {
            buildTriggerMessage = sanitizedMessage(for: error)
            return false
        }
    }

    func setWorkflowEnabled(workflowID: String, isEnabled: Bool) async -> Bool {
        guard hasCompleteCredentials, let credentials else {
            workflowManagementMessage = "Credentials are missing."
            return false
        }

        isManagingWorkflows = true
        defer { isManagingWorkflows = false }

        do {
            try await apiClient.setWorkflowEnabled(
                credentials: credentials,
                workflowID: workflowID,
                isEnabled: isEnabled
            )
            workflowManagementMessage = nil
            await loadWorkflows()
            return true
        } catch {
            workflowManagementMessage = sanitizedMessage(for: error)
            return false
        }
    }

    func deleteWorkflow(workflowID: String) async -> Bool {
        guard hasCompleteCredentials, let credentials else {
            workflowManagementMessage = "Credentials are missing."
            return false
        }

        isManagingWorkflows = true
        defer { isManagingWorkflows = false }

        do {
            try await apiClient.deleteWorkflow(
                credentials: credentials,
                workflowID: workflowID
            )
            workflowManagementMessage = nil
            await loadWorkflows()
            await refreshBuildRuns()
            return true
        } catch {
            workflowManagementMessage = sanitizedMessage(for: error)
            return false
        }
    }

    func duplicateWorkflow(workflowID: String, newName: String) async -> Bool {
        guard hasCompleteCredentials, let credentials else {
            workflowManagementMessage = "Credentials are missing."
            return false
        }

        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            workflowManagementMessage = "Workflow name cannot be empty."
            return false
        }

        isManagingWorkflows = true
        defer { isManagingWorkflows = false }

        do {
            try await apiClient.duplicateWorkflow(
                credentials: credentials,
                workflowID: workflowID,
                newName: trimmedName
            )
            workflowManagementMessage = nil
            await loadWorkflows()
            return true
        } catch {
            workflowManagementMessage = sanitizedMessage(for: error)
            return false
        }
    }

    func loadBuildDiagnostics(runID: String) async throws -> BuildRunDiagnostics {
        guard hasCompleteCredentials, let credentials else {
            throw AppStoreConnectClientError.missingCredentials
        }

        return try await apiClient.fetchBuildRunDiagnostics(
            credentials: credentials,
            runID: runID
        )
    }

    func loadCompatibilityMatrix() async {
        guard hasCompleteCredentials, let credentials else {
            compatibilityMatrix = nil
            compatibilityMessage = "Credentials are missing."
            return
        }

        isLoadingCompatibility = true
        defer { isLoadingCompatibility = false }

        do {
            compatibilityMatrix = try await apiClient.fetchCompatibilityMatrix(credentials: credentials)
            compatibilityMessage = nil
        } catch {
            compatibilityMatrix = nil
            compatibilityMessage = sanitizedMessage(for: error)
        }
    }

    func loadRepositories() async {
        guard hasCompleteCredentials, let credentials else {
            repositories = []
            repositoryMessage = "Credentials are missing."
            return
        }

        guard let selectedApp else {
            repositories = []
            repositoryMessage = "Select an app in Settings first."
            return
        }

        isLoadingRepositories = true
        defer { isLoadingRepositories = false }

        do {
            repositories = try await apiClient.fetchRepositories(
                credentials: credentials,
                appID: selectedApp.id
            )
            repositoryMessage = repositories.isEmpty ? "No repositories were returned." : nil
        } catch {
            repositories = []
            repositoryMessage = sanitizedMessage(for: error)
        }
    }

    func refreshBuildRuns() async {
        guard hasCompleteCredentials, let credentials else {
            errorMessage = "Credentials are missing."
            buildRuns = []
            return
        }

        isLoadingBuildRuns = true
        defer { isLoadingBuildRuns = false }

        // Fast path: one portfolio request across all apps/workflows.
        do {
            let runs = try await apiClient.fetchPortfolioBuildRuns(
                credentials: credentials,
                limit: 200
            )
            buildRuns = runs.filter(Self.isRunFromToday)
            errorMessage = nil
            lastUpdated = Date()
            return
        } catch {
            // Fallback to per-app fan-out when portfolio endpoint is unavailable.
        }

        var mergedRuns: [BuildRunSummary] = []
        var partialErrors: [String] = []

        if availableApps.isEmpty {
            await loadApps()
        }

        let appsToMonitor = availableApps
        guard !appsToMonitor.isEmpty else {
            errorMessage = "No apps are available for these credentials."
            buildRuns = []
            return
        }

        for app in appsToMonitor {
            do {
                let appRuns = try await apiClient.fetchLatestBuildRuns(
                    credentials: credentials,
                    appID: app.id,
                    limit: 20
                )
                mergedRuns.append(contentsOf: appRuns.map { $0.withApp(app) })
            } catch {
                partialErrors.append("\(app.name): \(sanitizedMessage(for: error))")
            }
        }

        let runs = mergedRuns
            .filter(Self.isRunFromToday)
            .sorted(by: Self.sortRuns)

        if !partialErrors.isEmpty {
            errorMessage = "Some apps could not be refreshed."
        } else {
            errorMessage = nil
        }

        buildRuns = runs
        lastUpdated = Date()
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

    func configureLiveStatusPolling(enabled: Bool, endpoint: String, intervalSeconds: TimeInterval) {
        liveStatusTask?.cancel()
        liveStatusTask = nil
        isPollingLiveStatus = false

        guard enabled else {
            liveStatusEndpointURL = nil
            lastRegisteredDeviceSubscription = nil
            Task { [weak self] in
                await self?.liveStatusDeviceRegistrationClient.setEndpointURL(nil)
            }
            liveStatusMessage = nil
            Task { [weak self] in
                await self?.liveActivityManager.end()
            }
            return
        }

        guard let endpointURL = URL(string: endpoint),
              let scheme = endpointURL.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            liveStatusEndpointURL = nil
            lastRegisteredDeviceSubscription = nil
            Task { [weak self] in
                await self?.liveStatusDeviceRegistrationClient.setEndpointURL(nil)
            }
            liveStatus = nil
            liveStatusMessage = "Set a valid status endpoint URL."
            return
        }

        liveStatusEndpointURL = endpointURL
        let interval = max(10, intervalSeconds)
        isPollingLiveStatus = true

#if os(iOS)
        ensureRemoteNotificationRegistration()
#endif

        let deviceRegistrationEndpoint = Self.derivedDeviceRegistrationEndpoint(from: endpointURL)
        Task { [weak self] in
            guard let self else { return }
            self.lastRegisteredDeviceSubscription = nil
            await self.liveStatusDeviceRegistrationClient.setEndpointURL(deviceRegistrationEndpoint)
            await self.registerDeviceForWakeNotificationsIfNeeded()
        }

        liveStatusTask = Task { [weak self] in
            guard let self else { return }

            await self.refreshLiveStatus(endpointURL: endpointURL)

            while !Task.isCancelled {
                let nanoseconds = UInt64(interval * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)

                guard !Task.isCancelled else { return }
                await self.refreshLiveStatus(endpointURL: endpointURL)
            }
        }
    }

    func stopLiveStatusPolling() {
        liveStatusTask?.cancel()
        liveStatusTask = nil
        isPollingLiveStatus = false
        liveStatusEndpointURL = nil
        lastRegisteredDeviceSubscription = nil
        Task { [weak self] in
            await self?.liveStatusDeviceRegistrationClient.setEndpointURL(nil)
        }
        Task { [weak self] in
            await self?.liveActivityManager.end()
        }
    }

    private func refreshLiveStatus(endpointURL: URL) async {
        let scopedAppID = liveStatusScopeAppID()
        let activityAppID = scopedAppID ?? "all-apps"
        let activityAppName = scopedAppID == nil ? "All Apps" : (selectedApp?.name ?? "Selected App")

        do {
            let status = try await liveStatusClient.fetchStatus(
                endpointURL: endpointURL,
                appID: scopedAppID
            )
            liveStatus = status
            liveStatusMessage = nil

            await liveActivityManager.update(
                appID: activityAppID,
                appName: activityAppName,
                runningCount: status.runningCount,
                singleBuildStartedAt: status.singleBuildStartedAt
            )
        } catch {
            liveStatusMessage = sanitizedMessage(for: error)
        }
    }

    private func reloadAfterCredentialUpdate() async {
        if !hasCompleteCredentials {
            availableApps = []
            selectedApp = nil
            buildRuns = []
            workflows = []
            compatibilityMatrix = nil
            repositories = []
            clearSelectedAppDefaults()
            errorMessage = "Credentials are missing."
            buildTriggerMessage = "Credentials are missing."
            compatibilityMessage = "Credentials are missing."
            repositoryMessage = "Credentials are missing."
            stopAutoRefresh()
            stopLiveStatusPolling()
            return
        }

        await refreshBuildRuns()

        await loadApps()
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

    private func persistDashboardFilterAppID(_ appID: String?) {
        if let appID {
            userDefaults.set(appID, forKey: DefaultsKey.dashboardFilterAppID)
        } else {
            userDefaults.removeObject(forKey: DefaultsKey.dashboardFilterAppID)
        }
    }

    private func loadDashboardFilterAppFromDefaults() {
        dashboardFilterAppID = userDefaults.string(forKey: DefaultsKey.dashboardFilterAppID)
    }

    private func bootstrapLiveStatusConfigurationFromDefaults() {
        let isEnabled = userDefaults.bool(forKey: DefaultsKey.liveStatusEnabled)
        let endpoint = userDefaults.string(forKey: DefaultsKey.liveStatusEndpointURL) ?? ""
        let interval = userDefaults.object(forKey: DefaultsKey.liveStatusPollIntervalSeconds) as? Double ?? 30
        configureLiveStatusPolling(
            enabled: isEnabled,
            endpoint: endpoint,
            intervalSeconds: interval
        )
    }

    private static func derivedDeviceRegistrationEndpoint(from statusEndpoint: URL) -> URL? {
        guard var components = URLComponents(url: statusEndpoint, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.query = nil
        components.fragment = nil

        let path = components.path.isEmpty ? "/status.php" : components.path
        let directory = (path as NSString).deletingLastPathComponent
        let normalizedDirectory = directory.isEmpty ? "/" : directory
        components.path = (normalizedDirectory as NSString).appendingPathComponent("register_device.php")
        return components.url
    }

#if os(iOS)
    private func ensureRemoteNotificationRegistration() {
        guard !hasRequestedRemoteNotifications else { return }
        hasRequestedRemoteNotifications = true
        UIApplication.shared.registerForRemoteNotifications()
    }
#endif

    private func handleRemoteDeviceTokenUpdate(_ token: String) async {
        latestRemoteDeviceToken = token
        await registerDeviceForWakeNotificationsIfNeeded()
    }

    private func handleLiveStatusWakeNotification() async {
        guard isPollingLiveStatus, let endpointURL = liveStatusEndpointURL else { return }
        await refreshLiveStatus(endpointURL: endpointURL)
    }

    private func registerDeviceForWakeNotificationsIfNeeded() async {
        guard isPollingLiveStatus,
              liveStatusEndpointURL != nil,
              let latestRemoteDeviceToken,
              let appBundleID = Bundle.main.bundleIdentifier else {
            return
        }

        let registrationAppID = liveStatusScopeAppID()
        let scopeKey = registrationAppID ?? "__all_apps__"
        let candidate = DeviceSubscription(appID: scopeKey, token: latestRemoteDeviceToken)
        guard candidate != lastRegisteredDeviceSubscription else { return }

        do {
            try await liveStatusDeviceRegistrationClient.registerDevice(
                appID: registrationAppID,
                deviceToken: latestRemoteDeviceToken,
                appBundleID: appBundleID
            )
            lastRegisteredDeviceSubscription = candidate
        } catch {
            liveStatusMessage = sanitizedMessage(for: error)
        }
    }

    private func liveStatusScopeAppID() -> String? {
        guard monitoringMode == .singleApp else { return nil }
        return selectedApp?.id
    }

    func sanitizedMessage(for error: Error) -> String {
        if let known = error as? AppStoreConnectClientError {
            return known.localizedDescription
        }

        if let known = error as? CIRunningBuildStatusClientError {
            return known.localizedDescription
        }

        if let known = error as? LiveStatusDeviceRegistrationError {
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

    private static func sortRunsByLastRun(lhs: BuildRunSummary, rhs: BuildRunSummary) -> Bool {
        let lhsDate = lhs.finishedDate ?? lhs.startedDate ?? lhs.createdDate ?? .distantPast
        let rhsDate = rhs.finishedDate ?? rhs.startedDate ?? rhs.createdDate ?? .distantPast

        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }

        return sortRuns(lhs: lhs, rhs: rhs)
    }

    private static func isRunFromToday(_ run: BuildRunSummary) -> Bool {
        let referenceDate = run.createdDate ?? run.startedDate ?? run.finishedDate
        guard let referenceDate else { return false }
        return Calendar.current.isDateInToday(referenceDate)
    }

    private var dashboardFilteredRuns: [BuildRunSummary] {
        guard let dashboardFilterAppID else { return buildRuns }
        return buildRuns.filter { $0.app?.id == dashboardFilterAppID }
    }
}
