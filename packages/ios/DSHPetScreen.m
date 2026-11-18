#import "DSHPetScreen.h"
#import "DSHPetBoot.h"
#import <dlfcn.h>

// 这些类型在 AXRuntime 里是 C 结构体指针，Theos SDK 没有头文件，
// 这里只按"指针"用，不碰内部布局（一旦碰布局就会随系统版本变）。
typedef const void *DSHAXElement;
typedef int32_t DSHAXError;

typedef DSHAXElement (*DSHAXCreateSystemWideFn)(void);
typedef DSHAXElement (*DSHAXCreateAppFn)(int32_t pid);
typedef DSHAXError (*DSHAXCopyAttrFn)(DSHAXElement, CFStringRef, CFTypeRef *);

static DSHAXCreateSystemWideFn gCreateSystemWide = NULL;
static DSHAXCreateAppFn gCreateApp = NULL;
static DSHAXCopyAttrFn gCopyAttr = NULL;
static BOOL gLoaded = NO;
static BOOL gLoadTried = NO;

// 节点/字符预算：无障碍树在复杂界面上是爆炸级的（一个列表几百个元素），
// 不设上限会直接把 SpringBoard 主线程拖住 —— 这是越狱插件被 watchdog 杀的经典原因。
static const NSInteger kMaxNodes = 240;
static const NSInteger kMaxDepth = 7;

@implementation DSHPetScreen

+ (void)loadSymbolsOnce {
    if (gLoadTried) {
        return;
    }
    gLoadTried = YES;

    const char *paths[] = {
        "/System/Library/PrivateFrameworks/AXRuntime.framework/AXRuntime",
        "/System/Library/PrivateFrameworks/AccessibilityUtilities.framework/AccessibilityUtilities",
        NULL
    };
    void *handle = NULL;
    for (int i = 0; paths[i] != NULL && handle == NULL; i++) {
        handle = dlopen(paths[i], RTLD_LAZY | RTLD_LOCAL);
    }
    if (handle == NULL) {
        DSHPetLog(@"screen", @"ax-dlopen-fail", @"warn", nil);
        return;
    }
    gCreateSystemWide = (DSHAXCreateSystemWideFn)dlsym(handle, "AXUIElementCreateSystemWide");
    gCreateApp = (DSHAXCreateAppFn)dlsym(handle, "AXUIElementCreateApplication");
    gCopyAttr = (DSHAXCopyAttrFn)dlsym(handle, "AXUIElementCopyAttributeValue");
    gLoaded = (gCreateSystemWide != NULL && gCopyAttr != NULL);
    DSHPetLog(@"screen", @"ax-symbols", gLoaded ? @"info" : @"warn",
              @{ @"sys": @(gCreateSystemWide != NULL),
                 @"app": @(gCreateApp != NULL),
                 @"copy": @(gCopyAttr != NULL) });
}

+ (BOOL)available {
    [self loadSymbolsOnce];
    if (!gLoaded) {
        return NO;
    }
    DSHAXElement sys = gCreateSystemWide();
    if (sys == NULL) {
        return NO;
    }
    CFRelease(sys);
    return YES;
}

+ (nullable NSString *)stringAttr:(CFStringRef)attr of:(DSHAXElement)el {
    if (el == NULL || gCopyAttr == NULL) {
        return nil;
    }
    CFTypeRef val = NULL;
    DSHAXError err = gCopyAttr(el, attr, &val);
    if (err != 0 || val == NULL) {
        return nil;
    }
    NSString *out = nil;
    if (CFGetTypeID(val) == CFStringGetTypeID()) {
        out = [(__bridge NSString *)val copy];
    } else if (CFGetTypeID(val) == CFNumberGetTypeID()) {
        out = [(__bridge NSNumber *)val stringValue];
    }
    CFRelease(val);
    return out;
}

// 取子节点。返回的是 +1 引用，调用方负责 CFRelease。
+ (NSArray *)childrenOf:(DSHAXElement)el {
    if (el == NULL || gCopyAttr == NULL) {
        return @[];
    }
    CFTypeRef val = NULL;
    if (gCopyAttr(el, CFSTR("AXChildren"), &val) != 0 || val == NULL) {
        return @[];
    }
    NSArray *arr = nil;
    if (CFGetTypeID(val) == CFArrayGetTypeID()) {
        arr = [(__bridge NSArray *)val copy];
    }
    CFRelease(val);
    return arr ?: @[];
}

