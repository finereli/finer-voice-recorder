# Finer Voice Recorder

A clean, native macOS voice recorder that transcribes what you say - in your language - and never makes you guess which microphone it's using.

Think of it as Voice Memos with two things it always got wrong fixed: the input device is right there in front of you, and every recording gets a transcript you can actually read, search, and copy.

## Why you might want it

- **Always record from the right microphone.** The input picker sits under the record button with a live level meter, so you see and choose your source before you hit record. No more recording a whole meeting off the wrong mic.
- **Transcripts in 63 languages, Hebrew included.** Recordings are transcribed automatically. It can detect the language on its own, and Hebrew, Arabic, and other right-to-left languages read the way they should.
- **Everything stays searchable.** Search across titles and transcripts to find that one thing someone said last week.
- **Small files.** Recordings are compressed (`.m4a`), so hours of audio don't eat your disk.
- **Your recordings are yours.** Export any recording - or a whole batch - to a folder, copy a transcript to the clipboard, or reveal the file in Finder. Nothing is locked in.

## Good for

- **Interviews and meetings** - record, then read the transcript instead of scrubbing audio.
- **Voice notes** - capture a thought, find it later by what you said.
- **Language practice** - speak, see the transcription, check yourself.
- **Drafting out loud** - talk through an idea and get text back.

## Getting started

1. Download the latest `.zip` from [Releases](https://github.com/finereli/finer-voice-recorder/releases) and unzip it.
2. Move **Finer Voice Recorder** to your Applications folder and open it.
3. Allow microphone and speech-recognition access when asked.

That's it. It's signed and notarized by Apple, so it opens with no scary warnings.

## Using it

- **Record.** Pick your input at the bottom of the sidebar, press the red button, press it again to stop.
- **Transcribe.** It happens automatically. To redo it in a specific language, pick one from the language menu under the transcript.
- **Rename.** Click a recording's title to rename it.
- **Find.** Type in the search box to match titles and transcript text.
- **Export.** Use the share button (or right-click) for a single recording, or select several and export them all to one folder at once. Transcripts come along as `.txt` files.
- **Batch actions.** ⌘-click or ⇧-click to select multiple recordings, then delete, favorite, or export the whole set.

## Your privacy

Recording happens on your Mac. Transcription uses Apple's built-in speech recognition, which runs on-device for many languages and may use Apple's servers for others - the same engine the rest of macOS uses. There are no accounts, and nothing is sent to us.

## Requirements

macOS 13 or later. Universal build - runs natively on both Apple Silicon and Intel Macs.

---

*Building from source: it's a pure SwiftPM SwiftUI app - `./build.sh` produces the app; `NOTARIZE=1 ./build.sh` makes a signed, notarized build.*
