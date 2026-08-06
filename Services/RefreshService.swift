import Foundation

@MainActor
final class RefreshService {
    private var refreshTask: Task<Void, Never>?
    private var backgroundScheduler: NSBackgroundActivityScheduler?
    private var lastExecution = Date.distantPast

    func start(
        interval: TimeInterval,
        operation: @escaping @MainActor @Sendable () async -> Void
    ) {
        stop()
        let effectiveInterval = max(interval, 5 * 60)
        lastExecution = Date()
        refreshTask = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(effectiveInterval))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await executeIfDue(interval: effectiveInterval, operation: operation)
            }
        }

        let scheduler = NSBackgroundActivityScheduler(identifier: "com.cpawidget.quota-refresh")
        scheduler.interval = effectiveInterval
        scheduler.tolerance = min(60, effectiveInterval * 0.1)
        scheduler.repeats = true
        scheduler.qualityOfService = .utility
        scheduler.schedule { [weak self] completion in
            Task { @MainActor in
                guard let self else {
                    completion(.deferred)
                    return
                }
                await self.executeIfDue(interval: effectiveInterval, operation: operation)
                completion(.finished)
            }
        }
        backgroundScheduler = scheduler
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        backgroundScheduler?.invalidate()
        backgroundScheduler = nil
    }

    deinit {
        refreshTask?.cancel()
        backgroundScheduler?.invalidate()
    }

    private func executeIfDue(
        interval: TimeInterval,
        operation: @escaping @MainActor @Sendable () async -> Void
    ) async {
        guard Date().timeIntervalSince(lastExecution) >= interval * 0.8 else { return }
        lastExecution = Date()
        await operation()
    }
}
