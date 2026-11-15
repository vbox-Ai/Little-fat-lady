#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "DSHPetBoot.h"
#import "DSHPetOverlay.h"

// S2：透明浮层骨架 + 一个可拖动的方块。
// 本阶段只证明四件事，不做宠物：
//   1. 能在 SpringBoard 的 windowScene 上再挂一个**独立 UIWindow**（不抢 App 的窗口）；
//   2. 这个 window 能浮在桌面图标与 App 之上（层级 = statusBar + 100，低于系统弹窗）；
//   3. 窗口背景透明、只有方块区域吃触摸，其余点击穿透给下面；
//   4. 方块能拖、能点、位置能落盘，旋转/分屏/锁屏后能回到正确坐标。

static NSString *const kUIConfigPath = @"/var/mobile/Library/DSHPet/config/ui.json";

#pragma mark - 配置读写

static NSMutableDictionary *DSHPetLoadUIConfig(void) {
    NSDictionary *raw = [NSDictionary dictionaryWithContentsOfFile:kUIConfigPath];
    NSMutableDictionary *cfg = raw ? [raw mutableCopy] : [NSMutableDictionary dictionary];
    if (!cfg[@"enabled"]) cfg[@"enabled"] = @YES;
    if (!cfg[@"size"]) cfg[@"size"] = @(100.0);
    if (!cfg[@"centerX"]) cfg[@"centerX"] = @(0.80);
    if (!cfg[@"centerY"]) cfg[@"centerY"] = @(0.22);
    if (!cfg[@"taps"]) cfg[@"taps"] = @(0);
    if (!cfg[@"windowLevel"]) cfg[@"windowLevel"] = @(UIWindowLevelStatusBar + 100.0);
    return cfg;
}

static void DSHPetSaveUIConfig(NSDictionary *cfg) {
    NSString *dir = [kUIConfigPath stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    [cfg writeToFile:kUIConfigPath atomically:YES];
}

#pragma mark - 窗口（只放行方块区域的触摸）

@interface DSHPetWindow : UIWindow
@property (nonatomic, weak) UIView *touchTarget;
@property (nonatomic, copy) void (^onLayout)(void);
@end

@implementation DSHPetWindow

- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.onLayout) self.onLayout();   // 旋转/分屏/安全区变化都会走到这里，比监听通知可靠
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    if (v == self || v == self.rootViewController.view) return nil;   // 空白处穿透
    if (self.touchTarget && ![self.touchTarget pointInside:[self.touchTarget convertPoint:point fromView:self] withEvent:event]) {
        return nil;
    }
    return v;
}

@end

#pragma mark - 浮层

@interface DSHPetOverlay ()
- (CGRect)sceneBoundsIfValid;
- (void)relayoutAndSettle:(BOOL)settle;
- (CGPoint)clampedCenter:(CGPoint)c inSize:(CGSize)b;
- (void)onOrientationChange:(NSNotification *)n;
@end

@implementation DSHPetOverlay {
    UIWindowScene *_scene;
    DSHPetWindow *_window;
    UIView *_box;
    NSMutableDictionary *_cfg;
    CGPoint _panStartCenter;
}

+ (instancetype)shared {
    static DSHPetOverlay *inst = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [[DSHPetOverlay alloc] init]; });
    return inst;
}

+ (BOOL)attachToScene:(UIWindowScene *)scene {
    if (!scene) {
        DSHPetLog(@"render", @"attach-failed", @"error", @{ @"reason": @"nil-scene" });
        return NO;
    }
    return [[self shared] attachToScene:scene];
}

