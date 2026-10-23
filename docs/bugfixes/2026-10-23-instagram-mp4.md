# Instagram progressive MP4 correction

## Confirmed cause and decision

The selected Instagram reel previews successfully with the user's explicitly
selected Brave profile but fails the MP4 format selector. Live metadata contains
labelled VP9 video and AAC audio plus progressive MP4 candidates missing both
codec labels. A temporary diagnostic downloaded one observed candidate without
publishing; the normal ArtifactVerifier confirmed H.264/AAC. Owned diagnostic
media was removed after runners/readers and FFprobe completed. No actual URL,
source ID/title, profile name/ID, raw metadata, or cookie data is recorded here.

Ruling: extend the existing Facebook-only missing-codec progressive MP4 fallback
to parsed instagram.com and its subdomains, retaining strict selection first and
mandatory actual H.264/AAC verification before exclusive publication — reproduced
live evidence establishes a compatible candidate that missing labels exclude —
cost if wrong: an incompatible Instagram candidate can be downloaded and then
discarded; it cannot be published.

All other hosts, including generic direct MP4, fb.watch and lookalike domains,
retain strict selection. No transcoding, global relaxation, arbitrary selectors,
credential retry, profile persistence, or changes to process/file safety.

Approved design: ../superpowers/specs/2026-10-15-media-downloader-design.md.
Relevant original task: Task 3 in ../superpowers/plans/2026-10-15-media-downloader.md.
This correction narrowly extends the documented Facebook exception; all output,
process, file and credential contracts remain binding.

### Task 1: Extend the guarded candidate policy with regression coverage

1. Read AGENTS.md, the approved design and original Task 3. Extend only the host
   condition/comment in Sources/DownloaderCore/YTDLPCommands.swift to include exact
   instagram.com and subdomains. Preserve strict selector first and the existing
   trailing `/b[ext=mp4][vcodec^=?avc1][acodec^=?mp4a]`. Known incompatible/absent
   codecs remain excluded. Do not change coordinator or artifact validation.
2. TDD: add failing command tests for Instagram apex/subdomains/case and deceptive
   URL boundaries, then the minimal change. Preserve Facebook and generic strict
   tests. Test host parsing, not substrings in query/path/userinfo or suffix lookalikes.
3. Reuse the existing portrait-compatible.mp4 and portrait-incompatible.mp4 real
   loopback fixtures. Minimally generalize the test-only exact synthetic Facebook
   mapping to include an exact synthetic Instagram source. Parameterize both hosts
   and compatibility. Production builder policy must run before the mapping;
   cookies/external requests stay forbidden. Compatible unknown-label media must
   reach real FFprobe and publish; incompatible media must reach FFprobe and fail
   formatUnavailable with no publication or staging. Keep generic unknown-codec
   direct MP4 rejection. Capture genuine RED for the Instagram integration case.
4. Synchronize the design exception, original Task 3 exception, README and
   docs/VERIFICATION.md with the exact host scope. Preserve earlier historical
   evidence. Add only safe current results, counts and limitations.
5. Run focused RED/GREEN, then `bash scripts/verify.sh --integration` once on final
   code (this runs bash scripts/test.sh, release build, Python lifecycle checks and
   real loopback tests), plus `swift build --product MediaDownloader`. Use approved
   escalated permissions for SwiftPM/cache/process/loopback checks. No installs or
   updates. Do not repeat broad checks unless a failure/change warrants it.
6. Self-review and commit scoped implementation/docs only. Never commit live inputs,
   diagnostics/media/tools/build products. Write the implementer report in the
   task workspace with changed files, RED/GREEN evidence, exact command results,
   remaining limits and commit. Do not spawn subagents or perform live access.

Controller follow-up: independently review spec and quality, rebuild and retry
through the app with the same explicitly selected source/profile. Verify actual
published file via Finder and FFprobe; record safe evidence separately. Preserve
review and decision in tracked docs, then remove only this task's scratch workspace.

Sources: [upstream Instagram extraction](https://github.com/yt-dlp/yt-dlp/blob/master/yt_dlp/extractor/instagram.py)
and [format filter semantics](https://github.com/yt-dlp/yt-dlp#filtering-formats).
