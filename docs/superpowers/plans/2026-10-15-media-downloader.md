# Personal macOS Media Downloader Implementation Plan

Execution status (2026-10-23): all eight tasks implemented and independently reviewed using the user-selected subagent workflow. See [verification evidence](../../VERIFICATION.md) for completed local/public checks and pending private/browser/platform checks. The checklist below is the original execution plan.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Execution method awaits the user's choice; do not dispatch agents or start product implementation before that choice.

**Goal:** Build a personal native macOS app that previews one video URL and downloads compatible MP4 video or MP3 audio, optionally using explicitly selected browser cookies.

**Architecture:** A Swift package separates a testable core from a SwiftUI application. The core resolves external Homebrew tools, builds argument arrays, runs cancellable process groups, decodes structured events, and publishes verified files. A main-actor model presents the coordinator's snapshots; views never launch subprocesses.

**Tech Stack:** Swift 6.2 language mode, SwiftUI/AppKit, Foundation, Darwin POSIX APIs, Swift Testing, external yt-dlp/FFmpeg/FFprobe/Deno. Target macOS 14+ for the app; verification in this project initially covers this Apple Silicon macOS 26.6.2 machine only. No third-party Swift package dependencies.

**Spec:** [Approved design](../specs/2026-10-15-media-downloader-design.md). Read it with this plan. [Review and original evidence](../../PLAN-REVIEW.md).

**Execution:** User selected subagent-driven execution. During execution the user requested an explicit Brave profile picker; Tasks 3/6/7 incorporate that refinement. Task 1 supplies `scripts/test.sh` to accommodate this installed Command Line Tools' Testing framework; substitute `bash scripts/test.sh` for bare `swift test` in every subsequent command, including the integration harness.

## Global Constraints

The following requirements are copied from the approved spec and apply to every task:

- "No shell startup scripts."
- "Ignore user config and default plugin directories."
- "Disallow automatic remote component fetching; missing EJS produces a setup error."
- "Preview has a 60-second deadline; download has explicit cancel and bounded network retries rather than a short overall deadline."
- "Only the current operation may transition state."
- "Disable cancellation for the brief atomic publication operation so a completed file is not ambiguously reported as cancelled."
- "Never overwrite an existing file."
- "Delete only the owned staging directory after children stop; a crash may leave a directory to clean manually in v1."
- "No cookie export/import or cookie-content persistence in v1."
- "No automatic updates or installs."
- "No queues, batch files, collection downloads, subtitles, Safari, generic transcoding, bundled runtimes, automatic updates, account management, telemetry, or distribution packaging."

Additional fixed implementation decisions: one preview or download at a time; metadata line limit 16 MiB, other line limit 64 KiB, transient diagnostic tail 64 KiB; SIGTERM grace 2 seconds before SIGKILL; dependency/probe timeout 15 seconds; socket timeout 20 seconds, retries 2 and fragment retries 2. Timers use a monotonic clock. Unknown errors show fixed safe copy rather than raw tool output. These limits are explicit policies to test, not guarantees that every site responds within them.

## Review Focus

1. A title containing percent placeholders, emoji, or path separators must never change command options or the output template — Tasks 3 and 5.
2. An FFmpeg-like descendant ignoring SIGTERM must stop after Cancel/Quit, including when its parent exits first — Task 2 and coordinator checks in Task 6.
3. Finder launch with a minimal PATH and a moved/deleted destination must produce setup/destination errors while preserving existing files — Tasks 4, 5, and 8.
4. URL/browser edits while metadata is returning must never reuse stale metadata or cookies; retry must capture the intended input — Task 6.
5. An exit-zero job with a forged final path, missing audio, wrong codec, or failed publication must never show success — Tasks 5, 6, and 8.

## File map

All paths below are relative to the repository root. Keep responsibilities in the listed files rather than building one large service.

| Files | Responsibility |
|---|---|
| `Package.swift`, `.gitignore`, `README.md`, `AGENTS.md`, `CLAUDE.md` | Build/test contract and persistent project guidance |
| `Sources/DownloaderCore/Models.swift` | Shared immutable values and safe public errors |
| `Sources/DownloaderCore/ProcessCommand.swift` | Executable/argument/environment/timeout values and runner protocol |
| `Sources/DownloaderCore/ProcessRunner.swift`, `LineFramer.swift` | Process groups, pipes, cancellation, incremental byte framing |
| `Sources/ProcessFixture/main.swift` | Developer-only subprocess test helper; excluded from `.app` |
| `Sources/DownloaderCore/URLValidator.swift`, `YTDLPCommands.swift`, `YTDLPEvents.swift`, `MetadataDecoder.swift`, `BraveProfiles.swift` | URL policy, commands, events, metadata validation, opt-in profile display-name discovery |
| `Sources/DownloaderCore/DependencyResolver.swift`, `DependencyDiagnostics.swift` | Tool discovery and offline capability report |
| `Sources/DownloaderCore/JobFiles.swift`, `ArtifactVerifier.swift` | Owned staging, safe names, codec checks, atomic publication |
| `Sources/DownloaderCore/JobCoordinator.swift`, `AppIssueClassifier.swift` | State, operation generations, workflow, safe error categories |
| `Sources/DownloaderPresentation/AppModel.swift` | Testable main-actor presentation state and injected native actions |
| `Sources/MediaDownloaderApp/MediaDownloaderApp.swift`, `MainView.swift`, `DependencyView.swift`, `PreviewView.swift`, `DownloadStatusView.swift`, `AppDelegate.swift` | Native window, controls, quit lifecycle |
| `scripts/build-app.sh`, `scripts/verify.sh`, `scripts/integration.py` | Local bundle, verification, credential-free loopback integration |
| `Resources/Info.plist` | App bundle identity and minimum macOS version |
| `Tests/DownloaderCoreTests/*Tests.swift`, `TestSupport.swift`, `ScriptedRunner.swift`, `Fixtures/*.json` | Unit/process/coordinator/artifact fixtures |
| `docs/VERIFICATION.md` | Observed test results and explicit remaining limits |

No tools, keys, URLs, cookies, staging media, or generated build products enter Git. `ProcessFixture` and Python are development tools, not runtime app requirements. `integration.py` uses Python's standard library; resolve `python3` at invocation and fail clearly if unavailable.

## Shared interfaces

Define the following contracts in Task 1 so subsequent tasks use identical names. Domain values are `Sendable`; structs carrying data are `Equatable` where useful in tests. Add memberwise public initializers for cross-target tests/app usage.

