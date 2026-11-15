#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "DSHPetBoot.h"
#import "DSHPetOverlay.h"
#import "DSHPetPlayer.h"
#import "DSHPetAnimator.h"

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
    // 1500 = 状态栏(1000)之上、系统弹窗(2000)之下：
    // 短剧/视频类 App 会把自己的全屏窗口抬到 1000 以上，1100 会被压在下面（宠物"消失"）。
    // 老配置里存着 1100 的一律迁移上来，否则改默认值也救不了已装用户。
    if (!cfg[@"windowLevel"] || [cfg[@"windowLevel"] doubleValue] <= UIWindowLevelStatusBar + 100.5) {
        cfg[@"windowLevel"] = @(1500.0);
    }
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
- (void)relayoutAndSettle:(BOOL)settle;
- (CGPoint)clampedCenter:(CGPoint)c inSize:(CGSize)b;
- (void)onOrientationChange:(NSNotification *)n;
- (void)setLayerVisible:(BOOL)visible;
@end

@implementation DSHPetOverlay {
    CGFloat _pinchStartW;
    UIWindowScene *_scene;
    DSHPetWindow *_window;
    UIView *_box;
    NSMutableDictionary *_cfg;
    CGPoint _panStartCenter;
    UIInterfaceOrientation _lastInterfaceOrient;
    NSUInteger _orientToken;
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
    _lastInterfaceOrient = scene.interfaceOrientation;
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

    // 宠物宿主：宽 = size，高按 2160x1215 素材比例（1.778）算。
    CGFloat scrW = CGRectGetWidth([UIScreen mainScreen].bounds);
    CGFloat maxW = scrW * 0.62;   // 上限：再大就盖住图标文字了
    CGFloat minW = scrW * 0.16;   // 下限：太小看不清表情

    // 宽度来源按优先级：sizeRatio（跨机型可移植）> size（旧配置/像素）> 默认 30% 屏宽。
    // 注意：这里不能拿"小于某个绝对值"当"没配过"的判据——用户捏到 118pt 是合法值，
    // 之前写 `size < 120 → 300` 正是"缩小后注销又变大"的根因。
    CGFloat size = 0;
    if (_cfg[@"sizeRatio"]) {
        size = scrW * [_cfg[@"sizeRatio"] doubleValue];
    } else if ([_cfg[@"size"] doubleValue] > 0) {
        size = [_cfg[@"size"] doubleValue];
    } else {
        size = scrW * 0.30;
    }
    if (size > maxW) size = maxW;
    if (size < minW) size = minW;
    CGFloat petW = size;
    CGFloat petH = round(size * 1215.0 / 2160.0);
    _box = [[UIView alloc] initWithFrame:CGRectMake(0, 0, petW, petH)];
    _box.backgroundColor = [UIColor colorWithRed:0.15 green:0.78 blue:0.55 alpha:0.85];
    _box.layer.cornerRadius = 16.0;
    _box.layer.borderWidth = 1.0;
    _box.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.65].CGColor;
    _box.userInteractionEnabled = YES;
    [root.view addSubview:_box];
    _window.touchTarget = _box;

    // S3：有素材就把方块换成 HEVC-alpha 视频；没素材保持方块当占位。
    BOOL hasPet = [[DSHPetPlayer shared] attachToHostView:_box size:CGSizeMake(petW, petH)];
    if (hasPet) {
        // 素材真实比例优先：不同素材宽高比不一样，写死 2160x1215 会让画面上下/左右留大片透明边，
        // 看起来就是"宠物离边缘很远"。拿到 naturalSize 后立刻按它重算宿主高度。
        CGSize nat = [[DSHPetPlayer shared] naturalSize];
        if (nat.width > 1.0 && nat.height > 1.0) {
            petH = round(petW * nat.height / nat.width);
            CGRect f = _box.frame;
            f.size = CGSizeMake(petW, petH);
            _box.frame = f;
            [[DSHPetPlayer shared] setDisplaySize:CGSizeMake(petW, petH)];
        }
        DSHPetLog(@"render", @"pet-aspect", @"debug", @{ @"natW": @(nat.width), @"natH": @(nat.height), @"boxW": @(petW), @"boxH": @(petH) });
        _box.backgroundColor = [UIColor clearColor];
        _box.layer.cornerRadius = 0.0;
        _box.layer.borderWidth = 0.0;
        _box.accessibilityLabel = @"小肥娘";
        [[DSHPetAnimator shared] startWithDirectory:@"/var/mobile/Library/DSHPet/assets"];
    } else {
        _box.accessibilityLabel = @"小肥娘（占位，未装素材）";
    }

    CGSize b = _window.bounds.size;
    _box.center = CGPointMake(b.width * [_cfg[@"centerX"] doubleValue],
                              b.height * [_cfg[@"centerY"] doubleValue]);

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onTap:)];
    [_box addGestureRecognizer:tap];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPan:)];
    [_box addGestureRecognizer:pan];

    // S7 之前先给个临时尺寸入口：双指捏合直接改大小，松手落盘
    UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(onPinch:)];
    [_box addGestureRecognizer:pinch];

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
    [[DSHPetAnimator shared] handleTap];
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

