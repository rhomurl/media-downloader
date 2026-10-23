# Personal macOS media downloader: proposed design

Date: 2026-10-15. Status: approved by the user on 2026-10-15 ("Looks good to me").

User refinement during implementation: Brave must offer an explicit profile picker. The supplied public test URL is retained only in the ignored execution workspace, not in project documentation.

## Purpose and success

The user confirmed a personal app for this Mac, supporting MP4 video, MP3 audio, and browser cookies for login-required videos. The goal is to paste a supported URL and obtain a usable local file without entering terminal commands for each download.

The approved approach uses SwiftUI, external Homebrew tools, one active job, and the browser/output policies below. Public site availability remains dependent on yt-dlp and the site; login credentials cannot guarantee success.

## User flow

1. Startup checks yt-dlp, FFmpeg, FFprobe, and Deno without accessing browser cookies. A dependency screen explains missing tools and shows resolved paths/versions.
2. The main window has a URL field, browser selector (`None`, Chrome, Brave, Firefox), and Preview action. Selecting Brave exposes a profile picker; the user must choose a profile before cookie-backed preview/download. The picker reads only profile IDs/display names from Brave's local registry, after Brave is selected, without reading cookie stores. Cookie access occurs only when the user invokes preview/download with a browser selected.
3. Preview is optional and shows title and duration when present. Thumbnail is optional; failure to load it does not block downloading. No raw format-ID picker is required.
4. The user selects MP4 or MP3 and chooses a destination, initially Downloads. Folder-picker cancellation leaves the prior choice intact. Remember destination and output preference locally; cookie use defaults to None on each app launch.
5. Download works immediately after valid URL/browser/profile, output and destination selection; the Preview button is optional (user refinement, 2026-10-23). Without a current matching ready preview, one core-owned download operation runs the same bounded metadata extraction and single-recorded-video validation internally, showing a cancellable preparation status, then begins transfer without exposing an intermediate ready state. Current matching ready previews skip that extra metadata command. Download reports transfer progress when available and a separate processing phase. Cancel applies during preview, preparation, transfer, and processing. Edits to URL/browser/Brave profile invalidate preview; active downloads freeze click-time URL/browser/profile/preset/destination across pending preview shutdown, preparation and transfer. Cancel or Quit while waiting for prior invalidation prevents launch. Metadata failure, collection/live input and uncertain shutdown prevent transfer; unsafe shutdown retains staging and blocks the session.
6. Success offers Show in Finder for the actual completed file. Failure offers a readable reason and retry. Retry starts a fresh job with fresh metadata preparation; no automatic credential retry or cross-session resume.

## Output contract

MP4 means H.264 video with AAC audio, selected from source formats and merged/remuxed without video transcoding. Verified source labels are existing `avc1`/`mp4a` prefixes plus exact `h264`/`aac` aliases (2026-10-23 correction); mixed labels and separate or combined streams are eligible. Alias lookalikes and unknown labels remain ineligible under strict selection, including for TikTok. Actual artifact validation remains mandatory. Use the best available compatible resolution; no resolution selector in the first slice. If the required streams are absent, report that this preset is unavailable. Sources without an audio stream are outside this initial MP4 preset.

Approved correction (2026-10-23): retain strict labelled H.264/AAC selection first.
For parsed HTTP(S) hosts equal to `facebook.com` or `instagram.com`, or a subdomain
of either, permit a progressive MP4 candidate with missing codec labels using the trailing selector
`/b[ext=mp4][vcodec^=?avc1][acodec^=?mp4a]`. Known incompatible or absent-stream
labels remain excluded. Unknown labels are not evidence of compatibility: actual
FFprobe H.264/AAC validation is mandatory before exclusive publication, and an
incompatible artifact fails as format unavailable. Other probe errors retain their
existing classifications and unsafe shutdown still retains staging. Other hosts,
including `fb.watch` and `instagr.am`, and generic direct MP4 inputs retain strict
rejection of unknown codecs. No transcoding or credential retry is added. The
[Facebook correction](../../bugfixes/2026-10-23-facebook-mp4.md) and
[Instagram extension](../../bugfixes/2026-10-23-instagram-mp4.md) record the selected-source
evidence and permitted cost: downloading then discarding an incompatible candidate.

MP3 selects an available audio source and converts when needed with FFmpeg, using VBR quality 2. Sources without audio fail clearly. Do not describe conversion as improving source fidelity. No arbitrary local-file conversion or silent output-format fallback.

Probe the resulting artifact with FFprobe before success to check the container/stream contract. A nonzero subprocess exit, missing/empty output, failed verification, or failed final move is a failed job. Missing or interrupted media fragments must fail rather than publish a playable partial result.

## Components and boundaries

