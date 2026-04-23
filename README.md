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

## Current Status

The app shell compiles as a Swift package and now includes a validated split-source call-capture spike plus a transcription-planning layer that chooses which audio sources should feed later local inference.

The following areas are intentionally scaffolded but not yet fully implemented:

- final production-grade microphone capture tuning
- production-grade ScreenCaptureKit call capture hardening
- whisper.cpp execution and model management
- speaker diarization
- model download and offline inference
- transcript merge logic across separately transcribed local and remote sources

## Build

```bash
swift build
```

## Validation

The validated manual capture procedure is documented in [TESTING.md](/Users/gepluse/Coding/LoqBar/TESTING.md).
