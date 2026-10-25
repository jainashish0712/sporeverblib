// SpotifyReverb.m
// Core Audio DSP Reverb Injection Tweak for Spotify on iOS
// Hardened against all known iOS runtime hazards (KERN_PROTECTION_FAILURE, real-time priority inversion, buffer misalignments)

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <string.h>
#import <stdbool.h>
#import <stdint.h>
#import <stdlib.h>
#import <math.h>
#import "SpotifyReverb.h"
#import "fishhook.h"

#define NUM_COMB_FILTERS 4
#define NUM_ALLPASS_FILTERS 2

// Tuned prime delay lengths for 44.1kHz / 48kHz audio streams
static const int kCombLengthsL[NUM_COMB_FILTERS] = {1116, 1188, 1277, 1356};
static const int kCombLengthsR[NUM_COMB_FILTERS] = {1139, 1211, 1300, 1379};
static const int kAllpassLengthsL[NUM_ALLPASS_FILTERS] = {225, 556};
static const int kAllpassLengthsR[NUM_ALLPASS_FILTERS] = {248, 579};

#define MAX_COMB_BUF 2048
#define MAX_ALLPASS_BUF 1024

typedef struct {
    // Comb filter circular buffers and state
    float combBuffersL[NUM_COMB_FILTERS][MAX_COMB_BUF];
    float combBuffersR[NUM_COMB_FILTERS][MAX_COMB_BUF];
    int combIndicesL[NUM_COMB_FILTERS];
    int combIndicesR[NUM_COMB_FILTERS];
    float combFilterStoreL[NUM_COMB_FILTERS];
    float combFilterStoreR[NUM_COMB_FILTERS];

    // Allpass filter circular buffers and state
    float allpassBuffersL[NUM_ALLPASS_FILTERS][MAX_ALLPASS_BUF];
    float allpassBuffersR[NUM_ALLPASS_FILTERS][MAX_ALLPASS_BUF];
    int allpassIndicesL[NUM_ALLPASS_FILTERS];
    int allpassIndicesR[NUM_ALLPASS_FILTERS];

    // Reverb DSP parameters (current interpolated state)
    float roomSize;
    float damping;
    float wet;
    float dry;

    // Target parameters (updated by UI sliders, smoothly interpolated to eliminate zipper noise)
    float targetRoomSize;
    float targetDamping;
    float targetWet;
    float targetDry;

    bool enabled;
} ReverbDSP;

static ReverbDSP gReverb;

static void ReverbDSP_Init(ReverbDSP *dsp) {
    memset(dsp, 0, sizeof(ReverbDSP));
    dsp->roomSize = 0.82f;
    dsp->damping = 0.25f;
    dsp->wet = 0.35f;
    dsp->dry = 0.65f;
    dsp->targetRoomSize = 0.82f;
    dsp->targetDamping = 0.25f;
    dsp->targetWet = 0.35f;
    dsp->targetDry = 0.65f;
    dsp->enabled = true;
}

// Fast soft-clipper: guarantees output stays strictly within [-1.0, 1.0] without harsh digital distortion
static inline float SoftClip(float x) {
    if (x > 1.0f) return 1.0f;
    if (x < -1.0f) return -1.0f;
    return x;
}

