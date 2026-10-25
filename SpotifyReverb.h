// SpotifyReverb.h
// Public C Interface for Spotify Reverb DSP & UI Parameter Control
// Thread-safe, real-time audio safe, zero allocation

#ifndef SpotifyReverb_h
#define SpotifyReverb_h

#import <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Master Reverb Toggle
void SpotifyReverb_SetEnabled(bool enabled);
bool SpotifyReverb_IsEnabled(void);

// Dry / Wet Mix (0.0 to 1.0)
void SpotifyReverb_SetWetDry(float wet, float dry);
float SpotifyReverb_GetWet(void);
float SpotifyReverb_GetDry(void);

// Room Size / Decay Time (0.1 to 0.98)
void SpotifyReverb_SetRoomSize(float roomSize);
float SpotifyReverb_GetRoomSize(void);

// High-Frequency Damping / Absorption (0.0 to 1.0)
void SpotifyReverb_SetDamping(float damping);
float SpotifyReverb_GetDamping(void);

// Reset to Optimal Studio Acoustics Defaults
void SpotifyReverb_ResetDefaults(void);

#ifdef __cplusplus
}
#endif

#endif /* SpotifyReverb_h */
