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
RELEASE_FEED_URL="https://api.github.com/repos/OWNER/REPO/releases/latest" \
RELEASE_PAGE_URL="https://github.com/OWNER/REPO/releases" \
./Packaging/build-app.sh
```

## Manual update checks

LoqBar can show a lightweight `Check for Updates` flow in `Preferences > General`.

The packaged app reads its update source from the app bundle metadata:

- `LoqBarReleaseFeedURL`
- `LoqBarReleasePageURL`

`build-app.sh` fills those from:

- `RELEASE_FEED_URL`
- `RELEASE_PAGE_URL`

By default, LoqBar uses the GitHub Releases endpoints for:

- `GePlusE/LoqBar`

Supported feed formats:

- GitHub latest release API:
  - `https://api.github.com/repos/OWNER/REPO/releases/latest`
- a custom JSON manifest with fields like:
  - `version`
  - `build`
  - `title`
  - `download_url`
  - `release_page_url`
  - `published_at`
  - `notes`

For local `swift run` development, LoqBar also falls back to:

- environment variables `RELEASE_FEED_URL` and `RELEASE_PAGE_URL`
- `Packaging/release.env`
- `Packaging/release.env.local`

That makes it possible to test the manual updater before building a packaged `.app`.

## Validate the bundle

```bash
./Packaging/validate-release.sh
```

## Check distribution readiness

```bash
source ./Packaging/release.env.example
./Packaging/check-distribution-readiness.sh
```

## Create a DMG

```bash
./Packaging/create-dmg.sh
```

By default, `create-dmg.sh` also tries to apply a Finder layout so the mounted installer shows:

- `LoqBar.app`
- `Applications`

in a cleaner drag-to-install arrangement.

## Notarization later

Once the app is signed with a real Developer ID identity, the next step is notarization:

```bash
KEYCHAIN_PROFILE="YOUR_PROFILE" ./Packaging/notarize-app.sh
```

A fuller release flow is documented in [Packaging/RELEASE_CHECKLIST.md](/Users/gepluse/Coding/LoqBar/Packaging/RELEASE_CHECKLIST.md).

## Still missing

This packaging layer does **not** yet provide:

- a custom DMG background image by default
- Sparkle or another updater
- a login-item helper target
- automated notarization in CI

It is meant to be the first clean step from `swift run` toward a real distributable app.