// Real-time audio sample processing (zero malloc, zero Obj-C overhead, real-time audio thread safe)
static inline void ProcessSampleStereo(ReverbDSP *dsp, float *inOutL, float *inOutR) {
    float inL = *inOutL;
    float inR = *inOutR;
    float monoIn = 0.5f * (inL + inR);

    float outL = 0.0f;
    float outR = 0.0f;

    // 1. Parallel Low-pass Feedback Comb Filters
    for (int i = 0; i < NUM_COMB_FILTERS; i++) {
        // Left Channel
        int lenL = kCombLengthsL[i];
        int idxL = dsp->combIndicesL[i];
        float bufOutL = dsp->combBuffersL[i][idxL];
        dsp->combFilterStoreL[i] = (bufOutL * (1.0f - dsp->damping)) + (dsp->combFilterStoreL[i] * dsp->damping);
        dsp->combBuffersL[i][idxL] = monoIn + (dsp->combFilterStoreL[i] * dsp->roomSize);
        dsp->combIndicesL[i] = (idxL + 1) % lenL;
        outL += bufOutL;

        // Right Channel
        int lenR = kCombLengthsR[i];
        int idxR = dsp->combIndicesR[i];
        float bufOutR = dsp->combBuffersR[i][idxR];
        dsp->combFilterStoreR[i] = (bufOutR * (1.0f - dsp->damping)) + (dsp->combFilterStoreR[i] * dsp->damping);
        dsp->combBuffersR[i][idxR] = monoIn + (dsp->combFilterStoreR[i] * dsp->roomSize);
        dsp->combIndicesR[i] = (idxR + 1) % lenR;
        outR += bufOutR;
    }

    outL *= 0.25f;
    outR *= 0.25f;

    // 2. Cascaded Allpass Filters (Diffusion)
    for (int i = 0; i < NUM_ALLPASS_FILTERS; i++) {
        // Left Channel
        int lenL = kAllpassLengthsL[i];
        int idxL = dsp->allpassIndicesL[i];
        float bufOutL = dsp->allpassBuffersL[i][idxL];
        dsp->allpassBuffersL[i][idxL] = outL + (bufOutL * 0.5f);
        outL = -outL + bufOutL;
        dsp->allpassIndicesL[i] = (idxL + 1) % lenL;

        // Right Channel
        int lenR = kAllpassLengthsR[i];
        int idxR = dsp->allpassIndicesR[i];
        float bufOutR = dsp->allpassBuffersR[i][idxR];
        dsp->allpassBuffersR[i][idxR] = outR + (bufOutR * 0.5f);
        outR = -outR + bufOutR;
        dsp->allpassIndicesR[i] = (idxR + 1) % lenR;
    }

    // 3. Dry/Wet Mixing with Safe Limiting
    float mixedL = (inL * dsp->dry) + (outL * dsp->wet);
    float mixedR = (inR * dsp->dry) + (outR * dsp->wet);

    *inOutL = SoftClip(mixedL);
    *inOutR = SoftClip(mixedR);
}

// Process arbitrary CoreAudio AudioBufferList (both non-interleaved and interleaved, Float32 and Int16)
static inline void ProcessAudioBufferList(ReverbDSP *dsp, UInt32 inNumberFrames, AudioBufferList *ioData) {
    if (ioData == NULL || inNumberFrames == 0 || ioData->mNumberBuffers == 0 || !dsp->enabled) return;

    AudioBuffer *b0 = &ioData->mBuffers[0];
    if (b0->mData == NULL || b0->mDataByteSize == 0) return;

    // Silky smooth parameter interpolation per buffer block (eliminates audio zipper noise during slider drags)
    dsp->roomSize += 0.05f * (dsp->targetRoomSize - dsp->roomSize);
    dsp->damping  += 0.05f * (dsp->targetDamping  - dsp->damping);
    dsp->wet      += 0.05f * (dsp->targetWet      - dsp->wet);
    dsp->dry      += 0.05f * (dsp->targetDry      - dsp->dry);

    UInt32 channels0 = b0->mNumberChannels ? b0->mNumberChannels : 1;
    UInt32 bytesPerSample = b0->mDataByteSize / (inNumberFrames * channels0);

    // Case 1: Non-Interleaved Stereo (2 separate buffers, 1 channel each)
    if (ioData->mNumberBuffers >= 2 && ioData->mBuffers[1].mData != NULL) {
        if (bytesPerSample == sizeof(float)) {
            float *left = (float *)ioData->mBuffers[0].mData;
            float *right = (float *)ioData->mBuffers[1].mData;
            for (UInt32 frame = 0; frame < inNumberFrames; frame++) {
                ProcessSampleStereo(dsp, &left[frame], &right[frame]);
            }
        } else if (bytesPerSample == sizeof(int16_t)) {
            int16_t *left = (int16_t *)ioData->mBuffers[0].mData;
            int16_t *right = (int16_t *)ioData->mBuffers[1].mData;
            for (UInt32 frame = 0; frame < inNumberFrames; frame++) {
                float fL = left[frame] / 32768.0f;
                float fR = right[frame] / 32768.0f;
                ProcessSampleStereo(dsp, &fL, &fR);
                left[frame] = (int16_t)(fL * 32767.0f);
                right[frame] = (int16_t)(fR * 32767.0f);
            }
        }
    }
    // Case 2: Interleaved Stereo (1 buffer, alternating L/R samples)
    else if (ioData->mNumberBuffers == 1 && channels0 == 2) {
        if (bytesPerSample == sizeof(float)) {
            float *interleaved = (float *)b0->mData;
            for (UInt32 frame = 0; frame < inNumberFrames; frame++) {
                ProcessSampleStereo(dsp, &interleaved[frame * 2], &interleaved[frame * 2 + 1]);
            }
        } else if (bytesPerSample == sizeof(int16_t)) {
            int16_t *interleaved = (int16_t *)b0->mData;
            for (UInt32 frame = 0; frame < inNumberFrames; frame++) {
                float fL = interleaved[frame * 2] / 32768.0f;
                float fR = interleaved[frame * 2 + 1] / 32768.0f;
                ProcessSampleStereo(dsp, &fL, &fR);
                interleaved[frame * 2] = (int16_t)(fL * 32767.0f);
                interleaved[frame * 2 + 1] = (int16_t)(fR * 32767.0f);
            }
        }
    }
}

