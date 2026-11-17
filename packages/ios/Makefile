export TARGET = iphone:clang:latest:17.0
export ARCHS = arm64 arm64e
export THEOS_PACKAGE_SCHEME = rootless

# 版本号由 scripts/build-deb.sh 生成 DSHPetVersion.h（VERSION-BUILD），这里不重复定义。
export TWEAK_NAME = DSHPet
export DSHPet_FILES = Tweak.xm DSHPetBoot.m DSHPetOverlay.m DSHPetAnimator.m DSHPetPlayer.m DSHPetAssets.m DSHPetBubble.m DSHPetBridge.m DSHPetHaptics.m DSHPetPrefs.m DSHPetPet.m DSHPetCrew.m
export DSHPet_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-incomplete-umbrella
export DSHPet_FRAMEWORKS = UIKit QuartzCore AVFoundation
export DSHPet_FRAMEWORKS += CoreMotion
export DSHPet_LIBRARIES = substrate

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk

# 注意：这里不要挂 after-install 的 sbreload。
# 一是不该在打包/安装事务里重启 SpringBoard（会把 Sileo 的 dpkg 事务打断），
# 二是 deb 安装路径根本不会执行这段（它只服务 make install）。
