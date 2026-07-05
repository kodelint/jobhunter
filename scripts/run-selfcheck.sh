#!/usr/bin/env bash
# Compiles the pure logic sources + selfcheck.swift into a CLI and runs the asserts.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK="$(xcrun --show-sdk-path)"
TMP="$(mktemp -d)"
cp "$ROOT/scripts/selfcheck.swift" "$TMP/main.swift"   # top-level code must be in main.swift
swiftc -sdk "$SDK" \
  "$ROOT/Sources/Models.swift" \
  "$ROOT/Sources/ATS.swift" \
  "$ROOT/Sources/ConstraintParser.swift" \
  "$ROOT/Sources/KeywordScorer.swift" \
  "$ROOT/Sources/Geo.swift" \
  "$TMP/main.swift" \
  -o "$TMP/jh-selfcheck"
"$TMP/jh-selfcheck"
