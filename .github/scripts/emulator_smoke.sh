#!/usr/bin/env bash
# Installs the release APK on the running emulator and drives the real app:
# hardware-keyboard input, "=" commit, a 16 326-digit factorial, rotation,
# every tab, the folding display and a cold restart. Screenshots and logcat
# go to $2.
#
# The script fails when the app is not running or logcat shows an error. It
# does not read the screen: that the results are right and that the history
# is back from SQLite after the restart is to be seen in the screenshots.
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

# A swipe to the left across the display card shows the next tab. The card is
# a third of the screen on Standard and Scientific and a 56 dp bar at the top
# on Lab, Convert and History, so the swipe runs through that top strip. It
# starts in the gap between the mode badges and the buttons on the right.
BAR_Y=$((H * 93 / 1000))
next_tab() { adb shell input swipe $((W * 56 / 100)) "$BAR_Y" $((W * 8 / 100)) "$BAR_Y" 200; sleep 3; }
next_tab; shot 06_scientific_tab
next_tab; shot 06_lab_tab                       # the display is folded into its bar
adb shell input tap $((W * 56 / 100)) "$BAR_Y"; sleep 3
shot 06_lab_display_open                        # a tap on the bar opens it in place
next_tab; shot 06_convert_tab                   # folded again on the next tab
next_tab; shot 06_history_tab

adb shell am force-stop "$PKG"; sleep 2
adb shell am start -W -n "$PKG/.MainActivity" >> "$OUT/smoke.log" 2>&1
sleep 8
shot 07_after_restart
next_tab; next_tab; next_tab; next_tab          # the app starts on Standard
shot 08_history_after_restart
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
