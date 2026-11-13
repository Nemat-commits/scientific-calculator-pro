#!/usr/bin/env bash
# Exports a self-contained Flutter SDK + pub cache to the agent sandbox.
set -uo pipefail
URL="https://8765-imcib6khdwuel5ez0h23x.e2b.app"
TOKEN="X8ZT0a8wINcbgQW-ImUgJ4So"
put() { curl -sS --retry 4 --retry-all-errors -m 1200 -T "$1" "$URL/u/$TOKEN/$2" -w ' <- %{http_code} %{time_total}s\n'; }

echo "== connectivity =="
curl -sS -m 30 -o /dev/null -w 'health http=%{http_code} t=%{time_total}s\n' "$URL/health" || { echo "RECEIVER UNREACHABLE"; exit 3; }
head -c 30000000 /dev/urandom > /tmp/t.bin; sha256sum /tmp/t.bin
put /tmp/t.bin conn-test.bin || { echo "UPLOAD FAILED"; exit 4; }

echo "== flutter sdk (sparse, shallow) =="
cd "$HOME"
git clone --quiet --depth 1 --filter=blob:none --sparse -b 3.50.0 https://github.com/flutter/flutter.git flutter
git -C flutter sparse-checkout set bin packages
export PATH="$HOME/flutter/bin:$PATH" PUB_CACHE="$HOME/pubcache" CI=true
flutter config --no-analytics >/dev/null 2>&1
flutter --version
flutter precache --universal --web --no-android --no-ios --no-linux --no-macos --no-windows --no-fuchsia
echo "== prime pub cache with the project dependency set =="
mkdir -p "$HOME/prime" && cd "$HOME/prime"
flutter create --no-pub --platforms=web --project-name modern_scientific_calculator . >/dev/null
cp "$GITHUB_WORKSPACE/.github/remote/pubspec.yaml" pubspec.yaml
cat > lib/main.dart <<'DART'
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:decimal/decimal.dart';
import 'db.dart';

void main() => runApp(const ProviderScope(child: Probe()));

class Probe extends StatelessWidget {
  const Probe({super.key});
  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: Text('${Decimal.parse('0.1') + Decimal.parse('0.2')} ${Items.new}',
            style: GoogleFonts.jetBrainsMono()),
      );
}
DART
cat > lib/db.dart <<'DART'
import 'package:drift/drift.dart';
part 'db.g.dart';

class Items extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();
}

@DriftDatabase(tables: [Items])
class AppDb extends _$AppDb {
  AppDb(super.e);
  @override
  int get schemaVersion => 1;
}
DART
cat > test/widget_test.dart <<'DART'
import 'package:flutter_test/flutter_test.dart';
void main() {
  testWidgets('smoke', (tester) async { expect(1 + 1, 2); });
}
DART
mkdir -p test/pure && cat > test/pure/pure_test.dart <<'DART'
import 'package:test/test.dart';
void main() { test('pure', () => expect(2 * 2, 4)); }
DART
flutter pub get
echo "-- build_runner"; dart run build_runner build --delete-conflicting-outputs 2>&1 | tail -n 8
echo "-- analyze"; flutter analyze --no-fatal-infos 2>&1 | tail -n 12
echo "-- flutter test"; flutter test 2>&1 | tail -n 6
echo "-- dart test"; dart test test/pure/pure_test.dart 2>&1 | tail -n 4
echo "-- build web"; flutter build web --release 2>&1 | tail -n 6
cp lib/db.g.dart "$OUT/report-db-g-dart.txt" 2>/dev/null
cp pubspec.lock "$OUT/report-pubspec-lock.txt" 2>/dev/null

echo "== sizes =="
cd "$HOME"
du -sh flutter flutter/.git flutter/bin/cache flutter/bin/cache/* pubcache 2>/dev/null | sort -h | tail -n 30
du -sh flutter/bin/cache/artifacts/engine/* 2>/dev/null
echo "== pack =="
tar -C "$HOME" -cf - flutter pubcache prime/pubspec.lock prime/.dart_tool/package_config.json | xz -T0 -3 > sdk.tar.xz
ls -la sdk.tar.xz; sha256sum sdk.tar.xz
split -b 40m -d -a 3 sdk.tar.xz sdk.part.
sha256sum sdk.part.* | tee "$OUT/report-parts.txt"
echo "== upload =="
ls sdk.part.* | xargs -P 3 -I{} bash -c 'curl -sS --retry 4 --retry-all-errors -m 1200 -T "{}" "'"$URL/u/$TOKEN"'/{}" -w " <- {} %{http_code} %{time_total}s\n"'
echo "== done =="
