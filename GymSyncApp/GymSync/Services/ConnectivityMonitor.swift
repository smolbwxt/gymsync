import Foundation
import Network

/// App-wide network reachability signal, backed by `NWPathMonitor`.
///
/// Singleton (matches `AppState.shared`/`AuthService`'s convention — see
/// `AppState.swift`'s doc comment) rather than a per-View `@State` instance,
/// so any screen can read `isOnline` directly without RootView needing to
/// thread a new environment value through the tab hierarchy. Verified no
/// existing reachability signal before adding this (Canvas Completion
/// Task 4 — `docs/superpowers/plans/2026-07-13-gym-sync-canvas-completion.md`).
///
/// `isOnline` starts `true` (optimistic) so nothing offline-shaped flashes
/// on cold launch before the monitor's first callback fires.
@Observable
@MainActor
final class ConnectivityMonitor {
    static let shared = ConnectivityMonitor()

    private(set) var isOnline: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "app.gymsync.connectivity-monitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                self?.isOnline = online
            }
        }
        monitor.start(queue: queue)
    }
}
