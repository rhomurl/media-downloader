# Verification evidence

Observed 2026-10-15 on this Apple Silicon Mac. This is Task 1 build/contract
verification, not v1 usability or live-site verification.

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
yt-dlp options, MP3 encoder and MP4 muxer support, Deno's 2.3.0 baseline, and
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
