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
@end

@implementation DSHPetWindow

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
    _box.center = CGPointMake(b.width * [_cfg[@"centerX"] doubleValue],
                              b.height * [_cfg[@"centerY"] doubleValue]);

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onTap:)];
    [_box addGestureRecognizer:tap];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPan:)];
    [_box addGestureRecognizer:pan];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onCoordinateSpaceChange:)
                                                 name:UIWindowSceneDidUpdateCoordinateSpaceNotification
                                               object:scene];

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

// 手势保护区（方案 §15.1）：顶部 40pt / 左右 20pt / 底部 34pt 不放方块，避免和系统手势抢
- (void)clampAndPersist {
    CGSize b = _window.bounds.size;
    CGFloat half = _box.bounds.size.width / 2.0;
    CGFloat minX = 20.0 + half, maxX = b.width - 20.0 - half;
    CGFloat minY = 40.0 + half, maxY = b.height - 34.0 - half;
    CGPoint c = _box.center;
    c.x = MAX(minX, MIN(maxX, c.x));
    c.y = MAX(minY, MIN(maxY, c.y));
    _box.center = c;

    _cfg[@"centerX"] = @(b.width > 0 ? c.x / b.width : 0.8);
    _cfg[@"centerY"] = @(b.height > 0 ? c.y / b.height : 0.2);
    DSHPetSaveUIConfig(_cfg);
    DSHPetLog(@"render", @"drag-end", @"info", @{ @"x": @(c.x), @"y": @(c.y) });
}

- (void)onCoordinateSpaceChange:(NSNotification *)n {
    UIWindowScene *s = (UIWindowScene *)n.object;
    CGRect r = s.coordinateSpace.bounds;
    _window.frame = r;
    CGSize b = r.size;
    _box.center = CGPointMake(b.width * [_cfg[@"centerX"] doubleValue],
                              b.height * [_cfg[@"centerY"] doubleValue]);
    [self clampAndPersist];
    DSHPetLog(@"render", @"relayout", @"info", @{ @"w": @(b.width), @"h": @(b.height) });
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