```swift
enum CookieBrowser: String, CaseIterable, Sendable { case none, chrome, brave, firefox }
enum OutputPreset: String, CaseIterable, Sendable { case mp4, mp3 }
struct PreviewRequest: Equatable, Sendable { let rawURL: String; let browser: CookieBrowser }
struct VideoMetadata: Equatable, Sendable {
    let id: String
    let title: String
    let duration: Double?
    let thumbnail: URL?
}
struct ResolvedTools: Equatable, Sendable {
    let ytdlp: URL; let ffmpeg: URL; let ffprobe: URL; let deno: URL
}
struct TransferProgress: Equatable, Sendable {
    let downloadedBytes: Double?; let totalBytes: Double?
    let totalIsEstimate: Bool; let speed: Double?; let eta: Double?
    let streamID: String?
}
enum JobPhase: Equatable, Sendable {
    case checkingDependencies, idle, previewing, ready, downloading, processing
    case validating, publishing, cancelling, succeeded, failed, cancelled
}
enum AppIssue: Error, Equatable, Sendable {
    case dependency, invalidURL, unsupported, collection, browserAccess, loginRequired
    case unavailable, formatUnavailable, network, destination, processing, timeout, unknown
}
struct JobSnapshot: Sendable {
    let operationID: UUID?; let phase: JobPhase; let metadata: VideoMetadata?
    let progress: TransferProgress?; let output: URL?; let issue: AppIssue?
    let notice: String?
}
enum ProcessStream: Sendable { case stdout, stderr }
struct ProcessLine: Sendable { let stream: ProcessStream; let bytes: Data }
struct ProcessCommand: Sendable {
    let executable: URL; let arguments: [String]; let environment: [String: String]
    let timeout: Duration?; let maximumLineBytes: Int
}
struct ProcessResult: Sendable { let exitCode: Int32 }
enum ProcessFailure: Error, Sendable { case launch(Int32), timeout, oversizedLine, read(Int32) }
protocol ProcessRunning: Sendable {
    func run(_ command: ProcessCommand,
             onLine: @escaping @Sendable (ProcessLine) async -> Void) async throws -> ProcessResult
}
```

Cancellation throws `CancellationError` only after group shutdown and pipe-reader cleanup. `run` returns nonzero exits for callers to interpret; it does not throw solely because exit status is nonzero. A timeout follows the same shutdown path and throws `ProcessFailure.timeout`. Decode process bytes only after framing a full line, so split UTF-8 is preserved. No `ProcessResult` contains raw output.

### Task 1: Establish a reproducible SwiftUI build and core contracts

**Files:** Create `Package.swift`, `.gitignore`, `README.md`, `AGENTS.md`, `CLAUDE.md`, `Sources/DownloaderCore/Models.swift`, `Sources/DownloaderCore/ProcessCommand.swift`, `Sources/MediaDownloaderApp/MediaDownloaderApp.swift`, `Tests/DownloaderCoreTests/BuildContractTests.swift`.

**Consumes:** Approved design and the installed Swift toolchain.
**Produces:** `DownloaderCore` library, `MediaDownloader` executable, shared interfaces above, and a passing SwiftUI build using the selected SDK.

- [ ] **Step 1: Establish the SDK/build boundary.** Record `swift --version`, `xcode-select -p`, and `xcrun --sdk macosx --show-sdk-path`. Prepare the package manifest with `.macOS(.v14)`, library/executable/test targets, no package dependencies, and Swift 6 mode. Add the smallest app source:

```swift
// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "MediaDownloader",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DownloaderCore", targets: ["DownloaderCore"]),
        .executable(name: "MediaDownloader", targets: ["MediaDownloaderApp"])
    ],
    targets: [
        .target(name: "DownloaderCore"),
        .executableTarget(name: "MediaDownloaderApp", dependencies: ["DownloaderCore"]),
        .testTarget(name: "DownloaderCoreTests", dependencies: ["DownloaderCore"])
    ],
    swiftLanguageModes: [.v6]
)
```

Initially `Models.swift` contains only `import Foundation` and `BuildContractTests.swift` contains only `import Testing`, ensuring targets have source files before the build check. The app source is:

```swift
import SwiftUI
@main struct MediaDownloaderApp: App {
    var body: some Scene { WindowGroup { Text("Media Downloader") } }
}
```

Run `swift build --product MediaDownloader`. Expected: SwiftUI imports and links successfully. If SDK/toolchain fails, preserve the error in `docs/VERIFICATION.md` and resolve developer setup before building core/UI layers; do not silently switch stacks.

- [ ] **Step 2: Write the first contract test before adding domain types.**

```swift
import Testing
@testable import DownloaderCore
@Test func cookieAccessIsAnExplicitChoice() {
    #expect(CookieBrowser.allCases.map(\.rawValue) == ["none", "chrome", "brave", "firefox"])
    #expect(OutputPreset.allCases.map(\.rawValue) == ["mp4", "mp3"])
}
```

Run `swift test --filter cookieAccessIsAnExplicitChoice`; expect a compile failure for missing types. Add shared contracts exactly as defined above, then rerun and expect PASS.

- [ ] **Step 3: Document and initialize the project.** Ignore `.build/`, `dist/`, `.swiftpm/`, `.DS_Store`, generated media and local diagnostics. README records build/test commands, personal external-tool scope, browser opt-in, and deferred distribution. `AGENTS.md` points to approved spec/plan and requires regression coverage for process/file safety, no implicit cookie reads, and honest live-verification limits; `CLAUDE.md` points to `AGENTS.md`. If still outside Git, use `git init -b main`. Do not add a remote or push.
- [ ] **Step 4: Run `swift test` and `swift build --product MediaDownloader`.** Record actual results. Commit only the docs, manifest, guidance, and source/test files: `git commit -m "build: establish native downloader package and contracts"` after explicitly staging those paths.

### Task 2: Implement subprocess groups, framing, and cancellation

**Files:** Create `Sources/DownloaderCore/ProcessRunner.swift`, `Sources/DownloaderCore/LineFramer.swift`, `Sources/ProcessFixture/main.swift`, `Tests/DownloaderCoreTests/ProcessRunnerTests.swift`, `Tests/DownloaderCoreTests/LineFramerTests.swift`, `Tests/DownloaderCoreTests/TestSupport.swift`; modify `Package.swift` to add developer-only `ProcessFixture` executable target/product.

