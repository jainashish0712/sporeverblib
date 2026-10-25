# SpotifyReverb

An ultra-low latency, studio-quality Core Audio DSP Reverb tweak for Spotify on iOS, complete with an on-screen interactive control HUD.

## Features
- **Pizzicato / Freeverb DSP Architecture:** 4 parallel low-pass feedback comb filters tuned with prime delay lines + 2 cascaded allpass diffusion stages.
- **Floating Interactive HUD (Option A):**
  - **Floating Pill Button (`🎛️`):** Sits unobtrusively on screen above the player bar. Fully draggable anywhere on the screen (with automatic boundary and notch/safe-area clamping).
  - **Frosted Dark Glass Control Panel:** High-resolution blur card with Spotify Green `#1DB954` accents.
  - **Enable / Disable Toggle:** Instant bypass switch.
  - **Wet / Dry Mix Slider:** 0% to 100% wet mix with live percentage readout.
  - **Room Size Slider:** 0.1 to 0.98 feedback gain control (decay duration).
  - **Damping Slider:** 0.0 to 1.0 high-frequency absorption filter.
  - **Reset to Studio Defaults:** One-tap restoration of optimal listening acoustics.
  - **Two-Finger Double-Tap Shortcut:** Double-tapping anywhere on the screen with two fingers toggles the HUD open or closed.
- **Audio Thread Safety:**
  - Zero memory allocations (`malloc`), zero locks, and zero Objective-C message sends on the real-time audio thread.
  - Real-time parameter smoothing (`target` interpolation) eliminates zipper clicks and audio popping when dragging sliders.
  - Fast soft-clipping limiter prevents harsh digital distortion.
- **Hardened Symbol Hooking:**
  - Dual hook strategy: Intercepts both `AudioUnitSetProperty` (`kAudioUnitProperty_SetRenderCallback`) and `AudioUnitRender`.
  - Supports modern compile-time `DYLD_INTERPOSE` alongside runtime `fishhook` with `vm_protect` memory page protection to safely patch iOS `__DATA_CONST` segments without `KERN_PROTECTION_FAILURE`.

## Project Structure
- `SpotifyReverb.h`: Public C interface for thread-safe reverb DSP parameter controls.
- `SpotifyReverb.m`: Core Audio DSP engine, callback wrappers, and symbol interposing.
- `SpotifyReverbUI.h`: UIKit HUD controller interface.
- `SpotifyReverbUI.m`: Floating draggable button, modal HUD panel, sliders, and gestures.
- `fishhook.h` & `fishhook.c`: Mach-O symbol rebinding engine patched for modern iOS memory protection.
- `Makefile`: Theos tweak build specification.
- `build.sh`: Direct compilation script using Apple's `clang`.
- `.github/workflows/build.yml`: Automated GitHub Actions build workflow to generate `SpotifyReverb.dylib` on macOS runners.

## How to Build
### Option 1: GitHub Actions (No Local Mac Required)
Push to GitHub; the pre-configured workflow compiles the tweak on Apple's macOS runner and uploads `SpotifyReverb.dylib` under Artifacts.

### Option 2: Local Mac / Theos
```bash
# Using build.sh
./build.sh

# Or using Theos
make package
```
