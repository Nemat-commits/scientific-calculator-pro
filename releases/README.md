# Releases

APKs of Scientific Calculator Pro, built by the
[CI workflow](../.github/workflows/ci.yml) of this repository.

## 3.2.1

| File | For | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| [`scientific-calculator-pro-3.2.1-arm64-v8a.apk`](https://github.com/Nemat-commits/scientific-calculator-pro/raw/main/releases/scientific-calculator-pro-3.2.1-arm64-v8a.apk) | 64-bit ARM Android: most current phones and tablets. Take this one first. | 19,441,502 | `997c739b1e05eba9ef4165d8de5fec5a4ecb7e6b91c226de7a15b4c34dfd4373` |
| [`scientific-calculator-pro-3.2.1-armeabi-v7a.apk`](https://github.com/Nemat-commits/scientific-calculator-pro/raw/main/releases/scientific-calculator-pro-3.2.1-armeabi-v7a.apk) | 32-bit ARM Android: older devices and many entry-level ones. Take it when Android refuses the first one as not compatible. | 17,051,000 | `ab9dbd52520b72ea4fcb93364c8f0c6863b7032885256446d970d7ac982396ef` |

The links download the file from the `main` branch.

- Package `com.scientific.calculator.modern`, version 3.2.1, for Android 7.0
  (API 24) and newer.
- Built by run
  [43572485599](https://github.com/Nemat-commits/scientific-calculator-pro/actions/runs/43572485599)
  from commit `c9fbfd90bfb4413447776a41e9b144d9b970aa23` of pull request #8.
  The app sources of that commit are the ones that were merged; the commits
  after it changed this folder, the README and the CI files only.
- The files are the artifacts `app-arm64-v8a-release.apk` and
  `app-armeabi-v7a-release.apk` of that run under another name: the
  checksums above are the digests the run lists for them.
- The same run installed its universal APK on an Android 14 emulator and
  drove it (see "What has been verified" in the [README](../README.md)). The
  two files here come from the same build; the run did not install them.
- There is no x86_64 or universal APK here: both are attached to every CI
  run, as described under "Download" in the README.
- These files replaced those of 3.2.0, which are still in the history:
  [`releases/` as it was for 3.2.0](https://github.com/Nemat-commits/scientific-calculator-pro/tree/fd6ebd17a97504d9679132505baee7b0085e29ff/releases).

### Installing

1. Download the file on the phone and open it. Android asks once to allow the
   browser or the file manager to install apps.
2. If the app is already installed, uninstall it first (see below). This
   removes its stored history and variables.

### Signature

The repository has no release keystore, so CI signed these files with the
debug key of that run (APK signature scheme v2, certificate SHA-256
`9ba7cbd48cb971fbc87e47ccbe6b8200cf54793ffd9e58e7289efbf6b8e9ebb2`). They
install and run normally. Android only updates an installed app with a file
that carries the same signature, and every CI run without a keystore has a key
of its own: that is why an earlier build has to be uninstalled first.
"Signing a release" in the README says how to give CI a permanent key, after
which updates install over one another.