**Consumes:** `ProcessCommand`, `ProcessRunning`, `ProcessResult`, `ProcessLine`, `ProcessFailure` from Task 1.
**Produces:** `actor ProcessRunner: ProcessRunning`; `struct LineFramer` with `init(limit: Int)`, `mutating func append(_ data: Data) throws -> [Data]`, `mutating func finish() throws -> [Data]`. Framing strips LF and optional CR, emits trailing bytes at EOF, and bounds incomplete lines.

- [ ] **Step 1: Add framing and lifecycle regression tests.**

```swift
@Test func splitUTF8IsFramedBeforeDecoding() throws {
    var framer = LineFramer(limit: 64)
    #expect(try framer.append(Data([0xF0, 0x9F])).isEmpty)
    let lines = try framer.append(Data([0x98, 0x80, 0x0A]))
    #expect(lines.map { String(decoding: $0, as: UTF8.self) } == ["😀"])
}
@Test func floodsBothPipesWithoutDeadlock() async throws {
    let sink = TestLineSink()
    let command = TestSupport.fixtureCommand(["flood", "2097152"])
    let result = try await ProcessRunner().run(command) { await sink.accept($0) }
    #expect(result.exitCode == 0)
    #expect(await sink.streamsSeen() == Set(["stdout", "stderr"]))
}
```

`TestLineSink` is an actor in TestSupport: `accept(_ line: ProcessLine)`, `streamsSeen() -> Set<String>`, `lines() -> [ProcessLine]`; keep only bounded fixture output in tests. `fixtureCommand(_ args: [String], timeout: Duration? = .seconds(5)) -> ProcessCommand` locates `.build/debug/ProcessFixture` under repository CWD (or `MEDIA_DOWNLOADER_FIXTURE_PATH`) and supplies safe test environment/64 KiB line limit.

Add tests for CRLF/trailing line, invalid UTF-8, a line over the cap, nonexistent executable, nonzero exit, immediate cancellation, simultaneous timeout/cancel, repeated cancellation, and EOF ordering. Run `swift test --filter 'LineFramer|ProcessRunner'`; expect failure before implementation.

- [ ] **Step 2: Implement the fixture executable and spawn contract.** Fixture modes: `flood <bytes>` writes bounded LF lines to both pipes; `sleep <seconds>` holds; `exit <code>` exits; `fork-hold` creates a child that ignores SIGTERM and reports child PID; `orphan-hold` reports such a child then lets its parent exit; `echo-arguments` prints a JSON argument array. All fixture work is local. Use raw Darwin calls in forked child paths; no Cocoa/thread work after fork.

For the real runner, use `posix_spawn` with absolute executable and argv, file actions wiring two pipes and stdin `/dev/null`, and a fresh process group. Do not wrap commands in `/bin/sh` or mutate process-global environment/CWD. Core group setup:

```swift
var attributes: posix_spawnattr_t?
let initError = posix_spawnattr_init(&attributes)
guard initError == 0 else { throw ProcessFailure.launch(initError) }
defer { posix_spawnattr_destroy(&attributes) }
let groupError = posix_spawnattr_setpgroup(&attributes, 0)
let flagsError = posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
guard groupError == 0 else { throw ProcessFailure.launch(groupError) }
guard flagsError == 0 else { throw ProcessFailure.launch(flagsError) }
```

Supply the final initialized attrs to `posix_spawn`. Own all file descriptors and close unused ends in both parent and child actions. Consume pipes concurrently on dedicated I/O queues; line handlers must not block pipe draining. Use a bounded serial event handoff and fail/stop on overflow rather than grow an unbounded AsyncStream. `waitpid` must handle EINTR and decode signal exits. Do not block Swift's cooperative executor with pipe reads or waits.

- [ ] **Step 3: Pin shutdown with child-PID tests.** Cancel the `fork-hold` run, assert its task throws `CancellationError` within 5 seconds, and use `kill(childPID, 0)` with a bounded poll to establish that it is gone. Repeat using `orphan-hold` so shutdown cannot rely on the direct parent's liveness. On cancel/timeout send SIGTERM to `-pgid`, then SIGKILL after 2 seconds if the group remains; wait for the direct child and readers before returning. Ensure natural parent exit cannot leave pipes or owned descendants alive indefinitely. Test cleanup ordering with an actor latch, not arbitrary test sleeps. Never signal a group the runner did not create.
- [ ] **Step 4: Build fixture, run tests, commit.** Run `swift build --product ProcessFixture`, then `swift test --filter 'LineFramer|ProcessRunner'`; expect PASS with no surviving fixture PIDs. Record evidence and commit `feat: run tools with bounded output and group cancellation`.

### Task 3: Define URL, command, metadata, and event contracts

**Files:** Create `URLValidator.swift`, `YTDLPCommands.swift`, `YTDLPEvents.swift`, `MetadataDecoder.swift`, `BraveProfiles.swift` in `Sources/DownloaderCore/`; extend `PreviewRequest` and `AppIssue` in `Models.swift` for the user-requested Brave profile choice; create corresponding `*Tests.swift` and fixtures `single-video.json`, `collection.json`, `metadata-missing-optionals.json`, `brave-local-state.json` under `Tests/DownloaderCoreTests/Fixtures/`; configure copied test resources in `Package.swift`.

**Consumes:** Core types and runner protocol. **Produces:** `URLValidator.validate(_ raw: String) throws -> URL`; `YTDLPCommands(tools: ResolvedTools)` with `preview(_ request: PreviewRequest) throws -> ProcessCommand` and `download(_ request: PreviewRequest, preset: OutputPreset, staging: URL) throws -> ProcessCommand`; `MetadataDecoder.decode(_ bytes: Data) throws -> VideoMetadata`; `YTDLPEventDecoder.decode(_ line: ProcessLine) -> YTDLPEvent?`.

Define `YTDLPEvent` cases `download(TransferProgress)`, `postprocess`, `finalPath(String)`, `malformed`. Decode metadata only in preview, and progress/final events only in download. Validate string size/depth through bounded input and `JSONDecoder`; malformed control JSON fails the job safely rather than silently reporting completion.

