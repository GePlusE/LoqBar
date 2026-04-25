# Packaging LoqBar

This folder contains the first app-bundle packaging flow for LoqBar.

## What it does

`build-app.sh` builds the Swift package and wraps the resulting `LoqBar` executable in a proper macOS `.app` bundle:

- `LoqBar.app/Contents/MacOS/LoqBar`
- `LoqBar.app/Contents/Info.plist`
- `LoqBar.app/Contents/Resources/LoqBar.icns` when `Packaging/LoqBar.appiconset` or `Packaging/LoqBar.icns` is present

The bundle is created in:

```bash
dist/LoqBar.app
```

The script also creates a distributable ZIP:

```bash
dist/LoqBar.zip
```

A DMG can be created from the built app bundle:

```bash
./Packaging/create-dmg.sh
```

That produces:

```bash
dist/LoqBar.dmg
```

## Build a local app bundle

```bash
./Packaging/build-app.sh
```

By default this uses ad-hoc signing (`SIGNING_IDENTITY=-`), which is fine for local testing.

## App icon

If `Packaging/LoqBar.appiconset` exists, `build-app.sh` automatically generates `Packaging/LoqBar.icns` with `iconutil` before bundling the app.

## Build with a real signing identity

```bash
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./Packaging/build-app.sh
```

Optional overrides:

```bash
BUNDLE_ID="com.yourcompany.loqbar" \
MARKETING_VERSION="0.1.0" \
BUILD_NUMBER="42" \
./Packaging/build-app.sh
```

## Validate the bundle

```bash
./Packaging/validate-release.sh
```

## Create a DMG

```bash
./Packaging/create-dmg.sh
```

## Notarization later

Once the app is signed with a real Developer ID identity, the next step is notarization:

```bash
KEYCHAIN_PROFILE="YOUR_PROFILE" ./Packaging/notarize-app.sh
```

A fuller release flow is documented in [Packaging/RELEASE_CHECKLIST.md](/Users/gepluse/Coding/LoqBar/Packaging/RELEASE_CHECKLIST.md).

## Still missing

This packaging layer does **not** yet provide:

- a styled/custom DMG layout
- Sparkle or another updater
- a login-item helper target
- automated notarization in CI

It is meant to be the first clean step from `swift run` toward a real distributable app.
