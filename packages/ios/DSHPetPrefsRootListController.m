// 小肥娘 · 设置面板控制器
//
// 为什么要有这个文件（血的教训）：
//   纯 plist 面板（bundle 里只有 Info/Root.plist，没有可执行文件）在 iOS 17 + PreferenceLoader 2.2.8 上两种都错：
//     · entry 带 detail/isController  → 能显示，点进去报「未能载入软件包…未能找到其可执行文件的位置」
//     · entry 去掉 detail/isController → 设置里连那一行都不出现
//   对照同生态能正常工作的面板（com.axs.appiconbundles）：走的是代码 bundle ——
//   bundle 里有可执行文件、Info.plist 里有 CFBundleExecutable + NSPrincipalClass，
//   entry 里 detail 指到 bundle 内的 PSListController 子类。所以这里就按那条路走。
//
// 这个文件只做两件事：让 PSListController 正常实例化（Root.plist 仍负责界面）、
// 以及把读写钉死在 com.vboxai.littlefatlady.prefs 这个域上（dylib 侧读的就是它）。

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Preferences 是私有框架，CI 的 SDK 里没有 PSListController.h。
// 只声明我们用到的那几个面，避免依赖私有头文件。
@interface PSSpecifier : NSObject
- (NSString *)identifier;
@property(nonatomic, readonly) NSMutableDictionary *properties;
@end

@interface PSListController : UIViewController
- (NSArray *)specifiers;
- (void)reloadSpecifiers;
- (id)readPreferenceValue:(PSSpecifier *)specifier;
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier;
@end

static NSString *const kDSHPetPrefsDomain = @"com.vboxai.littlefatlady.prefs";

@interface DSHPetPrefsRootListController : PSListController
@end

@implementation DSHPetPrefsRootListController

// 返回 nil 就会落到 Root.plist 里每个 specifier 的 default 上。
// 这样「第一次装、什么键都没写过」时界面显示的是代码里的真默认值，而不是空开关。
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier identifier];
    if (key.length == 0) return nil;
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                    (__bridge CFStringRef)kDSHPetPrefsDomain);
    if (!v) return nil;
    return CFBridgingRelease(v);
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier identifier];
    if (key.length == 0) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             (__bridge CFStringRef)kDSHPetPrefsDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kDSHPetPrefsDomain);
}

@end
