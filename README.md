# SpotifyReverb & Pitch

An ultra-low latency, studio-quality Core Audio DSP Reverb & Pitch tweak for Spotify on iOS, complete with an on-screen interactive control HUD.

## Features
- **Independent Real-Time Pitch Shifter:**
  - Range: **-4.0 to +4.0 semitones** in **0.2 semitone intervals** (41 discrete steps).
  - **Zero Tempo Change:** Strict frame-invariant dual-tap Hann window crossfade preserves song speed and playback duration.
  - **Default: 0.0 semitones** (bit-exact passthrough when unaltered).
- **Pizzicato / Freeverb DSP Architecture:**
  - 4 parallel low-pass feedback comb filters tuned with prime delay lines + 2 cascaded allpass diffusion stages.
  - Optimal internal studio acoustic absorption.
- **Floating Interactive HUD (Option A):**
  - **Floating Pill Button (`🎛️`):** Hosted in a high-level passthrough overlay window (`windowLevel = UIWindowLevelNormal + 1000`). Always floats above Spotify's Now Playing screen, album art, lyrics, and modal views.
  - **Frosted Dark Glass Control Panel:** Half-intensity blur with Spotify Green `#1DB954` accents and responsive full-width card layout.
  - **Enable / Disable Toggle:** Instant bypass switch for all DSP effects.
  - **Pitch Slider:** Stepped from -4.0 to +4.0 semitones in 0.2 intervals with live text readout (`Pitch: 0.0 st (Original)`, `Pitch: +1.4 st`, `Pitch: -2.0 st`).
  - **Reverb Mix Slider:** Strictly complementary crossfade (`Dry% + Wet% = 100%`).
  - **Room Size Slider:** 0.1 to 0.98 feedback gain control (decay duration).
  - **Reset to Studio Defaults:** One-tap restoration of original pitch (`0.0 st`) and standard room acoustics.
  - **Two-Finger Double-Tap Shortcut:** Double-tapping anywhere on the screen with two fingers toggles the HUD open or closed.
- **Audio Thread Safety:**
  - Zero memory allocations (`malloc`), zero locks, and zero Objective-C message overhead on the real-time audio thread.
  - Real-time parameter smoothing (`target` interpolation) eliminates zipper clicks and audio popping when dragging sliders.
  - Fast soft-clipping limiter prevents harsh digital distortion.
- **Hardened Symbol Hooking & Linking:**
  - Dual hook strategy: Intercepts both `AudioUnitSetProperty` (`kAudioUnitProperty_SetRenderCallback`) and `AudioUnitRender`.
  - Links against Apple's standard frameworks: `AudioToolbox`, `Foundation`, `UIKit`, `CoreGraphics`, `QuartzCore`.
  - Supports modern compile-time `DYLD_INTERPOSE` alongside runtime `fishhook` with `vm_protect` memory page protection to safely patch iOS `__DATA_CONST` segments without `KERN_PROTECTION_FAILURE`.

## Direct Dylib Download (No Zip)
Every push to GitHub automatically compiles and attaches the raw uncompressed `SpotifyReverb.dylib` to the rolling `latest` release:
```text
https://github.com/<OWNER>/<REPO>/releases/latest/download/SpotifyReverb.dylib
```
See [LiveContainer_iOS_Shortcut_Guide.md](file:///D:/apps/com.spotify.client-9.1.94-eeveedecrypter/SpotifyReverb/LiveContainer_iOS_Shortcut_Guide.md) to set up a 1-tap download shortcut on your iPhone.

## How to Build
### GitHub Actions (Automated)
Push to GitHub; the pre-configured workflow compiles the tweak on Apple's macOS runner, updates the `latest` release with the raw `SpotifyReverb.dylib`, and uploads the artifact.

### Local Mac / Theos
```bash
# Using build.sh
./build.sh

# Or using Theos
make package
```
