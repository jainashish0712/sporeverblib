# SpotifyReverb

An ultra-low latency, studio-quality Core Audio DSP Reverb, Pitch, & System Volume tweak for Spotify on iOS.

## Features
- **Real-Time Pitch Shifter:** -4.0 to +4.0 semitones in 0.2 intervals (0% tempo change).
- **Freeverb DSP:** 4 comb filters + 2 allpass filters with 100% complementary Dry/Wet mix.
- **System Volume Control:** Integrated hardware volume slider (`MPVolumeView`).
- **Compact HUD:** Ergonomic right-handed thumb reach floating above the Now Playing screen.

## Direct Dylib Download (No Zip)
Direct raw `.dylib` link for LiveContainer:
```text
https://github.com/<OWNER>/<REPO>/releases/latest/download/SpotifyReverb.dylib
```
*(Automated 1-tap download shortcut guide: [LiveContainer_iOS_Shortcut_Guide.md](LiveContainer_iOS_Shortcut_Guide.md))*

## Build
```bash
./build.sh
```
