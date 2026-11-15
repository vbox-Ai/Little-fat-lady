export TARGET = iphone:clang:latest:17.0
export ARCHS = arm64 arm64e
export THEOS_PACKAGE_SCHEME = rootless

# 版本号由 scripts/build-deb.sh 生成到 DSHPetVersion.h（VERSION-BUILD），这里不重复定义
export TWEAK_NAME = DSHPet
export DSHPet_FILES = Tweak.xm DSHPetBoot.m DSHPetOverlay.m
export DSHPet_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
export DSHPet_FRAMEWORKS = UIKit QuartzCore
export DSHPet_LIBRARIES = substrate

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "sbreload"
