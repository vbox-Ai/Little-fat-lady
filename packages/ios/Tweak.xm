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
static NSString *const kDSHPetDisabledPath = @"/var/mobile/Library/DSHPet/disabled";
static NSString *const kDSHPetGuardPath = @"/var/mobile/Library/DSHPet/boot-guard.json";

static BOOL DSHPetKillSwitch(void) {
    return [[NSFileManager defaultManager] fileExistsAtPath:kDSHPetDisabledPath];
}

// ── 自保护看门狗（v0.1.0-138）─────────────────────────────────────────────
//
// 用户问得好：为什么每次都要他自己去 Filza 建 disabled？插件自己不能建吗？
// 能，而且应该由插件建 —— 因为"开不了 App"这种状态下，用户根本没有能力去建文件。
//
// 机制（三次启动判据，不需要用户参与）：
//   每次 SpringBoard 起来，attempts += 1 并落盘；
//   40 秒后如果这个进程还活着，说明这次启动是好的 → attempts 清零；
//   如果连续 3 次都在 40 秒内挂掉（SpringBoard 重启），第 3 次就直接写 disabled，
//   并把原因写到 disabled.txt 里。此后插件完全不加载，系统恢复可用。
//
// 为什么是 40 秒：够覆盖"启动即崩"和"进桌面后几十秒内崩"，又短于人真正开始用手机的时间。
// 为什么是 3 次：留一次给正常的重装/重越狱（那种也会重启 SpringBoard）。
static void DSHPetGuardWrite(NSInteger attempts) {
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:@"/var/mobile/Library/DSHPet"
   withIntermediateDirectories:YES attributes:nil error:NULL];
    NSDictionary *d = @{ @"attempts": @(attempts),
                         @"ts": @([[NSDate date] timeIntervalSince1970]),
                         @"ver": DSHPET_VERSION_STRING };
    [d writeToFile:kDSHPetGuardPath atomically:YES];
}

// 返回 YES = 本次不要加载（已自动停用）
static BOOL DSHPetGuardCheck(void) {
    @try {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:kDSHPetGuardPath];
        NSInteger attempts = 0;
        if ([d isKindOfClass:[NSDictionary class]]) {
            attempts = [d[@"attempts"] integerValue];
        }
        attempts += 1;

        if (attempts >= 3) {
            // 自己建逃生文件 + 留一张说明。用户删掉 disabled 就恢复。
            [@"" writeToFile:kDSHPetDisabledPath atomically:YES
                    encoding:NSUTF8StringEncoding error:NULL];
            NSString *why =
                [NSString stringWithFormat:
                    @"小肥娘已自动停用（自保护）。\n\n"
                    @"原因：连续 %ld 次在启动后 40 秒内退出（SpringBoard 重启）。\n"
                    @"版本：%@\n时间：%@\n\n"
                    @"恢复方法：删掉本目录下的 disabled 文件，然后注销/重启。\n"
                    @"日志：本目录下 logs/*.jsonl，最新的在 app.jsonl / boot.jsonl。\n",
                    (long)attempts, DSHPET_VERSION_STRING, [NSDate date]];
            [why writeToFile:@"/var/mobile/Library/DSHPet/disabled.txt"
                  atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            DSHPetBootLog(@"boot", @{ @"self-disabled": @YES, @"attempts": @(attempts) });
            return YES;
        }

        DSHPetGuardWrite(attempts);

        // 活过 40 秒 = 这次启动成功，计数清零。下一次崩溃重新从 0 开始数。
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(40.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            DSHPetGuardWrite(0);
            DSHPetBootLog(@"boot", @{ @"guard-cleared": @YES });
        });
        return NO;
    } @catch (__unused NSException *e) {
        return NO;   // 看门狗自己出错，绝不要因此拦住插件
    }
}

static BOOL DSHPetSelfDisabled = NO;   // 本次进程里看门狗判定"已停用"

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
        // 自保护：连续 3 次启动即挂 → 自己写 disabled，用户不用去 Filza
        if (DSHPetGuardCheck()) {
            DSHPetSelfDisabled = YES;
        }
    }
}

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    if (DSHPetSelfDisabled) {
        DSHPetBootLog(@"springboard-ready", @{ @"self-disabled": @YES });
        return;
    }
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
