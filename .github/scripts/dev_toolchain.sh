#!/usr/bin/env bash
# TEMPORARY development aid - removed before the branch is finished.
set -uo pipefail
OUT="$RUNNER_TEMP/out"; mkdir -p "$OUT"; export OUT
R="$OUT/report-toolchain.txt"
FR="${FLUTTER_ROOT:-$(dirname "$(dirname "$(command -v flutter)")")}"
PC="${PUB_CACHE:-$HOME/.pub-cache}"
{
  echo "FLUTTER_ROOT=$FR"
  echo "PUB_CACHE=$PC"
  echo "HOME=$HOME"
  echo "WORKSPACE=$GITHUB_WORKSPACE"
  echo "which flutter=$(command -v flutter) dart=$(command -v dart)"
  echo "ImageOS=${ImageOS:-?} ImageVersion=${ImageVersion:-?} glibc=$(ldd --version | head -n 1)"
  flutter --version 2>&1
} | tee "$R"

# Exercise every tool once so that everything it needs is in the caches.
{
  echo "== pub get"; flutter pub get 2>&1 | tail -n 4
  echo "== analyze"; flutter analyze 2>&1 | tail -n 3
  echo "== format"; dart format --output=none lib/main.dart 2>&1 | tail -n 2
  echo "== dart test"; dart test test/domain/engine_verification_test.dart 2>&1 | tail -n 2
  echo "== flutter test"; flutter test test/presentation --timeout 120s 2>&1 | tail -n 3
  echo "== screenshots"; CALC_SCREENSHOTS=1 flutter test test/screenshots --timeout 90s 2>&1 | tail -n 3
} 2>&1 | tee -a "$R"

{
  echo "== sizes"
  du -sh "$FR" "$PC" 2>/dev/null
  (cd "$FR" && du -sh .[a-zA-Z]* * 2>/dev/null | sort -h | tail -n 16)
  (cd "$FR/bin/cache" && du -sh * artifacts/* artifacts/engine/* 2>/dev/null | sort -h | tail -n 34)
  (cd "$FR/bin/cache/dart-sdk" && du -sh * bin/* bin/snapshots/* lib/_internal/* 2>/dev/null | sort -h | tail -n 44)
  (cd "$PC" && du -sh * 2>/dev/null | sort -h | tail -n 8)
  ls -la "$FR" "$FR/bin/cache" 2>&1 | head -n 90
  echo "== tool launch line"; grep -n 'SNAPSHOT_PATH\|package_config' "$FR/bin/internal/shared.sh" | head -n 30
} 2>&1 | tee -a "$R"

cd "$RUNNER_TEMP"
tar -C / -cf - \
  --exclude="${FR#/}/.git" \
  --exclude="${FR#/}/dev" \
  --exclude="${FR#/}/examples" \
  --exclude="${FR#/}/docs" \
  --exclude="${FR#/}/engine" \
  --exclude="${FR#/}/.github" \
  --exclude="${FR#/}/bin/cache/downloads" \
  --exclude="${FR#/}/bin/cache/flutter_web_sdk" \
  --exclude="${FR#/}/bin/cache/artifacts/engine/android-*" \
  --exclude="${FR#/}/bin/cache/artifacts/engine/linux-x64-profile" \
  --exclude="${FR#/}/bin/cache/artifacts/engine/linux-x64-release" \
  --exclude="${FR#/}/bin/cache/artifacts/gradle_wrapper" \
  --exclude="${FR#/}/bin/cache/dart-sdk/bin/snapshots/dart2js*" \
  --exclude="${FR#/}/bin/cache/dart-sdk/bin/snapshots/dartdevc*" \
  --exclude="${FR#/}/bin/cache/dart-sdk/bin/snapshots/dart2wasm*" \
  --exclude="${FR#/}/bin/cache/dart-sdk/bin/snapshots/wasm*" \
  --exclude="${FR#/}/bin/cache/dart-sdk/bin/utils/wasm-opt" \
  --exclude="${FR#/}/bin/cache/dart-sdk/bin/resources/devtools" \
  --exclude="${FR#/}/bin/cache/dart-sdk/lib/_internal/dart2js*" \
  --exclude="${FR#/}/bin/cache/dart-sdk/lib/_internal/ddc*" \
  --exclude="${FR#/}/bin/cache/dart-sdk/lib/_internal/dart2wasm*" \
  --exclude="${FR#/}/bin/cache/dart-sdk/lib/dev_compiler" \
  --exclude="${FR#/}/packages/flutter/test" \
  --exclude="${FR#/}/packages/flutter_tools/test" \
  --exclude="${PC#/}/_temp" \
  --exclude="${PC#/}/log" \
  "${FR#/}" "${PC#/}" \
  "${GITHUB_WORKSPACE#/}/.dart_tool/package_config.json" \
  "${GITHUB_WORKSPACE#/}/.dart_tool/package_graph.json" \
  2>>"$R" | xz -T0 -2 > toolchain.tar.xz
{
  echo "== bundle"; ls -la toolchain.tar.xz; sha256sum toolchain.tar.xz
} 2>&1 | tee -a "$R"

bash "$GITHUB_WORKSPACE/.github/scripts/dev_reports.sh"
bash "$GITHUB_WORKSPACE/.github/scripts/dev_carry.sh" toolchain toolchain.tar.xz