User-requested auth refinement: add `braveProfileID: String?` to `PreviewRequest` and an initializer defaulting it to nil, preserving existing callers. Add `AppIssue.profileRequired` with safe copy “Choose a Brave profile to use its login.” Define `struct BraveProfile: Identifiable, Equatable, Sendable { let id: String; let name: String }`, `protocol BraveProfileProviding: Sendable { func profiles() async throws -> [BraveProfile] }`, and `struct BraveProfileStore: BraveProfileProviding` with `init(registry: URL)` and `static func decode(_ bytes: Data) throws -> [BraveProfile]`. The default registry is `~/Library/Application Support/BraveSoftware/Brave-Browser/Local State`. Read at most 16 MiB off the main actor, parse only `profile.info_cache` keys and each `name`, accept `Default` or `Profile <digits>` IDs, exclude Guest/System profiles, and sort deterministically. Duplicate display names are disambiguated by ID in the UI. No directory enumeration, cookie/database reads, registry logging, or profile persistence. Missing/malformed registry maps to a safe browser-access error. Discovery is called only when Brave is explicitly selected, never at startup.

- [ ] **Step 1: Write failing behavioral tests.**

```swift
@Test func pastedURLStaysOneArgument() throws {
    let request = PreviewRequest(rawURL: "https://example.com/watch?v=1&x=$(touch%20bad)", browser: .chrome)
    let command = try YTDLPCommands(tools: TestSupport.tools).preview(request)
    #expect(Array(command.arguments.suffix(2)) == ["--", request.rawURL])
    #expect(command.arguments.contains("--ignore-config"))
    #expect(command.arguments.contains("--no-plugin-dirs"))
    #expect(command.arguments.contains("--cookies-from-browser"))
}
@Test func estimatedProgressDoesNotRequireAnExactTotal() {
    let line = ProcessLine(stream: .stderr,
        bytes: Data(#"MD_DOWNLOAD:{"progress":{"status":"downloading","downloaded_bytes":50,"total_bytes_estimate":100},"stream_id":"137"}"#.utf8))
    guard case .download(let value) = YTDLPEventDecoder.decode(line) else {
        Issue.record("Expected progress event"); return
    }
    #expect(value.totalIsEstimate)
    #expect(value.totalBytes == 100)
}
```

Define `TestSupport.tools` with deterministic absolute fake tool URLs. Also test `file:`, missing host, credentials in authority, newline/NUL and option-like input rejection; query preservation; no-cookie default; same browser/profile in preview/download; Brave without an explicit profile; `brave:Profile 1` kept as one argument; invalid path/colon/NUL profile IDs; fixture registry parsing without touching actual browser data; duplicate names; Guest/System exclusion; missing/malformed/oversized registry; playlist and multi-video rejection; absent duration/thumbnail; non-HTTP thumbnail rejection; live/upcoming media rejection; malicious title containing `%(title)s`, quotes and slashes; progress on either stream, null/zero/negative totals, nonfinite/invalid numbers, stream ID changes, and JSON-escaped final paths. Run filtered tests and expect failure.

- [ ] **Step 2: Implement deterministic argument arrays.** Common flags: `--ignore-config`, `--no-plugin-dirs`, `--no-remote-components`, `--no-js-runtimes`, `--js-runtimes deno:<absolute-path>`, `--ffmpeg-location <ffmpeg-parent>`, `--no-playlist`, `--socket-timeout 20`, `--retries 2`, `--fragment-retries 2`, `--no-colors`. Apply cookies only if browser is not `.none`; Brave requires a validated explicit profile ID and passes `--cookies-from-browser` followed by the single argument `brave:<profile ID>`. Chrome/Firefox use their default browser profile in this slice. URL is always last after `--`. Build a controlled environment with resolved helper directories and system paths, preserving HOME for browser access but excluding `PYTHONPATH`, plugin paths, debugging overrides, and proxy credentials. Do not log arguments.

Preview adds `--dump-single-json --skip-download --flat-playlist --playlist-end 1`, timeout 60 seconds, and 16 MiB line cap. The bounded flat listing is only for identifying/rejecting collection results; do not extract/download collection entries. Reject `_type` playlist/multi-video results, including a one-item collection; accept a single-video URL with playlist context through `--no-playlist`. Reject active/upcoming live media explicitly because the first slice is a finite-file workflow.

Download adds `--no-simulate --newline --progress --progress-delta 0.2`, the following machine-readable templates, `--no-overwrites --no-post-overwrites`, and an absolute output template under staging:

```text
--progress-template download:MD_DOWNLOAD:{"progress":%(progress)j,"stream_id":%(info.format_id|"")j}
--progress-template postprocess:MD_POSTPROCESS:%(progress)j
--print after_move:MD_FINAL:%(filepath)j
-o <staging>/media.%(ext)s
```

The download envelope gets stream ID from `info.format_id`, not from `progress.info_dict`: the installed upstream template adapter removes `info_dict` from the progress object. The explicit `|""` fallback keeps missing IDs valid JSON (the default literal `NA` is not JSON). Treat absent/empty/`NA` stream IDs as nil. Tests must use this exact envelope shape so stream changes are exercised against the real command contract.

MP4 selector and options:

```text
-f bv[vcodec^=avc1]+ba[acodec^=mp4a]/b[vcodec^=avc1][acodec^=mp4a]
--merge-output-format mp4 --remux-video mp4
```

The selector is intentionally strict; if an extractor uses alternative codec labels, add only verified H.264/AAC aliases with selector fixtures and artifact checks. Unknown codec metadata does not establish compatibility and can yield format-unavailable even for a direct MP4 URL; pin this behavior in fixtures.

Approved scoped exception (2026-10-23): after the strict selector above, append
`/b[ext=mp4][vcodec^=?avc1][acodec^=?mp4a]` only when the validated HTTP(S) URL host
is `facebook.com` or `instagram.com`, or a subdomain of either. Facebook and
Instagram progressive MP4 entries can omit codec labels; known incompatible/absent-stream
labels remain excluded. `fb.watch`, `instagr.am`, lookalike hosts, and every other
host retain strict policy. Never inspect arbitrary query values to choose this policy. Actual FFprobe H.264/AAC validation remains
mandatory before publication; map only `incompatibleMedia` to format unavailable,
retaining other probe-error and shutdown-unconfirmed behavior. Add host/argv tests
and real-coordinator loopback regressions for portrait H.264/AAC publication and
portrait MPEG-4/AAC rejection with missing source labels. A test-only runner may
map only the exact reserved synthetic Facebook/Instagram URLs to loopback after
command construction; no automated real-site fetch or browser data is permitted. Preserve the generic
unknown-codec MP4 rejection test. See the
[Facebook requirements](../../bugfixes/2026-10-23-facebook-mp4.md) and
[Instagram extension](../../bugfixes/2026-10-23-instagram-mp4.md).

Do not expand to arbitrary codec fallback or use `--recode-video`. MP3 uses `-f ba/b -x --audio-format mp3 --audio-quality 2`. No `--ignore-errors`, remote component downloads, or shell `--exec` hooks.

