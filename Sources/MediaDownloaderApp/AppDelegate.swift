import AppKit
import DownloaderPresentation

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppSession.model
    private var terminationPending = false
    private var replied = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminationPending { return .terminateLater }
        terminationPending = true
        Task { [self] in
            await model.shutdown()
            guard !replied else { return }
            replied = true
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
