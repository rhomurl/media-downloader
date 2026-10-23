# Scoped Facebook MP4 review

## Spec Compliance

- ✅ Spec compliant for `9cd5e14..c5b5728`: the strict selector remains first, and only the validated HTTP(S) host equal to `facebook.com` or ending in `.facebook.com` receives the exact approved progressive fallback (`Sources/DownloaderCore/YTDLPCommands.swift:28-35`; `Sources/DownloaderCore/URLValidator.swift:4-12`). MP3 and preview selection remain unchanged.
- ✅ Actual incompatible-media failure alone gains `.formatUnavailable`; unsafe shutdown is handled before cancellation and ordinary classification, and probe exit/invalid JSON/timeout remain distinct (`Sources/DownloaderCore/JobCoordinator.swift:158-165,213-231`; `Tests/DownloaderCoreTests/JobCoordinatorTests.swift:172-185`).
- ✅ Canonical design, Task 3 plan, README, and verification evidence describe the same narrow exception and retain the live-source limits (`docs/superpowers/specs/2026-10-15-media-downloader-design.md:26`; `docs/superpowers/plans/2026-10-15-media-downloader.md:280`; `README.md:28`; `docs/VERIFICATION.md:392`).
- ⚠️ Actual failing-reel GUI success is outside this diff and remains pending. The implementation report and `docs/VERIFICATION.md:445-449` correctly avoid claiming it. The controller should retry with the user's explicitly chosen profile and record only a privacy-safe result.
- ⚠️ Process-group quiescence, exclusive file publication, and the presentation-layer shutdown latch are inherited contracts, not comprehensively re-reviewed here. This diff does not modify their implementations. Existing reported full-suite coverage is evidence supplied by the implementer, not a reviewer rerun.

## Strengths

- Host boundary regression cases cover root/subdomains/case/HTTP+port and exclude suffix lookalikes, query/fragment spoofing, a homograph, trailing-dot host, and `fb.watch` (`Tests/DownloaderCoreTests/YTDLPCommandsTests.swift:105-129`).
- The missing-value prefix filters allow absent/null labels but reject known AV1/HEVC/VP9/Opus and `none`. Focused inspection of installed yt-dlp 2026.8.19_2 `YoutubeDL.py:2204-2270,2594-2613` confirms `?` applies only to missing/null values and `b` rejects explicitly absent audio/video; no new execution or network access was needed.
- The compatible and incompatible portrait regressions both require a completed real FFprobe command, verify publication versus no output/staging, and retain the generic unknown-codec rejection (`Tests/DownloaderCoreTests/RealToolIntegrationTests.swift:49-80`; `scripts/integration.py:204-214`). The mapping changes only the exact synthetic yt-dlp input after production command construction; it forwards real process output and does not fabricate metadata, probe data, or final events (`Tests/DownloaderCoreTests/RealToolIntegrationTests.swift:179-218`).
- The test helper awaits coordinator shutdown before removing its destination and retains it for shutdown uncertainty (`Tests/DownloaderCoreTests/RealToolIntegrationTests.swift:117-128`).

## Issues

### Critical (Must Fix)

- None found.

### Important (Should Fix)

- None found.

### Minor (Nice to Have)

- None found.

## Focused checks and verification limits

- Read the provided diff in one pass, then recovered the tool-truncated integration-runner portion from the same diff; no Git commands or suite reruns.
- Named risk: host policy could accept non-HTTP(S) or userinfo input. Checked the existing `URLValidator.swift:4-12`; it validates the scheme and host and rejects user/password before the host policy runs.
- Named risk: the new missing-label candidate could bypass actual codec validation or weaken error precedence. Checked the cut-off coordinator workflow and existing `ArtifactVerifier.swift:12-44`: validation precedes synchronous publication, every audio/video stream must satisfy H.264/AAC, runner errors propagate unchanged, and uncertain shutdown skips cleanup and latches the coordinator (`JobCoordinator.swift:130-165,213-231`).
- Named risk: test source substitution could introduce browser access or remote fetch. Checked command construction around the cut-off builder function: cookies remain opt-in, config/plugins/remote components are disabled (`YTDLPCommands.swift:44-60`); the new mapping rejects any other yt-dlp input or cookie option before launching (`RealToolIntegrationTests.swift:192-196`). Generated fixtures contain only loopback media inputs.
- Supplied evidence records 151 Swift tests with seven explicit opt-in skips, ten Python lifecycle tests, six real integration functions/twelve cases, native build and release/ad-hoc-signature verification passing. No additional test was justified by a new unresolved code doubt; those runs were not repeated.

## Assessment

**Task quality:** Approved.

**Reasoning:** The two production edits implement the exact approved exception without weakening the verifier or publication gate. The regression tests exercise real selection/probing/publication behavior and preserve honest separation between synthetic verification and the pending live GUI retry.

## Controller follow-up closure

The actual-source item was resolved after this review: the same failing reel
previewed and downloaded through the rebuilt native app using the user's prior
explicit Brave profile choice. Finder selected the published MP4. Independent
FFprobe confirmed 720×1280 H.264 video plus AAC audio, 109.897188 seconds,
29,130,743 bytes. The privacy-safe live record is in VERIFICATION.md and the bugfix
plan; no actual input/profile details are recorded. Inherited process/file safety
remains unchanged and the full reported suite passed. No review finding remains
open. This outcome does not prove the source requires login or all private
Facebook content is supported.
