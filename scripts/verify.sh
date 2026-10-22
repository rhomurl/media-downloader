#!/bin/bash
set -euo pipefail
repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repository_root"
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != --integration ) ]]; then
    echo 'Usage: bash scripts/verify.sh [--integration]' >&2
    exit 2
fi
integration=false
if [[ $# -eq 1 ]]; then integration=true; fi
swift --version | sed -n '1p'
echo "macOS $(/usr/bin/sw_vers -productVersion), $(/usr/bin/uname -m)"
log="$(mktemp -t media-downloader-verify)"
trap 'rm -f "$log"' EXIT

# An inherited opt-in must not silently enable network tests in default mode.
unset MEDIA_DOWNLOADER_INTEGRATION_URL
if ! swift build --product ProcessFixture >"$log" 2>&1; then
    echo 'Process fixture build: FAIL' >&2
    exit 1
fi
echo 'Process fixture build: PASS'
set +e
bash scripts/test.sh >"$log" 2>&1
status=$?
set -e
# Keep unrestricted runtime output ephemeral. Test names and raw diagnostics are
# not copied to a persistent verification log.
sed -n '/Test run with /p' "$log"
if [[ $status -ne 0 ]]; then
    echo 'Unit/process/model tests: FAIL' >&2
    exit "$status"
fi
echo 'Unit/process/model tests: PASS; real-tool integration skipped (explicit opt-in required).'
bash scripts/build-app.sh
if $integration; then
    python_path="$(command -v python3 || true)"
    [[ -n "$python_path" ]] || { echo 'python3 unavailable; integration requires Python 3.' >&2; exit 1; }
    if ! "$python_path" scripts/test-integration.py >"$log" 2>&1; then
        sed -n '/^Ran [0-9]/p; /^FAILED/p' "$log"
        echo 'Harness lifecycle regressions: FAIL' >&2
        exit 1
    fi
    sed -n '/^Ran [0-9]/p' "$log"
    echo 'Harness lifecycle regressions: PASS'
    "$python_path" scripts/integration.py
else
    echo 'Loopback integration: NOT RUN; use --integration.'
fi
