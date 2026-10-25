TARGET := iphone:clang:latest:14.0
ARCHS := arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SpotifyReverb

SpotifyReverb_FILES = SpotifyReverb.m SpotifyReverbUI.m fishhook.c
SpotifyReverb_CFLAGS = -fobjc-arc -O3
SpotifyReverb_FRAMEWORKS = AudioToolbox Foundation UIKit

include $(THEOS_MAKE_PATH)/tweak.mk
