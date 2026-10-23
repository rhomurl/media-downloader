# Verification evidence

Current local evidence includes the Facebook MP4 fix and Instagram extension sections
(2026-10-23), below. Earlier
sections retain their original observations and limits. Local automated checks
and bundle signing are distinct from the controller GUI/public observations and
remaining live/browser limits recorded below.

## Developer setup

- `swift --version`: swift-driver 1.127.14.1, Apple Swift 6.2
  (`swiftlang-6.2.0.19.9 clang-1700.3.19.1`), target `arm64-apple-macosx26.0`.
- `xcode-select -p`: `/Library/Developer/CommandLineTools`.
- `xcrun --sdk macosx --show-sdk-path`:
  `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`.
- `/Applications` contains no Xcode.app. No global developer-directory changes
  were made.

The initial sandboxed `swift build --product MediaDownloader` exited 1 because
SwiftPM/Clang caches were inaccessible (`Operation not permitted` opening
`~/.cache/clang/ModuleCache/.../SwiftShims-UTLVU43OQQS4.pcm`). Its cascading diagnostic
also said `this SDK is not supported by the compiler`. Rerunning the identical
command with cache filesystem access succeeded, importing SwiftUI and linking the
native executable (38.44 seconds). That proves the selected SDK/toolchain can
build this app; the initial message did not establish a compiler incompatibility.

## Swift Testing discovery correction

Plain `swift test --filter cookieAccessIsAnExplicitChoice` exited 1 with
`no such module 'Testing'`. Verbose output showed SwiftPM passing `-I` and `-L`
for the CLT frameworks directory; Testing is installed as `Testing.framework`.
Adding Swift and linker `-F` reached the intended missing-domain-type RED failure.
After implementing the contracts, those flags built tests but execution failed
with `Library not loaded: @rpath/Testing.framework/Versions/A/Testing` (signal 5).
Adding the framework directory as a linker rpath resolved runtime discovery.

`scripts/test.sh` derives the selected CLT directory and supplies:

```sh
swift test -Xswiftc "-F$framework_dir" -Xlinker "-F$framework_dir" \
  -Xlinker -rpath -Xlinker "$framework_dir" "$@"
```

It applies these flags only to a selected standalone CommandLineTools installation
containing Testing.framework. It leaves the package manifest and product targets
free of machine-specific paths. Test execution requires normal compiler-cache
filesystem access in the Codex sandbox.

## Task 1 results

- RED: filtered contract compilation failed for missing `CookieBrowser` and
  `OutputPreset` before domain implementation, with explicit framework flags.
- GREEN: `bash scripts/test.sh --filter cookieAccessIsAnExplicitChoice` passed
  1 test with 0 failures.
- Full suite: `bash scripts/test.sh` passed 1 test with 0 failures.
- Native build: `swift build --product MediaDownloader` succeeded.

The suite currently covers the explicit browser/output choices only. No process
runner, command builder, runtime dependencies, files, downloads, Finder launch,
GUI interaction, cookies, remote URLs, or live sites have been tested in Task 1.
The minimum macOS deployment target is configured as 14; this run does not prove
execution on macOS 14 hardware.

## Task 4: offline external-tool readiness

Observed 2026-10-15 on the same Apple Silicon macOS machine. The resolver found
all four tools under `/opt/homebrew/bin` and reported no setup problems:

| Tool | Parsed version |
| --- | --- |
| yt-dlp | 2026.08.19 |
| FFmpeg | 9.0.2 |
| FFprobe | 9.0.2 |
| Deno | 2.9.7 |
| yt-dlp EJS | 0.8.0 |

This was an actual `DependencyResolver` run using `ProcessRunner`, enabled with
`MEDIA_DOWNLOADER_CHECK_LOCAL_TOOLS=1 bash scripts/test.sh --filter localOfflineReadinessVersionsOnly`.
It passed 1 test. The log contains only parsed numeric version fields and fixed
problem codes; verbose runtime diagnostics were neither saved nor displayed.
No URL, browser selection, cookie argument, or actual Brave registry was used.

