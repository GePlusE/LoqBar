# LoqBar Release Checklist

## Build

```bash
./Packaging/build-app.sh
```

Expected outputs:

- `dist/LoqBar.app`
- `dist/LoqBar.zip`

## Create installer DMG

```bash
./Packaging/create-dmg.sh
```

Expected output:

- `dist/LoqBar.dmg`

## Validate

```bash
./Packaging/validate-release.sh
```

Checks:

- bundle signature verifies
- Gatekeeper assessment passes
- ZIP contains the app bundle

## Distribution signing

```bash
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./Packaging/build-app.sh
```

## Notarize

```bash
KEYCHAIN_PROFILE="LoqBarNotary" ./Packaging/notarize-app.sh
```

## Final smoke check

- Launch `dist/LoqBar.app`
- Mount `dist/LoqBar.dmg`
- Confirm the menu bar icon appears
- Open Preferences
- Open Recent Sessions
- Start and stop a short recording
- Confirm transcript export still works

## Optional next steps

- styled DMG background/layout
- CI automation for build/sign/notarize
- updater integration
