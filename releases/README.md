# Releases

APKs of Scientific Calculator Pro, built by the
[CI workflow](../.github/workflows/ci.yml) of this repository.

## 3.2.0

| File | For | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| [`scientific-calculator-pro-3.2.0-arm64-v8a.apk`](https://github.com/Nemat-commits/scientific-calculator-pro/raw/main/releases/scientific-calculator-pro-3.2.0-arm64-v8a.apk) | 64-bit ARM Android: most current phones and tablets. Take this one first. | 19,441,502 | `ca12ec2c3fb09138c6b3019514a1c5b70b675e72064e5a0ebedd0e38e8cf47b0` |
| [`scientific-calculator-pro-3.2.0-armeabi-v7a.apk`](https://github.com/Nemat-commits/scientific-calculator-pro/raw/main/releases/scientific-calculator-pro-3.2.0-armeabi-v7a.apk) | 32-bit ARM Android: older devices and many entry-level ones. Take it when Android refuses the first one as not compatible. | 17,051,000 | `8b1ea3189e0eafc71bc3b34b3b95356544769d7b411c487bd6c8a96c01090607` |

The links download the file from the `main` branch.

- Package `com.scientific.calculator.modern`, version 3.2.0, for Android 7.0
  (API 24) and newer.
- Built by run
  [43552753614](https://github.com/Nemat-commits/scientific-calculator-pro/actions/runs/43552753614)
  from commit `4e12f154b848b6a479499f215529e20c400f80e5` of pull request #7.
  The app sources of that commit are the ones that were merged; the commit
  after it changed this folder, the README and the CI files only.
- The same run installed its universal APK on an Android 14 emulator and
  drove it (see "What has been verified" in the [README](../README.md)).
  These two files were not installed on a device.
- There is no x86_64 or universal APK here: both are attached to every CI
  run, as described under "Download" in the README.

### Installing

1. Download the file on the phone and open it. Android asks once to allow the
   browser or the file manager to install apps.
2. If the app is already installed, uninstall it first (see below). This
   removes its stored history and variables.

### Signature

The repository has no release keystore, so CI signed these files with the
debug key of that run (APK signature scheme v2, certificate SHA-256
`25631a0240bb21b28829ab9d3dff1c674d35f4978045890f5a19fe2df44ac64d`). They
install and run normally. Android only updates an installed app with a file
that carries the same signature, and every CI run without a keystore has a key
of its own: that is why an earlier build has to be uninstalled first.
"Signing a release" in the README says how to give CI a permanent key, after
which updates install over one another.
