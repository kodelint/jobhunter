#!/usr/bin/env bash
# Fast type-check of the whole app (arm64 only), for local iteration.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK="$(xcrun --show-sdk-path)"
swiftc -O -parse-as-library -target arm64-apple-macos14.0 -sdk "$SDK" "$ROOT"/Sources/*.swift -o /tmp/jh-compilecheck 2>/tmp/jh-cc.log
rc=$?
echo "compile rc=$rc"
grep -i "error:" /tmp/jh-cc.log | head -40 || true
exit $rc
