#!/usr/bin/env bash
# Installs the release APK on the running emulator and drives the real app:
# hardware-keyboard input, "=" commit, a 16 326-digit factorial, rotation,
# every tab and a cold restart (history must come back from SQLite).
# Screenshots and logcat go to $2.
#
#   emulator_smoke.sh <apk> <output-dir>
set -uo pipefail
APK="$1"; OUT="${2:-smoke}"; PKG=com.scientific.calculator.modern
mkdir -p "$OUT"
fail=0
note() { echo "[smoke] $*" | tee -a "$OUT/smoke.log"; }
shot() { adb exec-out screencap -p > "$OUT/$1.png"; note "screenshot $1 ($(wc -c < "$OUT/$1.png") bytes)"; }
alive() { adb shell pidof "$PKG" | tr -d '\r'; }

adb install -r "$APK" 2>&1 | tee -a "$OUT/smoke.log" || { note "install failed"; exit 1; }
adb shell settings put system accelerometer_rotation 0
adb shell settings put system user_rotation 0
adb logcat -c
adb shell am start -W -n "$PKG/.MainActivity" 2>&1 | tee -a "$OUT/smoke.log"
sleep 12
size="$(adb shell wm size | tr -d '\r' | sed -n 's/.*: \([0-9]*\)x\([0-9]*\).*/\1 \2/p' | tail -1)"
W="${size% *}"; H="${size#* }"
note "display ${W}x${H}, density $(adb shell wm density | tr -d '\r' | tail -1)"
[ -n "$(alive)" ] || { note "FAIL: process is not running after launch"; fail=1; }
shot 01_launch

adb shell "input text '7*6'"; sleep 3
shot 02_typed
adb shell input keyevent 66; sleep 3          # ENTER commits
shot 03_committed
adb shell "input text '+8'"; adb shell input keyevent 66; sleep 3   # continues from Ans -> 50
shot 04_ans_plus_8
adb shell "input text '5000!'"; adb shell input keyevent 66; sleep 5  # 4.2285779266 x 10^16325
shot 04_factorial_5000

adb shell settings put system user_rotation 1; sleep 5
shot 05_landscape
adb shell settings put system user_rotation 0; sleep 5

# The five segments of the tab bar (display card = top 35 %, bar = next 7 %).
tab() { adb shell input tap $((W * (10 + 20 * $1) / 100)) $((H * 395 / 1000)); sleep 3; }
tab 1; shot 06_scientific_tab
tab 2; shot 06_lab_tab
tab 3; shot 06_convert_tab
tab 4; shot 06_history_tab

adb shell am force-stop "$PKG"; sleep 2
adb shell am start -W -n "$PKG/.MainActivity" >> "$OUT/smoke.log" 2>&1
sleep 8
shot 07_after_restart
tab 4; shot 08_history_after_restart
[ -n "$(alive)" ] || { note "FAIL: process is not running after restart"; fail=1; }

adb logcat -d > "$OUT/logcat_full.txt" 2>/dev/null
grep -E " (E|F) (flutter|AndroidRuntime|DEBUG|libc) *:|FATAL EXCEPTION|I flutter" "$OUT/logcat_full.txt" > "$OUT/logcat_app.txt" || true
note "logcat: $(wc -l < "$OUT/logcat_full.txt") lines, $(wc -l < "$OUT/logcat_app.txt") app-relevant"
grep -E "I flutter" "$OUT/logcat_app.txt" | sed 's/^.*I flutter *: */[app] /' | sort -u | head -20 | tee -a "$OUT/smoke.log"
if grep -qE " E flutter|FATAL EXCEPTION| F libc| F DEBUG" "$OUT/logcat_full.txt"; then
  note "FAIL: errors in logcat"; grep -E " E flutter|FATAL EXCEPTION| F libc| F DEBUG" "$OUT/logcat_full.txt" | head -60 | tee -a "$OUT/smoke.log"; fail=1
fi
adb shell dumpsys package "$PKG" | grep -E "versionName|versionCode|targetSdk|minSdk" | tee -a "$OUT/smoke.log"
note "result: $([ $fail = 0 ] && echo PASS || echo FAIL)"
exit $fail
