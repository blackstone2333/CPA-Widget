import AppKit

@MainActor
final class CPAApplicationDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var menuBarController: MenuBarStatusController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarStatusController(model: model)
        Task { await model.launch() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
