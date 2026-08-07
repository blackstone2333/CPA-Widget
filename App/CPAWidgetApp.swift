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

        MenuBarQuotaScene(
            model: appDelegate.model,
            presentation: appDelegate.model.menuBarPresentation
        )
    }
}

private struct MenuBarQuotaScene: Scene {
    let model: AppModel
    @ObservedObject var presentation: MenuBarPresentationState

    var body: some Scene {
        MenuBarExtra(isInserted: Binding(
            get: { presentation.isInserted },
            set: { isEnabled in
                var configuration = model.menuBarConfiguration
                configuration.isEnabled = isEnabled
                model.updateMenuBarConfiguration(configuration)
            }
        )) {
            MenuBarQuotaPanel()
                .environmentObject(model)
        } label: {
            MenuBarQuotaStatusItem()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.window)
    }
}
