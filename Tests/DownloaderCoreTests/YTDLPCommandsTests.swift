import Foundation
import Testing
@testable import DownloaderCore

struct YTDLPCommandsTests {
    let builder = YTDLPCommands(tools: TestSupport.tools)
    let staging = URL(fileURLWithPath: "/synthetic/destination/.job-staging", isDirectory: true)

    @Test func pastedURLStaysOneArgument() throws {
        let request = PreviewRequest(rawURL: "https://example.com/watch?v=1&x=$(touch%20bad)", browser: .chrome)
        let command = try builder.preview(request)
        #expect(Array(command.arguments.suffix(2)) == ["--", request.rawURL])
        #expect(command.executable == TestSupport.tools.ytdlp)
        for flag in ["--ignore-config", "--no-plugin-dirs", "--no-remote-components", "--no-js-runtimes", "--no-playlist", "--no-colors"] {
            #expect(command.arguments.contains(flag))
        }
        #expect(command.timeout == .seconds(60))
        #expect(command.maximumLineBytes == 16 * 1_024 * 1_024)
        #expect(command.arguments.contains("deno:/synthetic/runtime/deno"))
        for pair in [["--ffmpeg-location", "/synthetic/bin"], ["--socket-timeout", "20"], ["--retries", "2"], ["--fragment-retries", "2"]] {
            let index = try #require(command.arguments.firstIndex(of: pair[0]))
            #expect(command.arguments[index + 1] == pair[1])
        }
        #expect(Array(command.arguments.suffix(7).prefix(5)) == ["--dump-single-json", "--skip-download", "--flat-playlist", "--playlist-end", "1"])
    }

    @Test func noCookieDefaultAndControlledEnvironment() throws {
        let command = try builder.preview(PreviewRequest(rawURL: "https://example.com/video", browser: .none))
        #expect(!command.arguments.contains("--cookies-from-browser"))
        #expect(command.environment["HOME"] == FileManager.default.homeDirectoryForCurrentUser.path)
        #expect(command.environment["PATH"] == "/synthetic/bin:/synthetic/runtime:/usr/bin:/bin:/usr/sbin:/sbin")
        #expect(Set(command.environment.keys).isSubset(of: ["PATH", "HOME", "LANG"]))
    }

    @Test(arguments: [CookieBrowser.chrome, .firefox, .brave])
    func sameExplicitBrowserForBothOperations(_ browser: CookieBrowser) throws {
        let request = PreviewRequest(rawURL: "https://example.com/video", browser: browser, braveProfileID: "Profile 1")
        let expected = browser == .brave ? "brave:Profile 1" : browser.rawValue
        for command in [try builder.preview(request), try builder.download(request, preset: .mp4, staging: staging)] {
            let index = try #require(command.arguments.firstIndex(of: "--cookies-from-browser"))
            #expect(command.arguments[index + 1] == expected)
        }
    }

    @Test func braveRequiresSelection() {
        #expect(throws: AppIssue.profileRequired) {
            try builder.preview(PreviewRequest(rawURL: "https://example.com/video", browser: .brave))
        }
    }

    @Test func defaultBraveProfileIsPassedExplicitly() throws {
        let command = try builder.preview(PreviewRequest(rawURL: "https://example.com/video", browser: .brave, braveProfileID: "Default"))
        #expect(command.arguments.contains("brave:Default"))
    }

    @Test func nonlocalToolAndStagingAreRejected() {
        let tools = ResolvedTools(ytdlp: URL(string: "https://example.com/tool")!, ffmpeg: TestSupport.tools.ffmpeg, ffprobe: TestSupport.tools.ffprobe, deno: TestSupport.tools.deno)
        #expect(throws: AppIssue.dependency) { try YTDLPCommands(tools: tools).preview(PreviewRequest(rawURL: "https://example.com/video", browser: .none)) }
        #expect(throws: AppIssue.destination) { try builder.download(PreviewRequest(rawURL: "https://example.com/video", browser: .none), preset: .mp4, staging: URL(string: "https://example.com/staging")!) }
    }

    @Test(arguments: ["../Default", "/tmp/Default", "Default:secret", "Profile 1\u{0}", "Guest Profile", "Profile -1", "Profile ", "Default\n"])
    func rejectsUntrustedProfile(_ id: String) {
        #expect(throws: AppIssue.browserAccess) {
            try builder.download(PreviewRequest(rawURL: "https://example.com/video", browser: .brave, braveProfileID: id), preset: .mp3, staging: staging)
        }
    }

    @Test func downloadHasStrictPresetAndControlTemplates() throws {
        let request = PreviewRequest(rawURL: "https://example.com/video", browser: .none)
        let command = try builder.download(request, preset: .mp4, staging: staging)
        #expect(command.timeout == nil)
        #expect(command.maximumLineBytes == 65_536)
        for value in ["--no-simulate", "--newline", "--progress", "--no-overwrites", "--no-post-overwrites", #"download:MD_DOWNLOAD:{"progress":%(progress)j,"stream_id":%(info.format_id|"")j}"#, "postprocess:MD_POSTPROCESS:%(progress)j", "after_move:MD_FINAL:%(filepath)j", "/synthetic/destination/.job-staging/media.%(ext)s", "bv[vcodec^=avc1]+ba[acodec^=mp4a]/b[vcodec^=avc1][acodec^=mp4a]"] {
            #expect(command.arguments.contains(value))
        }
        #expect(!command.arguments.contains("--recode-video"))
        #expect(!command.arguments.contains("--ignore-errors"))
        let audio = try builder.download(request, preset: .mp3, staging: staging)
        #expect(Array(audio.arguments.suffix(9)) == ["-f", "ba/b", "-x", "--audio-format", "mp3", "--audio-quality", "2", "--", request.rawURL])
    }

    @Test func destinationPercentIsLiteralAndMetadataDoesNotBecomeOutputTemplate() throws {
        let metadata = try MetadataDecoder.decode(TestSupport.fixture("single-video"))
        #expect(metadata.title.contains("%(title)s"))
        let request = PreviewRequest(rawURL: "https://example.com/video", browser: .none)
        let command = try builder.download(request, preset: .mp4,
            staging: URL(fileURLWithPath: "/synthetic/%(title)s/.job-staging"))
        let output = try #require(command.arguments.firstIndex(of: "-o"))
        #expect(command.arguments[output + 1] == "/synthetic/%%(title)s/.job-staging/media.%(ext)s")
        #expect(!command.arguments.contains(metadata.title))
    }

    @Test func unknownCodecFixtureDoesNotWidenSelection() throws {
        // The fixture's direct MP4 has unknown codecs. Only verified codec
        // labels qualify; container extension alone must not widen selection.
        _ = try MetadataDecoder.decode(TestSupport.fixture("single-video"))
        let command = try builder.download(PreviewRequest(rawURL: "https://example.com/direct.mp4", browser: .none), preset: .mp4, staging: staging)
        let format = try #require(command.arguments.firstIndex(of: "-f"))
        #expect(command.arguments[format + 1] == "bv[vcodec^=avc1]+ba[acodec^=mp4a]/b[vcodec^=avc1][acodec^=mp4a]")
        #expect(!command.arguments.contains("--recode-video"))
    }
}
