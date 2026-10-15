# HANDOFF: macOS GUI app wrapping yt-dlp

## Goal
Build a macOS desktop app with a GUI that lets a user paste a video URL
(TikTok, YouTube, Instagram, Facebook, others) and download/convert it
using yt-dlp under the hood. Target user is non-technical.

## Background (what was established in the prior conversation)

### yt-dlp basics (source: official README, github.com/yt-dlp/yt-dlp)
- Command line audio/video downloader, supports 1,700+ extractors.
- Support for any given site can break at any time when the site changes.
  The project says the only reliable check is to try it.
- Unsupported sites may still work via embed extraction or the generic
  extractor (direct .mp4/.m3u8 links, embedded players).
- DRM-protected content (Netflix, Spotify, etc.) is NOT supported.

### Installation on macOS
- Option A: Homebrew: `brew install yt-dlp ffmpeg`
- Option B: official standalone binary `yt-dlp_macos` from GitHub releases
  (README recommends this for macOS). Needs chmod +x and may need
  `xattr -d com.apple.quarantine` to clear Gatekeeper.
- ffmpeg + ffprobe are required for merging separate video/audio streams
  and for conversions (e.g. mp3).
- YouTube now requires a JavaScript runtime (deno is the default; node,
  bun, quickjs also supported) plus the yt-dlp-ejs component. Official
  binaries bundle ejs, but the runtime must still be installed.
- Updating: `yt-dlp -U` for binaries. README recommends the NIGHTLY
  channel for regular users (`yt-dlp --update-to nightly`) because the
  stable channel can lag behind site changes.

### Useful commands/options
- Basic: `yt-dlp "URL"` (always quote URLs; zsh breaks on & and ?)
- List formats: `-F`; pick format: `-f 137+140`
- mp4 preset: `-t mp4`; mp3 preset: `-t mp3`
- Output template: `-o "~/Downloads/%(title)s.%(ext)s"`
- Metadata as JSON (good for GUI preview): `-J` or `-j`
- Simulate without downloading: `--simulate`
- Playlist items: `-I 1:5`; single video only: `--no-playlist`
- Subtitles: `--write-subs --sub-langs en`
- Progress for parsing: `--newline`, `--progress-template`
- Embedding: yt-dlp also has a Python API (YoutubeDL class).

### Facebook specifics
- Works with a normal URL: `yt-dlp "URL"`
- Private/group/friends-only videos need login cookies:
  `--cookies-from-browser chrome` (also safari, firefox, brave, etc.)
- Facebook often serves video and audio separately, so ffmpeg is needed.

### Errors hit during testing, and fixes
1. Safari cookies:
   `[Errno 1] Operation not permitted: ...Safari/Data/Library/Cookies/Cookies.binarycookies`
   Cause: macOS privacy protection blocks the terminal/app from reading
   Safari's cookie file.
   Fixes: (a) grant the app Full Disk Access (System Settings > Privacy
   & Security > Full Disk Access, then fully restart the app);
   (b) use another browser (chrome/firefox/brave) with --cookies-from-browser,
   Chrome triggers a Keychain prompt; (c) export a cookies.txt file and
   use --cookies FILE (treat it like a password).
2. "File name too long": Facebook titles can be the entire post caption.
   Fix: use ID-based or truncated templates, e.g.
   `-o "%(uploader).30s - %(id)s.%(ext)s"`, or `--trim-filenames 100`,
   plus `--restrict-filenames` if emoji/non-ASCII still break it.
   macOS limit is 255 BYTES, so emoji count for more than one character.
   The app should handle this by default.

## Suggested architecture (my suggestion, not yet decided)
- SwiftUI app that launches a bundled yt-dlp binary via Process (shell out),
  rather than reimplementing anything.
- Bundle: yt-dlp_macos, ffmpeg/ffprobe, and a JS runtime (deno).
- Flow: paste URL > run `yt-dlp -J` for title/thumbnail/formats preview >
  user picks quality/format (video mp4, audio mp3) > download with
  progress bar parsed from stdout > open in Finder.
- Default output template should be ID-based/truncated to avoid the
  filename error.
- Built-in updater that pulls the nightly yt-dlp build, since breakage
  from site changes is the main maintenance cost.
- Cookies: offer "use cookies from browser" dropdown, with a clear
  explanation when Safari is blocked and a default that avoids Safari.
- Friendly error messages mapped from common yt-dlp errors.
- Queue for multiple URLs, batch file support (`-a`).

## Risks and blind spots to resolve BEFORE building
1. Mac App Store is probably not viable. Sandboxing conflicts with
   running external binaries and reading browser cookies, and downloader
   apps face review risk. Plan for Developer ID signing + notarization
   and direct distribution.
2. Licensing: the README says PyInstaller-bundled yt-dlp executables
   include GPLv3+ code, so the combined work is GPLv3+. Bundling them in a
   distributed app likely triggers GPL obligations (offer source). ffmpeg
   license depends on the build. Get this checked before commercial release.
3. Legal/ToS: downloading from TikTok, Instagram, Facebook, YouTube
   generally violates platform terms, and copyright applies. Decide the
   use case (own content? personal use? public product?) because it
   changes distribution and liability.
4. Maintenance: sites break constantly. Without auto-update, the app
   decays within weeks. Budget ongoing time for this.
5. Competition: Downie, Stacher, and open-source yt-dlp GUIs already exist.
   Define what this app does differently (e.g. workflow integration,
   specific output presets) before investing.
6. Clarify "converting": download only, or also transcode (e.g. to
   different codecs, resolutions)? Transcoding is heavier and uses ffmpeg.

## Open questions for the user
- Personal tool or product to distribute/sell?
- Which output formats and presets matter most?
- Native SwiftUI, or is a cross-platform stack (Tauri/Electron) acceptable?