- (void)onPinch:(UIPinchGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) {
        _pinchStartW = CGRectGetWidth(_box.bounds);
    }
    CGFloat w = _pinchStartW * g.scale;
    if (g.state == UIGestureRecognizerStateChanged || g.state == UIGestureRecognizerStateEnded) {
        [self applyPetWidth:w];
    }
    if (g.state == UIGestureRecognizerStateEnded) {
        CGFloat ratio = CGRectGetWidth(_box.bounds) / CGRectGetWidth([UIScreen mainScreen].bounds);
        _cfg[@"size"] = @(round(CGRectGetWidth(_box.bounds)));
        _cfg[@"sizeRatio"] = @(round(ratio * 1000.0) / 1000.0);
        [self saveConfig];
        DSHPetLog(@"render", @"pet-resize", @"info", @{ @"w": @(round(CGRectGetWidth(_box.bounds))), @"ratio": @(ratio) });
    }
}

- (void)applyPetWidth:(CGFloat)w {
    CGFloat scrW = CGRectGetWidth([UIScreen mainScreen].bounds);
    w = MAX(scrW * 0.16, MIN(scrW * 0.62, w));
    CGSize nat = [[DSHPetPlayer shared] naturalSize];
    CGFloat ratio = (nat.width > 1.0) ? (nat.height / nat.width) : (1215.0 / 2160.0);
    CGFloat h = round(w * ratio);
    CGRect f = _box.frame;
    CGPoint c = _box.center;
    f.size = CGSizeMake(w, h);
    _box.frame = f;
    _box.center = c;
    [[DSHPetPlayer shared] setDisplaySize:CGSizeMake(w, h)];
}

- (void)onPan:(UIPanGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) [[DSHPetAnimator shared] handleDragBegin];
    CGPoint t = [g translationInView:_window];
    if (g.state == UIGestureRecognizerStateBegan) {
        _panStartCenter = _box.center;
    } else if (g.state == UIGestureRecognizerStateChanged) {
        _box.center = CGPointMake(_panStartCenter.x + t.x, _panStartCenter.y + t.y);
    } else if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
        [self clampAndPersist];
        [[DSHPetAnimator shared] handleDragEnd];
    }
}

// 手势保护区（方案 §15.1）：顶部 40pt / 左右 20pt / 底部 34pt 不放方块，避免和系统手势抢。
// 用 safeAreaInsets 兜住带刘海/Home 条的机型，取两者更大的那个边距。
- (CGPoint)clampedCenter:(CGPoint)c inSize:(CGSize)b {
    if (b.width <= 0 || b.height <= 0) return c;
    CGFloat half = MAX(_box.bounds.size.width, _box.bounds.size.height) / 2.0;
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

- (void)saveConfig {
    [_cfg writeToFile:kUIConfigPath atomically:YES];
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

    // 用设备方向做"早退场"：它比 scene.interfaceOrientation 早，
    // 能在 SpringBoard 开始拍旋转快照之前把这一层撤出合成。
    // 轻微晃动只会让相邻两个方向来回抖，方向类别没变就直接忽略。
    UIDeviceOrientation d = [UIDevice currentDevice].orientation;
    UIInterfaceOrientation target = UIInterfaceOrientationUnknown;
    if (d == UIDeviceOrientationPortrait) target = UIInterfaceOrientationPortrait;
    else if (d == UIDeviceOrientationPortraitUpsideDown) target = UIInterfaceOrientationPortraitUpsideDown;
    else if (d == UIDeviceOrientationLandscapeLeft) target = UIInterfaceOrientationLandscapeRight;
    else if (d == UIDeviceOrientationLandscapeRight) target = UIInterfaceOrientationLandscapeLeft;

    if (target == UIInterfaceOrientationUnknown || target == _lastInterfaceOrient) {
        DSHPetLog(@"render", @"orient-ignore", @"debug", @{
            @"dev": @(d),
            @"iface": @(_lastInterfaceOrient),
            @"name": n.name ?: @"",
        });
        return;
    }
    _lastInterfaceOrient = target;
    NSUInteger token = ++_orientToken;

    // 旋转期间整层退出合成：SpringBoard 拍旋转快照时会把我们这层一起拍进去，
    // 快照缓冲只有当前（旧）尺寸那么大，叠在旋转动画上，屏幕外围就是一圈黑。
    [self setLayerVisible:NO];
    DSHPetLog(@"render", @"orient", @"info", @{ @"dev": @(d), @"target": @(target) });

    __weak DSHPetOverlay *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        DSHPetOverlay *s = weakSelf;
        if (!s || s->_orientToken != token) return;
        [s relayoutAndSettle:YES];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.80 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        DSHPetOverlay *s = weakSelf;
        if (!s || s->_orientToken != token) return;
        [s relayoutAndSettle:YES];
        [s setLayerVisible:YES];
    });
}

- (void)setLayerVisible:(BOOL)visible {
    if (!_window) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (visible) {
        _window.hidden = NO;
    } else {
        _window.hidden = YES;
    }
    [CATransaction commit];
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
