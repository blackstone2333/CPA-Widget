import SwiftUI

@main
struct CPAWidgetApp: App {
    @NSApplicationDelegateAdaptor(CPAApplicationDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 920, minHeight: 720)
                .onOpenURL { url in
                    guard url.scheme == "cpawidget", url.host == "refresh" else { return }
                    Task { await model.refreshQuota() }
                }
        }
        .defaultSize(width: 1120, height: 900)

        Settings {
            ContentView()
                .environmentObject(model)
                .frame(width: 980, height: 760)
        }
    }
}
