# Rootless (Dopamine / ElleKit) build. `make package` -> packages/*.deb
THEOS_PACKAGE_SCHEME = rootless
TARGET := iphone:clang:latest:15.0
ARCHS = arm64

# Bundle id from the IPA: com.tensquaregames.letsfish2
# Set the real executable name if you want `make install` to respring-less relaunch it.
INSTALL_TARGET_PROCESSES = LetsFish2

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LetsFish2Mod

LetsFish2Mod_FILES = $(wildcard src/*.xm) $(wildcard src/*.mm)
LetsFish2Mod_CFLAGS = -fobjc-arc -Isrc -Wno-unused-function
LetsFish2Mod_CCFLAGS = -std=c++17
LetsFish2Mod_FRAMEWORKS = UIKit Foundation

include $(THEOS)/makefiles/tweak.mk
