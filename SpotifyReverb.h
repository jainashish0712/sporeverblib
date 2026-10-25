// SpotifyReverb.h
// Public C Interface for Spotify Reverb & Pitch DSP Parameter Control
// Thread-safe, real-time audio safe, zero allocation

#ifndef SpotifyReverb_h
#define SpotifyReverb_h

#import <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Master Effect Toggle
void SpotifyReverb_SetEnabled(bool enabled);
bool SpotifyReverb_IsEnabled(void);

// Real-Time Pitch Shift (-4.0 to +4.0 semitones in 0.2 intervals, tempo preserved)
void SpotifyReverb_SetPitch(float semitones);
float SpotifyReverb_GetPitch(void);

// Dry / Wet Mix (0.0 to 1.0)
void SpotifyReverb_SetWetDry(float wet, float dry);
float SpotifyReverb_GetWet(void);
float SpotifyReverb_GetDry(void);

// Room Size / Decay Time (0.1 to 0.98)
void SpotifyReverb_SetRoomSize(float roomSize);
float SpotifyReverb_GetRoomSize(void);

// Reset to Optimal Studio Acoustic Defaults (Pitch 0.0, Room 0.82, Wet 0.35, Dry 0.65)
void SpotifyReverb_ResetDefaults(void);

#ifdef __cplusplus
}
#endif

#endif /* SpotifyReverb_h */
