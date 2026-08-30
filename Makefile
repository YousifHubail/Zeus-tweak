export ARCHS = arm64
export SDKVERSION = 14.5
INSTALL_TARGET_PROCESSES = Instagram

GO_EASY_ON_ME = 1
FINALPACKAGE = 1

# Non-obfuscating toolchain (no Hikari)
export PREFIX = $(THEOS)/toolchain/Xcode14.xctoolchain/usr/bin/

ifeq ($(filter 1,$(SIDELOAD) $(ROOTLESS)), 1 1)
$(error "SIDELOAD and ROOTLESS cannot both be set")
endif

ifeq ($(ROOTLESS), 1)
	THEOS_PACKAGE_SCHEME = rootless
	Theta_CFLAGS += -DROOTLESS=1
endif

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/aggregate.mk

TWEAK_NAME = Theta

Theta_FILES = TweakCOMPILE.xm fishhook.c \
	$(wildcard Source/UI/*.m) \
	$(wildcard Source/Media/*.m) \
	$(wildcard Source/ProfileAnalyzer/*.m)

Theta_FRAMEWORKS = UIKit Foundation CoreGraphics Photos CoreServices SystemConfiguration SafariServices Security QuartzCore AuthenticationServices WebKit UserNotifications AVFoundation
Theta_LDFLAGS = -lsqlite3
Theta_PRIVATE_FRAMEWORKS = Preferences

ifneq ($(SIDELOAD),1)
Theta_LIBRARIES += substrate
else
	Theta_CFLAGS += -I$(THEOS)/vendor/lib/CydiaSubstrate.framework/Headers
	Theta_LDFLAGS += -F$(THEOS)/vendor/lib -weak_framework CydiaSubstrate
	Theta_CFLAGS += -DSIDELOAD=1
endif

# The bundled/patched iPhoneOS14.5 SDK ships no usr/include/c++/v1 at all — old
# Theos SDKs relied on the paired Xcode *toolchain* for libc++ headers, but Xcode
# 15+ moved those into the SDK instead. On a modern host toolchain that leaves no
# <cmath> etc. anywhere in the search path (fails inside the ObjC++ 'simd' module
# build). Fall back to the current Xcode's own iphoneos SDK C++ headers for those;
# they're version-agnostic pure-C++ standard library headers, so this is safe
# regardless of which Xcode/SDK is actually installed on the build machine.
HOST_IOS_CXX_HEADERS := $(shell xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)/usr/include/c++/v1

Theta_CFLAGS += -fobjc-arc \
	-Wno-unused-variable -Wno-unused-value -Wno-deprecated-declarations \
	-Wno-nullability-completeness -Wno-unused-function -Wno-incompatible-pointer-types \
	-I$(THEOS_PROJECT_DIR) \
	-DTHETA_VERSION='"v$(THEOS_PACKAGE_BASE_VERSION)"' \
	-isystem $(HOST_IOS_CXX_HEADERS)

# FFmpeg headers (runtime loaded via dlopen)
Theta_CFLAGS += -I"$(THEOS_PROJECT_DIR)/layout/Library/Application Support/ffmpeg.framework"

ifeq ($(SIDELOAD), 1)
	Theta_CFLAGS += -DTHETA_PROJECT='"theta Jailed v$(THEOS_PACKAGE_BASE_VERSION)"'
	CODESIGN_IPA = 0
	TARGET_CODESIGN =
	LDID_FLAGS =
else
	Theta_CFLAGS += -DTHETA_PROJECT='"theta v$(THEOS_PACKAGE_BASE_VERSION)"'
endif

include $(THEOS_MAKE_PATH)/tweak.mk

before-all::
	@rm -f TweakCOMPILE.xm
	@python3 scripts/assemble.py
	@mkdir -p "ThetaResources.bundle"
	@mkdir -p "layout/Library/Application Support/ThetaResources.bundle"

after-all::
	@rm -f TweakCOMPILE.xm

after-install::
	install.exec "uiopen --bundleid com.burbn.instagram"