+ (void)collectFrom:(DSHAXElement)el
              depth:(NSInteger)depth
               into:(NSMutableArray<NSString *> *)lines
               seen:(NSMutableSet<NSString *> *)seen
              count:(NSInteger *)count {
    if (el == NULL || depth > kMaxDepth || *count >= kMaxNodes) {
        return;
    }
    *count += 1;

    // 只要"人能看见的字"：标题、值、描述、无障碍标签。
    // 不取 AXFrame / AXRole 这类结构信息 —— 对说话没用，还占预算。
    NSArray *attrs = @[@"AXLabel", @"AXTitle", @"AXValue", @"AXDescription"];
    for (NSString *an in attrs) {
        NSString *s = [self stringAttr:(__bridge CFStringRef)an of:el];
        if (s.length == 0) {
            continue;
        }
        s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        // 纯数字/单字符多半是角标、分隔符，丢掉
        if (s.length < 2) {
            continue;
        }
        if (![seen containsObject:s]) {
            [seen addObject:s];
            [lines addObject:s];
        }
        if (lines.count >= kMaxNodes) {
            return;
        }
    }

    for (id child in [self childrenOf:el]) {
        [self collectFrom:(__bridge DSHAXElement)child
                    depth:depth + 1
                     into:lines
                     seen:seen
                    count:count];
        if (*count >= kMaxNodes) {
            return;
        }
    }
}

+ (nullable NSString *)currentScreenTextWithLimit:(NSInteger)maxChars {
    [self loadSymbolsOnce];
    if (!gLoaded) {
        return nil;
    }
    @try {
        DSHAXElement sys = gCreateSystemWide();
        if (sys == NULL) {
            return nil;
        }

        // 优先"焦点元素"，它通常就是用户正在看的那一块；
        // 拿不到再退回"焦点窗口"（整屏），最后退回"焦点 App"。
        DSHAXElement start = NULL;
        CFTypeRef focused = NULL;
        if (gCopyAttr(sys, CFSTR("AXFocusedUIElement"), &focused) == 0 && focused != NULL) {
            start = (DSHAXElement)focused;
        }
        if (start == NULL) {
            CFTypeRef win = NULL;
            if (gCopyAttr(sys, CFSTR("AXFocusedWindow"), &win) == 0 && win != NULL) {
                start = (DSHAXElement)win;
            }
        }
        if (start == NULL) {
            CFTypeRef app = NULL;
            if (gCopyAttr(sys, CFSTR("AXFocusedApplication"), &app) == 0 && app != NULL) {
                start = (DSHAXElement)app;
            }
        }
        if (start == NULL) {
            CFRelease(sys);
            DSHPetLog(@"screen", @"no-focus", @"warn", nil);
            return nil;
        }

        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        NSMutableSet<NSString *> *seen = [NSMutableSet set];
        NSInteger count = 0;
        [self collectFrom:start depth:0 into:lines seen:seen count:&count];

        if (focused != NULL) {
            CFRelease(focused);
        }
        CFRelease(sys);

        if (lines.count == 0) {
            DSHPetLog(@"screen", @"empty", @"warn", @{ @"nodes": @(count) });
            return nil;
        }

        NSMutableString *out = [NSMutableString string];
        for (NSString *s in lines) {
            if (out.length + s.length + 1 > (NSUInteger)MAX(maxChars, 200)) {
                break;
            }
            if (out.length > 0) {
                [out appendString:@" / "];
            }
            [out appendString:s];
        }
        DSHPetLog(@"screen", @"read", @"info",
                  @{ @"nodes": @(count), @"lines": @(lines.count), @"chars": @(out.length) });
        return out.length > 0 ? out : nil;
    } @catch (NSException *e) {
        // 无障碍 API 在越狱环境里偶尔抛 ObjC 异常，不能让 SpringBoard 跟着死
        DSHPetLog(@"screen", @"exception", @"warn", @{ @"name": e.name ?: @"?" });
        return nil;
    }
}

@end