- (BOOL)attachToScene:(UIWindowScene *)scene {
    if (_window) {
        DSHPetLog(@"render", @"attach-skip", @"debug", @{ @"reason": @"already-attached" });
        return YES;
    }
    _cfg = DSHPetLoadUIConfig();
    if (![_cfg[@"enabled"] boolValue]) {
        DSHPetLog(@"render", @"attach-skip", @"info", @{ @"reason": @"disabled-by-config" });
        return NO;
    }

    _scene = scene;
    _window = [[DSHPetWindow alloc] initWithWindowScene:scene];
    _window.frame = scene.coordinateSpace.bounds;
    _window.windowLevel = (CGFloat)[_cfg[@"windowLevel"] doubleValue];
    _window.backgroundColor = [UIColor clearColor];
    _window.opaque = NO;
    _window.hidden = NO;
    _window.userInteractionEnabled = YES;
    // 这层必须"彻底透明"：不透明标记、组透明度、光栅化、默认阴影任何一项留着，
    // 旋转/截图时都会显出一个黑底或阴影方块。
    _window.layer.opaque = NO;
    _window.layer.backgroundColor = [UIColor clearColor].CGColor;
    _window.layer.allowsGroupOpacity = NO;
    _window.layer.shouldRasterize = NO;
    _window.layer.shadowOpacity = 0.0;

    UIViewController *root = [[UIViewController alloc] init];
    root.view.backgroundColor = [UIColor clearColor];
    _window.rootViewController = root;

    CGFloat size = [_cfg[@"size"] doubleValue];
    _box = [[UIView alloc] initWithFrame:CGRectMake(0, 0, size, size)];
    _box.backgroundColor = [UIColor colorWithRed:0.15 green:0.78 blue:0.55 alpha:0.85];
    _box.layer.cornerRadius = 16.0;
    _box.layer.borderWidth = 1.0;
    _box.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.65].CGColor;
    _box.userInteractionEnabled = YES;
    _box.accessibilityLabel = @"小肥娘测试方块";
    [root.view addSubview:_box];
    _window.touchTarget = _box;

    CGSize b = _window.bounds.size;
    _box.center = CGPointMake(b.width * [_cfg[@"centerX"] doubleValue],
                              b.height * [_cfg[@"centerY"] doubleValue]);

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onTap:)];
    [_box addGestureRecognizer:tap];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPan:)];
    [_box addGestureRecognizer:pan];

    [[NSNotificationCenter defaultCenter] removeObserver:self];

    __weak DSHPetOverlay *weakSelf = self;
    _window.onLayout = ^{
        [weakSelf relayoutForCurrentBounds];
    };

    // 旋转时 layoutSubviews 可能早于最终尺寸，再补一次延迟校正
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onOrientationChange:)
                                                 name:UIDeviceOrientationDidChangeNotification
                                               object:nil];
    // 场景尺寸变化（含 180° 翻转：两次横屏之间场景尺寸不变，只有它有事件）。
    // 16.5 SDK 里没有这个常量，所以用字符串名注册，避免编译期符号缺失。
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onOrientationChange:)
                                                 name:@"UIWindowSceneDidUpdateCoordinateSpaceNotification"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onOrientationChange:)
                                                 name:@"UIApplicationDidChangeStatusBarOrientationNotification"
                                               object:nil];

    DSHPetLog(@"render", @"attach-ok", @"info", @{
        @"size": @(size),
        @"level": @(_window.windowLevel),
        @"centerX": @(_box.center.x),
        @"centerY": @(_box.center.y),
        @"screenW": @(b.width),
        @"screenH": @(b.height),
        @"scale": @([[UIScreen mainScreen] scale]),
    });
    return YES;
}

#pragma mark 交互

- (void)onTap:(UITapGestureRecognizer *)g {
    NSInteger taps = [_cfg[@"taps"] integerValue] + 1;
    _cfg[@"taps"] = @(taps);
    DSHPetSaveUIConfig(_cfg);
    DSHPetLog(@"render", @"tap", @"info", @{ @"count": @(taps) });
    [UIView animateWithDuration:0.12 animations:^{
        self->_box.transform = CGAffineTransformMakeScale(1.12, 1.12);
    } completion:^(BOOL f) {
        [UIView animateWithDuration:0.12 animations:^{ self->_box.transform = CGAffineTransformIdentity; }];
    }];
}

- (void)onPan:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:_window];
    if (g.state == UIGestureRecognizerStateBegan) {
        _panStartCenter = _box.center;
    } else if (g.state == UIGestureRecognizerStateChanged) {
        _box.center = CGPointMake(_panStartCenter.x + t.x, _panStartCenter.y + t.y);
    } else if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
        [self clampAndPersist];
    }
}

// 手势保护区（方案 §15.1）：顶部 40pt / 左右 20pt / 底部 34pt 不放方块，避免和系统手势抢。
// 用 safeAreaInsets 兜住带刘海/Home 条的机型，取两者更大的那个边距。
- (CGPoint)clampedCenter:(CGPoint)c inSize:(CGSize)b {
    if (b.width <= 0 || b.height <= 0) return c;
    CGFloat half = _box.bounds.size.width / 2.0;
    UIEdgeInsets sa = _window.safeAreaInsets;
    CGFloat left = MAX(20.0, sa.left + 8.0);
    CGFloat right = MAX(20.0, sa.right + 8.0);
    CGFloat top = MAX(40.0, sa.top + 8.0);
    CGFloat bottom = MAX(34.0, sa.bottom + 8.0);

    CGFloat minX = left + half, maxX = b.width - right - half;
    CGFloat minY = top + half, maxY = b.height - bottom - half;

    if (minX > maxX) minX = maxX = b.width / 2.0;      // 极端尺寸下退化为居中，绝不丢
    if (minY > maxY) minY = maxY = b.height / 2.0;

    c.x = MAX(minX, MIN(maxX, c.x));
    c.y = MAX(minY, MIN(maxY, c.y));
    return c;
}

