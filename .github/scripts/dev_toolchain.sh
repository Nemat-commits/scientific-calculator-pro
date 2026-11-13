#!/usr/bin/env bash
# TEMPORARY development aid - removed before the branch is finished.
# Second pass: only the outputs of the native-asset build hooks (the SQLite
# library the sqlite3 package downloads from a GitHub release).
set -uo pipefail
OUT="$RUNNER_TEMP/out"; mkdir -p "$OUT"; export OUT
R="$OUT/report-toolchain.txt"
{
  flutter pub get 2>&1 | tail -n 2
  echo "== dart test"; dart test test/domain/engine_verification_test.dart 2>&1 | tail -n 2
  echo "== flutter test"; flutter test test/presentation/display_card_test.dart --timeout 120s 2>&1 | tail -n 2
  echo "== hook outputs"
  find .dart_tool/hooks_runner -maxdepth 6 \( -name '*.so' -o -name 'output.json' -o -name 'input.json' \) -exec ls -la {} \;
  find .dart_tool build -name 'libsqlite3*' -exec sha256sum {} \; 2>/dev/null
  ls -la .dart_tool build 2>/dev/null
} 2>&1 | tee "$R"
tar -cf "$RUNNER_TEMP/hooks.tar" .dart_tool/hooks_runner/shared $(ls -d build/native_assets 2>/dev/null) 2>>"$R"
ls -la "$RUNNER_TEMP/hooks.tar" | tee -a "$R"
bash "$GITHUB_WORKSPACE/.github/scripts/dev_reports.sh"
bash "$GITHUB_WORKSPACE/.github/scripts/dev_carry.sh" hooks "$RUNNER_TEMP/hooks.tar"
