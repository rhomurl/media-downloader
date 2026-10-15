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
