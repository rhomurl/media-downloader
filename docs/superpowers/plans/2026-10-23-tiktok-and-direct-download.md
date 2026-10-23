# TikTok compatibility and direct Download implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Fix the reproduced TikTok MP4 selection failure, document actual site evidence and future priorities, and let Download work without pressing Preview.

**Architecture:** Accept verified H.264/AAC label aliases without relaxing unknown-codec policy. Add an atomic core operation that checks metadata then downloads, exposed by the existing Download action; retain optional Preview and fresh-preview reuse. Keep validation, subprocess and file lifecycle in the core.

**Tech Stack:** Swift 6, macOS 14+, SwiftUI, external yt-dlp/FFmpeg/FFprobe/Deno; no new dependencies.

**Spec:** ../specs/2026-10-15-media-downloader-design.md, with the user's 2026-10-23 refinement: Download may skip the Preview button. The direct-download description below records the small requested extension; all existing safety contracts bind it.

## Global Constraints

- MP4 means H.264 video with AAC audio, selected from source formats and merged/remuxed without video transcoding.
- Probe the resulting artifact with FFprobe before success to check the container/stream contract.
- Never read browser cookies implicitly. Startup and dependency checks are credential-free. Access is allowed only for an explicitly selected browser when the user invokes preview or download. Never persist cookie contents.
- cancellation must stop owned process groups and readers before cleanup, only owned staging may be removed, publication must never overwrite, and artifact validation precedes success.
- Keep shutdownUnconfirmed session latch, stale-generation rejection, one active operation, absolute argv launches, config/plugin/remote-component restrictions and privacy contracts.
- No installs/updates, remotes/push, distribution, real-source fixtures, stored metadata/URLs/profile identifiers, or generated media/builds committed.

## Direct-download behavior

The user can paste a URL, select output/destination and explicit browser/profile,
then click Download. Preview remains optional. If a current matching preview is
ready, reuse it. Otherwise run the existing bounded metadata extraction and
single-recorded-video validation internally, then download automatically without
an intermediate ready state requiring another click. Capture URL, browser/profile,
preset and destination at click time; freeze UI inputs for the entire operation.
Show a preparation status while metadata loads and allow Cancel. Metadata failure,
collection/live rejection, cancellation or shutdown uncertainty must prevent the
media-transfer phase. Retry is explicit and fresh. Browser choice still resets
on launch. No site-specific auto-cookie retry or automatic credential selection.

## Review Focus

- Cancel or Quit while internal metadata extraction or its pending invalidation barrier is in progress must prevent transfer.
- Concurrent clicks, URL/browser/profile changes, stale preview completion and dependency rechecks must not substitute inputs or start a second operation.
- Missing/invalid URL, no explicit Brave profile, collection/live sources and failed metadata must fail without staging/publication.
- Real yt-dlp selector semantics must admit exact h264/aac aliases and mixed verified labels, while rejecting unknown or incompatible/absent codecs.
- Verified output/publication/shutdown behavior and the optional explicit Preview workflow must remain intact.

### Task 1: Verified H.264/AAC aliases for TikTok

**Files:** Sources/DownloaderCore/YTDLPCommands.swift; Tests/DownloaderCoreTests/YTDLPCommandsTests.swift and RealToolIntegrationTests.swift (or focused test helper); approved design output paragraph; original Task 3 selector paragraph; README.md; docs/VERIFICATION.md.

**Evidence:** Native TikTok preview succeeds with browser None and download fails
formatUnavailable. Live metadata uses h264/aac labels with no avc1/mp4a entry.
A temporary observed-format download without publication passes the normal real
ArtifactVerifier as H.264/AAC; owned diagnostic media was cleaned. Installed and
upstream TikTok extraction explicitly emit h264/aac. Do not record real inputs.

- [ ] Add genuine failing selector tests using installed real yt-dlp and entirely
  synthetic metadata/loopback media. Accept existing avc1/mp4a prefixes plus exact
  h264 and aac aliases, including mixed labels, separate streams and combined
  streams. Reject h265/HEVC/AV1/VP9/Opus/none, missing/null and lookalike alias strings
  (h264junk/aacjunk). Reject unknown codecs for generic/TikTok inputs. Preserve the
  existing Facebook/Instagram-only unknown-label progressive exception verbatim.
- [ ] Use regex filters preserving old prefix behavior and exact aliases:
  `bv[vcodec~='^(avc1.*|h264)$']+ba[acodec~='^(mp4a.*|aac)$']/b[vcodec~='^(avc1.*|h264)$'][acodec~='^(mp4a.*|aac)$']`.
  Verify this exact syntax with installed yt-dlp rather than only string assertions.
  Keep strict labelled selection first, the existing scoped trailing selector,
  remux/no-transcoding and all launch flags unchanged. No TikTok unknown fallback.
