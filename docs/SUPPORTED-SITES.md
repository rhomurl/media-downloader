# Site compatibility

Updated 2026-10-23. Selected videos from **YouTube, Facebook, and Instagram**
have completed live native-app downloads. This is evidence for those selected
sources, not a promise that every video on those sites works.

## Verified live results

| Site | Actual observed result | Limits |
| --- | --- | --- |
| YouTube | Public video preview, MP4 and MP3 through the native app with browser None. | One selected source; no private/login-required YouTube check. |
| Facebook | Selected reel preview and MP4; independent FFprobe confirmed H.264/AAC. | Explicitly selected Brave profile; login necessity was not established. MP3 and other sources were not verified. |
| Instagram | Selected reel preview and MP4; independent FFprobe confirmed H.264/AAC. | Explicitly selected Brave profile; login necessity was not established. MP3 and other sources were not verified. |
| TikTok | Current selected-source attempt reproduced format unavailable; investigation and retry pending. | Not yet verified as working in this app. Installed extractor presence alone does not resolve this failure. |

The [verification record](VERIFICATION.md) contains the actual observations,
tool versions, and remaining manual/platform limits. The successful live checks
used yt-dlp 2026.08.19, FFmpeg/FFprobe 9.0.2, and Deno 2.9.7 on this Mac.

## Potential next integrations

**X/Twitter, Reddit, and SoundCloud are the user's selected priorities.**
All candidates below have relevant extractors in the installed yt-dlp
2026.08.19 inventory. None has been live-tested in this app as part of this
compatibility assessment. Extractor availability is a starting point for
integration and verification, not completed app support.

| Candidate | Installed extractor | Likely verification work; expectations, not observed results |
| --- | --- | --- |
| **X/Twitter — prioritized** | `twitter` | Verify a single recorded video, codec labels, and access/rate-limit behavior. |
| **Reddit — prioritized** | `Reddit` | Verify a single native video with audio; check handling of posts linking to other hosts. |
| **SoundCloud — prioritized** | `soundcloud` | Verify a single track to MP3 and access restrictions. Audio-only tracks cannot satisfy the MP4 preset. |
| Vimeo | `vimeo` | Verify a single accessible recorded video and compatible streams; private/embedded access needs separate evidence. |
| Twitch recorded clips/VODs | `twitch:clips`, `twitch:vod` | Verify individual recorded items, segment completeness, and access restrictions; live streams remain excluded. |
| Dailymotion | `dailymotion` | Verify a single recorded item and available H.264/AAC streams. |
| Bandcamp | `Bandcamp` | Verify a single track to MP3; album/batch downloads remain excluded. |
| Bilibili | `BiliBili` | Verify a single item, codec availability, region/access restrictions, and rejection of collection results. |

The inventory was checked without a URL or browser access using
`/opt/homebrew/bin/yt-dlp --ignore-config --no-plugin-dirs --list-extractors`.
The official [extractor list](https://github.com/yt-dlp/yt-dlp/blob/master/supportedsites.md)
also includes these families and warns that listed sites can break as websites
change. The upstream [README](https://github.com/yt-dlp/yt-dlp#usage-and-options)
documents the inventory command. Upstream master may differ from the installed
version. No candidate media requests or tool installs/updates were performed
for this assessment.

## What every site must satisfy

The app handles one recorded item at a time. Playlists, collections, live
streams, and DRM bypass are outside scope. MP4 requires H.264 video **and AAC
audio**, with no video transcoding; a source lacking compatible streams can
fail even if yt-dlp recognizes its site. MP3 requires an audio source and may
convert it with FFmpeg; conversion does not improve source fidelity. Actual
artifact verification must pass before success/publication.

Facebook and Instagram have a scoped progressive-MP4 fallback for missing
codec labels, still subject to actual FFprobe validation. That exception does
not imply equivalent behavior for other sites or short-link hosts. See the
[approved output contract](superpowers/specs/2026-10-15-media-downloader-design.md#output-contract).

Browser access occurs only after explicit selection when invoking preview or
download; Brave also requires explicit profile selection. Cookie contents and
Brave profile selection are not persisted. Cookies do not establish that a
private source works. Chrome, Brave, and Firefox are the app's browser choices;
upstream yt-dlp options do not add app features automatically.

Site changes and external-tool updates can change availability. The app never
installs or updates tools automatically. Future candidates need selected-source
native-app checks and artifact verification before moving into the verified
table.
