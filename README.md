# LoqBar

LoqBar is a native macOS menu bar app for capturing meetings locally and exporting structured Markdown transcripts that are easy for downstream agents to work with.

## What LoqBar does today

LoqBar already supports a real end-to-end local workflow:

- menu bar app with `Auto`, `Local`, and `Remote` modes
- local microphone recording
- split-source call capture with microphone plus system audio
- isolated diagnostics:
  - `Microphone Only Test`
  - `System Audio Only Test`
- configurable storage root
- managed local transcription setup inside the hidden `.loqbar` folder
- external `whisper-cli` + model paths when you already have your own setup
- local transcript export to Markdown
- session history, search, filters, and date range filtering
- session detail editing:
  - speaker aliases
  - per-segment speaker reassignment
  - manual transcript corrections with audit trail
  - shared links and additional context for downstream agents
- retry transcription on existing recordings
- lightweight manual update check against GitHub Releases
- release packaging as `.app`, `.zip`, and `.dmg`

## Current product shape

LoqBar is already useful in real work, but it is still an MVP and not a fully polished public Mac app.

The biggest still-open product areas are:

- mixed-language reliability within one recording
- broader multi-speaker diarization for large remote calls
- continued capture hardening across different call apps and edge cases
- smoother update/install flow
- optional future notarization/signing polish for broader public distribution

## Download and install

The easiest way to install LoqBar on another Mac is from GitHub Releases:

- Open the [LoqBar Releases page](https://github.com/GePlusE/LoqBar/releases)
- Download the latest `LoqBar.dmg`
- If you prefer, you can also download `LoqBar.zip`

### Install from the DMG

1. Open the downloaded `LoqBar.dmg`
2. Drag `LoqBar.app` into `Applications`
3. Open `Applications`
4. Launch `LoqBar`

### Install from the ZIP

1. Open the downloaded `LoqBar.zip`
2. Move `LoqBar.app` into `Applications`
3. Launch `LoqBar` from `Applications`

### First launch on another Mac

LoqBar is currently packaged for trusted-user distribution, not a frictionless public App Store-style install. On some Macs, Gatekeeper may block the first launch.

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

## First-use setup

LoqBar now includes a first-use readiness checklist in:

- first-run onboarding
- `Preferences > General`

The checklist helps a new Mac confirm:

- `Microphone` permission
- `Screen & System Audio Recording` permission for `Remote` mode
- storage root setup
- local transcription readiness

### Permissions

Depending on how you use LoqBar, macOS may ask for:

- `Microphone` access for local capture
- `Screen Recording` / `Screen & System Audio Recording` for remote/call capture

If you want to use `Remote` mode, both permissions should be enabled.

### Troubleshooting screen permission

If macOS shows LoqBar as enabled for screen/system-audio recording, but LoqBar still behaves as if the permission is missing:

1. Open `LoqBar > Preferences > General`
2. Click `Reset Screen Permission`
3. If macOS prompts again, allow the permission
4. If `Remote` still looks unavailable, quit and reopen LoqBar once

This repairs a stale macOS `ScreenCapture` permission state that can occasionally survive normal toggling in System Settings, especially after manual app replacement during updates.

## Transcription setup

Recording works on its own. Transcription is optional and can be completed later.

LoqBar supports two ways to transcribe locally:

1. **Managed setup**
   - LoqBar installs its bundled `whisper-cli`
   - LoqBar installs runtime libraries
   - LoqBar downloads the selected model into the hidden `.loqbar` folder inside your storage root

2. **External setup**
   - you point LoqBar at an existing `whisper-cli`
   - and an existing local model file

### Managed setup on a new Mac

1. Open `LoqBar > Preferences > Transcription`
2. Choose a model
3. Click `Install Managed Setup`
4. Wait until the status changes to `Ready`

If transcription was not ready during a recording, LoqBar still keeps the saved audio and lets you use `Retry Transcription` later once setup is complete.

### Model guidance

Current built-in choices:

- `Base`: fastest, weakest
- `Small`: best default for call recordings
- `Medium`: slower, stronger
- `Large`: highest quality in the current picker, but much heavier on memory and processing time

## Using LoqBar

### Main modes

- `Auto`: uses the current default capture logic
- `Local`: optimized for local microphone capture
- `Remote`: optimized for call capture with microphone plus system audio

### Productive workflow

A typical workflow looks like this:

1. Start a recording from the menu bar
2. Stop the recording when the meeting ends
3. Let LoqBar optimize audio and transcribe in the background
4. Open `Sessions`
5. Review the transcript
6. Fix transcript errors or speaker assignments if needed
7. Add:
   - shared links
   - additional context
8. use the exported Markdown with your downstream agent

### Session editing

LoqBar supports:

- renaming sessions
- per-session transcription language override
- speaker aliasing
- per-segment speaker reassignment
- manual transcript corrections with the original machine text kept visible
- session context fields for links and notes

## Testing and validation

The validated capture procedures are documented in [TESTING.md](TESTING.md).

That file currently covers:

- Teams split-source validation on two Macs
- microphone-only and system-audio-only diagnostics
- recommended manual validation approach for call capture

## Development

### Build from source

```bash
swift build
```

### Run from source

```bash
swift run LoqBar
```

### Run tests

```bash
swift test
```

The current test suite focuses on core model and setup behavior:

- managed transcription path mapping
- transcription setup status detection
- speaker roster expansion logic
- backward-compatible session decoding

## Packaging

LoqBar can be wrapped into a proper macOS app bundle:

```bash
./Packaging/build-app.sh
```

That produces:

```bash
dist/LoqBar.app
dist/LoqBar.zip
```

A DMG can be created with:

```bash
./Packaging/create-dmg.sh
```

Packaging details are documented in [Packaging/README.md](Packaging/README.md).

## Known limitations

The main known limitations right now are:

- remote call capture still benefits from continued real-world validation across apps
- true automatic diarization for many remote speakers is not fully solved yet
- mixed-language switching inside one session still needs improvement
- the built-in updater currently checks for updates and opens the release manually; it does not self-install yet
- LoqBar is packaged for a trusted-user workflow rather than a mass-market release path
