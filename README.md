# Voice Recorder

A native macOS voice-recording app in the spirit of Apple's Voice Memos, built
as a pure SwiftPM SwiftUI app.

## What it does

- **Records to compressed `.m4a`** (AAC) via `AVAudioEngine`. A ~6-second clip is
  a few dozen KB, not megabytes.
- **Input device selection is a first-class, always-visible control.** The bar
  across the top of the window lists every Core Audio input device with a live
  level meter, and hot-plugging a device updates the list automatically. You
  choose the mic before you hit record, never buried in a menu.
- **Built-in transcription** using Apple's on-device/relay Speech framework, in
  any of the 63 languages macOS supports - **including Hebrew (he-IL)**. The
  transcript panel renders right-to-left for Hebrew/Arabic/Farsi. Recordings are
  transcribed automatically after capture, and you can re-transcribe in a
  different language anytime.
- **Easy filesystem export.** Every recording has "Export Audio…" (save-panel
  copy of the `.m4a`), "Export Transcript…" (`.txt`), and "Reveal in Finder".
- Search across titles and transcripts, favorites, rename, delete, 15-second
  skip, click-to-seek waveform.

## Where files live

`~/Library/Application Support/VoiceRecorder/` - the `.m4a` files plus a
`recordings.json` manifest holding titles, durations, languages and transcripts.

## Build

```bash
./build.sh              # fast local ad-hoc build
SIGN=1 ./build.sh       # Developer ID signed (hardened runtime)
NOTARIZE=1 ./build.sh   # signed + Apple-notarized + stapled, no Gatekeeper warning
open VoiceRecorder.app
```

Requires macOS 13+. First launch prompts for microphone and speech-recognition
permission.

## Architecture

| File | Role |
|------|------|
| `AudioDeviceManager` | Core Audio input-device enumeration + selection + hot-plug |
| `AudioRecorder` | `AVAudioEngine` capture → AAC `.m4a`, live level + waveform |
| `AudioPlayer` | `AVAudioPlayer` playback with a published clock |
| `WaveformGenerator` | Downsamples a file into amplitude bins for drawing |
| `Transcriber` | `SFSpeechRecognizer` file transcription, per-language |
| `RecordingStore` | On-disk files + JSON manifest |
| `AppModel` | Coordinator tying it all together |
| `Views/*` | `DeviceBar`, `SidebarView`, `DetailView`, `TranscriptPanel`, `WaveformView` |