- [ ] **Step 3: Decode metadata/events and retest.** Clamp display fractions to 0...1 only for positive finite totals; absent sizes remain indeterminate. A stream's 100% event does not mean job completion. Return nil for ordinary warnings; `.malformed` for an invalid app-prefixed control event. Require one root video object and valid nonempty ID/title; invalid optional metadata does not crash the UI. Run `swift test --filter 'URLValidator|YTDLPCommands|MetadataDecoder|YTDLPEvents'`, expect PASS; commit `feat: define safe extraction and progress contracts`.

### Task 4: Resolve tools and verify offline readiness

**Files:** Create `Sources/DownloaderCore/DependencyResolver.swift`, `DependencyDiagnostics.swift`, `Tests/DownloaderCoreTests/DependencyResolverTests.swift`, `DependencyDiagnosticsTests.swift`, `ScriptedRunner.swift`.

**Consumes:** `ProcessRunning` and `ResolvedTools`. **Produces:** `DependencyResolver(runner: any ProcessRunning)` with `check(overrides: [String: URL]) async -> DependencyReport`; `DependencyReport` contains `tools: ResolvedTools?`, `versions: [String: String]`, `problems: [DependencyProblem]`. Define `DependencyProblem` as a safe code/tool/path record, never raw output. The application can continue only when the report has all resolved tools and no problems.

- [ ] **Step 1: Add injectable runner tests.** `actor ScriptedRunner: ProcessRunning` supports `init(replies: [ScriptedReply])`, `commands() -> [ProcessCommand]`, and `append(_ reply: ScriptedReply)`. `ScriptedReply` has `lines: [ProcessLine]`, `exitCode: Int32`, `failure: ScriptedFailure?`; `ScriptedFailure` cases `timeout`, `launch`. Its implementation invokes supplied lines in order and returns/throws the selected outcome. Test absent/nonexecutable override, fallback `/opt/homebrew/bin` and `/usr/local/bin` without trusting terminal PATH, missing FFprobe, wrong binary, timeout, Deno unsupported, and missing EJS.

```swift
@Test func missingEJSIsNotHiddenByAnInstalledDeno() async {
    let runner = ScriptedRunner(replies: TestSupport.diagnosticsWithoutEJS)
    let report = await DependencyResolver(runner: runner).check(overrides: TestSupport.toolOverrides)
    #expect(report.tools == nil)
    #expect(report.problems.contains { $0.code == "missing-ejs" })
    #expect(await runner.commands().allSatisfy { !$0.arguments.contains("--cookies-from-browser") })
}
```

`TestSupport.toolOverrides` points to executable temp fixtures; `diagnosticsWithoutEJS` supplies versions/help then debug readiness replies in actual invocation order. Run the filtered tests and expect failure.

- [ ] **Step 2: Implement version/capability checks.** Resolve user overrides first; otherwise probe Homebrew absolute locations. Validate executability and ensure FFmpeg/FFprobe share the directory passed to yt-dlp. Run tool version commands and yt-dlp help to establish required flags exist; use FFmpeg's `-encoders`/`-muxers` listings to confirm MP3 encoding and MP4 output support, without imposing FFmpeg 9 merely because it is installed here. Deno must be supported by the installed yt-dlp diagnostic, with 2.3.0 as the documented baseline. Do not silently pick a broken override's fallback.

Run this offline yt-dlp diagnostic with explicit helper paths and a 15-second limit:

```text
yt-dlp --ignore-config --no-plugin-dirs --no-remote-components
  --no-js-runtimes --js-runtimes deno:<absolute-path>
  --ffmpeg-location <ffmpeg-parent> --verbose --simulate --
```

No URL means no extraction. The local installed build prints `Optional libraries: ... yt_dlp_ejs-0.8.0` and `JS runtimes: deno-2.9.7`, then reports a missing-URL usage error with exit code 2 (verified locally). Accept that specific diagnostic exit only when expected readiness markers and the expected no-URL outcome are present; do not accept arbitrary nonzero failures. Parse only these bounded transient diagnostic fields, never persist/display complete verbose output (it can contain environment/proxy information). Unknown diagnostic format is a setup failure with package-manager guidance. This tests dependency discovery, not a live YouTube challenge.

- [ ] **Step 3: Retest and record the actual local report.** Run `swift test --filter 'DependencyResolver|DependencyDiagnostics'`; expect PASS. Invoke the resolver through a small test limited to resolved version fields, without any cookie reads or URLs. Record versions in `docs/VERIFICATION.md`; commit `feat: report external tool readiness without credential access`.

### Task 5: Own staging files, validate outputs, and publish safely

**Files:** Create `Sources/DownloaderCore/JobFiles.swift`, `ArtifactVerifier.swift`, `Tests/DownloaderCoreTests/JobFilesTests.swift`, `ArtifactVerifierTests.swift`, fixtures `probe-h264-aac.json`, `probe-mp3.json`, `probe-wrong-codec.json`.

**Consumes:** `OutputPreset`, `ResolvedTools`, `ProcessRunning`, decoded final-path string.
**Produces:** `struct StagedJob` with readable `id: UUID`, `directory: URL`, `destination: URL`, private captured device/inode identity, and an internal initializer used by `JobFiles.create` only; `JobFiles.create(id:destination:) throws -> StagedJob`, `candidate(finalPath:job:preset:) throws -> URL`, `publish(candidate:job:title:preset:) throws -> URL`, `cleanup(_ job:) throws`; `ArtifactVerifier(runner:tools:)` with `verify(_ file: URL, preset: OutputPreset) async throws`. Define `protocol FilePublishing: Sendable { func moveExclusively(from: URL, to: URL) throws }`, production `struct DarwinFilePublisher: FilePublishing`, and `JobFiles(publisher: any FilePublishing = DarwinFilePublisher())` so publication errors can be injected without filling disks.

- [ ] **Step 1: Write failing tests for ownership and codec policy.**

```swift
@Test func outputNameKeepsTitleInsideAByteBudget() throws {
    let folder = try TestSupport.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let files = JobFiles()
    let job = try files.create(id: UUID(), destination: folder)
    let candidate = job.directory.appendingPathComponent("media.mp4")
    try Data([1]).write(to: candidate)
    let output = try files.publish(candidate: candidate, job: job,
        title: String(repeating: "😀", count: 200) + "/../%(title)s", preset: .mp4)
    #expect(output.deletingLastPathComponent() == folder)
    #expect(output.lastPathComponent.utf8.count <= 162)
    #expect(output.pathExtension == "mp4")
}
```

