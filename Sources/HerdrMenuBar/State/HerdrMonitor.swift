import AppKit
import Foundation

/// Status arrives by push, but the set of panes is reconciled on a timer: Herdr's
/// lifecycle subscriptions replay the whole event buffer, so they can't be treated as news.
@MainActor
final class HerdrMonitor: ObservableObject {
    @Published private(set) var agents: [Agent] = []
    @Published private(set) var isConnected = false
    @Published private(set) var lastError: String?
    @Published private var workspaces: [String: Workspace] = [:]

    nonisolated private static let reconcileInterval: TimeInterval = 5
    nonisolated private static let initialBackoffSeconds: UInt32 = 1
    nonisolated private static let maxBackoffSeconds: UInt32 = 15
    nonisolated private static let threadStackSize = 512 * 1024

    private var monitorThread: Thread?
    private let settings: Settings
    private let notificationPolicy: NotificationPolicy
    nonisolated private let client = HerdrClient()
    private var hasConnectedOnce = false
    private var autoQuitTask: Task<Void, Never>?

    // Snapshot and status-change Tasks are handed to the main actor unstructured,
    // so they can run out of order. The monitor thread stamps each hand-off with
    // a sequence at initiation (only it writes this counter) and the apply sites
    // drop anything stale: a snapshot requested before an event was read carries
    // older state than that event even when its Task runs later. Without this,
    // a late snapshot reverted a pushed status and the next reconcile
    // re-announced the transition as a duplicate notification.
    nonisolated(unsafe) private var handoffSequence = 0
    private var lastAppliedSequence = 0
    private var lastEventSequence: [String: Int] = [:]

    init(settings: Settings, notifier: Notifier) {
        self.settings = settings
        notificationPolicy = NotificationPolicy(settings: settings, notifier: notifier)
    }

    func start() {
        guard monitorThread == nil else { return }
        let thread = Thread { [weak self] in self?.runConnectionLoop() }
        thread.name = "herdr.monitor"
        thread.stackSize = Self.threadStackSize
        monitorThread = thread
        thread.start()
    }

    var summaryStatus: AgentStatus {
        for status in [AgentStatus.blocked, .done, .working]
        where agents.contains(where: { $0.status == status }) {
            return status
        }
        return .idle
    }

    var agentsByWorkspace: [(workspace: Workspace, agents: [Agent])] {
        Dictionary(grouping: agents, by: \.workspaceID)
            .map { id, agents in
                (workspaces[id] ?? Workspace(workspaceID: id, label: nil, number: nil),
                 agents.sorted(by: Self.ordering))
            }
            .sorted { Self.tabStripOrdering($0.workspace, $1.workspace) }
    }

    // MARK: - Background connection

    nonisolated private func runConnectionLoop() {
        var backoff = Self.initialBackoffSeconds
        while true {
            do {
                try streamUntilPaneSetChanges()
                backoff = Self.initialBackoffSeconds
            } catch {
                reportDisconnected(error)
                sleep(backoff)
                backoff = min(backoff * 2, Self.maxBackoffSeconds)
            }
        }
    }

    nonisolated private func streamUntilPaneSetChanges() throws {
        let paneIDs = try resync()
        let stream = try client.subscribeToStatusChanges(of: paneIDs)
        Log.debug("subscribed over \(paneIDs.count) panes")
        reportConnected()

        var lastReconcile = Date()
        while true {
            if case .statusChange(let change) = try stream.next() {
                handoffSequence += 1
                let sequence = handoffSequence
                Task { @MainActor [weak self] in self?.apply(change, sequence: sequence) }
            }
            // Checked every iteration, not only on timeout, so a busy stream can't starve it.
            guard Date().timeIntervalSince(lastReconcile) >= Self.reconcileInterval else { continue }
            lastReconcile = Date()
            let current = try resync()
            if Set(current) != Set(paneIDs) {
                Log.debug("pane set changed (\(paneIDs.count) -> \(current.count)); resubscribing")
                return
            }
        }
    }

    nonisolated private func resync() throws -> [String] {
        handoffSequence += 1
        let sequence = handoffSequence
        let snapshot = try client.snapshot()
        Task { @MainActor [weak self] in self?.apply(snapshot, sequence: sequence) }
        return snapshot.paneIDs
    }

