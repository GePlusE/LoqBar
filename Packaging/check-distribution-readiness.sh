#!/bin/zsh

set -euo pipefail

SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-}"

echo "Available code signing identities:"
security find-identity -v -p codesigning || true
echo

if [[ -z "$SIGNING_IDENTITY" ]]; then
  echo "SIGNING_IDENTITY is not set."
else
  echo "SIGNING_IDENTITY is set to:"
  echo "  $SIGNING_IDENTITY"
fi

echo

if [[ -z "$KEYCHAIN_PROFILE" ]]; then
  echo "KEYCHAIN_PROFILE is not set."
else
  echo "Checking keychain profile:"
  xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" >/dev/null
  echo "  $KEYCHAIN_PROFILE is usable."
fi
