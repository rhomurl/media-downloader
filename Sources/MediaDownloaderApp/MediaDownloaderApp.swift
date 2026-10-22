import SwiftUI
import DownloaderPresentation

@MainActor enum AppSession {
    // Shared by every scene and the quit delegate. Initialization launches no tools.
    static let model = AppModel.live()
}

@main struct MediaDownloaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppSession.model
    var body: some Scene {
        Window("Media Downloader", id: "main") {
            MainView(model: model)
                .task { if model.dependencyReport == nil { await model.checkDependencies() } }
        }
        .defaultSize(width: 620, height: 720)
        Settings { DependencyView(model: model, allowsOverrides: true).padding(24).frame(minWidth: 520) }
    }
}