`TestSupport.temporaryDirectory() throws -> URL` creates a test-owned scratch directory only. Add tests for an existing output with the same UUID, empty title fallback, NUL/control characters, slash/colon/backslash, `%` remaining filename data, symlink candidate, sibling path sharing a prefix, `../` final path, nonexistent/zero-byte artifact, incorrect extension, deleted destination, and cleanup refusal for an unowned directory. Stub a publication filesystem failure with ENOSPC rather than filling the user's disk. Probe fixtures must reject H.265/AAC for MP4, H.264 without audio, additional incompatible audio/video streams, mislabeled container, MP3 without audio, and nonzero/invalid probe output. Expect filtered tests to fail.

- [ ] **Step 2: Implement controlled file operations.** Create destination child `.media-downloader-<UUID>` with private directory permissions and track ownership in the `StagedJob` value and filesystem identity. yt-dlp's basename is always `media`. The candidate must resolve to the exact expected regular non-symlink `media.mp4`/`media.mp3` in that staging directory; use filesystem path-component equality, not string-prefix containment. A JSON final path is untrusted input.

Normalize a title for display filenames, remove control/separator characters, append Unicode scalars without splitting UTF-8 beyond 120 bytes, trim trailing whitespace, fall back to `video`, then append `-<full UUID>.<extension>`. Keep title strings away from command templates. Publish using same-filesystem `renamex_np(..., RENAME_EXCL)` so collisions never overwrite; an error leaves the candidate owned by the job. Cleanup must check ownership and remove only that directory. Never clean before runner completion; coordinator owns ordering.

- [ ] **Step 3: Implement artifact inspection.** Run absolute FFprobe with `-v error -show_format -show_streams -of json <candidate>`, 15-second timeout and 1 MiB cap. Require an MP4-family container with H.264 video and AAC audio for `.mp4`; every video/audio stream must satisfy that codec policy, rather than accepting one compatible pair alongside incompatible streams. Require MP3 container/audio and no video for `.mp3`. Reject empty data, symlinks, malformed JSON, missing/incorrect streams, nonzero exit, and cancellation. Preserve the exact `ProcessFailure.shutdownUnconfirmed(Int32)` case through verifier errors so the coordinator can retain staging when child shutdown is uncertain; add a fixture for it. Do not decode/play the whole file. Run `swift test --filter 'JobFiles|ArtifactVerifier'`, expect PASS; commit `feat: validate and atomically publish owned output files`.

### Task 6: Integrate preview/download state and safe errors

**Files:** Create `Sources/DownloaderCore/JobCoordinator.swift`, `AppIssueClassifier.swift`, `Tests/DownloaderCoreTests/JobCoordinatorTests.swift`, `AppIssueClassifierTests.swift`; extend `ScriptedRunner.swift` with controllable suspended replies for race tests.

**Consumes:** All earlier core components.
**Produces:** `actor JobCoordinator` initialized with `runner`, `tools`, `files` (default `JobFiles()`). Public methods: `updates() -> AsyncStream<JobSnapshot>`, `preview(_ request: PreviewRequest) async`, `invalidatePreview() async`, `download(preset: OutputPreset, destination: URL) async`, `cancel() async`, `shutdown() async`. Updates stream is newest-only buffering with the latest snapshot emitted on subscription; dropping intermediate UI snapshots never drops subprocess control events.

- [ ] **Step 1: Write failing end-to-end core tests with scripted processes.**

```swift
@Test func finalEventWithFailedExitCannotSucceed() async throws {
    let harness = try await CoordinatorHarness.readyVideo()
    await harness.coordinator.download(preset: .mp4, destination: harness.destination)
    let command = try await harness.runner.waitForCommand(at: 1)
    await harness.runner.resume(ScriptedReply(
        lines: [try harness.finalPathLine(for: command)], exitCode: 1, failure: nil), at: 1)
    let terminal = try await harness.waitForTerminal()
    #expect(terminal.phase == .failed)
    #expect(terminal.output == nil)
    #expect(try harness.completedFiles().isEmpty)
}
```

Define `CoordinatorHarness` in test support to own the runner/coordinator/temp destination; `readyVideo() async throws -> CoordinatorHarness` previews a fixture video; `finalPathLine(for: ProcessCommand) throws -> ProcessLine` reads the staging output template from that command, substitutes the expected extension, and JSON-encodes the path; `waitForTerminal() async throws -> JobSnapshot` subscribes with a five-second test deadline; `completedFiles() throws -> [URL]` lists non-staging files. Extend `ScriptedRunner` with `waitForCommand(at index: Int) async throws -> ProcessCommand` (five-second deadline) and `resume(_ reply: ScriptedReply, at index: Int)`; a run without an enqueued reply waits at that index and observes task cancellation. This captures staging paths before sending final events rather than assuming random UUIDs.

Cover: valid preview; timeout; malformed JSON; collection/live input; repeated preview; slow old preview completing after a changed URL/browser/Brave profile; missing metadata optionals; download without ready preview; second active operation refused; same browser and exact profile ID in preview/download; unknown totals/stream changes; processing after transfer 100%; duplicate/missing final event; forged path; FFmpeg exit failure; FFprobe rejection; disk-full/publication failure; clean success; cancellation in each cancellable phase; retry with fresh generation; quit with active descendants; cleanup after readers finish. During publication, Cancel does not convert a published result to cancelled. Expect tests to fail before workflow implementation.

- [ ] **Step 2: Implement generation-owned workflow and bounded diagnostics.** Keep one tracked task. `preview` captures the immutable request and replaces only a preview, awaiting old cancellation before starting another subprocess. URL/browser edits invalidate cached metadata. A download captures the validated request/metadata/preset/destination; disable mutating controls until terminal state. Operation UUID checks guard every asynchronous callback and publication step. Cancellation during validation is supported; publication is a non-suspending actor operation after a final cancellation/generation check.

Preview success saves only display metadata and immutable request in memory, not cookie data or signed media URLs. Download re-extracts using that request. Require current generation, successful exit, exactly one valid final event, candidate verification, and atomic publication before `.succeeded`. Run the verifier before publication and clean staging on terminal paths only after children are confirmed stopped. `ProcessFailure.shutdownUnconfirmed(Int32)` from download or verification takes precedence over cancellation/timeout, produces safe failure copy and a notice that temporary files were retained, and MUST skip cleanup. Add tests for both unsafe-shutdown origins. Cleanup failure is a safe secondary message, not permission to delete other paths. Publish/cleanup errors cannot be mistaken for network errors.