The check validates executable paths, helper colocation/names, tool identities,
yt-dlp options, libmp3lame MP3 encoder and MP4 muxer support, Deno's 2.3.0 baseline, and
installed yt-dlp's discovery of both EJS and the explicitly selected Deno. The
no-URL yt-dlp diagnostic must exit 2 with the exact missing-URL outcome and the
expected readiness markers. Other nonzero outcomes fail setup. All probes have
15-second deadlines and credential-free argument arrays with a restricted
environment. No terminal PATH or shell startup files participate in discovery.

The installed build hides accepted legacy aliases `--no-colors` and
`--playlist-end` from help. Readiness therefore requires their advertised modern
equivalents `--color` and `--playlist-items`, and passes both legacy aliases in
the no-URL diagnostic to prove parser acceptance. An unknown-option exit 2
without readiness markers is a regression fixture and fails readiness.

Validation results:

- RED: the initial filtered run failed compilation because `DependencyResolver`
  did not exist. A renamed-helper regression failed with an incorrectly accepted
  report before filename validation. The local-help regression failed setup
  before modern-option/legacy-alias capability discovery was corrected.
- `bash scripts/test.sh --filter 'DependencyResolver|DependencyDiagnostics'`:
  12 tests across 2 suites passed; the opt-in local probe was skipped in this run.
- `bash scripts/test.sh`: 72 tests across 10 suites passed; the same opt-in local
  probe was skipped. It passed separately with the environment switch above.
- `swift build --product MediaDownloader`: succeeded.
- `git diff --check`: clean.

Swift commands required compiler-cache filesystem access in the Codex sandbox,
as in earlier tasks. No install, update, network extraction, or cookie access was
performed. Unknown or changed diagnostic formats deliberately block readiness;
setup UI should offer fixed package-manager guidance to check or manually update
`yt-dlp`, `ffmpeg`, and `deno`, then recheck. The resolver never executes that
maintenance itself. FFmpeg 9 is not a minimum: synthetic capability fixtures also
pass with FFmpeg/FFprobe 6.1 and Deno 2.3.0.

These results establish local dependency discovery only. They do not prove a
live public or login-required site works, that a YouTube challenge succeeds,
that browser permissions allow cookie access, or that the application is usable
from Finder. Live smoke checks, local media integration, GUI workflow checks,
and macOS 14 execution remain outstanding.

Task 4 review correction: the MP3 gate now requires `libmp3lame`, which yt-dlp
selects explicitly for the app's MP3 conversion command. An FFmpeg build with
only `libshine` is rejected with `missing-mp3` and nil tools. The new regression
failed before correction (1 test, 2 failed expectations), then
`bash scripts/test.sh --filter 'DependencyResolver|DependencyDiagnostics'`
passed 13 tests across 2 suites. Existing libmp3lame/Deno-baseline success cases
remain covered. The opt-in local probe was skipped in this focused run; the
full suite, native build, and actual local readiness results above predate this
single-predicate correction and were not rerun for it.


## Task 8: current core, model, packaging, and real-tool integration

Observed 2026-10-23 on Apple Silicon macOS 26.6.2 (25G83, arm64), Apple Swift 6.2
(`swiftlang-6.2.0.19.9`, `clang-1700.3.19.1`), standalone Command Line Tools.
Deployment remains macOS 14 minimum; execution on macOS 14 was not tested.

### Automated results

