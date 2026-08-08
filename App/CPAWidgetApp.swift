import SwiftUI

@main
struct CPAWidgetApp: App {
    @NSApplicationDelegateAdaptor(CPAApplicationDelegate.self) private var appDelegate

    var body: some Scene {
        Window("CPA Widget", id: "main") {
            ContentView()
                .environmentObject(appDelegate.model)
                .frame(minWidth: 920, minHeight: 720)
        }
        .defaultSize(width: 1120, height: 900)
    }
}
