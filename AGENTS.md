# Project guidance

Read the [approved design](docs/superpowers/specs/2026-10-15-media-downloader-design.md)
and the relevant task from the [implementation plan](docs/superpowers/plans/2026-10-15-media-downloader.md)
before changes. Keep their safety contracts intact.

- Use Swift 6 mode, macOS 14+, SwiftUI, and a testable core without third-party
  Swift package dependencies. Views must not orchestrate subprocesses.
- Build with `swift build --product MediaDownloader`; run `bash scripts/test.sh` before
  claiming completion. Record actual results and outstanding verification limits.
- Add regression coverage for process and file safety: cancellation must stop owned
  process groups and readers before cleanup, only owned staging may be removed,
  publication must never overwrite, and artifact validation precedes success.
- Never read browser cookies implicitly. Startup and dependency checks are
  credential-free. Access is allowed only for an explicitly selected browser when
  the user invokes preview or download. Never persist cookie contents.
- Launch absolute executables with argument arrays; never source shell startup
  scripts. Ignore user configs/plugins and disallow remote component fetching.
- Never commit credentials, real user URLs, live extracted metadata, raw runtime
  diagnostics, generated media, runtime tools, staging files, or build products.
  Synthetic metadata/URL fixtures and loopback test URLs are allowed for tests;
  they must contain no actual account, browser-profile, or private-source data.
- Fixture, build, and local integration results do not prove live public or
  login-required site support. Describe manual and live checks honestly, including
  skipped checks, tool versions, and permission failures.
- No automatic installs or updates. Distribution remains outside the approved v1
  scope. Do not add remotes or push unless explicitly requested.