After unconfirmed shutdown, latch `AppIssue.shutdownUnconfirmed` for this coordinator session and refuse further preview/download operations, including retry. Invalidate/cancel must not clear this block. Fixed safe copy instructs quitting and checking that tools stopped before reopening; restarting is not evidence of prior process quiescence. Add refusal tests. The presentation layer also latches the equivalent `shutdown-unconfirmed` dependency problem and cannot bypass the block by replacing a coordinator or rerunning checks.

- [ ] **Step 3: Classify errors without exposing raw stderr.** `AppIssueClassifier.classify(exitCode: Int32, diagnostic: Data) -> AppIssue` pattern-matches transient bounded data; `message(for: AppIssue) -> String` returns fixed UI copy. Use specific cookie permission/decryption markers before generic authentication/site/network patterns. Unknown output maps to `.unknown`; never interpolate URLs, headers, paths to browser profiles, tokens, titles, or original output into errors. Test secrets in unknown output and embedded signed URLs never appear in UI copy. Do not infer expired login from a generic extraction failure.
- [ ] **Step 4: Run `swift test --filter 'JobCoordinator|AppIssueClassifier'` and the complete core suite.** Expect PASS. Commit `feat: coordinate preview download validation and safe retry`.

### Task 7: Connect the native window, preferences, and quit flow

**Files:** Create `Sources/DownloaderPresentation/AppModel.swift`; create `MainView.swift`, `DependencyView.swift`, `PreviewView.swift`, `DownloadStatusView.swift`, `AppDelegate.swift` in `Sources/MediaDownloaderApp/`; update app entry point; create `Tests/DownloaderPresentationTests/AppModelTests.swift` and declare `DownloaderPresentation` library/test targets in `Package.swift`. The app imports the presentation library; tests import that same model rather than duplicating it.

**Consumes:** Coordinator updates, dependency report, and safe error copy.
**Produces:** `@MainActor @Observable final class AppModel` with `rawURL`, `browser`, `braveProfiles: [BraveProfile]`, `braveProfileID: String?`, `preset`, `destination`, `snapshot`, `dependencyReport`; methods `checkDependencies() async`, `refreshBraveProfiles() async`, `preview() async`, `download() async`, `cancel() async`, `selectDestination()`, `revealOutput()`, `shutdown() async`. Inject `BraveProfileProviding`, preference storage, and folder/Finder closures for deterministic model tests. Production preference keys: `destinationPath`, `outputPreset`, and optional `toolPath.ytdlp`, `toolPath.ffmpeg`, `toolPath.ffprobe`, `toolPath.deno`; never persist browser choice, Brave profile, or request data.

- [ ] **Step 1: Write failing model tests.** Start with fresh UserDefaults suite and a previous saved preset/destination; assert they load and browser remains `.none` with no profile selected or profile-provider call. Explicit Brave selection loads profile display names, requires a choice, and passes that exact ID to preview/download. Changing profile invalidates preview; stale profile loads after switching away from Brave cannot reselect a profile. Simulate folder-picker cancellation and assert the prior destination survives. During download ensure editing requests do not mutate captured job input. On URL/browser edits invalidate preview; changing output preference alone need not reload metadata. A fake Finder closure receives only the succeeded output URL. Test safe error text and accessible busy/control labels. Run filtered tests and expect failure.

Also test that a queued old `.ready` snapshot arriving while current-input invalidation or replacement starts cannot enable Download for the wrong URL/profile. Keep controls conservatively disabled until current preview identity is established; add the smallest core query/return-value adapter only if the existing operation ID API cannot establish that handshake.

```swift
@Test @MainActor func cancellingFolderPickerPreservesDestination() {
    let model = AppModelTestHarness.makeModel(folderChoice: nil)
    let before = model.destination
    model.selectDestination()
    #expect(model.destination == before)
    #expect(model.browser == .none)
}
```

`AppModelTestHarness.makeModel(folderChoice:)` constructs the model with in-memory preferences, scripted core, and injected folder/Finder callbacks. Keep tests around user behavior rather than view-tree snapshots.

- [ ] **Step 2: Implement the compact window.** Show URL input, browser popup and explanation, a Brave-only profile picker with “Choose a profile” and display-name/ID labels, preview, metadata card, output segmented control, destination picker, download/cancel, safe status/error, and Finder reveal. Keep profile loading/errors clear and disable Brave-backed preview until a profile is explicitly chosen. Use indeterminate progress where totals are absent and during processing/validation. `AsyncImage` may fetch only validated HTTP(S) thumbnails without forwarding browser cookies. Thumbnail failure falls back to an icon. Truncate long titles visually with full accessible labels; never use text as a format string. Respect dynamic type/keyboard focus. Use fixed safe UI text from the core.
- [ ] **Step 3: Wire launch and shutdown.** Resolve dependencies at startup; display failures and a retry check. Settings permits absolute tool-path overrides (via file picker) used only for named tools; store paths only and rerun readiness. Do not offer arbitrary flags or run install/update commands. AppKit delegate returns `.terminateLater` while `shutdown()` cancels active work, then calls `reply(toApplicationShouldTerminate: true)` exactly once. Cancel/Quit remain responsive during preview, download, processing, and validation; publishing completes before termination. No automatic preview or cookie extraction at launch.

Construct one shared `AppModel` at app scope, shared by all windows and the quit delegate, or use a single-window scene. Register the shutdown path before dependency subprocesses can start. Opening a new window must not create a new coordinator or reset a latched safety block.

Latch session blocking after `AppIssue.shutdownUnconfirmed` or dependency problem code `shutdown-unconfirmed`. Disable all subprocess-starting checks/previews/downloads for that app session, including settings-triggered checks; changing preferences must not create a new coordinator to bypass it. Keep Quit available and show the fixed safe notice. Test that later dependency rechecks and profile/input changes cannot clear this block.
- [ ] **Step 4: Run model/core tests and build the app executable.** Expect PASS. Commit `feat: add native preview and download workflow`.

### Task 8: Assemble the local app and prove real-tool integration

**Files:** Create `Resources/Info.plist`, `scripts/build-app.sh`, `scripts/verify.sh`, `scripts/integration.py`, `Tests/DownloaderCoreTests/RealToolIntegrationTests.swift`, `docs/VERIFICATION.md`; update `README.md`.

**Consumes:** App executable and full core. **Produces:** `dist/Media Downloader.app`, reusable verification commands, and observed evidence.

