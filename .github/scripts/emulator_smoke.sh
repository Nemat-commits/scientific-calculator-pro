#!/usr/bin/env bash
# Installs the release APK on the running emulator and drives the real app:
# hardware-keyboard input, "=" commit, a 16 326-digit factorial, rotation,
# every tab, the INV, Σ and CALC keys of the scientific grid, the folding
# display and a cold restart. Screenshots and logcat go to $2.
#
# The script fails when the app is not running, when logcat shows an error or
# when a tap that should change the screen leaves it as it was. It does not
# read the screen: that the results are right and that the history is back
# from SQLite after the restart is to be seen in the screenshots.
#
#   emulator_smoke.sh <apk> <output-dir>
set -uo pipefail
APK="$1"; OUT="${2:-smoke}"; PKG=com.scientific.calculator.modern
mkdir -p "$OUT"
fail=0
note() { echo "[smoke] $*" | tee -a "$OUT/smoke.log"; }
shot() { adb exec-out screencap -p > "$OUT/$1.png"; note "screenshot $1 ($(wc -c < "$OUT/$1.png") bytes)"; }
alive() { adb shell pidof "$PKG" | tr -d '\r'; }
# changed <before> <after>: two different screens never give the same picture.
changed() { cmp -s "$OUT/$1.png" "$OUT/$2.png" && { note "FAIL: $2 shows the same screen as $1"; fail=1; }; return 0; }

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

# The five segments of the tab bar. The bar sits below the display card, which
# is a third of the screen on Standard and Scientific and a 56 dp bar at the
# top on Lab, Convert and History: hence two heights. The fractions are those
# of the API 34 "pixel_6" emulator of the workflow (1080x2400, 420 dpi).
TABS_OPEN=$((H * 405 / 1000)); TABS_FOLDED=$((H * 154 / 1000)); BAR=$((H * 93 / 1000))
tab() { adb shell input tap $((W * (10 + 20 * $1) / 100)) "$2"; sleep 3; }
tab 1 "$TABS_OPEN";   shot 06_scientific_tab;   changed 04_factorial_5000 06_scientific_tab

# Three keys of the scientific grid (five columns, six rows; same emulator):
# INV top left, Σ in the middle of the first row, CALC bottom left.
KEY_LEFT=$((W / 10)); KEY_MID=$((W / 2)); ROW_1=$((H * 519 / 1000)); ROW_6=$((H * 902 / 1000))
key() { adb shell input tap "$1" "$2"; sleep 2; }
key "$KEY_LEFT" "$ROW_1"; shot 06_scientific_inv;  changed 06_scientific_tab 06_scientific_inv   # second functions, in amber
key "$KEY_LEFT" "$ROW_1"                                                                        # INV off again
adb shell input keyevent 111                                                                    # ESC clears the line
adb shell "input text 'x*x+3'"; sleep 1
key "$KEY_LEFT" "$ROW_6"; shot 06_calc_prompt;     changed 06_scientific_inv 06_calc_prompt      # asks for x
adb shell "input text '5'"; adb shell input keyevent 66; sleep 3                                # x = 5 -> 28, formula kept
shot 06_calc_result;                               changed 06_calc_prompt 06_calc_result
adb shell input keyevent 111
key "$KEY_MID" "$ROW_1"                                                                         # Σ template
adb shell "input text '1'"; adb shell input keyevent 22                                         # from 1 ...
adb shell "input text '4'"; adb shell input keyevent 22                                         # ... to 4 ...
adb shell "input text 'x'"; adb shell input keyevent 66; sleep 3                                # ... of x -> 10
shot 06_sum;                                       changed 06_calc_result 06_sum
tab 2 "$TABS_OPEN";   shot 06_lab_tab;          changed 06_sum 06_lab_tab                     # display folded
adb shell input tap $((W / 2)) "$BAR"; sleep 3                                                # tap on the bar
shot 06_lab_display_open;                       changed 06_lab_tab 06_lab_display_open        # display open again
tab 3 "$TABS_OPEN";   shot 06_convert_tab;      changed 06_lab_display_open 06_convert_tab    # folded again
tab 4 "$TABS_FOLDED"; shot 06_history_tab;      changed 06_convert_tab 06_history_tab

adb shell am force-stop "$PKG"; sleep 2
adb shell am start -W -n "$PKG/.MainActivity" >> "$OUT/smoke.log" 2>&1
sleep 8
shot 07_after_restart
tab 4 "$TABS_OPEN";   shot 08_history_after_restart; changed 07_after_restart 08_history_after_restart
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