| Command/check | Observed result |
| --- | --- |
| `bash scripts/verify.sh --integration` | PASS: process fixture built; whole suite reported 146 tests across 16 suites (11.370 seconds); release bundle assembled and signature verified; opt-in integration passed 5 test functions / 10 cases (2.021 seconds) |
| `python3 scripts/integration.py` after test error-path cleanup hardening and summary-only output filtering | PASS: 5 test functions / 10 cases (2.897 seconds); coordinator shutdown is joined before test-destination cleanup, including assertion/timeout errors |
| `bash scripts/test.sh --filter RealToolIntegration` without opt-in | All 5 integration test functions explicitly skipped with the missing URL/absolute-tool-path reason; runner still reports 5 tests, so that count does not mean integration ran |
| `MEDIA_DOWNLOADER_CHECK_LOCAL_TOOLS=1 bash scripts/test.sh --filter localOfflineReadinessVersionsOnly` | PASS: 1 test (1.281 seconds), no problem codes, parsed versions below; no URL or cookies |
| `swift build --product MediaDownloader` | PASS: native executable built (4.05 seconds), no warnings/errors |
| `bash -n scripts/build-app.sh scripts/verify.sh`, `plutil -lint Resources/Info.plist`, `git diff --check` | PASS |
| Absolute build-script path invoked from `/private/tmp` with an owned sentinel in `dist` | PASS: bundle replaced and unrelated sentinel preserved, then sentinel removed |
| Importable fixture lifecycle check | PASS: codec-declared master, generated direct MP4, long HTML title, controlled slow-segment gate, joined server, owned temporary-root deletion |

The whole-suite count includes intentional skips: the five real-tool test
functions and the preexisting opt-in offline-tool probe. Integration is run
separately with explicit opt-in; the offline probe is run separately with its
switch. Parameterized cases are not counted as separate test functions in Swift
Testing's summary. No skipped integration is counted as a successful real-tool
check. The previous Task 7 baseline reported 141 tests in 15 suites; this task
adds five integration functions in one suite and a fragment-capability case to an
existing parameterized dependency test.

The whole suite covers domain/URL/browser argument policies, framing/events,
metadata, dependency diagnostics and readiness, process ownership and descendant
shutdown, cancellation/timeouts/readers, file ownership and exclusive publication,
artifact validation, coordinator races and session safety blocking, and the real
presentation model's preferences, profile selection, stale events, UI state,
native-action injection, and quit barrier. These are automated core/model checks,
not observations of native GUI interaction. In particular, synthetic profile
providers never read the real Brave registry or cookies.

Installed tool observations (all four executables under `/opt/homebrew/bin`):

| Tool | Version |
| --- | --- |
| yt-dlp | 2026.08.19 |
| FFmpeg / FFprobe | 9.0.2 / 9.0.2 |
| Deno | 2.9.7 |
| Local yt-dlp EJS (parsed readiness diagnostic) | 0.8.0 |

### Real media and failure evidence

The standard-library Python harness generates a two-second, 320×180, 15 fps
H.264/AAC HLS sample using the resolved FFmpeg and the planned command. FFmpeg's
master manifest declares codecs. The same sample is remuxed into a direct MP4 and
an audio-only HLS fixture. An ephemeral HTTP server binds only to 127.0.0.1 and
serves the private generated root. Raw tool output is held transiently; the
harness prints versions and test summaries. After a successful driver it closes
tracked request sockets and joins all HTTP workers before deleting its owned root.
Forced or uncertain driver outcomes retain the fixture root, as described below. All launches use subprocess argument arrays. No fixture is part
of the product bundle.

Both presets use the real JobCoordinator, ProcessRunner, yt-dlp, FFmpeg,
ArtifactVerifier/FFprobe, JobFiles, and exclusive publisher. Success requires a
nonempty file larger than 1 KiB, the selected extension, and successful real
container/codec verification at both the staged and returned final paths. The
final destination contains exactly that returned file and no staging residue.
MP4 verifies the MP4-family container with H.264 video and AAC audio; MP3 verifies
the MP3 container and audio with no video.

Ten integration cases cover MP4/MP3 success; direct-MP4 unknown-codec metadata
rejected as format-unavailable; HTTP 404 and HTML without media rejected during
preview; audio-only HLS rejected for the MP4 preset; truncated HTTP fragment and
missing fragment rejected for each preset. Every failure checks nil output and
an empty destination, including staging cleanup after subprocess completion.

