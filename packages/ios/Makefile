export TARGET = iphone:clang:latest:17.0
export ARCHS = arm64 arm64e
export THEOS_PACKAGE_SCHEME = rootless

# 版本号由 scripts/build-deb.sh 生成 DSHPetVersion.h（VERSION-BUILD），这里不重复定义。
export TWEAK_NAME = DSHPet
# Linux 上用系统 clang 编时，SDK 的 AVFoundation 伞头有个 submodule 声明缺失，
# 会触发 -Werror,-Wincomplete-umbrella；这里只关这一条。
export DSHPet_CFLAGS = -Wno-incomplete-umbrella

export DSHPet_FILES = Tweak.xm DSHPetBoot.m DSHPetOverlay.m DSHPetAnimator.m DSHPetPlayer.m DSHPetAssets.m
export DSHPet_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
export DSHPet_FRAMEWORKS = UIKit QuartzCore AVFoundation
export DSHPet_LIBRARIES = substrate

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk

# 注意：这里不要挂 after-install 的 sbreload。
# 一是不该在打包/安装事务里重启 SpringBoard（会把 Sileo 的 dpkg 事务打断），
# 二是 deb 安装路径根本不会执行这段（它只服务 make install）。
