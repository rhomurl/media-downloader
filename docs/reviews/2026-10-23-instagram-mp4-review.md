# Scoped Instagram MP4 review

## Spec Compliance

- ✅ Spec compliant for `0ebef4e..a36d25c`. The only production change adds parsed `instagram.com` apex/subdomains to the existing Facebook condition. Strict selection remains first; the fallback selector, remux options, and MP3 behavior remain unchanged (`Sources/DownloaderCore/YTDLPCommands.swift:28`).
- ✅ Required documentation is synchronized in `README.md:28`, `docs/superpowers/specs/2026-10-15-media-downloader-design.md:27`, `docs/superpowers/plans/2026-10-15-media-downloader.md:280`, and `docs/VERIFICATION.md:483`.
- ⚠️ Live Instagram download, selected-profile behavior, native GUI retry, and Finder confirmation were controller-owned and pending at the reviewed commit. Synthetic integration success does not establish those behaviors (`docs/VERIFICATION.md:529`).
- ⚠️ Process-group cancellation, credential-free startup, owned-staging cleanup, and exclusive publication implementations are unchanged. Their broader guarantees inherit baseline review and verification; this scoped review does not independently re-establish them.

## Strengths

- The host check uses the validated URL's lowercased host and dot-delimited subdomain suffixes, preserving the intended boundary without query/path matching (`Sources/DownloaderCore/YTDLPCommands.swift:29`).
- Command regressions cover apex, nested subdomains, uppercase, HTTP/port, suffix and Unicode lookalikes, redirect domains, path/query/fragment decoys, and userinfo rejection (`Tests/DownloaderCoreTests/YTDLPCommandsTests.swift:131`).
- The integration matrix exercises both hosts and both media variants through production command construction. Each case requires a completed FFprobe call; compatible output receives another real artifact verification, while incompatible output must fail with `formatUnavailable`, no output, and an empty destination (`Tests/DownloaderCoreTests/RealToolIntegrationTests.swift:48`).
- Test-only mapping accepts exactly the two synthetic source constants, rejects browser-cookie flags, and substitutes loopback only after production command construction (`Tests/DownloaderCoreTests/RealToolIntegrationTests.swift:199`).

## Issues

- Critical: None.
- Important: None.
- Minor: None.

## Checks and evidence limits

- Reviewed supplied range `0ebef4e27b11d8ea2f3bdc3bbbd0bb184dc82392..a36d25c044e783047424c06cccefb2d27e190513`, its task brief, and implementer report.
- Initial combined tool output truncated the package. Recovered omitted report and diff portions; no Git commands were run.
- Two integration functions were cut off by diff context. Focused reads of `RealToolIntegrationTests.swift:48–74` and `:194–223` confirmed publication/rejection assertions and real-runner probe counting. No broader code crawl was performed.
- Supplied evidence reports genuine command-test and integration RED, followed by GREEN; final combined verification reports 154 tests across 16 suites, ten Python lifecycle tests, and six real-integration functions/fourteen cases. Native build and diff check also passed. These are implementer-reported executions, not reviewer reruns.
- Default-suite opt-in skips and the intentionally retained failed-RED fixture root are disclosed. No unexplained warnings or failures appear in the supplied report.
- No test execution, mutations, subagents, browser access, or external requests were performed during this review.

## Declined to judge

- Unrelated baseline Facebook/app implementation and earlier eight-task history: explicitly excluded from this complete bugfix review surface.
- Live Instagram/profile/GUI/Finder success: pending separate controller verification; unavailable from the reviewed diff and synthetic evidence.

## Assessment

Task quality: Approved. Whole-bugfix-range readiness: Approved for integration;
live retry was outstanding at review time. The minimal host-policy extension
matches the approved scope and preserves the existing validation boundary.
Regression coverage exercises host discrimination and actual compatible/
incompatible artifact outcomes without introducing production test hooks.

## Controller closure

Both deferred items are accounted for. The unrelated baseline remains unchanged
and retains its existing review evidence. The selected-source native retry was
completed independently after this commit: preview/download succeeded with the
user's previously explicit Brave profile. Finder selected the published file;
FFprobe at that exact path confirmed 720×1280 H.264 video and AAC audio,
23.727937 seconds, 20,026,153 bytes. Browser choice reset to None on relaunch.
The bugfix plan and VERIFICATION.md preserve privacy-safe evidence and limits.
No findings remain open. This does not establish that the source requires login
or that every private Instagram source is supported.