- [ ] Add a real loopback positive alias case through actual download and artifact
  validation (synthetic labelled info JSON is allowed; a test-only runner may load
  that fixture after production argv construction, preserving actual downloaded
  bytes/probe results). Include falsely labelled incompatible fixture rejection
  if the fixture infrastructure can share the existing portrait pair. Clearly
  disclose synthetic metadata, no fabricated process/probe/final-event success.
  Keep fixture files under owned integration roots and cleanup barriers intact.
- [ ] Run focused RED/GREEN command and enabled loopback checks. Update docs with
  verified aliases, safe evidence, and live-retry pending. Self-review, diff check
  and commit scoped files. Full final verification runs in Task 2 after combined
  final code; do not redundantly run full/release checks in Task 1.
- [ ] Write task-1-report.md with files, RED/GREEN command evidence/counts, limits
  and commit. No subagents or live requests; root handles independent review.

### Task 2: Direct Download with cancellable internal metadata validation

**Files:** Sources/DownloaderCore/JobCoordinator.swift; Sources/DownloaderPresentation/AppModel.swift; Sources/MediaDownloaderApp/MainView.swift and relevant status/error copy; Tests/DownloaderCoreTests/JobCoordinatorTests.swift, Tests/DownloaderPresentationTests/AppModelTests.swift, Tests/DownloaderCoreTests/RealToolIntegrationTests.swift; README.md; canonical design flow and original Tasks 6/7/8 notes; docs/VERIFICATION.md.

**Interfaces:** Keep existing `download(preset:destination:previewOperationID:operationID:)`
for matching-ready preview reuse. Add overload on JobCoordinator and JobCoordinating:
`download(_ request: PreviewRequest, preset: OutputPreset, destination: URL, operationID: UUID) async -> Bool`.
It owns one download operation across metadata preparation and transfer. Reuse
metadata extraction/validation internally without duplicating the parser/runner
logic. Do not orchestrate subprocesses in views or chain via observer polling.

- [ ] Add failing tests for direct MP4/MP3, immutable click-time capture, valid
  matching-preview reuse, missing/invalid URL, explicit Brave profile requirement,
  metadata/collection/live rejection, repeated clicks and stale completion.
- [ ] Add deterministic barrier-based tests: cancel/quit during metadata and while
  awaiting an earlier invalidation, concurrent new requests, metadata failure,
  unsafe shutdown (including stale operation) cannot launch media/probe or clean
  retained staging. Prove metadata completion is joined before transfer. Existing
  old-ready tests should assert no stale authorization/metadata; canDownload now
  means eligible to begin preparation, not proof of already-ready metadata.
- [ ] Implement the overload and AppModel path. Guard identity/cancellation again
  after every suspension and before launch. Freeze operation inputs from click,
  block dependency changes and duplicate work, preserve shutdown precedence and
  never expose intermediate ready as an opportunity for another launch. Avoid
  sleeps, task-yield assumptions and duplicated operation lifecycle logic.
- [ ] Enable Download when dependencies and URL/browser/profile inputs allow a new
  operation; keep Preview optional and busy/blocked states disabled. Validate
  invalid URL before spawning. Update initial/status/error copy to avoid insisting
  on Preview; preserve safe fixed error strings.
- [ ] Extend real loopback MP4/MP3 success and preparation-failure coverage to the
  new direct coordinator entry, while retaining explicit Preview coverage.
- [ ] Update canonical flow and README; link docs/SUPPORTED-SITES.md (root/research
  agent owns that file; do not modify it). Record safe actual verification.
- [ ] Run focused RED/GREEN, then one final `bash scripts/verify.sh --integration`
  (includes bash scripts/test.sh, release/signature, Python lifecycle and real
  loopback) and `swift build --product MediaDownloader`. Required checks must pass;
  fix actual failures before claiming completion. Escalate for approved standard
  SwiftPM/cache/process/loopback permissions. No installs/updates.
- [ ] Self-review and commit only scoped files, write task-2-report.md with exact
  results/limits. No subagents or live requests. Root independently reviews final
  work, retries actual TikTok through the direct Download GUI, checks Finder exact
  output with FFprobe, and records honest per-site verification limits.

## Site documentation companion

A research worker owns only docs/SUPPORTED-SITES.md. It distinguishes verified
selected-source YouTube/Facebook/Instagram evidence from pending TikTok and untested
extractor availability. User priorities are X/Twitter, Reddit and SoundCloud;
these are future integration checks, not promised working sites. Root integrates
this document and updates TikTok status only after actual live success. No new
site feature beyond verified aliases is authorized by merely listing candidates.
