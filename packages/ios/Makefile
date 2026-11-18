export TARGET = iphone:clang:latest:15.0
export ARCHS = arm64 arm64e
export THEOS_PACKAGE_SCHEME = rootless

# 最低系统 15.0 而不是 17.0：Dopamine 主力机型都在 iOS 15–16，
# 之前写 17.0 会让那些设备上的 dylib 处于「加载了但不受支持的」灰区。
# 我们用到的最新 API 是 CADisplayLink.preferredFramesPerSecond（iOS 15），15.0 够。

# 版本号由 scripts/build-deb.sh 生成 DSHPetVersion.h（VERSION-BUILD），这里不重复定义。
export TWEAK_NAME = DSHPet
export DSHPet_FILES = Tweak.xm DSHPetBoot.m DSHPetOverlay.m DSHPetAnimator.m DSHPetPlayer.m DSHPetAssets.m DSHPetBubble.m DSHPetBridge.m DSHPetHaptics.m DSHPetPrefs.m DSHPetPet.m DSHPetCrew.m DSHPetTodoPanel.m DSHPetMenuPanel.m DSHPetState.m DSHPetLines.m DSHPetVoice.m DSHPetSFX.m DSHPetScheduler.m
export DSHPet_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-incomplete-umbrella
export DSHPet_FRAMEWORKS = UIKit QuartzCore AVFoundation
export DSHPet_FRAMEWORKS += CoreMotion
export DSHPet_LIBRARIES = substrate

# 设置面板：代码 bundle（不是纯 plist 面板）。
# 纯 plist 面板在 iOS 17 + PreferenceLoader 2.2.8 上要么整行不显示、要么点进去报载入失败，
# 只有自带可执行文件 + NSPrincipalClass 的代码 bundle 两条都能过。
export BUNDLE_NAME = DSHPetPrefs
export DSHPetPrefs_INSTALL_PATH = /Library/PreferenceBundles
export DSHPetPrefs_FILES = DSHPetPrefsRootListController.m
export DSHPetPrefs_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
export DSHPetPrefs_FRAMEWORKS = UIKit Foundation
# Preferences 是私有框架，Theos 的 iOS SDK 里没有它的 .tbd（`ld: framework 'Preferences' not found`），
# 所以不能写 _PRIVATE_FRAMEWORKS。改成动态查找：PSListController 由宿主 Preferences.app
# 进程自己提供，运行期符号一定在，链接期只需要放行未定义符号。
export DSHPetPrefs_LDFLAGS = -undefined dynamic_lookup

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk
include $(THEOS_MAKE_PATH)/aggregate.mk

# 注意：这里不要挂 after-install 的 sbreload。
# 一是不该在打包/安装事务里重启 SpringBoard（会把 Sileo 的 dpkg 事务打断），
# 二是 deb 安装路径根本不会执行这段（它只服务 make install）。