A genuine pre-fix run showed yt-dlp skipping a missing HLS fragment after a valid
one, returning exit zero, and publishing a playable partial MP4. Three assertions
failed: phase was succeeded, output/issue indicated success, and the destination
was nonempty. Codec/container validation alone cannot establish complete transfer.
Download argv now includes `--abort-on-unavailable-fragments` for both presets;
readiness requires support for that flag. Both preset cases pass after the fix.
The command regression failed before the flag (two assertions); a restored-after-
run readiness mutation omitting the required capability failed two assertions
for its new missing-fragment-flag case. The approved output contract and README
now state this strict missing-fragment policy.

Initial test-authoring runs also exposed a test-only comparison of `/private/var`
and `/var` aliases for the same output. The assertion now compares resolved paths.
This was distinct from the genuine partial-publication failure. Initial sandbox
execution could not bind localhost; verification succeeded with normal compiler-
cache and loopback access. No tools were installed or modified. One intermediate
verify attempt was interrupted by editing its running shell script; the unchanged
final combined command was rerun successfully. This intermediate run is not
counted as successful verification.

### Local bundle and signing

`bash scripts/build-app.sh` builds the release product and assembles
`dist/Media Downloader.app`. Info.plist declares identifier
`local.rhomuel.media-downloader`, display name `Media Downloader`, executable
`MediaDownloader`, and minimum macOS 14.0. Observed output is an arm64 Mach-O
executable with mode 755, Info.plist, and generated signature resources only.
There are no embedded runtime tools, Python helpers, process fixtures, test media,
or test bundles. `codesign --verify --strict` succeeds and signature inspection
reports `adhoc` with no TeamIdentifier. The script signs before replacement and
verifies the installed result; it replaces only its fixed output bundle and
refuses a symlinked dist directory.

This is a locally assembled personal bundle. Developer ID signing, notarization,
Gatekeeper distribution behavior, release artifacts, and distribution remain
unverified and outside the approved v1 scope.

### Review fixes: harness shutdown and fail-closed retention

The Task 8 review reproduced two outer-harness gaps: an immediate-process timeout
could leave test-driver descendants alive, including separately owned process
groups; daemon HTTP workers could survive fixture deletion. Both are now covered
by `python3 scripts/test-integration.py`, using only synthetic Python processes,
owned temporary files, and loopback clients.

Before fixes, six synthetic tests produced five behavioral failures: timeout and
interruption descendants survived; a nonzero driver deleted the root; a partial
HTTP request reader and a blocked response writer survived fixture close. Those
regressions explicitly cleaned up their known synthetic processes/sockets. After
fixes, nine tests pass (10.117 seconds), adding actual SIGTERM interruption,
incomplete-inspection, and unjoinable-worker retention checks. The existing
`verify.sh --integration` branch now runs these Python regressions before real
media integration; default verification still has no Python requirement. This
shell wiring passed `bash -n`; the final combined command is controller-owned.
The affected real harness independently passed all five Swift integration
functions / ten cases (2.414 seconds) after the shutdown fixes.

The driver supervisor inspects only children of already known owned PIDs through
macOS libproc. It records PID/start-time/UID identity, follows observed ancestry
across separate process groups, stops observed descendants individually after
identity checks, and waits for the immediate driver plus observed descendant
quiescence. Only known owned processes may be signalled; it does not scan all
system processes. Timeout, interruption (including SIGTERM), nonzero/crashed
exit, incomplete inspection, unexpected ancestry/reparenting, or a remaining
observed descendant latches retention and reports shutdown/cleanup unconfirmed.
There is no automatic temporary-directory finalizer that can bypass retention.

This is bounded ancestry observation, not containment of arbitrary fast
fork/daemonization. macOS does not provide the old kqueue child-tracking flags;
a child can reparent between snapshots. Even if every observed process stops,
a forced/uncertain outcome retains its root. Normal driver exit zero with the
successful coordinator checks may clean after HTTP shutdown. This narrowed
policy was explicitly approved during review.

