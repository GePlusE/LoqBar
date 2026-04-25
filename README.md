# LoqBar

LoqBar is a native macOS menu bar app concept for capturing meetings locally and exporting structured Markdown transcripts.

This repository currently contains an MVP scaffold built in SwiftUI with:

- menu bar app shell
- first-run setup flow
- settings and session history
- capture mode selection (`Auto`, `Local Meeting`, `Call`)
- isolated `Microphone Only Test` and `System Audio Only Test` diagnostics
- permission and login-item service boundaries
- validated microphone + ScreenCaptureKit capture spike
- transcription planning seam for future whisper.cpp integration

## Download And Install

The easiest way to install LoqBar on another Mac is through GitHub Releases:

- Open the [LoqBar Releases page](https://github.com/GePlusE/LoqBar/releases)
- Download the latest `LoqBar.dmg`
- If you prefer, you can also download `LoqBar.zip`

### Install From The DMG

1. Open the downloaded `LoqBar.dmg`
2. In the installer window, drag `LoqBar.app` into `Applications`
3. Open `Applications`
4. Launch `LoqBar`

### Install From The ZIP

1. Open the downloaded `LoqBar.zip`
2. Move `LoqBar.app` into `Applications`
3. Launch `LoqBar` from `Applications`

### First Launch On Another Mac

LoqBar is currently packaged and signed for testing, but not yet fully notarized for frictionless public distribution. On some Macs, Gatekeeper may block the first launch.

If that happens:

1. Open `Applications`
2. Right-click `LoqBar.app`
3. Choose `Open`
4. Confirm `Open`

If macOS still blocks it:

1. Try opening `LoqBar.app` once so macOS registers the block
2. Open `System Settings > Privacy & Security`
3. Scroll down to the security section
4. Click `Open Anyway`

### Permissions

On first use, LoqBar may ask for:

- `Microphone` access for local capture
- `Screen Recording` access for remote/call capture

If you want to use `Remote` / `Call` capture, both permissions should be enabled.

### Transcription Setup

Recording works on its own, but local transcription still needs a whisper engine and model on each Mac.

After installation:

1. Open `LoqBar > Preferences`
2. Go to `Transcription`
3. Either:
   - choose existing external `whisper-cli` and model paths
   - or use LoqBar's managed transcription setup flow

If transcription is not configured yet, LoqBar will still save recordings and let you retry transcription later.

## Current Status

The app shell compiles as a Swift package and now includes a validated split-source call-capture spike plus a transcription-planning layer that chooses which audio sources should feed later local inference.

The following areas are intentionally scaffolded but not yet fully implemented:

- final production-grade microphone capture tuning
- production-grade ScreenCaptureKit call capture hardening
- whisper.cpp execution and model management
- speaker diarization
- model download and offline inference
- transcript merge logic across separately transcribed local and remote sources

## Build From Source

```bash
swift build
```

## Run From Source

```bash
swift run LoqBar
```

## App Bundle

LoqBar can also be wrapped into a proper macOS `.app` bundle:

```bash
./Packaging/build-app.sh
```

That produces:

```bash
dist/LoqBar.app
```

Packaging details and signing/notarization notes are documented in [Packaging/README.md](/Users/gepluse/Coding/LoqBar/Packaging/README.md).

## Validation

The validated manual capture procedure is documented in [TESTING.md](/Users/gepluse/Coding/LoqBar/TESTING.md).