- [ ] **Step 1: Add real-tool integration tests with an explicit opt-in.** Test cases skip with a recorded reason unless `MEDIA_DOWNLOADER_INTEGRATION_URL` and absolute tool paths are supplied by the integration harness. The harness creates a private temporary root and generates a two-second H.264/AAC HLS sample with a master manifest declaring its codecs, using the resolved FFmpeg:

```text
ffmpeg -f lavfi -i testsrc=size=320x180:rate=15
  -f lavfi -i sine=frequency=440:sample_rate=44100 -t 2
  -c:v libx264 -pix_fmt yuv420p -b:v 256k -c:a aac -b:a 64k
  -f hls -hls_time 1 -hls_playlist_type vod
  -hls_segment_filename segment-%03d.ts -master_pl_name master.m3u8
  -var_stream_map v:0,a:0 media.m3u8
```

`integration.py` binds `ThreadingHTTPServer` to `127.0.0.1` on an ephemeral port, serves only that temporary directory, suppresses request logs, runs `swift test --filter RealToolIntegration` with the master-manifest URL/tool environment, and always stops the server and deletes its own root. Use `subprocess.run([...])` arrays, no shell commands. Test both output presets through the real coordinator/verifier and assert codec/container/size. Generate a direct MP4 by remuxing the same sample and test its unknown-codec metadata case against the explicit format-unavailable policy rather than assuming the generic extractor knows its codecs. Serve additional fixtures for 404, metadata unavailable, unsupported format, and interrupted stream. Assert failures never publish. No browser cookies, site URLs, or external network in this layer. Run once before implementation fixes as a genuine failing integration test, then fix only observed contract mismatches.

- [ ] **Step 2: Build the bundle reproducibly.** `build-app.sh` uses `set -euo pipefail`, resolves repository root from its own location, runs `swift build -c release --product MediaDownloader`, copies only the app executable into a new bundle's `Contents/MacOS`, and copies `Info.plist` into `Contents`. Bundle ID `local.rhomuel.media-downloader`, display name `Media Downloader`, executable `MediaDownloader`, minimum system 14.0. Ensure the copy has executable permissions. Ad-hoc sign locally using `/usr/bin/codesign --force --sign -` and verify that signature; this is not Developer ID signing or notarization. Do not embed Homebrew binaries or fixtures. Replace only the build script's known output bundle; never clean the whole destination directory.

- [ ] **Step 3: Add a single verify command.** `scripts/verify.sh` builds the fixture, runs `swift test` and a release app build, then runs loopback integration when explicitly requested with `--integration`. Default mode must not start the app, read cookies, contact remote sites, or silently count skipped integration as verified. Log test summaries and tool versions only; keep raw metadata/diagnostics ephemeral. Run `bash scripts/verify.sh --integration`; expected: unit, process, model, and real MP4/MP3 integration PASS. Record actual counts, skips, platform, and failures in `docs/VERIFICATION.md`.
- [ ] **Step 4: Verify Finder launch and GUI behavior.** Open `dist/Media Downloader.app` through Finder/Launch Services with a minimal inherited PATH. Check dependency screen, paste/preview, browser selector default None, folder picker cancel, MP4/MP3 actions, progress/processing/cancel/retry, long title layout, window responsiveness, and actual Show in Finder. Use the loopback sample where useful. Verify Quit during a controlled long-running fixture leaves no descendants. Record observed UI evidence separately from unit/integration results. Do not claim GUI verification if only a command-line launch was observed.
- [ ] **Step 5: Run user-selected live smoke checks.** Ask for one public URL and one login-required URL/browser if not already provided. User authorization to include cookies does not choose a browser profile or private source on their behalf. Use only that explicit selection; do not enumerate browser data or dump logs. Record site name, tool versions, output type, outcome, and any permission failure without storing the full URL/title. If inputs or OS permission are unavailable, keep live verification marked pending; finish the rest of the app. README explains that local fixtures cannot establish live site support.
- [ ] **Step 6: Review the complete change, rerun only affected checks after fixes, and commit.** Compare against every spec section and this plan's Review Focus. Run the agreed final independent review if the selected execution method authorizes one. Fix actionable regressions with focused tests. Commit `feat: package and verify personal macOS downloader`. Report local build, unit/process/integration, GUI, live-site checks, signing, and distribution as separate states. Never describe a successful local bundle as a notarized or released app.

## Plan self-review / coverage map

| Approved requirement | Owner and evidence |
|---|---|
| Native personal app, reproducible build | Tasks 1, 7, 8 |
| Dependency readiness including EJS, Finder PATH | Task 4 offline diagnostics, Task 8 GUI launch |
| URL validation and explicit cookie selection | Task 3 argv tests, Task 6 request capture, Task 7 default None |
| Metadata and optional thumbnail | Task 3 fixtures, Task 7 fallback UI |
| Strict MP4 and MP3 policies | Task 3 selectors, Task 5 FFprobe, Task 8 real outputs |
| Progress and processing phases | Task 3 events, Task 6 states, Task 7 UI |
| One operation, stale callback rejection | Task 6 gate-controlled races |
| Cancellation, timeout, quit and child cleanup | Task 2 process-group fixtures, Tasks 6 and 7 lifecycle |
| Bounded output and no secret diagnostics | Tasks 2, 4 and 6 |
| Owned staging, byte-safe title, no overwrite | Task 5 files, Task 6 cleanup ordering |
| Output/destination preference and folder cancellation | Task 7 model tests |
| Safe retry and actual Finder output | Tasks 6 and 7, Task 8 GUI |
| Local integration distinct from live site support | Task 8 separate evidence entries |
| Deferred scope remains excluded | README, AGENTS, final review |

No runtime application code has been implemented while writing this plan. The offline EJS diagnostic was exercised with the already-installed tool; it confirmed local dependency discovery only. SDK/SwiftUI compilation, POSIX runner behavior, and all app tests remain execution work.

## Execution handoff

Recommended method: **Native execution in this chat**, because the eight tasks share a tightly coupled process/state/file contract and this is a personal local application. A final independent review provides another look after the interfaces work together.

Alternative: **Subagent-driven**, assigning a fresh implementer and reviewer for each task, with higher context and review cost. Either method must follow task order for dependencies and run the complete integrated suite before reporting completion.

The user should review this plan and select a method before product implementation begins, as required by the writing-plans workflow. On execution, preserve existing docs and initialize Git in Task 1; this initially empty repository has no other checkout to isolate. After a Git baseline exists, use an isolated branch/worktree when the active execution skill requires it.
