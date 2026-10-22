# Verification evidence

Current local evidence is recorded below under Task 8 (2026-10-23). Earlier
sections retain their original observations and limits. Local automated checks
and bundle signing do not establish GUI usability or live-site support.

## Developer setup

- `swift --version`: swift-driver 1.127.14.1, Apple Swift 6.2
  (`swiftlang-6.2.0.19.9 clang-1700.3.19.1`), target `arm64-apple-macosx26.0`.
- `xcode-select -p`: `/Library/Developer/CommandLineTools`.
- `xcrun --sdk macosx --show-sdk-path`:
  `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`.
- `/Applications` contains no Xcode.app. No global developer-directory changes
  were made.

The initial sandboxed `swift build --product MediaDownloader` exited 1 because
SwiftPM/Clang caches were inaccessible (`Operation not permitted` opening
`~/.cache/clang/ModuleCache/.../SwiftShims-UTLVU43OQQS4.pcm`). Its cascading diagnostic
also said `this SDK is not supported by the compiler`. Rerunning the identical
command with cache filesystem access succeeded, importing SwiftUI and linking the
native executable (38.44 seconds). That proves the selected SDK/toolchain can
build this app; the initial message did not establish a compiler incompatibility.

## Swift Testing discovery correction

Plain `swift test --filter cookieAccessIsAnExplicitChoice` exited 1 with
`no such module 'Testing'`. Verbose output showed SwiftPM passing `-I` and `-L`
for the CLT frameworks directory; Testing is installed as `Testing.framework`.
Adding Swift and linker `-F` reached the intended missing-domain-type RED failure.
After implementing the contracts, those flags built tests but execution failed
with `Library not loaded: @rpath/Testing.framework/Versions/A/Testing` (signal 5).
Adding the framework directory as a linker rpath resolved runtime discovery.

`scripts/test.sh` derives the selected CLT directory and supplies:

```sh
swift test -Xswiftc "-F$framework_dir" -Xlinker "-F$framework_dir" \
  -Xlinker -rpath -Xlinker "$framework_dir" "$@"
```

It applies these flags only to a selected standalone CommandLineTools installation
containing Testing.framework. It leaves the package manifest and product targets
free of machine-specific paths. Test execution requires normal compiler-cache
filesystem access in the Codex sandbox.

## Task 1 results

- RED: filtered contract compilation failed for missing `CookieBrowser` and
  `OutputPreset` before domain implementation, with explicit framework flags.
- GREEN: `bash scripts/test.sh --filter cookieAccessIsAnExplicitChoice` passed
  1 test with 0 failures.
- Full suite: `bash scripts/test.sh` passed 1 test with 0 failures.
- Native build: `swift build --product MediaDownloader` succeeded.

The suite currently covers the explicit browser/output choices only. No process
runner, command builder, runtime dependencies, files, downloads, Finder launch,
GUI interaction, cookies, remote URLs, or live sites have been tested in Task 1.
The minimum macOS deployment target is configured as 14; this run does not prove
execution on macOS 14 hardware.

## Task 4: offline external-tool readiness

Observed 2026-10-15 on the same Apple Silicon macOS machine. The resolver found
all four tools under `/opt/homebrew/bin` and reported no setup problems:

| Tool | Parsed version |
| --- | --- |
| yt-dlp | 2026.08.19 |
| FFmpeg | 9.0.2 |
| FFprobe | 9.0.2 |
| Deno | 2.9.7 |
| yt-dlp EJS | 0.8.0 |

This was an actual `DependencyResolver` run using `ProcessRunner`, enabled with
`MEDIA_DOWNLOADER_CHECK_LOCAL_TOOLS=1 bash scripts/test.sh --filter localOfflineReadinessVersionsOnly`.
It passed 1 test. The log contains only parsed numeric version fields and fixed
problem codes; verbose runtime diagnostics were neither saved nor displayed.
No URL, browser selection, cookie argument, or actual Brave registry was used.

The check validates executable paths, helper colocation/names, tool identities,
yt-dlp options, libmp3lame MP3 encoder and MP4 muxer support, Deno's 2.3.0 baseline, and
installed yt-dlp's discovery of both EJS and the explicitly selected Deno. The
no-URL yt-dlp diagnostic must exit 2 with the exact missing-URL outcome and the
expected readiness markers. Other nonzero outcomes fail setup. All probes have
15-second deadlines and credential-free argument arrays with a restricted
environment. No terminal PATH or shell startup files participate in discovery.

The installed build hides accepted legacy aliases `--no-colors` and
`--playlist-end` from help. Readiness therefore requires their advertised modern
equivalents `--color` and `--playlist-items`, and passes both legacy aliases in
the no-URL diagnostic to prove parser acceptance. An unknown-option exit 2
without readiness markers is a regression fixture and fails readiness.

Validation results:

