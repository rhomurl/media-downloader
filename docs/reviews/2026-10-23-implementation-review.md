# Final whole-branch review

Reviewed 2026-10-23. Base `14fa34e`; head `7c62b0a`; 19 commits, 67 changed files. Scope: the approved personal native macOS downloader and its development harness. The review used `review-14fa34e..7c62b0a.diff`, the current source at that head, `AGENTS.md`, the approved design, implementation plan, implementation decisions, and verification record.

## Strengths

- Process ownership is treated as a completion condition. `ProcessRunner` retains the direct child until its final group signal and inspection, checks for live group members, joins pipe readers and callback delivery, and propagates `shutdownUnconfirmed` ahead of cancellation. The coordinator preserves staging and the presentation layer latches the same block across dependency checks and coordinator replacement.
- Success has a clear chain of prerequisites: successful tool exit, exactly one final-path event, the expected nonempty regular staging file, compatible FFprobe output, and an exclusive same-filesystem rename. Cleanup checks directory identity and uses descriptor-relative traversal without following links. Failed or duplicate control events cannot be mistaken for completed media.
- Command construction is separated from process execution and presentation. Absolute executable paths, argument arrays, an environment allowlist, disabled configs/plugins/remote components, and explicit browser/profile arguments make the intended execution policy inspectable. Startup readiness has no URL or cookie arguments and establishes local EJS discovery separately from Deno's version.
- UI operation identity is established before suspension and checked again when Download captures the ready request. The shared app model and quit delegate use one coordinator lifecycle. Terminal snapshots clear `downloadActive`; the ordinary succeeded/failed/cancelled paths therefore restore folder selection and other controls.
- Tests exercise meaningful failure boundaries: real closed-output descendants, callback completion, cancellation/timeout precedence, stale generations, exclusive publication, replaced directories, malformed controls, probe rejection, missing fragments, and real loopback MP4/MP3 outputs. Verification documentation distinguishes automated results, controller GUI observations, selected public-site observations, and unresolved private/browser checks.

## Issues

### Critical — must fix

None found.

### Important — should fix

None found.

### Minor — nice to have

1. **[P3] Await the stale profile refresh itself before asserting its rejection.**
   - File: `Tests/DownloaderPresentationTests/AppModelTests.swift:58` (test starts at line 52).
   - Trigger: release the held profile provider after switching the browser from Brave to None. `AppModel.browser.didSet` already sets `isLoadingProfiles = false` synchronously at `Sources/DownloaderPresentation/AppModel.swift:32`, so `eventually { !isLoadingProfiles }` may return before the released refresh resumes on the main actor. The next assertion can observe the cleared state without exercising the stale response. The following `shutdown()` can then make the response fail its `closed` check, masking a regression in the browser/epoch guard.
   - Impact: this regression test can pass without proving the Task 7 stale-profile requirement. This is a test ordering weakness, not an observed product defect: the current guard at `AppModel.swift:187` correctly checks closure, browser, and profile epoch.
   - Fix: retain and await a refresh task that the test explicitly starts. For example, finish the automatic initial load, hold the next provider call, start an explicit refresh task, switch away, release the provider, await that task's value, and then assert that no profiles/selection were restored. Avoid substituting sleeps or a fixed number of yields for the completion barrier.
   - Triage: retain as a nonblocking minor finding. It does not justify changing the production guard or reopening the completed lifecycle implementation.

## Plan alignment and quality

The implementation supplies all eight planned components within the approved scope: Swift 6/macOS 14 package, supervised subprocesses, extraction commands and decoders, offline tool readiness, owned staging and validation/publication, generation-safe coordination, native presentation and quit handling, and local bundle/integration tooling. There are no third-party Swift package dependencies or runtime install/update paths.

The documented adjustments preserve or strengthen the contracts: explicit ephemeral Brave profiles, the CLT test wrapper, libproc quiescence inspection, fail-closed session blocking, all-stream codec validation, and abort-on-unavailable-fragments. The caller-supplied operation ID and expected-preview ID adapter is narrowly scoped to the presentation race it addresses. The developer harness's retention policy is accurately narrower than arbitrary descendant containment.

The remaining verification work is not equivalent to missing implementation. Cookie-backed/private-site behavior, native permission flows, and the listed platform/GUI checks are explicitly pending. The code is suitable for accepting the personal-app implementation with those limits; it is not evidence that every planned live/manual check has completed.

## Evidence and verification limits

