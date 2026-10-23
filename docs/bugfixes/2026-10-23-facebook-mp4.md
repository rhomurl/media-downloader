# Facebook portrait MP4 compatibility fix

## Confirmed cause

A user-selected Facebook reel previews but MP4 selection fails. Live inspection
using the user's already selected Brave profile found labelled AV1 video and AAC
audio, plus SD/HD progressive MP4 entries without codec labels. The current
avc1/mp4a selector rejects those unlabelled entries. A diagnostic requested the
observed HD entry without publishing it; the normal ArtifactVerifier confirmed
H.264/AAC, and owned diagnostic media was cleaned after runner/probe completion.
No real URL, source ID/title, profile name/ID, raw metadata, or cookie data is
recorded here. Portrait orientation itself is not a selection condition.

## Scoped correction

Keep the H.264/AAC MP4 output contract, no video transcoding, mandatory actual
artifact validation, exclusive publication, shutdown-before-cleanup, and explicit
ephemeral browser/profile selection. Keep the original strict selector first.
For parsed HTTP(S) URLs whose host is facebook.com or a subdomain of it, append:

```text
/b[ext=mp4][vcodec^=?avc1][acodec^=?mp4a]
```

This permits missing codec labels on a progressive MP4 candidate, but rejects
known AV1/HEVC/VP9/Opus and known absent audio/video. Unknown labels are not proof
of compatibility: publish only after actual FFprobe H.264/AAC verification.
Other sites and generic direct MP4 URLs retain their existing strict policy.
Do not admit lookalike hosts or scan/modify arbitrary request parameters. No
cookie retry, metadata cache, transcode, or arbitrary format selector UI.
Map actual incompatible-media verification to format-unavailable; preserve other
probe errors and shutdown-unconfirmed handling.

Decision: replace the plan's unknown-codec rejection policy only for Facebook
progressive MP4 candidates, based on reproduced live evidence, while retaining
all output/file/process safety contracts. Cost if wrong: an incompatible
Facebook candidate may be downloaded then discarded after validation; no
incompatible file is published. fb.watch and other redirect domains retain
strict policy unless separately verified.

## Execution and verification

1. Add failing selector/host boundary and real-coordinator regression tests.
2. Make the minimal builder/verifier-error mapping changes above.
3. Verify synthetic portrait H.264/AAC with missing source labels publishes;
   incompatible unknown-codec media fails validation and publishes nothing.
   Real tools must be served loopback only in automated tests. An injectable
   test runner may map a reserved synthetic Facebook reel URL to loopback before
   executing commands; production format selection must run before that mapping.
4. Preserve generic unknown-codec rejection and existing cancellation/publication
   tests. Run bash scripts/test.sh, native build, and --integration verification.
5. Independently review the complete scoped diff, rebuild the local signed app,
   and retry the actual failing reel with the explicitly chosen profile. Do not
   commit live inputs/metadata/media or persist profile choice.

## Binding sources

Approved design: ../superpowers/specs/2026-10-15-media-downloader-design.md.
Relevant original task: Task 3 in ../superpowers/plans/2026-10-15-media-downloader.md.
The original plan allows only verified codec aliases and rejects unknown labels;
this document explicitly narrows that policy change to the Facebook case above.
Installed yt-dlp 2026.08.19 and upstream Facebook extractor omit codec fields on
progressive entries. Selector missing-value syntax was exercised offline with
that installed version: unlabelled MP4 accepted; known AV1, Opus and no-audio
rejected; labelled H.264/AAC retained. All observations apply to this selected
source and installed tools, not every Facebook video.