- RED: the initial filtered run failed compilation because `DependencyResolver`
  did not exist. A renamed-helper regression failed with an incorrectly accepted
  report before filename validation. The local-help regression failed setup
  before modern-option/legacy-alias capability discovery was corrected.
- `bash scripts/test.sh --filter 'DependencyResolver|DependencyDiagnostics'`:
  12 tests across 2 suites passed; the opt-in local probe was skipped in this run.
- `bash scripts/test.sh`: 72 tests across 10 suites passed; the same opt-in local
  probe was skipped. It passed separately with the environment switch above.
- `swift build --product MediaDownloader`: succeeded.
- `git diff --check`: clean.

Swift commands required compiler-cache filesystem access in the Codex sandbox,
as in earlier tasks. No install, update, network extraction, or cookie access was
performed. Unknown or changed diagnostic formats deliberately block readiness;
setup UI should offer fixed package-manager guidance to check or manually update
`yt-dlp`, `ffmpeg`, and `deno`, then recheck. The resolver never executes that
maintenance itself. FFmpeg 9 is not a minimum: synthetic capability fixtures also
pass with FFmpeg/FFprobe 6.1 and Deno 2.3.0.

These results establish local dependency discovery only. They do not prove a
live public or login-required site works, that a YouTube challenge succeeds,
that browser permissions allow cookie access, or that the application is usable
from Finder. Live smoke checks, local media integration, GUI workflow checks,
and macOS 14 execution remain outstanding.

Task 4 review correction: the MP3 gate now requires `libmp3lame`, which yt-dlp
selects explicitly for the app's MP3 conversion command. An FFmpeg build with
only `libshine` is rejected with `missing-mp3` and nil tools. The new regression
failed before correction (1 test, 2 failed expectations), then
`bash scripts/test.sh --filter 'DependencyResolver|DependencyDiagnostics'`
passed 13 tests across 2 suites. Existing libmp3lame/Deno-baseline success cases
remain covered. The opt-in local probe was skipped in this focused run; the
full suite, native build, and actual local readiness results above predate this
single-predicate correction and were not rerun for it.


## Task 8: current core, model, packaging, and real-tool integration

Observed 2026-10-23 on Apple Silicon macOS 26.6.2 (25G83, arm64), Apple Swift 6.2
(`swiftlang-6.2.0.19.9`, `clang-1700.3.19.1`), standalone Command Line Tools.
Deployment remains macOS 14 minimum; execution on macOS 14 was not tested.

### Automated results

| Command/check | Observed result |
| --- | --- |
| `bash scripts/verify.sh --integration` | PASS: process fixture built; whole suite reported 146 tests across 16 suites (11.370 seconds); release bundle assembled and signature verified; opt-in integration passed 5 test functions / 10 cases (2.021 seconds) |
| `python3 scripts/integration.py` after test error-path cleanup hardening and summary-only output filtering | PASS: 5 test functions / 10 cases (2.897 seconds); coordinator shutdown is joined before test-destination cleanup, including assertion/timeout errors |
| `bash scripts/test.sh --filter RealToolIntegration` without opt-in | All 5 integration test functions explicitly skipped with the missing URL/absolute-tool-path reason; runner still reports 5 tests, so that count does not mean integration ran |
| `MEDIA_DOWNLOADER_CHECK_LOCAL_TOOLS=1 bash scripts/test.sh --filter localOfflineReadinessVersionsOnly` | PASS: 1 test (1.281 seconds), no problem codes, parsed versions below; no URL or cookies |
| `swift build --product MediaDownloader` | PASS: native executable built (4.05 seconds), no warnings/errors |
| `bash -n scripts/build-app.sh scripts/verify.sh`, `plutil -lint Resources/Info.plist`, `git diff --check` | PASS |
| Absolute build-script path invoked from `/private/tmp` with an owned sentinel in `dist` | PASS: bundle replaced and unrelated sentinel preserved, then sentinel removed |
| Importable fixture lifecycle check | PASS: codec-declared master, generated direct MP4, long HTML title, controlled slow-segment gate, joined server, owned temporary-root deletion |

The whole-suite count includes intentional skips: the five real-tool test
functions and the preexisting opt-in offline-tool probe. Integration is run
separately with explicit opt-in; the offline probe is run separately with its
switch. Parameterized cases are not counted as separate test functions in Swift
Testing's summary. No skipped integration is counted as a successful real-tool
check. The previous Task 7 baseline reported 141 tests in 15 suites; this task
adds five integration functions in one suite and a fragment-capability case to an
existing parameterized dependency test.

The whole suite covers domain/URL/browser argument policies, framing/events,
metadata, dependency diagnostics and readiness, process ownership and descendant
shutdown, cancellation/timeouts/readers, file ownership and exclusive publication,
artifact validation, coordinator races and session safety blocking, and the real
presentation model's preferences, profile selection, stale events, UI state,
native-action injection, and quit barrier. These are automated core/model checks,
not observations of native GUI interaction. In particular, synthetic profile
providers never read the real Brave registry or cookies.