- This was a read-only source review except for this requested report. `HEAD` was verified as `7c62b0a`, with a clean working tree before the report. `git diff --check 14fa34e..7c62b0a` passed. No package-wide suite, native UI action, cookie/profile access, external-site request, install, Git mutation, or distribution action was performed by this reviewer.
- The controller's recorded combined run on `dad298c` reports 146 Swift test functions across 16 suites, including six explicit opt-in skips; separately enabled integration passed five functions/ten cases; nine Python lifecycle tests and release-bundle/signature checks passed. These are controller-reported execution results, not reruns by this reviewer. The reviewed real tests do invoke the production coordinator, runner, verifier, and publisher.
- Changes from `dad298c` to `7c62b0a` are limited to the verification document and Python harness/tests. The latest fix evaluates the final live-PID lookup before reading `tree.uncertain`, and its focused regression deliberately introduces uncertainty during that lookup. The parent reports ten Python tests passing in 10.097 seconds after that change. No Swift or app binary source changed in this range.
- Native folder-picker behavior after completed jobs was considered. The inspected terminal-state model releases `downloadActive` for matching succeeded/failed/cancelled snapshots, and the view disables the button only while busy. The reported automation clicks that sometimes showed no panel do not establish a source-level product defect. A reproducible native failure would need a separate targeted check; this review does not certify every post-download AppKit interaction.
- The selected public YouTube MP4/MP3 and Finder observations are recorded by the controller. They do not establish general public-site coverage. Actual Brave registry/profile/cookie access, private/login-required extraction, and browser/Keychain permissions remain unverified. Minimal inherited PATH, visually observed processing/validation, GUI FFmpeg/Deno-descendant shutdown, VoiceOver/dynamic type, macOS 14 execution, and Intel execution also remain unverified as documented.

## Recommendations

Fix the one small test barrier when convenient, then run its focused presentation test. Preserve the existing distinction between implementation acceptance and live/private-site readiness in the final handoff; no broad retesting is indicated by this review alone.

## Declined to judge

- Developer ID signing, notarization, Gatekeeper distribution behavior, public release, and bundled-runtime licensing: distribution is explicitly outside the approved personal v1 scope.
- Queues, batch/collection downloads, subtitles, Safari, arbitrary local conversion/transcoding, account management, telemetry, and automatic updates: explicitly deferred features, not gaps in this branch.
- Protection against a malicious same-UID process racing the exact path-based publication syscall: explicitly excluded by implementation decision 12; ordinary replacement, symlink, ownership, and overwrite cases were reviewed.
- Containment of arbitrary fast daemonization by a hostile test driver or trusted external tool replacement: outside the documented process-group and bounded ancestry guarantees. The harness's forced/uncertain retention policy was reviewed; no broader containment claim is endorsed.
- Compatibility with every remote site or every future yt-dlp/runtime version: outside any bounded smoke test and dependent on external software/services. Current command and fail-closed readiness behavior were reviewed.

## Assessment

**Ready to merge? Yes, with one nonblocking minor test improvement.**

No critical or important defect was found in the reviewed production paths or final harness fix. The branch preserves the approved process, file, credential, and publication contracts; acceptance should retain the explicit live/browser and platform verification limits rather than claim unrestricted v1 readiness.

## Follow-up closure

The sole P3 was fixed in `b49d7ef`. A deliberate stale-guard mutation failed the
strengthened test, the restored production guards passed all 22 presentation
tests, and scoped review approved the explicit callback-completion barrier.

A subsequent full validation run exposed an existing test-adapter race in the
orphan-process Quit fixture. This was reproduced deterministically and corrected
in test-only commit `3834115`: normal and throwing process returns now reach the
same held boundary; error cleanup joins shutdown before deleting owned files and
retains uncertainty. Scoped review approved both corrections with no new
findings. The controller's final full suite passed 148 tests in 16 suites in
10.795 seconds. App source, resources, and bundle assembly are unchanged since
`f735190`, the production version exercised by the GUI/public checks.

### Profile test scoped review

