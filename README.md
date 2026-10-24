# SpotifyReverb - iOS Reverb DSP Tweak

A native CoreAudio DSP Reverb injection tweak for Spotify on iOS.

## How It Works
- Intercepts Apple's Core Audio `AudioUnitRender` pipeline dynamically using Meta's `fishhook`.
- Directly filters stereo PCM audio streams (`ioData->mBuffers`) using an algorithmic Schroeder-Moorer / Freeverb DSP engine (4 parallel comb filters + 2 series allpass diffusion stages).
- Operates on real-time audio threads with zero memory allocation (`malloc`/`free`) for 100% stutter-free playback and zero CPU overhead.

## Building `SpotifyReverb.dylib`

### Option 1: GitHub Actions (Easiest - No Mac Needed)
1. Push this folder to a GitHub repository.
2. Go to the **Actions** tab on GitHub.
3. Download the compiled `SpotifyReverb.dylib` artifact directly from the completed run.

### Option 2: Local Mac / Xcode
Run:
```bash
chmod +x build.sh
./build.sh
```

### Option 3: Theos
Run:
```bash
make package
```

## How to Inject into `Spotify.app`

### Method A: LiveContainer (No-Jailbreak)
1. Place `SpotifyReverb.dylib` into:
   `LiveContainer/Documents/Tweaks/spotify/SpotifyReverb.dylib`
2. Enable tweak injection for Spotify in LiveContainer.
3. Open Spotify. The reverb DSP will activate automatically on audio playback.

### Method B: Sideloadly / SideStore / AltStore
1. In Sideloadly or your sideloading tool, select your decrypted Spotify IPA.
2. In the **Advanced Options / Tweak Injection** section, select `SpotifyReverb.dylib`.
3. Sign and install the IPA to your iPhone/iPad.

### Method C: Direct Mach-O Injection with `optool`
```bash
# 1. Copy the dylib into the Frameworks directory
cp SpotifyReverb.dylib Payload/Spotify.app/Frameworks/

# 2. Inject the LC_LOAD_DYLIB command into Spotify's Mach-O binary
optool install -c load -p "@rpath/SpotifyReverb.dylib" -t Payload/Spotify.app/Spotify

# 3. Re-zip into an IPA
zip -qry Spotify-Reverb.ipa Payload
```
