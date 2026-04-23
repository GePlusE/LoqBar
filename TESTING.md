# LoqBar Capture Testing

This file documents the validated capture behavior observed during live Teams-call testing on two Macs:

- `MB1`: LoqBar running, headphones connected
- `MB2`: second Mac joined to the same Teams call

## Current Findings

### Validated

- `System Audio Only Test` on `MB1` captured remote Teams audio from `MB2` into `system-audio.caf`.
- `Microphone Only Test` on `MB1` captured local speech into `microphone.caf`.
- `Call Mode` produced separate `microphone.caf` and `system-audio.caf` files.
- With `MB1` speakers audible, the `MB1` microphone could pick up remote speech acoustically from the same machine.
- With `MB1` speakers effectively silent, `microphone.caf` stayed local-only while `system-audio.caf` captured the remote side.

### Product Implication

For Teams calls, the preferred architecture is:

- local speaker -> microphone capture
- remote participants -> ScreenCaptureKit/system audio capture

This is preferable to relying on a single mixed microphone capture path.

## Recommended Manual Test Procedure

### Setup

1. Put `MB1` and `MB2` in different rooms.
2. Connect headphones only to `MB1`.
3. Join the same Teams call from both Macs.
4. Run LoqBar on `MB1` only.

### Test 1: System Audio Only

Goal: verify `system-audio.caf` contains only the remote Teams audio heard by `MB1`.

1. Keep `MB1` muted.
2. Unmute `MB2`.
3. In LoqBar on `MB1`, click `Start System Audio Only Test`.
4. Speak on `MB2` for 10-15 seconds.
5. Mute `MB2`.
6. On `MB1`, click `Stop Recording`.

Expected result:

- `system-audio.caf` contains the remote `MB2` voice only.

### Test 2: Microphone Only

Goal: verify `microphone.caf` contains only the local voice on `MB1`.

1. Keep `MB2` muted.
2. Ensure `MB1` is not audibly playing remote speech into the room.
3. In LoqBar on `MB1`, click `Start Microphone Only Test`.
4. Speak near `MB1` for 10-15 seconds.
5. On `MB1`, click `Stop Recording`.

Expected result:

- `microphone.caf` contains the local `MB1` voice only.

### Test 3: Full Call Mode

Goal: verify the split-source architecture works in the main product mode.

1. Start with both Macs muted.
2. Set LoqBar on `MB1` to `Call Mode`.
3. Click `Start Recording`.
4. Unmute `MB2` and speak for 8-10 seconds.
5. Mute `MB2`.
6. Speak near `MB1` for 8-10 seconds.
7. Click `Stop Recording`.

Expected result:

- `system-audio.caf` mainly contains the remote `MB2` segment.
- `microphone.caf` mainly contains the local `MB1` segment.

## Practical Notes

- Avoid using the same person in the same room to simulate both the local and remote speakers; it makes acoustic bleed hard to interpret.
- If removing headphones interrupts the test flow, use prerecorded speech or TTS on `MB2` instead of physically moving yourself between machines.
- The current transcript export is still placeholder text; these tests validate capture routing, not transcription quality yet.
