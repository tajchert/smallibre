#!/bin/bash
# Read-only diagnostic. Output may contain owner book filenames; do not commit it.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --product SmallibreReaderHelper >&2
helper="$(swift build --show-bin-path)/SmallibreReaderHelper"
exec "$helper" --mtp-probe
