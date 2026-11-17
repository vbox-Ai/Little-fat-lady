#import "DSHPetPrefs.h"
#import "DSHPetBoot.h"
#import <math.h>
#import <CoreFoundation/CoreFoundation.h>

// 私有方法必须先声明：写在 @implementation 后半段、又被前半段调用，
// 会触发 "class method not found" 警告，CI 是 -Werror，直接红。
@interface DSHPetPrefs ()
+ (nullable id)rawValueForKey:(NSString *)key;
@end

// plist-only 面板 bundle 的 CFBundleIdentifier（Root.plist 所在的那个 bundle）。
// Settings 默认把用户改动写进这个域，所以它排第一优先。
static NSString *const kPrefsDomainBundle = @"com.vboxai.littlefatlady.prefs";
// 兼容：早期脚本/dpkg 直接写过主域，读的时候一块儿兜住。
static NSString *const kPrefsDomainMain = @"com.vboxai.littlefatlady";
// roothide/rootless 下 SpringBoard 里 CFPreferences 偶尔拿不到（守护进程缓存旧域），
// 直接读盘兜底。
static NSString *const kPrefsFileDirect = @"/var/mobile/Library/Preferences/com.vboxai.littlefatlady.prefs.plist";

@implementation DSHPetPrefs

+ (nullable id)rawValueForKey:(NSString *)key {
    if (!key.length) return nil;
    for (NSString *domain in @[kPrefsDomainBundle, kPrefsDomainMain]) {
        CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                        (__bridge CFStringRef)domain);
        if (v) return CFBridgingRelease(v);
    }
    // 落盘兜底：只读一次文件，结果缓存到本次调用（不开定时器，不做热监听）
    static NSDictionary *fileCache;
    static NSTimeInterval fileStamp;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:kPrefsFileDirect error:NULL];
    NSTimeInterval mtime = attrs ? [attrs[NSFileModificationDate] timeIntervalSince1970] : 0;
    if (mtime > 0 && (!fileCache || mtime != fileStamp)) {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:kPrefsFileDirect];
        if ([d isKindOfClass:[NSDictionary class]]) { fileCache = d; fileStamp = mtime; }
    }
    id v = fileCache[key];
    return v;
}

+ (BOOL)hasKey:(NSString *)key {
    return [self rawValueForKey:key] != nil;
}

+ (BOOL)boolForKey:(NSString *)key fallback:(BOOL)fb {
    id v = [self rawValueForKey:key];
    if ([v respondsToSelector:@selector(boolValue)]) return [v boolValue];
    return fb;
}

+ (double)doubleForKey:(NSString *)key fallback:(double)fb {
    id v = [self rawValueForKey:key];
    if ([v respondsToSelector:@selector(doubleValue)]) return [v doubleValue];
    return fb;
}

+ (NSString *)stringForKey:(NSString *)key fallback:(NSString *)fb {
    id v = [self rawValueForKey:key];
    if ([v isKindOfClass:[NSString class]] && [v length]) return v;
    return fb;
}

+ (void)stampVersion:(NSString *)version {
    if (!version.length) return;
    CFStringRef domain = (__bridge CFStringRef)kPrefsDomainBundle;
    CFPropertyListRef old = CFPreferencesCopyAppValue(CFSTR("installedVersion"), domain);
    NSString *oldStr = old ? CFBridgingRelease(old) : nil;
    if ([oldStr isEqualToString:version]) return;
    CFPreferencesSetAppValue(CFSTR("installedVersion"),
                             (__bridge CFPropertyListRef)version,
                             domain);
    CFPreferencesAppSynchronize(domain);
    DSHPetLog(@"prefs", @"stamp-version", @"info", @{ @"ver": version });
}