- (void)clampAndPersist {
    // 只用窗口 bounds（唯一坐标真相），不要回退到 scene bounds——那个永不随方向变。
    CGSize b = _window.bounds.size;
    if (b.width <= 0 || b.height <= 0) return;

    CGPoint c = [self clampedCenter:_box.center inSize:b];
    _box.center = c;

    _cfg[@"centerX"] = @(c.x / b.width);
    _cfg[@"centerY"] = @(c.y / b.height);
    DSHPetSaveUIConfig(_cfg);
    DSHPetLog(@"render", @"drag-end", @"info", @{ @"x": @(c.x), @"y": @(c.y), @"w": @(b.width), @"h": @(b.height) });
}

- (CGRect)sceneBoundsIfValid {
    if (!_scene) return CGRectZero;
    return _scene.coordinateSpace.bounds;
}

- (void)relayoutForCurrentBounds {
    [self relayoutAndSettle:NO];
}

- (void)relayoutAndSettle:(BOOL)settle {
    if (!_window || !_box) return;

    CGRect sb = [self sceneBoundsIfValid];

    // 坐标系只有一套：**就用窗口自己的 bounds**。
    //
    // 实测（v0.1.0-26 的 render.jsonl）：scene.coordinateSpace.bounds 在横屏时
    // 仍然是 393×852（竖屏尺寸，从不随方向换），而窗口 bounds 会正确变成 852×393。
    // 上一版拿 scene bounds 去硬同步窗口 frame，等于在横屏时把窗口重新塞回竖屏形状——
    // 方块就永远停在"竖屏那套坐标"的同一物理位置：左横刚好可见、右横落在屏幕外。
    // 外围那片黑，也是因为窗口只剩竖屏那么宽，屏幕其余部分没有窗口覆盖。
    //
    // 所以这里只管布局，一个字节都不碰 frame / transform（那是 UIKit 的活）。
    CGSize b = _window.bounds.size;
    if (b.width <= 1.0 || b.height <= 1.0) return;

    CGPoint wantC = CGPointMake(b.width * [_cfg[@"centerX"] doubleValue],
                                b.height * [_cfg[@"centerY"] doubleValue]);
    CGPoint got = [self clampedCenter:wantC inSize:b];
    BOOL forced = !CGPointEqualToPoint(wantC, got);
    _box.center = got;
    _box.hidden = NO;

    // 兜底：夹过了还落在窗口外，拉回默认位置，绝不让它消失。
    if (!CGRectIntersectsRect(_box.frame, CGRectMake(0.0, 0.0, b.width, b.height))) {
        _box.center = CGPointMake(b.width * 0.80, b.height * 0.22);
        forced = YES;
        DSHPetLog(@"render", @"rescued", @"warn", @{ @"why": @"box-outside-bounds" });
    }

    DSHPetLog(@"render", @"relayout", @"info", @{
        @"w": @(b.width),
        @"h": @(b.height),
        @"sceneW": @(sb.size.width),
        @"sceneH": @(sb.size.height),
        @"frameX": @(_window.frame.origin.x),
        @"frameY": @(_window.frame.origin.y),
        @"settle": @(settle),
        @"tf": [NSString stringWithFormat:@"%.2f/%.2f/%.2f/%.2f",
                _window.transform.a, _window.transform.b, _window.transform.c, _window.transform.d],
        @"orientation": @([[UIDevice currentDevice] orientation]),
        @"boxX": @(_box.center.x),
        @"boxY": @(_box.center.y),
        @"forced": @(forced),
    });
}

- (void)onOrientationChange:(NSNotification *)n {
    if (!_window || !_box) return;

    // 不再藏窗口、不再改 frame。窗口尺寸由 UIKit 换，layoutSubviews 会自动重排；
    // 这里只补一次延迟校正，兜住"旋转动画结束、安全区最后才更新"的时序差。
    CGSize b = _window.bounds.size;
    DSHPetLog(@"render", @"orient", @"debug", @{
        @"w": @(b.width),
        @"h": @(b.height),
        @"orientation": @([UIDevice currentDevice].orientation),
        @"name": n.name ?: @"",
    });

    __weak DSHPetOverlay *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [weakSelf relayoutAndSettle:YES];
    });
}

- (void)detach {
    if (!_window) return;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _window.hidden = YES;
    _window = nil;
    _box = nil;
    DSHPetLog(@"render", @"detach", @"info", nil);
}

@end
