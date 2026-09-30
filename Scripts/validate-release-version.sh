#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 || ! "$1" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo "Version must be MAJOR.MINOR.PATCH (three non-negative integers without leading zeros)." >&2
    exit 64
fi
