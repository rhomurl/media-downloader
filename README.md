# Media Downloader

A personal native macOS app for previewing one video URL and saving compatible
MP4 video or MP3 audio. Built with SwiftUI and a testable Swift 6 core, targeting
macOS 14 or later. There are no third-party Swift package dependencies.

## Setup and use

Install Apple Swift 6.2 with a compatible macOS SDK for development. Runtime tools
are external: yt-dlp with local EJS support, FFmpeg with libmp3lame and MP4 support,
FFprobe, and Deno 2.3.0 or later. The app checks their capabilities without cookies.
It searches `/opt/homebrew/bin` and `/usr/local/bin`; Settings accepts absolute
executable overrides. FFmpeg and FFprobe must retain their standard names in one
directory. The app never installs or updates tools.

Paste a single recorded-video URL, choose browser access if needed, and Preview.
Browser access defaults to None on each launch. Brave requires an explicit profile
selection; that selection stays in memory. Browser/profile changes invalidate the
preview. Cookie access occurs only for an explicitly selected browser when Preview
or Download is invoked. No cookie export/import or cookie-content persistence is
supported.

Choose MP4 or MP3 and a destination, then Download. One operation runs at a time.
Cancel stops owned subprocesses before staging cleanup. Success requires artifact
validation and exclusive publication; Show in Finder reveals the returned file.
Only destination, output preset, and tool overrides are saved.

MP4 requires source H.264 video plus AAC audio and uses merge/remux without video
transcoding. Selection first requires labelled compatible streams: `avc1`/`mp4a`
prefixes or exact `h264`/`aac` aliases, including mixed labels. TikTok uses this
strict policy; unknown labels and alias lookalikes remain excluded. For parsed hosts
`facebook.com` and `instagram.com`, and their subdomains, progressive MP4 candidates
may have missing codec labels; actual FFprobe H.264/AAC validation still gates publication. Known incompatible
labels are excluded, and an incompatible downloaded artifact is discarded with a
format-unavailable error. Other hosts, including `fb.watch` and `instagr.am`, retain
strict unknown-codec rejection even for a direct file ending in `.mp4`. Missing compatible streams
also produce format unavailable. MP3 uses FFmpeg conversion at VBR quality 2;
conversion does not improve source fidelity. Missing
media fragments fail the job rather than publish a playable partial file. Final
files are never overwritten.

## Build and verify

```sh
swift build --product MediaDownloader
bash scripts/test.sh
bash scripts/verify.sh
bash scripts/verify.sh --integration
```

`verify.sh` builds the developer process fixture, runs unit/process/model tests,
and builds and verifies the local release bundle. Default verification skips the
real-tool suite explicitly. `--integration` additionally generates synthetic
H.264/AAC HLS media in an owned temporary directory, serves it on an ephemeral
127.0.0.1 port, and exercises real yt-dlp/FFmpeg/FFprobe through the coordinator.
It checks MP4/MP3 outputs, strict generic unknown-codec rejection, the Facebook/Instagram
exception with compatible/incompatible portrait MP4s, real yt-dlp alias selection
using synthetic info JSON, alias-labelled portrait downloads with actual artifact
validation, and failures without publication.
The integration branch first runs synthetic harness lifecycle regressions.
Python 3 is required for this development-only integration harness. No site URLs,
browser cookies, or external network are needed. Versions and test summaries are
printed; unrestricted runtime diagnostics remain ephemeral. Forced or uncertain
driver shutdown retains the owned fixture root rather than deleting files while
work may remain. `python3 scripts/test-integration.py` runs synthetic harness
timeout/interruption and HTTP-worker cleanup regressions without media tools.

`scripts/test.sh` forwards options to `swift test`, for example
`bash scripts/test.sh --filter YTDLPCommandsTests`. For standalone Command Line
Tools, it discovers the selected Swift Testing framework and supplies framework
search/runtime paths; other installations use ordinary `swift test`. Compiler
caches must be writable. Loopback integration needs permission to bind localhost.
See [observed verification evidence and limits](docs/VERIFICATION.md).

## Local app bundle

```sh
bash scripts/build-app.sh
open "dist/Media Downloader.app"
```

The build script works from any current directory. It assembles only the release
executable and Info.plist, then applies and verifies a local ad-hoc signature. It
replaces only `dist/Media Downloader.app`, preserving other files in `dist`.
Runtime tools and development fixtures are not embedded. This is a local personal
bundle; Developer ID signing, notarization, distribution, and public release
remain outside scope.

Automated tests and a signed local build do not establish Finder launch, GUI
behavior, browser permissions, or live site support. Observed native GUI and user-selected public YouTube checks are recorded in
[VERIFICATION.md](docs/VERIFICATION.md), with their limits. Login-required/browser
cookie checks remain pending. Site availability depends on installed
tool versions and the site.

See [the approved design](docs/superpowers/specs/2026-10-15-media-downloader-design.md)
and [implementation plan](docs/superpowers/plans/2026-10-15-media-downloader.md).