HTTP workers and accepted sockets are tracked explicitly. Close stops accepts,
releases the slow-segment gate, shuts down request sockets to wake blocked reads
and writes, and joins every tracked worker against a bounded deadline. If any
worker remains, the owned root is retained and the error is reported. Ordinary
successful checks still clean up. Overall integration PASS is printed only after
fixture teardown succeeds. The Python harness fixes do not modify the app bundle.

### Controller GUI/public observations and remaining limits

The controller observed the final Task 8 local bundle on this Mac on 2026-10-23.
These are native observations, separate from the implementer's automated checks:

- Double-click launch in Finder reached dependency readiness with browser None,
  empty URL, and Downloads destination. The inherited PATH was not deliberately
  reduced, so minimal-PATH launch remains unverified.
- Native Choose Folder opened; Cancel preserved Downloads, and choosing an
  isolated ignored output directory updated the shown destination. An initial
  stale automation binding/control-index issue resolved after refresh and was
  not a product defect.
- Loopback preview showed a two-second duration, synthetic title, and fallback
  film thumbnail. Native MP4 and MP3 actions completed. Show in Finder selected
  the actual UUID-named MP4 output, and Finder showed H.264/AAC, 320×180, two
  seconds. FFprobe confirmed both local outputs below.
- A long synthetic title with percent, emoji, and slash characters truncated
  cleanly across three lines while accessibility retained its full label and
  controls remained readable. VoiceOver and dynamic type were not exercised.
- A controlled slow segment showed indeterminate downloading and working Cancel;
  URL/browser/preset/folder/check/download inputs were disabled during transfer.
  Cancel returned Cancelled; the recorded owned yt-dlp PID/group was absent and
  owned staging count was zero afterward.
- Preview/retry after Cancel worked. Cmd-Q during another controlled transfer
  quit the app; inspection found neither the recorded app/child PIDs nor the
  recorded process group, and owned staging count was zero. No FFmpeg or Deno
  descendant was active in that GUI case; their shutdown remains automated
  process-fixture evidence. Transfer responsiveness was observed.
- Relaunch cleared URL and browser selection back to None while retaining the
  output/destination preferences. Destination was restored to Downloads and the
  app left idle. Successful two-second transfers completed between observations;
  processing/validation phases were not visually captured.

The user-selected public YouTube input successfully previewed and completed both
MP3 and MP4 through the native UI with browser None. Controller FFprobe summaries
contain only codec/size/duration fields, without the source URL or title:

| Source/preset | Bytes | Duration (seconds) | Verified container/streams |
| --- | ---: | ---: | --- |
| Public YouTube MP3 | 18,752,732 | 812.628771 | MP3; MP3 audio, no video |
| Public YouTube MP4 | 130,909,408 | 812.675193 | MP4 family; H.264 video + AAC audio |
| Loopback MP3 | 11,487 | 2.043356 | MP3; MP3 audio, no video |
| Loopback MP4 | 35,251 | 2.043356 | MP4 family; H.264 video + AAC audio |

These observations apply to the selected public video and installed versions
listed above; they do not establish general site availability. Outputs remain
in the ignored controller output directory. No actual Brave registry, browser
cookies/profile selection, login-required extraction, or browser/Keychain
permission flow was exercised. Those private/cookie checks remain pending.
Minimal inherited PATH, visible processing/validation, active GUI FFmpeg/Deno
descendant shutdown, VoiceOver/dynamic type, macOS 14, and Intel remain unverified.
Developer ID signing, notarization, release, and distribution remain outside scope.

The importable `LoopbackFixture` retains `url`, `slow_url`, `long_title_url`,
`wait_for_segment(timeout)`, `release_segments()`, and `close()`/context-manager
methods for owned developer checks. Its slow master/playlist remain fast; the
segment waits on an explicit owner-controlled gate. No fixture or test switch
is embedded in the application.

### Final controller combined verification