    nonisolated private func reportConnected() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isConnected = true
            self.lastError = nil
            self.hasConnectedOnce = true
            self.autoQuitTask?.cancel()
            self.autoQuitTask = nil
        }
    }

    nonisolated private func reportDisconnected(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        Log.debug("connection ended: \(message)")
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isConnected = false
            self.lastError = message
            if self.hasConnectedOnce && self.settings.quitOnServerStop {
                self.scheduleAutoQuit()
            }
        }
    }

    private func scheduleAutoQuit() {
        guard autoQuitTask == nil else { return }
        Log.debug("Herdr connection lost after active session; scheduling auto-quit in 3 seconds")
        autoQuitTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, let self, !self.isConnected, self.settings.quitOnServerStop else { return }
            Log.debug("terminating app because Herdr server stopped")
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - State application

    private func apply(_ snapshot: Snapshot, sequence: Int) {
        guard sequence > lastAppliedSequence else { return }
        lastAppliedSequence = sequence
        let byID = Dictionary(snapshot.workspaces.map { ($0.workspaceID, $0) },
                              uniquingKeysWith: { _, latest in latest })
        if workspaces != byID { workspaces = byID }
        replaceAgents(snapshot.agents)
        // Panes that vanished no longer need their last event sequence.
        let live = Set(agents.map(\.paneID))
        lastEventSequence = lastEventSequence.filter { live.contains($0.key) }
    }

    private func replaceAgents(_ incoming: [Agent]) {
        let sorted = incoming.sorted(by: Self.ordering)
        // Republishing an identical list restarts the panel's animations, and
        // reconcile runs every few seconds, so the dropdown would never settle.
        guard sorted != agents else { return }

        // Decode dedupes pane ids; `uniquingKeysWith` keeps a malformed
        // snapshot from crashing here anyway.
        let previousStatuses = Dictionary(agents.map { ($0.paneID, $0.status) },
                                          uniquingKeysWith: { _, latest in latest })
        agents = sorted
        Log.debug("agent list changed (\(sorted.count) agents)")
        announceBlockedTransitions(since: previousStatuses)
    }

    /// A reconcile can reveal a transition no push event covered.
    private func announceBlockedTransitions(since previousStatuses: [String: AgentStatus]) {
        for agent in agents where agent.status == .blocked {
            if let previous = previousStatuses[agent.paneID], previous != .blocked {
                announce(agent, from: previous)
            }
        }
    }

    private func apply(_ change: StatusChange, sequence: Int) {
        guard let index = agents.firstIndex(where: { $0.paneID == change.paneID }) else { return }
        let previous = agents[index].status
        guard change.status != previous else { return }
        // Same-pane events are last-writer-wins; events for different panes
        // all apply even when their Tasks reorder.
        guard sequence > (lastEventSequence[change.paneID] ?? 0) else { return }
        lastEventSequence[change.paneID] = sequence
        lastAppliedSequence = max(lastAppliedSequence, sequence)
        Log.debug("status \(change.paneID): \(previous.rawValue) -> \(change.status.rawValue)")
        agents[index].status = change.status
        if let title = change.title, !title.isEmpty { agents[index].title = title }
        if let kind = change.displayAgent, !kind.isEmpty { agents[index].kind = kind }
        announce(agents[index], from: previous)
        agents.sort(by: Self.ordering)
    }

    private func announce(_ agent: Agent, from previous: AgentStatus) {
        notificationPolicy.announce(agent, from: previous,
                                    workspaceName: workspaces[agent.workspaceID]?.displayName)
    }

    // MARK: - Ordering

    /// Order never depends on status, so the row under the cursor doesn't move
    /// when an agent changes state; colour carries urgency instead.
    nonisolated private static func ordering(_ a: Agent, _ b: Agent) -> Bool {
        if a.workspaceID != b.workspaceID { return a.workspaceID < b.workspaceID }
        if a.paneNumber != b.paneNumber {
            return (a.paneNumber ?? .max) < (b.paneNumber ?? .max)
        }
        return a.paneID < b.paneID
    }

    nonisolated private static func tabStripOrdering(_ a: Workspace, _ b: Workspace) -> Bool {
        let left = a.number ?? .max
        let right = b.number ?? .max
        if left != right { return left < right }
        return a.workspaceID < b.workspaceID
    }
}