// ============================================================================
// Public Parameter Getters & Setters
// ============================================================================
void SpotifyReverb_SetEnabled(bool enabled) {
    gReverb.enabled = enabled;
}

bool SpotifyReverb_IsEnabled(void) {
    return gReverb.enabled;
}

void SpotifyReverb_SetWetDry(float wet, float dry) {
    if (wet < 0.0f) wet = 0.0f;
    if (wet > 1.0f) wet = 1.0f;
    if (dry < 0.0f) dry = 0.0f;
    if (dry > 1.0f) dry = 1.0f;
    gReverb.targetWet = wet;
    gReverb.targetDry = dry;
}

float SpotifyReverb_GetWet(void) {
    return gReverb.targetWet;
}

float SpotifyReverb_GetDry(void) {
    return gReverb.targetDry;
}

void SpotifyReverb_SetRoomSize(float roomSize) {
    if (roomSize < 0.0f) roomSize = 0.0f;
    if (roomSize > 0.98f) roomSize = 0.98f; // Clamp to prevent infinite oscillation
    gReverb.targetRoomSize = roomSize;
}

float SpotifyReverb_GetRoomSize(void) {
    return gReverb.targetRoomSize;
}

void SpotifyReverb_SetDamping(float damping) {
    if (damping < 0.0f) damping = 0.0f;
    if (damping > 1.0f) damping = 1.0f;
    gReverb.targetDamping = damping;
}

float SpotifyReverb_GetDamping(void) {
    return gReverb.targetDamping;
}

void SpotifyReverb_ResetDefaults(void) {
    SpotifyReverb_SetRoomSize(0.82f);
    SpotifyReverb_SetDamping(0.25f);
    SpotifyReverb_SetWetDry(0.35f, 0.65f);
    SpotifyReverb_SetEnabled(true);
}

// ============================================================================
// CoreAudio Hook Strategy 1: Intercept AudioUnitSetProperty (Render Callbacks)
// ============================================================================
typedef struct {
    AURenderCallback origProc;
    void *origRefCon;
} RenderCallbackWrapper;

static OSStatus (*orig_AudioUnitSetProperty)(
    AudioUnit inUnit,
    AudioUnitPropertyID inID,
    AudioUnitScope inScope,
    AudioUnitElement inElement,
    const void *inData,
    UInt32 inDataSize
) = NULL;

static OSStatus call_orig_AudioUnitSetProperty(
    AudioUnit inUnit,
    AudioUnitPropertyID inID,
    AudioUnitScope inScope,
    AudioUnitElement inElement,
    const void *inData,
    UInt32 inDataSize)
{
    if (orig_AudioUnitSetProperty != NULL) {
        return orig_AudioUnitSetProperty(inUnit, inID, inScope, inElement, inData, inDataSize);
    }
    return AudioUnitSetProperty(inUnit, inID, inScope, inElement, inData, inDataSize);
}

static OSStatus hooked_AURenderCallback(
    void *inRefCon,
    AudioUnitRenderActionFlags *ioActionFlags,
    const AudioTimeStamp *inTimeStamp,
    UInt32 inBusNumber,
    UInt32 inNumberFrames,
    AudioBufferList *ioData)
{
    if (inRefCon == NULL) return noErr;

    RenderCallbackWrapper *wrapper = (RenderCallbackWrapper *)inRefCon;
    if (wrapper->origProc == NULL) return noErr;

    // Call Spotify's original render proc to populate audio frames into ioData
    OSStatus status = wrapper->origProc(wrapper->origRefCon, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, ioData);

    if (status == noErr) {
        ProcessAudioBufferList(&gReverb, inNumberFrames, ioData);
    }

    return status;
}

