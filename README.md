# Media Downloader

A personal native macOS downloader, targeting macOS 14 or later with Swift 6.2.
The current foundation builds a minimal SwiftUI window and shared core contracts.
Download workflows are being implemented against the approved design.

## Build and test

Install a compatible Apple Swift 6.2 toolchain and macOS SDK, then run:

```sh
swift --version
xcode-select -p
xcrun --sdk macosx --show-sdk-path
swift build --product MediaDownloader
bash scripts/test.sh
```

`scripts/test.sh` forwards options to `swift test` (for example,
`bash scripts/test.sh --filter cookieAccessIsAnExplicitChoice`). With standalone
Command Line Tools it derives the selected developer directory with
`xcode-select -p` and adds framework search and runtime paths for the installed
Swift Testing framework. Other developer installations use plain `swift test`.
See [verification evidence](docs/VERIFICATION.md) for the observed setup limitation.

The Swift package has no external Swift dependencies. The intended runtime uses
externally installed yt-dlp, FFmpeg, FFprobe, and Deno from Homebrew; the app will
check their capabilities and will never install or update them automatically.
Browser cookies are opt-in per operation, with None on each launch. No cookie
export/import or cookie-content persistence is supported.

MP4 targets H.264 video plus AAC audio without video transcoding. MP3 uses audio
conversion at VBR quality 2. Site support depends on installed tool versions and
the site. The approved scope is one URL and one active operation at a time.

This is for personal use on this Mac. Distribution packaging, signing, and public
release are deferred. Passing local fixtures will not establish live site support.
See [the approved design](docs/superpowers/specs/2026-10-15-media-downloader-design.md)
and [implementation plan](docs/superpowers/plans/2026-10-15-media-downloader.md).
