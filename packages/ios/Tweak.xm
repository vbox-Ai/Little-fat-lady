#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "DSHPetBoot.h"
#import "DSHPetOverlay.h"

// S2：注入 SpringBoard → 找到它的 UIWindowScene → 挂一层透明浮层（DSHPetOverlay）。
// 铁律：
//   1. 任何异常都不许穿过 SpringBoard 的启动路径（全部包 @try）；
//   2. 拿不到 scene 不硬猜，记 error 日志后退出，等下一次前台通知重试；
//   3. 不 hook 别的类，不改 SpringBoard 自身行为，卸载即彻底消失。

// 逃生开关：桌面上出任何异常，只要存在这个文件，插件就完全不加载任何东西。
// 用 Filza 新建一个空文件即可，不需要终端。
static BOOL DSHPetKillSwitch(void) {
    return [[NSFileManager defaultManager] fileExistsAtPath:@"/var/mobile/Library/DSHPet/disabled"];
}

static UIWindowScene *DSHPetFindScene(id springboard) {
    // 首选 SpringBoard 私有 ivar（iOS 13+ 一直存在，用 KVC 避免硬编 ivar 偏移）
    @try {
        if ([springboard respondsToSelector:NSSelectorFromString(@"_sbWindowScene")]) {
            id s = [springboard valueForKey:@"_sbWindowScene"];
            if ([s isKindOfClass:[UIWindowScene class]]) return (UIWindowScene *)s;
        }
    } @catch (__unused NSException *e) {}

    // 兜底：按 activationState 挑一个前台 scene
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if (![s isKindOfClass:[UIWindowScene class]]) continue;
        if (s.activationState == UISceneActivationStateForegroundActive) return (UIWindowScene *)s;
    }
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]]) return (UIWindowScene *)s;
    }
    return nil;
}

static void DSHPetTryAttach(id springboard, NSInteger attempt) {
    UIWindowScene *scene = DSHPetFindScene(springboard);
    if (!scene) {
        DSHPetLog(@"render", @"scene-missing", @"warn", @{ @"attempt": @(attempt) });
        if (attempt < 5) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                DSHPetTryAttach(springboard, attempt + 1);
            });
        }
        return;
    }
    DSHPetLog(@"render", @"scene-found", @"info", @{
        @"attempt": @(attempt),
        @"scenes": @([[UIApplication sharedApplication].connectedScenes count]),
    });
    [DSHPetOverlay attachToScene:scene];
}

__attribute__((constructor))
static void dshpet_ctor(void) {
    @autoreleasepool {
        if (DSHPetKillSwitch()) {
            DSHPetBootLog(@"boot", @{ @"disabled": @YES });
            return;
        }
        DSHPetBootLog(@"boot", @{
            @"exe": [[NSBundle mainBundle] bundleIdentifier] ?: @"?",
            @"os": [[UIDevice currentDevice] systemVersion] ?: @"?",
            @"model": [[UIDevice currentDevice] model] ?: @"?",
            @"stage": @"s2",
        });
    }
}

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    if (DSHPetKillSwitch()) {
        DSHPetBootLog(@"springboard-ready", @{ @"disabled": @YES });
        return;
    }
    DSHPetBootLog(@"springboard-ready", @{ @"stage": @"s2" });
    @try {
        // 启动瞬间 scene 还没连上，给 1.2s 让 SpringBoard 布好桌面
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            @try {
                DSHPetTryAttach(self, 0);
            } @catch (NSException *e) {
                DSHPetLog(@"render", @"attach-exception", @"error", @{ @"reason": e.reason ?: @"?" });
            }
        });
    } @catch (NSException *e) {
        DSHPetLog(@"render", @"hook-exception", @"error", @{ @"reason": e.reason ?: @"?" });
    }
}

%end