On 2026-10-23, `bash scripts/verify.sh --integration` on `dad298c` exited 0:
146 reported Swift tests across 16 suites passed in 11.574 seconds, with the
five real-integration functions and one offline-tool function explicitly skipped
in the default Swift pass. The separately enabled real integration then passed
five functions / ten cases in 2.644 seconds. Nine Python harness lifecycle
regressions passed in 10.077 seconds. ProcessFixture build, release bundle
assembly, and local ad-hoc signature verification passed. Reported versions were
yt-dlp 2026.08.19, FFmpeg/FFprobe 9.0.2, and Deno 2.9.7.

The idle GUI was closed before rebuilding. This command starts neither browser
cookie access nor remote-site extraction. Final review status is recorded in
[implementation decisions](IMPLEMENTATION-NOTES.md); no distribution action is
implied by these local checks.

### Final test-only follow-ups and review closure

The whole-branch review found no critical or important issue. Its one P3 test
ordering weakness was fixed in `b49d7ef`: the stale profile refresh is explicitly
awaited before assertions/shutdown. Removing the production browser/epoch guards
made that test fail; restoring them passed all 22 presentation tests. Scoped
review approved the fix without production changes.

The next full run exposed one existing orphan-fixture timeout: a successful
underlying process return bypassed the test adapter's stopped/release barrier.
A deterministic natural-return-before-Quit regression reproduced it. Test-only
commit `3834115` gives normal/error results a common barrier and makes failure
cleanup join shutdown before deletion, retaining the root on typed uncertainty.
Three focused tests / five cases passed; independent scoped review approved both
corrections. The controller then ran `bash scripts/test.sh` on the final tree:
**148 reported tests / 16 suites passed in 10.795 seconds, exit 0**, with the same
six explicit opt-in skips. No warnings or failures were reported.

The final inspection-order Python correction at `7c62b0a` was separately checked
by the controller: `python3 scripts/test-integration.py` passed **10 tests in
10.097 seconds**, exit 0. This supersedes the earlier nine-test lifecycle count.
Real integration remains five functions / ten cases from the successful combined
run; there have been no app-source, resource, or bundle-assembly changes since
that verification. Only tests, developer harness, and documentation changed.

The completed [review record](reviews/2026-10-23-implementation-review.md) includes
scope limits and follow-up closure. Private/browser-cookie and listed platform
checks remain pending; no release or distribution action was taken.


## Facebook progressive MP4 correction (2026-10-23)

The [scoped requirements](bugfixes/2026-10-23-facebook-mp4.md) document the
controller's confirmed selected-source cause. This implementation adds only a
Facebook-host progressive MP4 fallback after strict selection and maps actual
incompatible-media validation to format unavailable. H.264/AAC verification,
no video transcoding, exclusive publication, explicit ephemeral browser/profile
selection, and shutdown-before-cleanup remain mandatory.

New host/argv and coordinator tests were run before the production changes:
`bash scripts/test.sh --filter 'YTDLPCommandsTests|probeFailureCannotPublish'`
reported 13 tests in two suites with six failures: five Facebook URLs lacked the
fallback, and incompatible FFprobe media had the old processing classification.
After the fix, the same 13 reported tests passed in 0.005 seconds. Probe exit,
invalid JSON, and timeout retain processing/timeout behavior; existing uncertain-
shutdown retention and cancellation tests remain in the full suite.

`python3 scripts/integration.py` before the fix reported six integration functions
with four failed assertions in the new portrait regression. Neither variant
reached FFprobe, and the compatible candidate failed instead of publishing.
A focused diagnostic rerun confirmed the same four assertions. Both nonzero test
drivers retained their own synthetic fixture roots according to the existing
fail-closed harness policy; these retained roots were not deleted. After the fix,
the same integration command passed six functions / twelve cases in 1.985 seconds.

