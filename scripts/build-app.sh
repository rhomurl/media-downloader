#!/bin/bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repository_root"

# A fixed destination: never remove a caller-supplied directory or clean dist/.
destination="$repository_root/dist"
bundle="$destination/Media Downloader.app"
[[ ! -L "$destination" ]] || { echo 'Refusing symlinked dist directory.' >&2; exit 1; }
mkdir -p "$destination"
work="$(mktemp -d "$destination/.media-downloader-build.XXXXXX")"
trap 'rm -rf "$work"' EXIT
log="$work/build-output"
if ! swift build -c release --product MediaDownloader >"$log" 2>&1; then
    echo 'Release app build failed; no bundle replaced.' >&2
    exit 1
fi
binary_directory="$(swift build -c release --show-bin-path)"
new_bundle="$work/Media Downloader.app"
mkdir -p "$new_bundle/Contents/MacOS"
cp "$binary_directory/MediaDownloader" "$new_bundle/Contents/MacOS/MediaDownloader"
chmod 755 "$new_bundle/Contents/MacOS/MediaDownloader"
cp "$repository_root/Resources/Info.plist" "$new_bundle/Contents/Info.plist"
/usr/bin/plutil -lint "$new_bundle/Contents/Info.plist" >/dev/null
/usr/bin/codesign --force --sign - "$new_bundle" >"$log" 2>&1
/usr/bin/codesign --verify --strict "$new_bundle" >"$log" 2>&1

# Replace only this script's exact output, after the new bundle is signed.
rm -rf "$bundle"
mv "$new_bundle" "$bundle"
/usr/bin/codesign --verify --strict "$bundle" >"$log" 2>&1
echo 'Release bundle: PASS (local ad-hoc signature verified).'
