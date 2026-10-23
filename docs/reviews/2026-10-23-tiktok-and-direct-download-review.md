# TikTok and direct Download reviews

## Task 1: verified codec aliases


Spec compliant; quality Approved. No critical, important or minor findings.
Sole production change is required regex at YTDLPCommands.swift:28. Real-selector
coverage includes prefixes, exact/mixed aliases, combined/separate streams,
incompatible/missing/null/alias lookalikes (RealToolIntegrationTests.swift:16-39).
Real download cases require FFprobe and distinguish compatible publication from
falsely labelled artifact rejection (:41-64). Fixture substitution preserves
production selection/safety arguments and actual bytes/probe/final events
(:244-276). Selector fixture roots owned and retained on unsafe shutdown (:316-343).
Focused unchanged-code checks: TestSupport.swift:142 unique root ownership;
JobCoordinator.swift:146-152 verification before publication;
ProcessRunner.swift:294-316 reader join and shutdown uncertainty propagation.
No mutations, tests or live requests by reviewer /root/review_tiktok_alias.
Live TikTok remains pending per VERIFICATION.md:599. Task 2 final combined checks
are intentionally outside this Task 1 gate.

## Task 2 and final integration review

Spec compliance: Task 2 compliant. Task quality: Approved. Complete two-task
integration: Ready, with no actionable findings. Reviewed Task 2 range
9435858..9b2d94e and the non-overlapping Task 1 range 93ed7c6..9435858.

- Atomic direct Download owns preparation and transfer under one operation, shares metadata extraction with Preview, and reuses only currently ready matching metadata (JobCoordinator.swift:92,104,152).
- Click-time request/preset/destination capture, duplicate-work blocking and cancellation checks after pending invalidation preserve input identity (AppModel.swift:98,217,244).
- Exact H.264/AAC aliases preserve the existing prefix and scoped unknown-codec policies (YTDLPCommands.swift:28). Real-selector tests and actual compatible/incompatible artifacts substantiate the change (RealToolIntegrationTests.swift:16,41).
- Direct preparation tests cover metadata-return ordering, rejection, cancellation, terminal retry freshness, stale unsafe shutdown and unsafe transfer/probe retention (JobCoordinatorTests.swift:635).
- Deterministic presentation barriers cover immutable capture and Cancel/Quit while awaiting invalidation (AppModelTests.swift:286). Real loopback success/failure retains both Preview and direct entry paths (RealToolIntegrationTests.swift:66,127).

Critical: None. Important: None. Minor: None.

### Focused checks outside the diff

- Risk: preparation could start transfer before processes/readers stop. Checked ProcessRunner.swift:295 and JobCoordinator.swift:120,232 completion, cancellation and current-generation barriers.
- Risk: shared lifecycle could weaken publication or retain unsafe work incorrectly. Checked JobCoordinator.swift:163,245 verification-before-publication and unsafe-error cleanup exclusion.
- Risk: pending cancellation or stale terminal events could release the model busy gate incorrectly. Checked AppModel.swift:244,267,280 cancellation, shutdown, matching-ID reception and unconditional unsafe-session latch.

### Evidence limits

Reviewed both supplied diffs, briefs, reports and Task 1 review; recovered only a
truncated plan-refinement paragraph. No Git operations, mutations, subprocess
tests or live requests by reviewer /root/review_direct_final. Supplied final
verification reports 168 functions/16 suites; ten Python lifecycle tests; nine
explicitly enabled integration functions/62 cases; release/signature and native
build. Intentional default opt-in skips are not failures. The initial compiler
cache permission failure was resolved and disclosed.

Controller-reported TikTok direct GUI success, Finder selection and independent
H.264/AAC probe provide selected-source evidence; the reviewer did not repeat
them. Final site catalog and safe live-evidence closure were controller-owned
outside reviewed implementation commits.

### Declined to judge

- Universal TikTok/site reliability and private/login-required access: selected-source and loopback evidence cannot establish those guarantees.
- macOS 14/Intel runtime behavior and distribution readiness: untested platforms and explicitly excluded distribution scope.
- A new whole-baseline audit: previously reviewed unchanged behavior was inspected only for the concrete integration risks listed above.

Final readiness: Yes for the two-task implementation, accompanied by controller
documentation closure. Mandatory process/file safety boundaries remain intact.

## Controller closure

The rebuilt project bundle was launched by its full dist path with blank URL
and browser None. Entering the same failing TikTok source enabled Download
immediately, and clicking it without Preview completed successfully. Finder
selected the actual published MP4; independent FFprobe at that exact path
confirmed 576×1024 H.264 video and AAC audio, 31.345011 seconds, 2,155,046 bytes.
The user's previous MP3 preference was restored after testing. No actual URL,
title, format/profile identifiers, raw metadata or diagnostics are saved here.

The final site catalog is integrated and linked from README: selected-source
YouTube/Facebook/Instagram/TikTok evidence is distinct from untested candidates.
X/Twitter, Reddit and SoundCloud are the user's future priorities. The controller
accepts the review's evidence boundaries: no universal/private guarantee,
macOS14/Intel check or distribution claim is made; no unrelated baseline audit
is required by these changes. No findings remain open. The installed copy was
preserved; the updated local dist bundle is the tested deliverable.
