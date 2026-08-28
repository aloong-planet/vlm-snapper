#!/bin/bash

set -euo pipefail

if [[ $# -ne 5 ]]; then
    echo "Usage: $0 <generate-appcast-tool> <private-key-file> <download-base-url> <architecture> <appcast-directory>" >&2
    exit 64
fi

generate_appcast_tool="$1"
private_key_file="$2"
download_base_url="${3%/}/"
architecture="$4"
appcast_directory="$(cd "$5" && pwd)"
appcast="$appcast_directory/appcast-$architecture.xml"

"$generate_appcast_tool" \
    --ed-key-file "$private_key_file" \
    --download-url-prefix "$download_base_url" \
    --maximum-versions 1 \
    --maximum-deltas 0 \
    -o "$appcast" \
    "$appcast_directory"
