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
- (void)setLayerVisible:(BOOL)visible;
- (void)onOrientationChange:(NSNotification *)n;
@end

@implementation DSHPetOverlay {
    UIWindowScene *_scene;
    DSHPetWindow *_window;
    UIView *_box;
    NSMutableDictionary *_cfg;
    CGPoint _panStartCenter;
    CGSize _lastSceneSize;     // 上一次真正处理过的场景尺寸，用来过滤"轻微晃动"引起的假旋转
    NSUInteger _orientToken;   // 旋转连发时只让最后一次收尾动作生效
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

    CGSize b = scene.coordinateSpace.bounds.size;
    _lastSceneSize = b;
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
    CGSize b = _window.bounds.size;
    if (b.width <= 0 || b.height <= 0) { b = _scene.coordinateSpace.bounds.size; }
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
    BOOL sceneValid = sb.size.width > 1.0 && sb.size.height > 1.0;
    BOOL hard = NO;

    // 旋转动画结束后才允许"硬同步"：此时 UIKit 不会再转第二次，设 frame 是安全的。
    // 关键：**frame 的 origin 必须归零**。
    // 右横时 scene 坐标空间的 bounds 带非零 origin，直接 frame = sb 会把整个窗口推出屏幕，
    // 方块就成了"看不见但没死"——这正是右横没有方块的根。
    if (settle && sceneValid) {
        CGRect want = CGRectMake(0.0, 0.0, sb.size.width, sb.size.height);
        BOOL off = !CGRectEqualToRect(_window.frame, want) ||
                   !CGAffineTransformIsIdentity(_window.transform);
        if (off) {
            _window.transform = CGAffineTransformIdentity;
            _window.frame = want;
            hard = YES;
        }
    }

    CGSize b = _window.bounds.size;
    if (b.width <= 1.0 || b.height <= 1.0) return;

    CGPoint wantC = CGPointMake(b.width * [_cfg[@"centerX"] doubleValue],
                                b.height * [_cfg[@"centerY"] doubleValue]);
    CGPoint got = [self clampedCenter:wantC inSize:b];
    BOOL forced = !CGPointEqualToPoint(wantC, got);
    _box.center = got;
    _box.hidden = NO;

    // 兜底：夹过了还落在窗口外（窗口自己被系统挪走），拉回默认位置，绝不让它消失。
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
        @"sceneX": @(sb.origin.x),
        @"sceneY": @(sb.origin.y),
        @"frameX": @(_window.frame.origin.x),
        @"frameY": @(_window.frame.origin.y),
        @"hardSync": @(hard),
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

    CGRect sb = [self sceneBoundsIfValid];
    if (sb.size.width < 1.0 || sb.size.height < 1.0) return;

    BOOL sizeSame = CGSizeEqualToSize(sb.size, _lastSceneSize);
    BOOL winStale = !CGSizeEqualToSize(_window.bounds.size, sb.size);

    // 手机轻微晃动会连发 UIDeviceOrientationDidChange，但场景尺寸没变。
    // 这种情况绝不能动 alpha（一藏一显就是"闪一下"），只补一次窗口尺寸。
    if (sizeSame) {
        if (winStale) [self relayoutAndSettle:YES];
        DSHPetLog(@"render", @"orient-ignore", @"debug", @{
            @"w": @(sb.size.width),
            @"h": @(sb.size.height),
            @"winStale": @(winStale),
            @"orientation": @([UIDevice currentDevice].orientation),
        });
        return;
    }

    _lastSceneSize = sb.size;
    NSUInteger token = ++_orientToken;

    // 只有真的换方向（尺寸变了）才藏整层：SpringBoard 会对窗口做快照再旋转，
    // 我们这层额外窗口若参与动画，就会留下黑边/阴影残影。
    [self setLayerVisible:NO];
    __weak DSHPetOverlay *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.55 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        DSHPetOverlay *s = weakSelf;
        if (!s || s->_orientToken != token) return;   // 期间又转了，交给最新一次收尾
        [s relayoutAndSettle:YES];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.10 * NSEC_PER_SEC)),
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
    [CATransaction setDisableActions:YES];   // 不要自带动画，避免又生成一层残影
    if (visible) {
        _window.hidden = NO;                 // 先回到窗口层级，再抬 alpha
        _window.alpha = 1.0;
    } else {
        _window.alpha = 0.0;
        // 只把 alpha 归零，窗口仍参与合成，SpringBoard 的快照里就还留着我们这一层
        // ——旋转时屏幕上那圈黑边/阴影就是这么来的。彻底 hidden 才会被排除在快照之外。
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
