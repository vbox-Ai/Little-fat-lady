export TARGET = iphone:clang:latest:17.0
export ARCHS = arm64 arm64e
export THEOS_PACKAGE_SCHEME = rootless

# 版本：<VERSION>-<提交数>，由 CI 从 git 推导；本地没有 git 时退化为 0.0.0-local
PACKAGE_VERSION ?= $(shell cat ../../VERSION 2>/dev/null || echo 0.1.0)-$(shell git rev-list --count HEAD 2>/dev/null || echo local)

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DSHPet
DSHPet_FILES = Tweak.xm DSHPetBoot.m
DSHPet_CFLAGS = -fobjc-arc -Wno-unused-function
DSHPet_FRAMEWORKS = Foundation UIKit
DSHPet_LIBRARIES = substrate
DSHPet_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries

include $(THEOS_MAKE_PATH)/tweak.mk

# 装完重载 SpringBoard（S1 只做日志，不加 UI，所以这一步是安全的）
after-install::
	install.exec "sbreload"