+ (BOOL)applyToUIConfig:(NSMutableDictionary *)cfg {
    if (!cfg) return NO;
    BOOL changed = NO;

    // —— 显示 ——
    if ([self hasKey:@"petEnabled"]) {
        BOOL on = [self boolForKey:@"petEnabled" fallback:YES];
        if ([cfg[@"enabled"] boolValue] != on) { cfg[@"enabled"] = @(on); changed = YES; }
    }
    if ([self hasKey:@"bubbleEnabled"]) {
        BOOL on = [self boolForKey:@"bubbleEnabled" fallback:YES];
        if ([cfg[@"bubbleEnabled"] boolValue] != on) { cfg[@"bubbleEnabled"] = @(on); changed = YES; }
    }
    if ([self hasKey:@"bubbleStatusEnabled"]) {
        BOOL on = [self boolForKey:@"bubbleStatusEnabled" fallback:NO];
        if ([cfg[@"bubbleStatusEnabled"] boolValue] != on) { cfg[@"bubbleStatusEnabled"] = @(on); changed = YES; }
    }

    // —— 贴边间距档位 0=贴紧 1=标准 2=宽松（clampedCenter 消费）——
    if ([self hasKey:@"edgePreset"]) {
        NSInteger preset = (NSInteger)[self doubleForKey:@"edgePreset" fallback:1.0];
        if (preset < 0) preset = 0;
        if (preset > 2) preset = 2;
        if ([cfg[@"edgePreset"] integerValue] != preset) { cfg[@"edgePreset"] = @(preset); changed = YES; }
    }

    // —— 尺寸：面板滑块是「用户明确表态」，所以这里破例允许覆盖 sizeRatio，
    //    并把 sizeManual 置 YES —— 否则自动 1:1 逻辑会把滑块的值又改回去。
    if ([self hasKey:@"sizePct"]) {
        double ratio = [self doubleForKey:@"sizePct" fallback:0.30];
        if (ratio < 0.16) ratio = 0.16;
        if (ratio > 0.62) ratio = 0.62;
        if (fabs([cfg[@"sizeRatio"] doubleValue] - ratio) > 0.005) { cfg[@"sizeRatio"] = @(ratio); changed = YES; }
        if (![cfg[@"sizeManual"] boolValue]) { cfg[@"sizeManual"] = @YES; changed = YES; }
    }

    // —— 物理与触感 ——
    NSMutableDictionary *ph = [cfg[@"physics"] isKindOfClass:[NSDictionary class]]
        ? [cfg[@"physics"] mutableCopy] : [NSMutableDictionary dictionary];
    __block BOOL phChanged = NO;
    void (^setPh)(NSString *, id) = ^(NSString *k, id v) {
        if (v && ![ph[k] isEqual:v]) { ph[k] = v; phChanged = YES; }
    };
    if ([self hasKey:@"gravityEnabled"]) {
        setPh(@"gravityEnabled", @([self boolForKey:@"gravityEnabled" fallback:YES]));
    }
    if ([self hasKey:@"tiltGravityEnabled"]) {
        setPh(@"tiltGravity", @([self boolForKey:@"tiltGravityEnabled" fallback:YES]));
    }
    if ([self hasKey:@"hapticEnabled"]) {
        setPh(@"hapticEnabled", @([self boolForKey:@"hapticEnabled" fallback:YES]));
    }
    if ([self hasKey:@"hapticLevel"]) {
        NSString *lv = [self stringForKey:@"hapticLevel" fallback:@"normal"];
        if (![lv isEqualToString:@"light"] && ![lv isEqualToString:@"normal"] && ![lv isEqualToString:@"heavy"]) lv = @"normal";
        setPh(@"hapticLevel", lv);
    }
    if (phChanged) { cfg[@"physics"] = ph; changed = YES; }

    // —— 连接 ——
    if ([self hasKey:@"bridgeEnabled"]) {
        BOOL on = [self boolForKey:@"bridgeEnabled" fallback:YES];
        if ([cfg[@"bridgeEnabled"] boolValue] != on) { cfg[@"bridgeEnabled"] = @(on); changed = YES; }
    }
    if ([self hasKey:@"bridgeBase"]) {
        NSString *b = [self stringForKey:@"bridgeBase" fallback:@""];
        if (b.length && ![cfg[@"bridgeBase"] isEqual:b]) { cfg[@"bridgeBase"] = b; changed = YES; }
    }
    if ([self hasKey:@"bridgeInterval"]) {
        double iv = [self doubleForKey:@"bridgeInterval" fallback:2.5];
        if (iv < 1.0) iv = 1.0;
        if (iv > 10.0) iv = 10.0;
        if (fabs([cfg[@"bridgeInterval"] doubleValue] - iv) > 0.01) { cfg[@"bridgeInterval"] = @(iv); changed = YES; }
    }

    // —— S6c 多开 ——
    // 面板里 multiPetsMax 是 PSSlider/PSListItems 都可能写成字符串，统一按数值读并夹到 1–8。
    if ([self hasKey:@"multiPetsEnabled"]) {
        BOOL on = [self boolForKey:@"multiPetsEnabled" fallback:NO];
        if ([cfg[@"multiPetsEnabled"] boolValue] != on) { cfg[@"multiPetsEnabled"] = @(on); changed = YES; }
    }
    if ([self hasKey:@"multiPetsMax"]) {
        NSInteger n = (NSInteger)[self doubleForKey:@"multiPetsMax" fallback:3.0];
        if (n < 1) n = 1;
        if (n > 8) n = 8;
        if ([cfg[@"multiPetsMax"] integerValue] != n) { cfg[@"multiPetsMax"] = @(n); changed = YES; }
    }
    if ([self hasKey:@"perSession"]) {
        BOOL on = [self boolForKey:@"perSession" fallback:YES];
        if ([cfg[@"perSession"] boolValue] != on) { cfg[@"perSession"] = @(on); changed = YES; }
    }

    if (changed) DSHPetLog(@"prefs", @"merged", @"info", @{ @"cfg": @{ @"enabled": cfg[@"enabled"] ?: @"(none)",
                                                                       @"edge": cfg[@"edgePreset"] ?: @"(none)",
                                                                       @"bridge": cfg[@"bridgeEnabled"] ?: @"(none)" } });
    return changed;
}

@end