- **P3: Await the stale profile refresh itself before asserting its rejection — ADDRESSED.** `Tests/DownloaderPresentationTests/AppModelTests.swift:55-64` finishes the initial load, retains an explicit refresh Task, waits for provider entry, switches away, releases the provider, and awaits `refresh.value` before asserting empty profiles/selection and shutting down. The stale callback must therefore finish while the model is still open.
- **Provider-entry barrier — checked.** `Tests/DownloaderPresentationTests/AppModelTests.swift:274-289` installs the held continuation before resuming the entry waiter. Actor isolation serializes registration and entry; `waitForHeldRefresh()` also returns immediately if entry already occurred. The single held call in this test is released before awaiting Task completion. No lost wakeup or new hang is apparent in the exercised sequence; no fixed sleep/yield was added.
- **New Breakage in the Fix Diff:** None found. The supplied `7c62b0a..b49d7ef` package contains one tests-only commit; no production change appears in it.
- **Out-of-Scope Observations:** None.
- **Checks:** Read the supplied diff once, the original P3, the fix brief/report, relevant Task 7/design contracts, and the changed test/helper with the production refresh guard for context. No suites or mutations were run. The report names the focused mutation command, exit 1 and failed post-refresh assertion, followed by `bash scripts/test.sh --filter AppModelTests`, exit 0 and 22 passing tests. These remain implementer-reported results, consistent with the reviewed change; no independent rerun is claimed.
- **Fix round: All findings addressed, no new Critical/Important breakage.**

### Descendant test repair scoped review

# Finding Verdicts

- **Normal ProcessRunner return bypasses the stopped/release boundary** — **ADDRESSED**. `Tests/DownloaderCoreTests/JobCoordinatorTests.swift:497–509` captures both underlying outcomes, emits the common `stopped` signal, awaits the same explicit release, and returns/rethrows the saved outcome. No normal-return bypass remains. `naturalDescendantReturnStillHoldsStoppedBoundaryBeforeQuit` at lines 557–580 forces normal underlying completion before Quit, checks the child is absent/zombie, and checks staging plus the incomplete adapter while cancellation is held at the gate.
- **Throwing test exits can remove the destination before asynchronous shutdown finishes** — **ADDRESSED**. The real-descendant test uses `withDescendantFixture` at `Tests/DownloaderCoreTests/JobCoordinatorTests.swift:389`. Both helper exits at lines 620–630 open the latch, await joined `coordinator.shutdown()`, and only then remove the unique test-owned root when the final issue is not `.shutdownUnconfirmed`. The throwing branch preserves the original body error. The injected safe/unsafe cases at lines 584–607 verify adapter completion before helper return and retain the synthetic uncertain root; the explicit later deletion is restricted to the case that launched no process.

# New Breakage in the Fix Diff

- **None.** The uncancellable `TestLatch` (`Tests/DownloaderCoreTests/TestSupport.swift:43–55`) cannot replace the saved typed error or release the adapter merely because Quit cancelled its task. Opening it on both helper exits prevents a test failure from stranding the deliberate gate. The underlying runner remains responsible for bounded process/readers shutdown; uncertainty does not become evidence of quiescence.

# Out-of-Scope Observations

- **None.** Review was restricted to the two defects, the supplied `b49d7ef..3834115` fix diff, and the helper/shutdown contracts needed to assess that diff.

# Evidence and Safety Checks

- **Recorded RED checked:** `final-validation-natural-return-red.log:14–18` names the forced-natural-return regression and records one deadline issue after 5.113 seconds. This matches the old success-branch bypass shown in the supplied diff.
- **Recorded focused GREEN checked:** `final-validation-descendant-focused.log:14–25` names all three covering tests and the two fork/orphan plus two safe/unsafe parameter cases; three tests / five cases passed, one suite, 2.029 seconds.
- **Recorded full GREEN checked:** `final-validation-descendant-full.log:429`, `:457`, `:485`, and `:503` show the covering tests and 148 tests / 16 suites passed in 10.725 seconds. These are inspected prior-run logs, not independently rerun results. The implementer's report also records exit 0 and a clean `git diff --check`; that diff-check result was not rerun.
- **Scope checked:** The supplied package changes only `Tests/DownloaderCoreTests/JobCoordinatorTests.swift`. Production process execution, browser/cookie policy, command construction, artifact validation, staging ownership, and exclusive publication remain unchanged. The synthetic uncertainty case starts no process. No additional test was warranted by a specific unresolved doubt, so no suite or focused test was rerun during this review.
- **Verification limits retained:** Fixture/log evidence establishes this test-ordering repair. It does not establish live-site support, browser permissions, GUI/Finder behavior, or real-media compatibility. No app product or bundle build was performed for this review. Product files, Git state, and the controller-owned `docs/reviews/` archive were not modified; only this requested ignored review report was written.

# Verdict

- **Fix round: All findings addressed, no new Critical/Important breakage.** Both reported defects are closed within the test-only repair.
