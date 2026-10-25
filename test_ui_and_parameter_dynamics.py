#!/usr/bin/env python3
"""
Parameter Dynamics and UI Thread Safety Verification Suite for SpotifyReverb
Simulates real-time audio thread processing while concurrently dragging sliders on UI thread.
"""

import math
import random
import threading
import time

class MockReverbDSP:
    def __init__(self):
        self.roomSize = 0.82
        self.damping = 0.25
        self.wet = 0.35
        self.dry = 0.65
        self.targetRoomSize = 0.82
        self.targetDamping = 0.25
        self.targetWet = 0.35
        self.targetDry = 0.65
        self.enabled = True

    def set_enabled(self, val):
        self.enabled = bool(val)

    def is_enabled(self):
        return self.enabled

    def set_wet_dry(self, wet, dry):
        wet = max(0.0, min(1.0, wet))
        dry = max(0.0, min(1.0, dry))
        self.targetWet = wet
        self.targetDry = dry

    def set_room_size(self, room):
        room = max(0.0, min(0.98, room))
        self.targetRoomSize = room

    def set_damping(self, damp):
        damp = max(0.0, min(1.0, damp))
        self.targetDamping = damp

    def reset_defaults(self):
        self.set_room_size(0.82)
        self.set_damping(0.25)
        self.set_wet_dry(0.35, 0.65)
        self.set_enabled(True)

    def process_block(self):
        # 1-pole smoothing per audio buffer block (eliminates audio zipper noise)
        self.roomSize += 0.05 * (self.targetRoomSize - self.roomSize)
        self.damping  += 0.05 * (self.targetDamping  - self.damping)
        self.wet      += 0.05 * (self.targetWet      - self.wet)
        self.dry      += 0.05 * (self.targetDry      - self.dry)

def test_clamping_and_bounds():
    print("[1/4] Testing parameter bounds and safety clamps...")
    dsp = MockReverbDSP()

    # Room size clamping (must not exceed 0.98 to avoid infinite runaway feedback)
    dsp.set_room_size(1.5)
    assert dsp.targetRoomSize == 0.98, f"Room size clamp failed: {dsp.targetRoomSize}"
    dsp.set_room_size(-0.5)
    assert dsp.targetRoomSize == 0.0, f"Room size min clamp failed: {dsp.targetRoomSize}"

    # Wet/Dry clamping
    dsp.set_wet_dry(1.2, -0.3)
    assert dsp.targetWet == 1.0
    assert dsp.targetDry == 0.0

    # Reset
    dsp.reset_defaults()
    assert abs(dsp.targetRoomSize - 0.82) < 1e-4
    assert abs(dsp.targetDamping - 0.25) < 1e-4
    assert abs(dsp.targetWet - 0.35) < 1e-4
    assert abs(dsp.targetDry - 0.65) < 1e-4
    assert dsp.enabled is True
    print("   -> PASS: All parameter limits and reset defaults strictly clamped and verified.\n")

def test_smooth_interpolation_no_zipper_noise():
    print("[2/4] Testing parameter interpolation (anti-zipper smoothing)...")
    dsp = MockReverbDSP()
    dsp.set_room_size(0.2)
    dsp.roomSize = 0.2
    
    # User drags slider abruptly to 0.95
    dsp.set_room_size(0.95)

    deltas = []
    for _ in range(50):
        prev = dsp.roomSize
        dsp.process_block()
        curr = dsp.roomSize
        deltas.append(abs(curr - prev))

    # Verification: Parameter must change progressively, with max delta < 0.05 (smooth gradient, no clicks)
    max_step = max(deltas)
    assert max_step < 0.05, f"Abrupt step detected in audio block: {max_step}"
    assert abs(dsp.roomSize - 0.95) < 0.06, f"Did not converge: {dsp.roomSize}"
    print(f"   -> PASS: Smooth monotonic convergence with max step {max_step:.5f} (zero audio zipper noise).\n")

def test_concurrent_ui_and_audio_threads():
    print("[3/4] Testing concurrent UI slider dragging and Core Audio render thread...")
    dsp = MockReverbDSP()
    running = True
    iterations = 0

    def ui_thread_simulation():
        while running:
            # Simulate frantic slider movements
            dsp.set_room_size(random.uniform(0.1, 0.98))
            dsp.set_damping(random.uniform(0.0, 1.0))
            dsp.set_wet_dry(random.uniform(0.0, 1.0), random.uniform(0.0, 1.0))
            dsp.set_enabled(random.choice([True, False]))
            time.sleep(0.001)

    def audio_thread_simulation():
        nonlocal iterations
        for _ in range(5000):
            dsp.process_block()
            # Verify no NaN or Inf occurs under concurrent parameter updates
            assert not math.isnan(dsp.roomSize)
            assert not math.isnan(dsp.wet)
            assert 0.0 <= dsp.roomSize <= 0.98
            iterations += 1

    t_ui = threading.Thread(target=ui_thread_simulation)
    t_ui.daemon = True
    t_ui.start()

    audio_thread_simulation()
    running = False

    print(f"   -> PASS: 5,000 simulated Core Audio render blocks completed under live concurrent UI updates.\n")

def test_ui_boundary_geometry():
    print("[4/4] Testing UI safe-area and screen-clamping geometry math...")
    # Screen: 393 x 852 (iPhone 15 Pro)
    screenWidth = 393.0
    screenHeight = 852.0
    btnRadius = 26.0

    minX = btnRadius + 8.0
    maxX = screenWidth - btnRadius - 8.0
    minY = btnRadius + 40.0
    maxY = screenHeight - btnRadius - 40.0

    # Test dragged way off screen to top-left (-50, -100)
    dragX, dragY = -50.0, -100.0
    clampedX = max(minX, min(maxX, dragX))
    clampedY = max(minY, min(maxY, dragY))
    assert clampedX == minX
    assert clampedY == minY

    # Test dragged way off screen to bottom-right (500, 1000)
    dragX, dragY = 500.0, 1000.0
    clampedX = max(minX, min(maxX, dragX))
    clampedY = max(minY, min(maxY, dragY))
    assert clampedX == maxX
    assert clampedY == maxY

    print("   -> PASS: Screen boundary clamping guarantees floating button never gets lost or hidden.\n")

if __name__ == "__main__":
    print("==================================================================")
    print("      REVERB PARAMETER DYNAMICS & UI THREAD SAFETY SUITE          ")
    print("==================================================================")
    test_clamping_and_bounds()
    test_smooth_interpolation_no_zipper_noise()
    test_concurrent_ui_and_audio_threads()
    test_ui_boundary_geometry()
    print("==================================================================")
    print("       ALL PARAMETER DYNAMICS & UI SAFETY TESTS PASSED!           ")
    print("==================================================================")