Installed tool observations (all four executables under `/opt/homebrew/bin`):

| Tool | Version |
| --- | --- |
| yt-dlp | 2026.08.19 |
| FFmpeg / FFprobe | 9.0.2 / 9.0.2 |
| Deno | 2.9.7 |
| Local yt-dlp EJS (parsed readiness diagnostic) | 0.8.0 |

### Real media and failure evidence

The standard-library Python harness generates a two-second, 320×180, 15 fps
H.264/AAC HLS sample using the resolved FFmpeg and the planned command. FFmpeg's
master manifest declares codecs. The same sample is remuxed into a direct MP4 and
an audio-only HLS fixture. An ephemeral HTTP server binds only to 127.0.0.1 and
serves the private generated root. Raw tool output is held transiently; the
harness prints versions and test summaries, then stops its server and deletes
its own root. All launches use subprocess argument arrays. No fixture is part
of the product bundle.

Both presets use the real JobCoordinator, ProcessRunner, yt-dlp, FFmpeg,
ArtifactVerifier/FFprobe, JobFiles, and exclusive publisher. Success requires a
nonempty file larger than 1 KiB, the selected extension, and successful real
container/codec verification at both the staged and returned final paths. The
final destination contains exactly that returned file and no staging residue.
MP4 verifies the MP4-family container with H.264 video and AAC audio; MP3 verifies
the MP3 container and audio with no video.

Ten integration cases cover MP4/MP3 success; direct-MP4 unknown-codec metadata
rejected as format-unavailable; HTTP 404 and HTML without media rejected during
preview; audio-only HLS rejected for the MP4 preset; truncated HTTP fragment and
missing fragment rejected for each preset. Every failure checks nil output and
an empty destination, including staging cleanup after subprocess completion.

A genuine pre-fix run showed yt-dlp skipping a missing HLS fragment after a valid
one, returning exit zero, and publishing a playable partial MP4. Three assertions
failed: phase was succeeded, output/issue indicated success, and the destination
was nonempty. Codec/container validation alone cannot establish complete transfer.
Download argv now includes `--abort-on-unavailable-fragments` for both presets;
readiness requires support for that flag. Both preset cases pass after the fix.
The command regression failed before the flag (two assertions); a restored-after-
run readiness mutation omitting the required capability failed two assertions
for its new missing-fragment-flag case. The approved output contract and README
now state this strict missing-fragment policy.

Initial test-authoring runs also exposed a test-only comparison of `/private/var`
and `/var` aliases for the same output. The assertion now compares resolved paths.
This was distinct from the genuine partial-publication failure. Initial sandbox
execution could not bind localhost; verification succeeded with normal compiler-
cache and loopback access. No tools were installed or modified. One intermediate
verify attempt was interrupted by editing its running shell script; the unchanged
final combined command was rerun successfully. This intermediate run is not
counted as successful verification.

### Local bundle and signing

`bash scripts/build-app.sh` builds the release product and assembles
`dist/Media Downloader.app`. Info.plist declares identifier
`local.rhomuel.media-downloader`, display name `Media Downloader`, executable
`MediaDownloader`, and minimum macOS 14.0. Observed output is an arm64 Mach-O
executable with mode 755, Info.plist, and generated signature resources only.
There are no embedded runtime tools, Python helpers, process fixtures, test media,
or test bundles. `codesign --verify --strict` succeeds and signature inspection
reports `adhoc` with no TeamIdentifier. The script signs before replacement and
verifies the installed result; it replaces only its fixed output bundle and
refuses a symlinked dist directory.

This is a locally assembled personal bundle. Developer ID signing, notarization,
Gatekeeper distribution behavior, release artifacts, and distribution remain
unverified and outside the approved v1 scope.

### GUI and live-site checks: pending controller verification

No Task 8 implementer check opened the app in Finder or exercised native UI.
Finder/Launch Services with a minimal PATH, dependency screen, browser default
None, preview/title layout, folder-picker cancellation, both output actions,
progress/processing, Cancel/Retry, responsive window, actual Show in Finder, and
Quit during transfer still require controller observations. Automated core/model
checks do not replace these native observations.

The importable `LoopbackFixture` exposes `url`, `slow_url`, `long_title_url`,
`wait_for_segment(timeout)`, `release_segments()`, and `close()`/context-manager
cleanup for those checks. The slow master/playlist remain fast; the segment waits
on an explicit owner-controlled gate. These are developer fixtures only.

No public-site or login-required extraction, browser/Keychain permission prompt,
real Brave registry enumeration, or cookie access was performed here. Public
and login-required smoke checks remain pending, and require user-selected inputs
plus an explicit browser/profile for cookie-backed operations. The controller
will record permitted site names, versions, preset, outcome, and permission
failures separately without retaining full URLs, titles, metadata, or diagnostics.
A supplied public input is kept only in the ignored execution workspace.
