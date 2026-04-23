# LoqBar

LoqBar is a native macOS menu bar app concept for capturing meetings locally and exporting structured Markdown transcripts.

This repository currently contains an MVP scaffold built in SwiftUI with:

- menu bar app shell
- first-run setup flow
- settings and session history
- capture mode selection (`Auto`, `Local Meeting`, `Call`)
- permission and login-item service boundaries
- transcript export model and sample export pipeline
- explicit placeholder seams for the high-risk Teams/headphones audio-capture spike

## Current Status

The app shell compiles as a Swift package and provides the product structure needed to implement the real recording and transcription pipeline next.

The following areas are intentionally scaffolded but not yet fully implemented:

- microphone recording pipeline
- ScreenCaptureKit-based call audio capture
- whisper.cpp integration
- speaker diarization
- model download and offline inference

## Build

```bash
swift build
```

## Recommended Next Step

Validate the `Call Mode` feasibility spike first:

1. capture microphone input
2. capture Teams/system audio while using headphones
3. determine whether separate or mixed streams are more reliable
4. finalize permission UX and fallback behavior
