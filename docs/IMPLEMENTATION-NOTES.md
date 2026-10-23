# Implementation decisions

The user approved the personal-use design and chose subagent-driven implementation.
The repository began empty and remains on `codex/personal-downloader`, with no
remote, push, release, or distribution step authorized. Each implementation task
has an independent spec and quality review; current verification evidence is in
[VERIFICATION.md](VERIFICATION.md).

## Decisions made during execution

These record the reasoning and costs of implementation choices made under the
approved scope, in chronological order.

1. Initialize the empty repository directly on codex/personal-downloader and work in this new checkout — no prior source checkout exists to protect and no worktree was requested — cost if wrong: moving this new branch to another checkout.
2. Task 1 Git initialization/document baseline are already done by the controller to establish review ranges — execution requires a commit before the first task can be reviewed — cost if wrong: one extra documentation commit.
3. Add a portable scripts/test.sh wrapper for the selected CLT framework search paths and use it in place of bare swift test throughout — this SDK compiles SwiftUI but bare SwiftPM cannot locate Testing.framework; product targets remain free of machine-specific flags — cost if wrong: wrapper adjustment for a future toolchain.
4. On natural direct-child exit retain its zombie while immediately killing residual owned group members, then reap/drain; reserve the 2-second TERM grace for active cancellation/timeouts — avoids adding fixed delay to every dependency/preview/probe command while preventing process-group ID reuse — cost if wrong: helpers that intentionally outlive a completed leader are stopped immediately (not supported by this command contract).
5. Extend the CLT-only test wrapper with -Xfrontend -disable-cross-import-overlays — this installed SDK lacks the Testing/Foundation overlay module, and process tests require both imports — cost if wrong: test overlay conveniences are unavailable under this toolchain; production compilation is unchanged.
6. Add a developer-only C helper for ProcessFixture fork modes — Darwin marks Swift fork unavailable, while post-fork signal-safe fixture behavior must be real — cost if wrong: an extra test-only target to maintain; no production C dependency.
7. Clarify AGENTS.md to permit synthetic metadata/URL fixtures while forbidding actual user URLs and live extracted data — the original categorical wording would prevent the plan's required offline tests — cost if wrong: reviewers must distinguish synthetic fixtures from real private data.
8. Use a macOS system API (libproc, with a small production C shim if Swift import requires it) to verify no live owned group members before releasing retained leader/returning — reproduced cleanup race outweighs avoiding an extra system helper — cost if wrong: macOS-specific supervision code and failure-path complexity; no external dependency.
9. Add ProcessFailure.shutdownUnconfirmed(Int32), taking precedence over cancellation/timeout; bound post-SIGKILL inspection and background reaper resources; downstream preserves staging on that error — OS inspection may fail or killed processes may not quiesce promptly, so cleanup must fail closed without hanging UI — cost if wrong: rare failures retain temporary files for manual cleanup.
10. Wrap download progress as {progress:<progress JSON>,stream_id:<info.format_id>} — installed yt-dlp removes info_dict before rendering templates, so the previous command could not supply stream identity — cost if wrong: decoder/template must change together if upstream fields change.
11. Prove hidden accepted yt-dlp aliases --no-colors/--playlist-end with explicit offline no-URL parser execution, requiring advertised modern equivalents plus readiness markers and expected missing-URL exit2 — installed help omits these aliases despite accepting them — cost if wrong: a future alias removal becomes a setup error until commands are updated.
12. Keep planned URL-based FilePublishing and exclusive atomic publication; reject observed path/inode changes and use descriptor-relative no-follow cleanup, but do not promise protection against a hostile same-user process racing the precise publication syscall — this personal tool assumes no concurrently malicious same-UID actor, and changing publishing API is unnecessary for ordinary replacement safety — cost if wrong: publication safety would need a stronger descriptor/identity-aware API for that threat.
13. Latch ProcessFailure.shutdownUnconfirmed for the coordinator session, expose distinct AppIssue.shutdownUnconfirmed, and refuse new preview/download; UI must retain this session block even through dependency rechecks — unknown descendants may still exist, so permitting retry would undermine one-active-operation safety — cost if wrong: a transient inspection failure requires quitting/checking tools before reopening. DependencyResolver already stops at first execute failure; Task7 must latch its shutdown-unconfirmed report code too.
14. The developer integration harness may supervise bounded identity-checked known descendants across process groups, but must retain its fixture root after forced timeout/interruption, failed/crashed driver, incomplete monitoring or uncertain ancestry, even when observed PIDs stop — macOS Python polling cannot prove containment of arbitrary fast daemonization, so fail-closed retention is preferable to broader OS containment — cost if wrong: failed developer runs may leave private temporary fixture directories for manual cleanup; arbitrary daemonizing test drivers remain outside the proof. HTTP workers still must be closed/joined before normal cleanup.

## Completion record

All eight implementation tasks passed independent spec/quality gates. Final
whole-branch review found no critical or important defect; its one minor test
finding and the separately discovered final-validation fixture race were fixed
and passed scoped review. The final Swift suite passed 148 reported tests with
six explicit opt-in skips; ten Python lifecycle tests and separately enabled
real MP4/MP3 integration passed. Native GUI and the selected public YouTube
MP4/MP3 checks passed within the exact limits in [VERIFICATION.md](VERIFICATION.md).

The [review record](reviews/2026-10-23-implementation-review.md) preserves the final
assessment and follow-up closure. Keep the local branch and checkout; no remote,
push, merge target, public release, or distribution was requested. Login-required
and actual browser-profile/cookie checks remain pending explicit user input.
