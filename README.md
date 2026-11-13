# Scientific Calculator Pro

A scientific calculator for Android, written in Flutter. Expressions are typed
and shown in two dimensions (fractions, roots, powers, integrals), numbers are
exact fractions for as long as possible and 50-digit decimals after that, and
every evaluation runs off the UI thread and can be cancelled.

<p>
  <img src="docs/screenshots/standard.png" width="19%" alt="Standard tab with the row of quick function keys open; the parenthesis that is still open is drawn as a ghost and counted on its key">
  <img src="docs/screenshots/scientific.png" width="19%" alt="Scientific tab: an integral plus a cube root times a power of e">
  <img src="docs/screenshots/lab_solver.png" width="19%" alt="Lab tab: the display folded into a bar, the quadratic solver with exact roots below it">
  <img src="docs/screenshots/convert.png" width="19%" alt="Convert tab: 12.5 metres in other length units">
  <img src="docs/screenshots/history.png" width="19%" alt="History tab: the tape of past calculations">
</p>
<p>
  <img src="docs/screenshots/tablet.png" width="97%" alt="Two-pane layout on a tablet">
</p>

The pictures are rendered by the screenshot test of this repository
(`test/screenshots`), with the fonts the app ships.

## Contents

- [What it does](#what-it-does)
- [Download](#download)
- [Build from source](#build-from-source)
- [Signing a release](#signing-a-release)
- [Tests](#tests)
- [Continuous integration](#continuous-integration)
- [Architecture](#architecture)
- [How the numbers are computed](#how-the-numbers-are-computed)
- [Design decisions and deviations from the blueprint](#design-decisions-and-deviations-from-the-blueprint)
- [What has been verified, and what has not](#what-has-been-verified-and-what-has-not)

## What it does

**Display.** One card stays on top of every tab. It shows the expression the
way it is written on paper, a live preview of the result while typing, and the
committed result with its second form (`0.5` and `1/2`). An empty line shows a
muted `0`, and a parenthesis that has not been closed yet is drawn as a ghost
`)` where it will be closed. A line that gets too long first shrinks, then
scrolls with faded edges; the caret stays in view. Badges switch the angle
unit (DEG, RAD, GRAD), real or complex results, and how `6÷2(1+2)` is read
(TI: 9, CASIO: 1); the last two say in a short message what they have just
switched to. Undo, redo, copy and paste sit next to them; pasted text such as
`1,250.50 × 2³ − √16` is cleaned up and turned into editable structure.
Pulling the handle down opens the recent history.

Lab, Convert and History have their own input and read-out. On these tabs the
card folds into a one-line bar that keeps the badges and shows the last
answer, and the tab gets the room. A tap on the bar opens the display where
it is; the chevron folds it again, and so does the next tab change.

**Five tabs.**

| Tab | Contents |
| --- | --- |
| Standard | Digits, `+ − × ÷`, `%`, a parenthesis key that opens or closes as needed and counts the groups that are still open, cursor keys for moving inside the 2D expression, `MC MR M+ M−` (`MC` and `MR` are outlined while the memory holds a value). `f(x)` opens a row with `sin cos tan ln √x x² xʸ π`, so that a single function does not need a tab change. |
| Scientific | The cursor and memory keys, then six rows of five: trigonometric, hyperbolic and inverse functions, `ln`, `log`, `log₂`, `logₐ`, powers and roots, fraction and absolute-value templates, `π`, `e`, `φ`, `i`, `×10ˣ`, factorial and gamma, `nCr`, `nPr`, `mod`, `gcd`, `lcm`, definite integral and derivative, variables `x`, `y`, `M`, `Ans`, and its own `AC`, `⌫` and `=`. `INV` and `HYP` change the key faces and release after one key; the corner of a key shows what `INV` turns it into. `,` moves on to the next argument of a function. |
| Lab | **Solver:** quadratic and cubic equations; rational roots stay exact fractions, complex roots are shown. **Matrix:** two matrices up to 4×4; sum, difference, product, determinant, inverse, transpose, rank, trace. **Table:** values of the current expression over a range. **Stats:** one-variable summary (mean, sums, both standard deviations, quartiles) and two-variable linear regression. **Base-N:** HEX, DEC, OCT, BIN at 8, 16, 32 or 64 bits, signed or unsigned, with `AND OR XOR NOT << >>`; a tap on a base makes it the one being typed, and digits it does not have are switched off. Roots, scalar matrix results, statistics and the decimal Base-N value have a `↗` that puts them into the main expression. |
| Convert | Twelve categories (length, mass, temperature, area, volume, speed, time, data, pressure, energy, power, angle), all units of a category at once (an empty field counts as 0, and `0 °C` is `32 °F`), a `↗` on every line that puts its value into the main expression, and 24 physical constants (CODATA 2022); a tap on a constant inserts it into the expression. |
| History | Searchable tape of past calculations stored in SQLite: a tap brings an expression back for editing, `Ans` inserts its result, and both return to the keypad; a long press opens the whole expression and result with copy buttons. Variable slots (`Ans`, `M`, `A`–`F`, `x`, `y`) can be inserted, filled from the last answer or cleared. |

In portrait one tab is visible at a time; from 600 dp of width the standard
keypad and the display stay on screen next to the other tabs (and the display
never folds). A swipe on the display card or the tab bar changes the tab, a
swipe on the keys never does.

**Also.** Hardware keyboards work (digits, `+ - * / ^ ( ) ! % .`, `=` or Enter,
Backspace, Esc, arrows, `x`, `e`, `p` for π). The expression in progress, the
modes, the variables and the history survive a restart. Haptic feedback
distinguishes digits, operators, clearing and errors. Displays that support
90 or 120 Hz are asked to use it. Expression, result and errors are exposed
to screen readers as text. The app works offline: the release build does not
hold the network permission, and its fonts are bundled.

## Download

APKs are not stored in git. Every run of the
[CI workflow](https://github.com/Nemat-commits/scientific-calculator-pro/actions/workflows/ci.yml)
attaches them to the run: open the newest run with a green check mark and
scroll down to **Artifacts**. Each APK is an artifact of its own and is
stored as it is, so the download is the `.apk` file, not a zip. A GitHub
login is needed to download artifacts, and they are kept for 90 days.

| Artifact | Size | Use it for |
| --- | --- | --- |
| `app-arm64-v8a-release.apk` | 19 MB | Phones and tablets running 64-bit ARM Android (most current devices). |
| `app-armeabi-v7a-release.apk` | 17 MB | 32-bit ARM Android: older devices and many entry-level ones. |
| `app-x86_64-release.apk` | 21 MB | Emulators and x86 Chromebooks. |
| `app-release.apk` | 55 MB | All three in one file. Installs everywhere; take it when unsure. |

Android 7.0 (API 24) or newer is required. Unless a keystore has been set up
(see [Signing a release](#signing-a-release)), CI signs the APKs of a run with
a debug key that exists only for that run. Such an APK installs and runs
normally, but Android will not accept the build of a later run as an update
of it: uninstall first, which also removes the stored history.

## Build from source

Requirements: Flutter 3.50 (Dart 3.14), a JDK that the Android Gradle Plugin
accepts (CI uses 21) and Android SDK platform 36. The exact versions CI uses
are listed under [Continuous integration](#continuous-integration); nothing
older has been tried.

```sh
flutter pub get
flutter run                                    # debug build on a connected device or emulator
flutter build apk --release --split-per-abi    # build/app/outputs/flutter-apk/app-<abi>-release.apk
flutter build apk --release                    # build/app/outputs/flutter-apk/app-release.apk (universal)
```

The Drift database code (`lib/data/local_db/app_database.g.dart`) is committed.
After changing a table, regenerate it and commit the result; CI fails when the
file is out of date:

```sh
dart run build_runner build
```

Only the Android platform folder exists. The Dart code picks its platform
services through conditional imports (no SQLite and no worker isolates where
`dart:io` is missing), but no other platform has been built or tested.

## Signing a release

Without `android/key.properties` a release build is signed with the debug key,
so `flutter build apk` works on a fresh checkout. For anything that should be
installable as an update later, create a keystore once and keep it safe:

```sh
keytool -genkeypair -v -keystore upload-keystore.jks -alias upload \
        -keyalg RSA -keysize 2048 -validity 10000
```

**Local builds.** Put the keystore at `android/app/upload-keystore.jks` and
create `android/key.properties` (both are ignored by git):

```properties
storeFile=upload-keystore.jks
storePassword=<keystore password>
keyAlias=upload
keyPassword=<key password>
```

`storeFile` is resolved relative to `android/app/`.

**CI builds.** Add four repository secrets (Settings → Secrets and variables →
Actions). The build job restores the keystore from them
(`.github/scripts/release_keystore.sh`); without them it falls back to the
debug key and says so in the run.

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Output of `base64 -w0 upload-keystore.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | `upload` |
| `ANDROID_KEY_PASSWORD` | Key password (may be left out when it equals the keystore password) |

The build job verifies every APK with `apksigner` and lists file, size,
SHA-256 and signer in the summary of the run.

## Tests

```sh
dart test test/domain/engine_verification_test.dart --plain-name "MathEngine"   # gate 1: TC-01 … TC-20
dart test test/domain/engine_verification_test.dart                              # gate 2: all 24 cases, under 50 ms together
dart test test/domain                                                            # the whole engine and editor suite; needs no Flutter
flutter test                                                                     # gate 3: the above plus state, isolates and widgets
CALC_SCREENSHOTS=1 flutter test test/screenshots                                 # renders 28 PNGs into build/screenshots/
```

| Suite | What it covers |
| --- | --- |
| `test/domain/engine_verification_test.dart` | The 24 verification cases of [the blueprint](#design-decisions-and-deviations-from-the-blueprint) (TC-01 … TC-24), their time budget and the precision constants. |
| `test/domain/editor_and_engines_test.dart` | Editor tree and cursor, paste clean-up, formatter, calculus, solver, matrices, statistics, Base-N, unit conversion. |
| `test/presentation/calculator_notifier_test.dart` | Live preview, what the next key does after `=`, errors, undo, memory, variables, persistence of modes and draft. |
| `test/presentation/evaluator_isolate_pool_test.dart` | Evaluation on a worker isolate, cancellation by newer input, the 250 ms preview budget, the watchdog that replaces a stuck worker. |
| `test/presentation/calculator_shell_test.dart`, `display_card_test.dart` | Keys, hardware keyboard, gestures, every tab and Lab mode at four screen sizes without overflow, shrinking and scrolling of long lines, screen-reader labels. |
| `test/presentation/ux_improvements_test.dart` | The changes of 3.1: folding and reopening of the display, mode messages, placeholder and ghost parentheses, the quick function row, the parenthesis counter, the scientific grid with its corner legends, sending values from Lab, Convert and History to the expression, Base-N on a small phone. |
| `test/screenshots/screenshots_test.dart` | Skipped unless `CALC_SCREENSHOTS=1`; then renders the screens at phone, small-phone, landscape and tablet sizes. |

`.github/scripts/emulator_smoke.sh <apk> <out-dir>` drives a release APK on a
running emulator or device through `adb`: typed input, `=`, `Ans`, `5000!`,
rotation, all tabs, the folded display and its reopening, and a forced stop
followed by a restart, with a screenshot after every step. It fails when the
app is no longer running, when logcat shows a Flutter error or a crash, or
when a tap on a tab leaves the screen as it was. It does not read the screen:
whether the results are right and the history is back after the restart is
for a person to see in the screenshots.

## Continuous integration

`.github/workflows/ci.yml` runs on pushes to `main` and to `arena/**` working
branches and on pull requests, in three jobs:

1. **Analyze & test** — `flutter pub get`, generated code up to date,
   `flutter analyze`, `dart format` check, gates 1 to 3, screenshots
   (artifact `screenshots`).
2. **Android release APK** — per-ABI and universal APKs, signature
   verification (one artifact per APK, named after the file).
3. **Emulator smoke test** — installs the universal APK on an API 34 x86_64
   emulator and runs the script above (artifact `emulator-smoke`: screenshots
   and logcat).

Toolchain on CI: Flutter 3.50.0 (Dart 3.14.0), Temurin JDK 21, Android Gradle
Plugin 9.3.1, Gradle 9.5.0, Kotlin 2.4.20, compile and target SDK 36,
minimum SDK 24.

## Architecture

```
lib/
  core/           colours, typography, haptics, unit and constant tables
  domain/         pure Dart, no Flutter import: can be run and tested with `dart` alone
    models/       editor nodes, syntax tree, values, errors, evaluation context
    editor/       2D editing: keys, cursor paths, the post-"=" state machine, paste clean-up
    compiler/     editor tree → tokens → implied multiplication → Pratt parser → syntax tree
    evaluator/    arithmetic, transcendental functions, gamma, calculus, complex numbers,
                  matrices, solver, statistics, Base-N, units, number formatting, cancellation
    math_engine.dart   facade over the whole pipeline
  data/           Drift database (history, variables), settings, draft of the current line
  presentation/
    isolate/      worker isolates, request protocol, shared generation counter
    state/        Riverpod notifier and UI state
    widgets/      display card, 2D expression painter, keys, tab bar, Lab building blocks
    tabs/         the five tab views
    screens/      the shell: portrait and two-pane layouts, hardware keyboard
  main.dart
```

**From key to result.** A key becomes a `CalcKey`. `MathPrintController`
applies it to the editor tree (`EditorNode`: atoms, fraction, power, root,
function call, integral, derivative; nesting is limited to depth 4) and moves
the cursor, which is a path into that tree. For evaluation the tree is lowered
to tokens, implied multiplications are made explicit according to the TI or
CASIO setting, and a Pratt parser builds the syntax tree. `AstEvaluator` walks
it and returns a `CalcValue` — exact rational, decimal, complex, matrix or
fixed-width integer — which `NumberFormatter` turns into text.

**Off the UI thread.** `CalculatorNotifier` sends every evaluation to
`EvaluatorIsolatePool`. Two mechanisms keep the UI responsive:

- *Cooperative.* Each request carries a generation number. The newest number
  also lives in one word of native memory that the worker can read while it is
  busy, because a message would only be read once the work is finished. The
  loops of the engine compare it every 64 iterations, together with a time
  budget of 250 ms for previews and 1,500 ms for `=`, and unwind when they are
  out of date or out of time.
- *Preemptive.* If a request is still unanswered when the watchdog fires
  (1,500 ms, plus 300 ms for `=` so that its own budget can report first), the
  worker isolate is killed and a spare that is already warm takes over.

**Persistence.** History and variables are in SQLite through Drift. Settings
and the line being typed are in `SharedPreferences`, which is readable
synchronously, so the expression is back in the first frame after a cold
start. A database or worker isolate that fails or is slow to start does not
keep the calculator from starting: it falls back to an empty variable list
and to evaluation on the main isolate.

**UI.** The app uses the widgets layer only (`material.dart` is deprecated in
Flutter 3.50). The expression is laid out and painted by
`math_print_canvas.dart`, with measured glyphs cached per text scale.
JetBrains Mono and Inter (SIL Open Font License 1.1, texts in
`assets/google_fonts/`) are bundled as subsets and runtime font fetching is
switched off.

## How the numbers are computed

- **Exact first.** Number literals and the results of `+ − × ÷` and integer
  powers are fractions of big integers: `0.1 + 0.2` is `0.3` and `1/3 + 1/6`
  is `1/2`. A fraction whose numerator or denominator outgrows 2,048 bits
  becomes a decimal.
- **Decimals** carry 50 significant digits; 34 are displayed. A sum or
  difference of inexact numbers that comes out more than 42 orders of
  magnitude below its operands is the rounding of a zero and is shown as `0`
  (`log(1000) − 3`); `(1 + 10⁻²⁵) − 1` is still `1e-25`.
- **Elementary functions** use argument reduction and series at the working
  precision; angles as large as 10²⁰ rad are reduced with enough digits of π.
- **Factorial.** Integers up to 2,500 are multiplied out exactly. Above that
  the logarithmic Stirling series gives mantissa and exponent
  (`5000! = 4.2285779266 × 10^16325`). Non-integers use Spouge's
  approximation of the gamma function and are kept to 15 digits.
- **Derivative.** Central differences with Richardson extrapolation, 14
  digits. A kink or jump at the point is reported as an error instead of a
  number.
- **Integral.** Composite 5-point Gauss–Legendre on repeatedly halved panels;
  the endpoints are never sampled. When an endpoint is singular or the rule
  stalls, a substitution that flattens the endpoints is applied, up to six
  times (`∫₀¹ dx/√x = 2`). A result is accepted only if a second mesh with an
  odd number of panels agrees. 14 digits; fewer when the integral converges
  slowly.
- **No invented digits.** An integral is known to about 14 digits, so
  `∫₀^π sin²x dx + 3e^(−1/2)` must not show 34. How many digits of the final
  value can be trusted depends on what was done with the numerical result:
  adding 10¹⁵ keeps all of them, subtracting a nearly equal number loses
  nearly all. The evaluator therefore repeats the arithmetic around every
  integral, derivative and non-integer factorial with that result moved by
  its error bound, and keeps the digits both runs share. A value smaller than
  its own uncertainty is shown as `0`. `Ans` receives the same rounded value.
- **Complex numbers** are pairs of decimals shown as `a + bi`; matrices are
  grids of decimals up to 4×4; Base-N values are integers wrapped to the
  chosen word size.
- **Limits.** Exponents up to ±999,999. Function tables have at most 200 rows.

## Design decisions and deviations from the blueprint

The app was built to a written specification, `ARCHITECTURE_BLUEPRINT.md`
("the blueprint"), which is not part of this repository. Where that document
left a choice open, or where following it literally was not possible, this is
what was done.

- **Layout of the project.** The Flutter project is at the repository root.
  The editing controller is `math_print_controller.dart`; `AngleUnit` and
  `JuxtapositionMode` are in `math_context.dart`, `InputPhase` in
  `input_phase.dart`. `package:test` is a dev dependency so that the engine
  gates run with plain `dart test`.
- **Verification cases.** TC-10 shows `0.5` as the result and `1/2` as the
  second form. TC-20 is asserted to the 14 digits given
  (`-0.64525128526578`). TC-15 is shown as `4.2285779266 × 10^16325`.
- **Stirling series.** Eight correction terms instead of two, so that the
  stored value is good to the working precision and `5000!/4999!` comes out
  clean.
- **Implied multiplication.** A number or symbol directly followed by a
  symbol (`2π`, `3x`) binds tightly in both modes. Other implied products
  (`2(…)`, `2sin(…)`) behave like `×` in TI mode and bind tighter than
  `×` and `÷` in CASIO mode. A power binds tighter than any implied product.
- **Minus sign.** JetBrains Mono draws U+2212 as narrow as a hyphen, so the
  display shows an en dash for it. Stored and copied text is unaffected.
- **Repeated `=`.** Pressing `=` again on a committed result adds no second
  history line.
- **Converter.** Starts from the base unit of a category (°C for
  temperature).
- **Android.** Application id `com.scientific.calculator.modern`.
  `flutter_displaymode` 0.6.0 pins compile SDK 33, which current AndroidX
  libraries reject; `android/build.gradle.kts` lifts plugin modules to
  SDK 36. The platform focus highlight is switched off in `MainActivity`,
  because with a hardware keyboard Android outlines the whole Flutter view.
- **Formatting.** `dart format` with a page width of 120
  (`analysis_options.yaml`).

### The UX review (version 3.1)

Version 3.1 applies a written review of the layout,
`ux_and_layout_improvements_blueprint.md` (not part of this repository
either): the folding display, the mode messages, the placeholder and the
ghost parentheses, the quick function row and the parenthesis counter, the
rearranged scientific grid, and the paths from Lab, Convert and History back
into the expression. Where the result differs from that document:

- **Functions the engine does not have.** The review puts `Σ`/`Π`, mixed
  fractions (`a b/c`), `Rand`, the polar `∠`, `ENG` and `CALC` on the
  scientific grid. They are not part of this version; each needs engine work
  and tests of its own. Their places hold functions that existed already:
  the angle-unit key (for `Σ`/`Π`), `x⁻¹` (for `a b/c`), `°` (for `Rand`),
  `log₂` (for `∠`), `logₐ` (for `ENG`) and `gcd`/`lcm` (for `CALC`). `mod`
  is the second face of `|x|` and `Γ` that of `x!`.
- **The folded display opens in place.** The review allows a tap on the bar
  to jump to the Standard tab or to expand the display; it expands, so the
  tab in use stays. The bar is 56 dp high.
- **Mode messages.** Without a Material layer there is no `SnackBar`. The
  message is a widget of the app that floats over the keypad for 1.5 s and
  lets touches through. The texts are shorter than in the review, and the
  badge keeps its name `TI`.
- **Sending a value.** A `↗` at the end of the line instead of a "Use in
  Calc" chip, which the narrow lines have no room for. A negative or complex
  value is inserted in parentheses.
- **Open parentheses inside a template.** A parenthesis left open in an
  exponent, a root or a fraction is closed where that slot ends, which is
  also where its ghost is drawn: `2^(1+1` followed by `×3` outside the
  exponent is `2^(1+1) × 3`.
- **`,` on the scientific grid.** Inside a function with several arguments
  it moves the caret to the next one; elsewhere it types a separator.
- **Converter.** There was no special case for zero: the dashes came from
  an empty field, which now counts as 0.

## What has been verified, and what has not

On CI, with the code as it is in this commit:

- `flutter analyze` reports no issues and `dart format` no changes.
- All 24 blueprint cases pass and take 10 to 15 ms together (budget 50 ms).
- `flutter test`: 127 tests pass (68 of them engine and editor tests that
  also run under plain `dart test`); the 4 screenshot tests are skipped
  unless requested and pass when run.
- The release APKs build, and `apksigner` accepts them.
- On an Android 14 (API 34) x86_64 emulator at 1080×2400 the release APK
  starts cold in under 3 s, computes typed input, `Ans` and `5000!`, lays out
  in landscape, shows all five tabs, and still has its history after being
  force-stopped and restarted. Logcat contains no Flutter error. What the
  screens show was read off the screenshots of the run.

Not verified:

- No physical device was used. Haptics, the 90/120 Hz request, real GPUs and
  ARM hardware are exercised only by code review and by the build.
- Only API 34 was run. API 24 to 33 and 35+ are covered by the build
  configuration alone.
- Signing with a keystore was exercised on CI once, with a throw-away test
  key passed through `release_keystore.sh` (the APK came out signed by that
  key). The repository secrets themselves have not been set, so the APKs CI
  produces today are debug-signed.
- Screen readers: labels are checked by tests, TalkBack itself was not run.

The earlier WebView-based app was removed from the tree in favour of this
implementation. Its releases were numbered 3.1.x as well: the tag `v3.1` is
one of them and is not version 3.1.0 of this app. Its history remains in git,
and the `gh-pages` branch still serves its web demo.
