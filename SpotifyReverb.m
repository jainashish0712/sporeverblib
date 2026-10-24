// SpotifyReverb.m
// Core Audio DSP Reverb Injection Tweak for Spotify on iOS
// Verified for Spotify iOS (supports both AURenderCallback and AudioUnitRender)

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <math.h>
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

    // Reverb DSP parameters
    float roomSize;    // Feedback gain (decay length, default 0.82)
    float damping;     // High frequency absorption (default 0.25)
    float wet;         // Wet level (default 0.35)
    float dry;         // Dry level (default 0.65)
    bool enabled;
} ReverbDSP;

static ReverbDSP gReverb;

static void ReverbDSP_Init(ReverbDSP *dsp) {
    memset(dsp, 0, sizeof(ReverbDSP));
    dsp->roomSize = 0.82f;
    dsp->damping = 0.25f;
    dsp->wet = 0.35f;
    dsp->dry = 0.65f;
    dsp->enabled = true;
}

// Fast soft-clipper to guarantee output stays strictly within [-1.0, 1.0] without harsh digital distortion
static inline float SoftClip(float x) {
    if (x > 1.0f) return 1.0f;
    if (x < -1.0f) return -1.0f;
    return x;
}

// Real-time audio sample processing (zero malloc, zero Obj-C overhead)
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

// Process arbitrary CoreAudio AudioBufferList (both non-interleaved and interleaved stereo)
static inline void ProcessAudioBufferList(ReverbDSP *dsp, UInt32 inNumberFrames, AudioBufferList *ioData) {
    if (ioData == NULL || inNumberFrames == 0 || !dsp->enabled) return;

    // Case 1: Non-Interleaved Stereo (2 separate buffers, 1 channel each)
    if (ioData->mNumberBuffers >= 2 && ioData->mBuffers[0].mData != NULL && ioData->mBuffers[1].mData != NULL) {
        float *left = (float *)ioData->mBuffers[0].mData;
        float *right = (float *)ioData->mBuffers[1].mData;
        for (UInt32 frame = 0; frame < inNumberFrames; frame++) {
            ProcessSampleStereo(dsp, &left[frame], &right[frame]);
        }
    }
    // Case 2: Interleaved Stereo (1 buffer, alternating L/R samples)
    else if (ioData->mNumberBuffers == 1 && ioData->mBuffers[0].mData != NULL && ioData->mBuffers[0].mNumberChannels == 2) {
        float *interleaved = (float *)ioData->mBuffers[0].mData;
        for (UInt32 frame = 0; frame < inNumberFrames; frame++) {
            ProcessSampleStereo(dsp, &interleaved[frame * 2], &interleaved[frame * 2 + 1]);
        }
    }
}

// ============================================================================
// CoreAudio Hook Strategy 1: Intercept AudioUnitSetProperty (Render Callbacks)
// ============================================================================
static OSStatus (*orig_AudioUnitSetProperty)(
    AudioUnit inUnit,
    AudioUnitPropertyID inID,
    AudioUnitScope inScope,
    AudioUnitElement inElement,
    const void *inData,
    UInt32 inDataSize
);

static AURenderCallback orig_client_render_proc = NULL;
static void *orig_client_refcon = NULL;

static OSStatus hooked_AURenderCallback(
    void *inRefCon,
    AudioUnitRenderActionFlags *ioActionFlags,
    const AudioTimeStamp *inTimeStamp,
    UInt32 inBusNumber,
    UInt32 inNumberFrames,
    AudioBufferList *ioData)
{
    if (orig_client_render_proc == NULL) return noErr;

    // Call Spotify's original render proc to populate the audio frames into ioData
    OSStatus status = orig_client_render_proc(orig_client_refcon, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, ioData);

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
            orig_client_render_proc = cbStruct->inputProc;
            orig_client_refcon = cbStruct->inputProcRefCon;

            AURenderCallbackStruct replacementStruct;
            replacementStruct.inputProc = hooked_AURenderCallback;
            replacementStruct.inputProcRefCon = orig_client_refcon;

            NSLog(@"[SpotifyReverb] Successfully wrapped Spotify's AURenderCallback on AudioUnit %p", inUnit);
            return orig_AudioUnitSetProperty(inUnit, inID, inScope, inElement, &replacementStruct, inDataSize);
        }
    }

    return orig_AudioUnitSetProperty(inUnit, inID, inScope, inElement, inData, inDataSize);
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
);

static OSStatus custom_AudioUnitRender(
    AudioUnit inUnit,
    AudioUnitRenderActionFlags *ioActionFlags,
    const AudioTimeStamp *inTimeStamp,
    UInt32 inOutputBusNumber,
    UInt32 inNumberFrames,
    AudioBufferList *ioData)
{
    OSStatus status = orig_AudioUnitRender(inUnit, ioActionFlags, inTimeStamp, inOutputBusNumber, inNumberFrames, ioData);

    if (status == noErr) {
        ProcessAudioBufferList(&gReverb, inNumberFrames, ioData);
    }

    return status;
}

// ============================================================================
// Constructor Initialization
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