- **Dependency resolver:** configured absolute executable paths, Homebrew locations, version/capability checks, explicit helper runtime locations. No shell startup scripts. Its readiness checks must establish EJS availability rather than assuming it from a Deno version check; the implementation plan must select a local, credential-free diagnostic for the installed distribution.
- **Command builder:** immutable preview/download argument arrays, validated HTTP(S) URL, explicit options and `--` delimiter. Ignore user config and default plugin directories. Disallow automatic remote component fetching; missing EJS produces a setup error. No arbitrary user flags.
- **Subprocess runner:** off-main-thread process execution, concurrent pipe draining, bounded buffers, incremental UTF-8 line framing, process-group ownership, termination escalation, and output-reader completion. Preview has a 60-second deadline; download has explicit cancel and bounded network retries rather than a short overall deadline.
- **Event decoder:** structured metadata, prefixed progress/postprocessing events, and final path event; tolerates unknown fields and absent/estimated totals. It consumes both output streams independently. Human-readable warnings are not control events.
- **Job coordinator:** owns immutable operation inputs and generation IDs; enforces one active operation; discards stale callbacks; controls staging, artifact checks, publication, and cleanup.
- **SwiftUI model/views:** main-actor presentation of state and user actions. No subprocess orchestration in view bodies.

Prefer a Swift package containing a testable core and a macOS executable, plus a reproducible local `.app` assembly script. First establish that the selected Command Line Tools/SDK can compile SwiftUI; if they cannot, document the required developer setup before changing build approaches. Do not require an Xcode-only project generator.

## State and lifecycle

States: checking dependencies, idle, previewing, ready, downloading, processing, validating, publishing, cancelling, succeeded, failed, cancelled. A new preview clears the previous result. Direct Download uses previewing as its internal preparation phase while retaining download ownership; it never emits ready between preparation and transfer. Direct Download never reuses an older preview tuple after a completed/cancelled/failed download. Only the current operation may transition ordinary job state. Inability to confirm shutdown of any owned process, including an older preview, latches a session safety block rather than being discarded as stale metadata.

Cancellation signals the owned process group, escalates after a short bounded grace period, waits for processes/readers to stop, then cleans that job's staging directory. Include FFmpeg and runtime descendants. Quit uses the same shutdown path. Disable cancellation for the brief atomic publication operation so a completed file is not ambiguously reported as cancelled.

If the OS cannot confirm shutdown within bounded supervision, fail with `shutdownUnconfirmed`, retain staging, and refuse further subprocess-starting operations for the app session. Dependency rechecks, preference changes, and coordinator replacement must not bypass this block. Quit remains available; restarting alone does not establish that previous processes stopped.

Do not claim success on transfer percentage or a final-path event alone. Require clean completion, a valid path inside the expected staging directory, a nonempty regular file, successful FFprobe validation, and successful publication.

## Files and privacy

Create a unique hidden staging directory under the chosen destination, keeping final publication on the same filesystem. yt-dlp writes an app-controlled basename there, such as `media.%(ext)s`. The UI title never becomes an unescaped yt-dlp template.

Publish to a readable title sanitized by the app, capped at 120 UTF-8 bytes, plus a full job UUID and the validated extension. Remove control characters and path separators; use `video` when the sanitized title is empty. Never overwrite an existing file. Delete only the owned staging directory after children stop; a crash may leave a directory to clean manually in v1. Never scan/delete unrelated `.part` files.

No cookie export/import or cookie-content persistence in v1. Browser access is opt-in for the operation. Brave profile selection is held only in memory and resets on launch; do not log profile registry contents, names, or cookie paths. Do not request Full Disk Access as part of normal setup. Do not persist URLs, raw metadata, titles, or raw stderr in diagnostic files. Bounded transient diagnostics must be redacted before display/copying; no verbose traffic/page dumps. Keep unknown error messages generic when safe redaction cannot be established.

## Error behavior

Separate dependency/setup, invalid URL, unsupported/collection URL, browser permission/decryption, login-required, unavailable/private, format-unavailable, network/rate-limit, disk/destination, processing, and cancellation outcomes. Pattern matching is best effort, with a safe unknown-error fallback. A browser login cannot be inferred to be expired solely from a generic extraction error.

No automatic updates or installs. Show resolved versions and package-manager maintenance guidance. Do not mutate the Homebrew installation through yt-dlp's self-update mechanism.

## Verification required before calling v1 usable

- Unit fixtures: safe argument construction, URL/option separation, split/invalid UTF-8 lines, unknown totals, stream changes, malformed events, stale preview callbacks, and success/failure transitions.
- Child-process fixtures: large stdout/stderr without deadlock, preview timeout, cancellation during an FFmpeg-like descendant operation, repeated cancel/quit, and launch failure. Prove descendants stop before cleanup.
- Local integration: generated media served from loopback, real yt-dlp plus FFmpeg/FFprobe producing MP4 and MP3, and correct artifact checks. No remote site or credentials required for this layer.
- File cases: long emoji titles, reserved/control characters, duplicate titles, preexisting outputs, unwritable/missing destination, processing failure, and publication failure.
- Manual GUI: launch the assembled app from Finder, folder picker, progress/processing/cancel/retry, responsive window, and actual Finder reveal.
- Live smoke checks: a user-selected public URL and a login-required URL using an explicitly selected browser. Record tested sites/versions and permission failures. Fixture success does not establish live site support.

## Scope boundaries

No queues, batch files, collection downloads, subtitles, Safari, generic transcoding, bundled runtimes, automatic updates, account management, telemetry, or distribution packaging. Direct distribution/signing/licensing decisions get a separate review if the intended audience changes.

## Review handoff

The user approved this design before implementation planning. The [review](../../PLAN-REVIEW.md) records findings and initial verification limits. The [implementation plan](../plans/2026-10-15-media-downloader.md) is the next review artifact. The workspace is not yet a Git repository.
