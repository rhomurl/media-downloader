import Testing
@testable import DownloaderCore

@Test func cookieAccessIsAnExplicitChoice() {
    #expect(CookieBrowser.allCases.map(\.rawValue) == ["none", "chrome", "brave", "firefox"])
    #expect(OutputPreset.allCases.map(\.rawValue) == ["mp4", "mp3"])
}
