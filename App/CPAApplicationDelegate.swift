import AppKit

@MainActor
final class CPAApplicationDelegate: NSObject, NSApplicationDelegate {
    private static let lastLaunchedBuildKey = "CPAWidgetLastLaunchedBuild"

    let model = AppModel()
    private var menuBarController: MenuBarStatusController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        restartWidgetExtensionAfterUpdateIfNeeded()
        menuBarController = MenuBarStatusController(model: model)
        Task { await model.launch() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// WidgetKit can keep the previous extension process alive after the app
    /// bundle is replaced. Restart it once per build so timeline reloads use
    /// the extension and shared-cache contract shipped with this installation.
    private func restartWidgetExtensionAfterUpdateIfNeeded() {
        guard let currentBuild = Bundle.main.object(
            forInfoDictionaryKey: kCFBundleVersionKey as String
        ) as? String else { return }

        let defaults = UserDefaults.standard
        guard defaults.string(forKey: Self.lastLaunchedBuildKey) != currentBuild else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        process.arguments = ["-x", "CPA Widget Extension"]

        do {
            try process.run()
            process.waitUntilExit()
            defaults.set(currentBuild, forKey: Self.lastLaunchedBuildKey)
        } catch {
            // Retry on the next launch if the system tool could not be run.
        }
    }
}