Both new portrait fixtures are generated locally at 180×320: H.264/AAC and an
incompatible MPEG-4/AAC MP4. A test-only runner maps one exact synthetic Facebook
reel URL to loopback after production command construction. Preview confirms
missing source codec labels. Both downloads complete their real FFprobe command;
only H.264/AAC publishes, while incompatible media returns format unavailable with
no output or remaining staging. The pre-existing generic direct MP4 unknown-codec
rejection still passes. No actual Facebook request, browser registry, profile,
cookie store, user URL, or live metadata was accessed by these automated checks.

Final checks on Apple Silicon macOS 26.6.2 with Apple Swift 6.2:

- `bash scripts/test.sh`: exit 0; 151 reported tests / 16 suites in 11.060 seconds.
  Six real-tool integration functions plus one offline-readiness function were
  explicitly skipped in this default pass.
- `swift build --product MediaDownloader`: exit 0; native build in 2.37 seconds.
- `bash scripts/verify.sh --integration`: exit 0. ProcessFixture built; 151 reported
  Swift tests / 16 suites passed in 11.152 seconds with the same explicit skips;
  the release bundle was rebuilt and its local ad-hoc signature verified; ten
  Python harness lifecycle tests passed in 10.100 seconds; separately enabled
  real integration passed six functions / twelve cases in 2.219 seconds.
- Tool versions: yt-dlp 2026.08.19, FFmpeg/FFprobe 9.0.2, Deno 2.9.7.
- `git diff --check`: passed. Tests/builds used normal compiler-cache and loopback
  permissions. No tool was installed or updated.

These results establish synthetic selection and artifact/publication behavior.
Independent controller review and the actual failing reel's native GUI retry with
an explicitly selected profile remain pending at implementation handoff. Earlier
public/GUI observations do not prove this Facebook fix. The installed extractor
and this selected source motivated the exception; availability for other Facebook
videos, `fb.watch`, private sources, browser permission flows, other macOS versions
or architectures, and distribution are not established by these checks.

## Facebook portrait MP4 correction (2026-10-23)

The selected Facebook reel had labelled AV1/AAC streams plus progressive SD/HD
MP4 entries lacking codec labels. The original selector refused those entries;
a non-publishing diagnostic confirmed its HD artifact satisfies H.264/AAC.
Commit `c5b5728` preserves strict-first selection and permits unknown-label
progressive MP4 candidates only for parsed facebook.com/subdomain hosts. Actual
FFprobe verification remains mandatory; known incompatible labels are excluded,
and incompatible artifacts fail format-unavailable without publication. Generic
unknown-codec/direct-MP4 behavior remains strict.

Observed checks: focused TDD RED/GREEN, 151 reported Swift tests across 16 suites
(11.152 seconds in combined verification, seven explicit opt-in skips), native
build, signed release bundle, ten Python lifecycle tests (10.100 seconds), and
six enabled real integration functions / twelve cases (2.219 seconds) passed.
Two synthetic fixture roots from genuine RED runs were retained under the
existing failed-driver policy. No actual user data is in those fixtures.

The controller's native retry of the same source with the user's previously
explicitly selected Brave profile succeeded through preview/download. Show in
Finder selected the completed file in Downloads. FFprobe of that exact file:
MP4-family container, 720×1280 H.264 video, AAC audio, 109.897188 seconds,
29,130,743 bytes. No video conversion was used. The local app was rebuilt and
ad-hoc signature verified. No runtime tools were installed or updated.

This adds actual selected-profile cookie-enabled Facebook evidence to the prior
public YouTube evidence. It does not prove the source requires login, all private
sources work, or every Facebook profile/site/runtime version works. URLs, source
titles/IDs, profile names/IDs, raw metadata and cookie contents were not saved in
repository evidence. Other documented platform/manual limits remain unchanged.
See [fix plan and result](bugfixes/2026-10-23-facebook-mp4.md) and
[independent scoped review](reviews/2026-10-23-facebook-mp4-review.md).

## Instagram progressive MP4 extension (2026-10-23)

