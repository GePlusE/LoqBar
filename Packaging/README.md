# Packaging LoqBar

This folder contains the first app-bundle packaging flow for LoqBar.

## What it does

`build-app.sh` builds the Swift package and wraps the resulting `LoqBar` executable in a proper macOS `.app` bundle:

- `LoqBar.app/Contents/MacOS/LoqBar`
- `LoqBar.app/Contents/Info.plist`
- optional `LoqBar.app/Contents/Resources/LoqBar.icns`

The bundle is created in:

```bash
dist/LoqBar.app
```

## Build a local app bundle

```bash
./Packaging/build-app.sh
```

By default this uses ad-hoc signing (`SIGNING_IDENTITY=-`), which is fine for local testing.

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
codesign --verify --deep --strict dist/LoqBar.app
spctl --assess --type execute dist/LoqBar.app
```

## Notarization later

Once the app is signed with a real Developer ID identity, the next step is notarization:

```bash
ditto -c -k --keepParent dist/LoqBar.app dist/LoqBar.zip
xcrun notarytool submit dist/LoqBar.zip --wait --keychain-profile "YOUR_PROFILE"
xcrun stapler staple dist/LoqBar.app
```

## Still missing

This packaging layer does **not** yet provide:

- a custom app icon
- DMG creation
- Sparkle or another updater
- a login-item helper target
- automated notarization in CI

It is meant to be the first clean step from `swift run` toward a real distributable app.
