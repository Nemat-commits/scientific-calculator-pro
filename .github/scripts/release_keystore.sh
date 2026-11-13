#!/usr/bin/env bash
# Prepares release signing on CI.
#
# With a keystore in the environment (the workflow passes the ANDROID_*
# repository secrets), the keystore file and android/key.properties are
# written; android/app/build.gradle.kts then signs the release build with
# that key. Without one nothing is written and Gradle falls back to the debug
# key, which is all a fork or a pull request can do anyway.
#
#   KEYSTORE_BASE64    the keystore file, base64 encoded
#   KEYSTORE_PASSWORD  its password
#   KEY_ALIAS          alias of the signing key
#   KEY_PASSWORD       password of that key (defaults to KEYSTORE_PASSWORD)
set -euo pipefail

if [ -z "${KEYSTORE_BASE64:-}" ]; then
  # Pin where the Android tools keep the debug keystore. On a fresh machine
  # they create it in ~/.android during the first Gradle run and in
  # ~/.config/.android during the next, which gave the per-ABI APKs and the
  # universal APK of one run two different signers.
  if [ -n "${GITHUB_ENV:-}" ]; then echo "ANDROID_USER_HOME=$HOME/.android" >> "$GITHUB_ENV"; fi
  echo "::notice title=APK signing::No release keystore is configured. The APKs are signed with a throw-away debug key: they install and run, but a later build cannot update them in place."
  exit 0
fi
: "${KEYSTORE_PASSWORD:?the keystore password is missing}"
: "${KEY_ALIAS:?the key alias is missing}"

# java.util.Properties reads a backslash as an escape character.
escaped() { printf '%s' "$1" | sed 's/\\/\\\\/g'; }

printf '%s' "$KEYSTORE_BASE64" | base64 --decode --ignore-garbage > android/app/release-keystore.jks
{
  echo "storeFile=release-keystore.jks"
  echo "storePassword=$(escaped "$KEYSTORE_PASSWORD")"
  echo "keyAlias=$(escaped "$KEY_ALIAS")"
  echo "keyPassword=$(escaped "${KEY_PASSWORD:-$KEYSTORE_PASSWORD}")"
} > android/key.properties
echo "Release keystore restored ($(wc -c < android/app/release-keystore.jks) bytes); the release build is signed with key '$KEY_ALIAS'."