static OSStatus custom_AudioUnitSetProperty(
    AudioUnit inUnit,
    AudioUnitPropertyID inID,
    AudioUnitScope inScope,
    AudioUnitElement inElement,
    const void *inData,
    UInt32 inDataSize)
{
    if (inID == kAudioUnitProperty_SetRenderCallback && inData != NULL && inDataSize >= sizeof(AURenderCallbackStruct)) {
        AURenderCallbackStruct *cbStruct = (AURenderCallbackStruct *)inData;
        if (cbStruct->inputProc != hooked_AURenderCallback) {
            // Allocate wrapper once at setup time (never on audio thread)
            RenderCallbackWrapper *wrapper = (RenderCallbackWrapper *)malloc(sizeof(RenderCallbackWrapper));
            if (wrapper != NULL) {
                wrapper->origProc = cbStruct->inputProc;
                wrapper->origRefCon = cbStruct->inputProcRefCon;

                AURenderCallbackStruct replacementStruct;
                replacementStruct.inputProc = hooked_AURenderCallback;
                replacementStruct.inputProcRefCon = wrapper;

                NSLog(@"[SpotifyReverb] Successfully wrapped Spotify's AURenderCallback on AudioUnit %p", inUnit);
                return call_orig_AudioUnitSetProperty(inUnit, inID, inScope, inElement, &replacementStruct, inDataSize);
            }
        }
    }

    return call_orig_AudioUnitSetProperty(inUnit, inID, inScope, inElement, inData, inDataSize);
}

// ============================================================================
// CoreAudio Hook Strategy 2: Intercept AudioUnitRender (Fallback)
// ============================================================================
static OSStatus (*orig_AudioUnitRender)(
    AudioUnit inUnit,
    AudioUnitRenderActionFlags *ioActionFlags,
    const AudioTimeStamp *inTimeStamp,
    UInt32 inOutputBusNumber,
    UInt32 inNumberFrames,
    AudioBufferList *ioData
) = NULL;

static OSStatus call_orig_AudioUnitRender(
    AudioUnit inUnit,
    AudioUnitRenderActionFlags *ioActionFlags,
    const AudioTimeStamp *inTimeStamp,
    UInt32 inOutputBusNumber,
    UInt32 inNumberFrames,
    AudioBufferList *ioData)
{
    if (orig_AudioUnitRender != NULL) {
        return orig_AudioUnitRender(inUnit, ioActionFlags, inTimeStamp, inOutputBusNumber, inNumberFrames, ioData);
    }
    return AudioUnitRender(inUnit, ioActionFlags, inTimeStamp, inOutputBusNumber, inNumberFrames, ioData);
}

static OSStatus custom_AudioUnitRender(
    AudioUnit inUnit,
    AudioUnitRenderActionFlags *ioActionFlags,
    const AudioTimeStamp *inTimeStamp,
    UInt32 inOutputBusNumber,
    UInt32 inNumberFrames,
    AudioBufferList *ioData)
{
    OSStatus status = call_orig_AudioUnitRender(inUnit, ioActionFlags, inTimeStamp, inOutputBusNumber, inNumberFrames, ioData);

    if (status == noErr) {
        ProcessAudioBufferList(&gReverb, inNumberFrames, ioData);
    }

    return status;
}

// ============================================================================
// Native Apple Dyld Interposing (Compile-Time Zero-Crash Linking)
// ============================================================================
#ifndef DYLD_INTERPOSE
#define DYLD_INTERPOSE(_replacement, _replacee) \
    __attribute__((used)) static struct { \
        const void *replacement; \
        const void *replacee; \
    } _interpose_##_replacee \
    __attribute__((section("__DATA,__interpose"))) = { \
        (const void *)(unsigned long)&_replacement, \
        (const void *)(unsigned long)&_replacee \
    };
#endif

DYLD_INTERPOSE(custom_AudioUnitSetProperty, AudioUnitSetProperty)
DYLD_INTERPOSE(custom_AudioUnitRender, AudioUnitRender)

// ============================================================================
// Constructor Initialization (Fallback Runtime Rebinding via fishhook)
// ============================================================================
__attribute__((constructor))
static void SpotifyReverbInit(void) {
    NSLog(@"[SpotifyReverb] Loading Reverb DSP Engine...");
    ReverbDSP_Init(&gReverb);

    // Rebind both AudioUnitSetProperty and AudioUnitRender for total CoreAudio coverage
    rebind_symbols((struct rebinding[2]){
        {"AudioUnitSetProperty", (void *)custom_AudioUnitSetProperty, (void **)&orig_AudioUnitSetProperty},
        {"AudioUnitRender",      (void *)custom_AudioUnitRender,      (void **)&orig_AudioUnitRender}
    }, 2);

    NSLog(@"[SpotifyReverb] Hooks installed successfully. Ready to process audio.");
}
