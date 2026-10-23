#!/bin/bash
set -euo pipefail

# SwiftPM in the standalone CLT installation supplies -I/-L for frameworks.
# Supply framework discovery and runtime lookup without changing app targets.
# This CLT lacks the Swift _Testing_Foundation overlay module; tests use the
# ordinary Foundation APIs and do not need Testing cross-import overlays.
developer_dir="$(xcode-select -p)"
framework_dir="$developer_dir/Library/Developer/Frameworks"
if [[ "$developer_dir" == */CommandLineTools && -d "$framework_dir/Testing.framework" ]]; then
    exec swift test \
        -Xswiftc "-F$framework_dir" \
        -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
        -Xlinker "-F$framework_dir" \
        -Xlinker -rpath -Xlinker "$framework_dir" \
        "$@"
fi

exec swift test "$@"