The [scoped extension](bugfixes/2026-10-23-instagram-mp4.md) adds parsed
`instagram.com` and its subdomains to the existing Facebook candidate policy.
The strict H.264/AAC selector remains first, followed only on these hosts by
`/b[ext=mp4][vcodec^=?avc1][acodec^=?mp4a]`. Known incompatible/absent-stream
labels remain excluded. Actual FFprobe verification and exclusive publication
remain mandatory. `fb.watch`, `instagr.am`, deceptive hosts, and generic direct
MP4 inputs retain strict unknown-codec rejection. Coordinator and artifact
validation code are unchanged.

Before the production change, `bash scripts/test.sh --filter YTDLPCommandsTests`
exited 1: 15 reported functions in one suite, with five missing-selector failures
for Instagram apex/subdomains/uppercase/port variants. Facebook, generic strict,
lookalike/path/query/fragment and rejected-userinfo cases passed. After the minimal
host-guard change the same command exited 0: 15 functions in 0.005 seconds.

The existing 180×320 compatible H.264/AAC and incompatible MPEG-4/AAC portrait
fixtures now run for both exact synthetic Facebook and Instagram inputs. The
test-only runner maps those inputs to loopback after production command building,
rejecting other inputs and cookie flags. Preview confirms missing codec labels;
both candidates must complete real FFprobe. Only compatible media publishes;
incompatible media fails format-unavailable with no publication or staging.
The generic unknown-codec direct MP4 rejection remains covered.

`python3 scripts/integration.py` before the production change exited 1: six
functions with four issues in 3.888 seconds. Its summary-only failed-driver policy
retained one owned synthetic fixture root; no retained root was deleted. After
the fix the same command exited 0: six functions / fourteen cases in 7.709 seconds.

Final checks on Apple Silicon macOS 26.6.2 with Apple Swift 6.2:

- `bash scripts/verify.sh --integration`: exit 0, run once on final code.
  ProcessFixture built; its `bash scripts/test.sh` pass reported 154 tests across
  16 suites in 12.827 seconds. Six real-integration functions and one offline-tool
  readiness function remain explicit opt-in skips in the default pass. Release
  bundle and local ad-hoc signature passed; ten Python lifecycle tests passed in
  10.148 seconds; separately enabled real integration passed six functions /
  fourteen cases in 4.678 seconds.
- `swift build --product MediaDownloader`: exit 0, 3.37 seconds.
- `git diff --check`: passed.
- Tools: yt-dlp 2026.08.19, FFmpeg/FFprobe 9.0.2, Deno 2.9.7. Checks used approved
  compiler-cache/process/loopback permissions. No tools were installed or updated.

These automated results prove synthetic selection and artifact/publication
behavior. This implementer performed no external requests, browser/profile/cookie
access, or live GUI checks. Controller review and the selected-source native retry
remain pending at this handoff; no live Instagram support claim follows from
loopback success. Earlier live observations and their limitations remain recorded
in their original sections above.

### Controller live retry closure

After the implementation handoff above, the rebuilt native app reset browser
choice to None on launch. The controller restored the same failing Instagram
source and the user's previously explicit Brave profile choice. Native preview
and MP4 download completed. Show in Finder selected the actual published file
in Downloads. Independent FFprobe at that exact path confirmed MP4-family
container, 720×1280 H.264 video plus AAC audio, 23.727937 seconds, 20,026,153 bytes.
This closes the selected-source retry item; independent review is recorded
separately in the scoped review document when complete.

No video transcoding, tool installs/updates, browser-profile persistence or new
permissions were involved. Live source/title/profile identifiers, raw metadata,
diagnostics and cookies are not recorded here. This verifies this selected
cookie-enabled Instagram reel; it does not establish that login was strictly
required or that other/private-only sources will work. Synthetic integration and
prior manual-platform limits remain distinct.

Independent [scoped review](reviews/2026-10-23-instagram-mp4-review.md) approved spec compliance and quality with no findings. Its pending native retry item is closed by the controller evidence above; inherited baseline safety limits remain explicit.
