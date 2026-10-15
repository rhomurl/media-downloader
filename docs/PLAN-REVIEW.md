# Handoff review: macOS media downloader

Reviewed 2026-10-15. Input: [original handoff](reference/original-handoff.md).

## Confirmed requirements

- Personal use on this Mac first.
- MP4 video and MP3 audio.
- Browser cookies in v1, including login-required Facebook/private videos where the account has access and the extractor supports the URL.

The user approved the linked design on 2026-10-15. The findings below explain the chosen architecture, output policy, and browser list; implementation planning follows that approval.

## Findings ranked by implementation impact

### 1. High: there is no subprocess lifecycle contract

The handoff specifies `Process` and progress parsing but not how jobs stop, how pipes are drained, or how late callbacks are handled. A blocked stderr pipe can stall a job; terminating yt-dlp alone can leave an FFmpeg child running; an old preview can replace a newer URL's result.

Before implementation, define concurrent bounded stdout/stderr consumption, incremental line framing, per-operation identifiers, preview timeout, and ownership of the complete child process group. Cancel must stop the group with bounded escalation and wait for readers to finish before cleanup. Never invoke a shell with pasted input. Pass separate arguments and an option terminator before a validated HTTP(S) URL. Disable implicit user configuration and default plugin loading so terminal customizations cannot change app behavior.

These are inferred failure modes to cover with fixtures, not reproduced app defects: the workspace has no application yet.

### 2. High: “MP4” leaves the quality/compatibility promise undefined

The upstream MP4 preset prefers codecs and remuxes; it does not guarantee H.264/AAC transcoding. A container extension alone cannot promise playback compatibility. See [preset and format options](https://github.com/yt-dlp/yt-dlp#preset-aliases).

Recommended v1 policy: select available H.264 video and AAC audio for an MP4, without video transcoding. Prefer useful resolution within those constraints. If unavailable, explain the limitation instead of silently returning another format. MP3 conversion can use FFmpeg with a fixed VBR policy; higher bitrate must not be presented as restoring missing source quality. Add broader conversion later if actually needed.

### 3. High: downloaded bytes reaching 100% is not success

Video and audio can download separately, followed by merging or conversion. Filename prediction before processing can also be wrong. Upstream exposes structured progress and final-stage printing for integrations: [embedding guidance](https://github.com/yt-dlp/yt-dlp#embedding-yt-dlp).

Use app-prefixed machine-readable events, tolerate missing sizes, show a separate indeterminate processing phase, and require successful exit plus an existing nonempty final artifact before publishing it. No parser may treat ordinary human-readable console text as its success contract. Test FFmpeg failure after download completes.

### 4. High: dependency discovery must work when launched from Finder

Finding tools in this terminal does not establish that the GUI process will find the same tools. Check absolute paths and versions; explicitly configure FFmpeg and the JS runtime. EJS is another dependency to verify rather than infer from Deno being present; see [official EJS setup](https://github.com/yt-dlp/yt-dlp/wiki/EJS).

Use the existing Homebrew installation for this personal version. Show missing/incompatible dependencies and their resolved locations. Do not install, upgrade, or switch channels automatically. A nightly recommendation does not justify replacing package-manager-owned files with the binary self-updater.

### 5. High: browser cookies need a privacy and consistency contract

Cookies are part of v1, so deferring all authentication would miss the intended use. Browser choice must apply to both preview and download. Reading a browser's cookies can trigger OS permissions or fail; a logged-in browser also cannot guarantee extractor/site success.

Default to no cookies and let the user explicitly select Chrome, Brave, or Firefox. Keep Safari out of the first supported set because the handoff already records a privacy-access failure. Do not read cookies during startup, persist cookie contents, dump metadata/raw logs, or automatically retry with credentials. Redact URLs and credentials from diagnostics. Distinguish permission/decryption failure from login-required, unavailable, unsupported, and network errors; allow an unknown-error fallback.

### 6. Medium: long filenames are only one part of file safety

The proposed character truncation is not an explicit UTF-8 byte budget, and duplicate titles, failed conversions, and cancellation are not addressed.

Use a job-owned staging folder in the selected destination. Publish only after success, with an app-sanitized title bounded by UTF-8 bytes and a unique suffix. Cleanup may remove only that job's directory after all children stop. Preserve previously completed downloads; never recursively clean an arbitrary user-selected folder. Test emoji, percent signs, path separators, duplicate titles, disk-full errors, and an unwritable destination.

### 7. Medium for v1, high before distribution: bundling plus self-update is a separate project

The handoff combines bundling, browser access, signing, and a nightly updater. Replacing nested code requires attention to the outer app signature; Apple documents bundle sealing and nested code in [TN2206](https://developer.apple.com/library/archive/technotes/tn2206/_index.html).

For personal use, use external tools and manual package-manager updates. Before distribution, design installation, signed updates, rollback, runtime compatibility, and dependency provenance together. Review actual dependency licenses then. The handoff's claim that GPL dependencies necessarily determine the Swift wrapper's license is not an established conclusion from the README alone. Likewise, App Store feasibility and blanket statements about platform terms are not verified decisions in this review.

## Proposed first slice

SwiftUI → dependency resolver → job coordinator → subprocess runner/event decoder. One URL and one active operation, preview, MP4/MP3 selection, browser selection, destination picker, download, cancel, error/retry, and Show in Finder.

Defer queue/batch, playlists, arbitrary conversion, subtitles, Safari, managed runtimes, auto-update, and public distribution. Reject collection-only URLs explicitly; do not accidentally enumerate/download a collection. A single-video link carrying playlist context should stay a single video.

## Alternatives

1. **SwiftUI + external Homebrew tools — recommended:** smallest personal macOS implementation; requires these tools to remain installed.
2. **SwiftUI + managed/bundled runtimes:** easier setup on another Mac; adds update, packaging, and distribution work immediately.
3. **Tauri/Electron:** useful if Windows/Linux becomes a real goal; introduces another UI stack without reducing extractor/process-management work.

## Environment verified locally

- Empty workspace; no Git repository or existing app.
- Apple Silicon, macOS 26.6.2, Swift 6.2.
- Selected developer directory: `/Library/Developer/CommandLineTools`; a working full-Xcode project build has not been established.
- `/opt/homebrew/bin`: yt-dlp `2026.08.19`, FFmpeg/FFprobe `9.0.2`, Deno `2.9.7`.

Version/help commands succeeded. No dependency was changed. Browser cookies were not read, no URL was downloaded, and live site support, EJS execution, SwiftUI builds, permissions, and cancellation remain unverified.

## Next artifact

The [design](superpowers/specs/2026-10-15-media-downloader-design.md) is approved. Review the [implementation plan](superpowers/plans/2026-10-15-media-downloader.md) and select an execution method next. There is no product code yet.
