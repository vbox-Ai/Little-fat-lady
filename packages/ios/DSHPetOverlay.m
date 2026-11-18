#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "DSHPetBoot.h"
#import "DSHPetOverlay.h"
#import "DSHPetBubble.h"
#import "DSHPetBridge.h"
#import "DSHPetHaptics.h"
#import "DSHPetPrefs.h"
#import "DSHPetCrew.h"
#import "DSHPetTodoPanel.h"
#import "DSHPetAssets.h"
#import <CoreMotion/CoreMotion.h>
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
- (void)hideBoxChrome;
- (void)setupBubbleInRoot:(UIView *)rootView;
- (void)anchorBubble;
- (NSString *)labelForWorkState:(NSString *)state;
- (void)clampAndPersist;
- (void)applySizeFromConfig;
- (void)applyPrefsNow;
#pragma mark - S6d 长按菜单
- (void)onLongPress:(UILongPressGestureRecognizer *)g;
- (void)showPetMenu;
- (void)showTodoPanel;
- (void)showBridgeStatus;
- (void)showSelfStatusBubble:(NSString *)text;
- (void)hideForAWhile:(NSTimeInterval)seconds;
- (CGRect)petFrameInOverlayRoot;
- (UIEdgeInsets)overlaySafeInsets;
- (void)showSelfCheckBubble;
@end

@implementation DSHPetOverlay {
    CGFloat _pinchStartW;
    UIWindowScene *_scene;
    DSHPetWindow *_window;
    UIView *_box;
    DSHPetBubble *_bubble;
    BOOL _bubbleReady;
    NSMutableDictionary *_cfg;
    CGPoint _panStartCenter;
    UIInterfaceOrientation _lastInterfaceOrient;
    NSUInteger _orientToken;
    id _firstFrameObs;
    BOOL _firstFrameSeen;
    // S5 物理
    CADisplayLink *_physLink;
    CGPoint _vel;
    CFTimeInterval _lastPhysT;
    CGPoint _panLastPoint;
    CFTimeInterval _panLastT;
    BOOL _physRunning;
    CMMotionManager *_motion;
    BOOL _userSized;      // 用户捏过之后就别再自动改尺寸
    id _prefsObs;         // S7：SpringBoard 回前台时重读设置面板
    id _sessionsObs;      // S6c：会话集合变化时调整多开数量
    DSHPetTodoPanel *_todoPanel;   // S6d：长按弹出的待办清单
    NSTimer *_hideTimer;           // S6d：「隐藏 1 小时」的自动恢复
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

- (void)setupBubbleInRoot:(UIView *)rootView {
    if (_bubbleReady) return;
    _bubbleReady = YES;

    _bubble = [[DSHPetBubble alloc] initWithHostView:rootView];

    __weak DSHPetOverlay *weakSelf = self;
    [[NSNotificationCenter defaultCenter] addObserverForName:DSHPetSayNotification
                                                     object:nil
                                                      queue:[NSOperationQueue mainQueue]
                                                 usingBlock:^(NSNotification *note) {
        DSHPetOverlay *me = weakSelf;
        if (!me) return;
        NSString *text = note.userInfo[@"text"];
        if (![text isKindOfClass:[NSString class]] || !text.length) return;
        if (me->_cfg[@"bubbleEnabled"] && ![me->_cfg[@"bubbleEnabled"] boolValue]) return;
        [me->_bubble showText:text duration:6.5];
        [me anchorBubble];
    }];
    [[NSNotificationCenter defaultCenter] addObserverForName:DSHPetStatusNotification
                                                     object:nil
                                                      queue:[NSOperationQueue mainQueue]
                                                 usingBlock:^(NSNotification *note) {
        DSHPetOverlay *me = weakSelf;
        if (!me) return;
        if (![me->_cfg[@"bubbleStatusEnabled"] boolValue]) return;
        NSString *st = note.userInfo[@"state"];
        if (![st isKindOfClass:[NSString class]] || !st.length) return;
        [me->_bubble showText:[me labelForWorkState:st] duration:4.0];
        [me anchorBubble];
    }];

    NSString *base = _cfg[@"bridgeBase"];
    if (![base isKindOfClass:[NSString class]] || !base.length) base = @"https://dsh.vbox.ltd:42429";
    BOOL enabled = _cfg[@"bridgeEnabled"] ? [_cfg[@"bridgeEnabled"] boolValue] : YES;
    if (enabled) {
        NSTimeInterval iv = _cfg[@"bridgeInterval"] ? [_cfg[@"bridgeInterval"] doubleValue] : 2.5;
        NSString *token = [_cfg[@"bridgeToken"] isKindOfClass:[NSString class]] ? _cfg[@"bridgeToken"] : @"";
        [[DSHPetBridge shared] startWithBase:base token:token interval:iv];
    }
    DSHPetLog(@"bubble", @"ready", @"info", @{ @"bridge": enabled ? base : @"off" });
}

- (NSString *)labelForWorkState:(NSString *)state {
    if ([state isEqualToString:@"working"]) return @"干活中…";
    if ([state isEqualToString:@"thinking"]) return @"在想…";
    if ([state isEqualToString:@"idle"]) return @"闲着呢";
    return state;
}

- (void)anchorBubble {
    if (!_bubble || !_box) return;
    UIView *host = _box.superview;
    if (!host) return;
    UIEdgeInsets insets = UIEdgeInsetsZero;
    if (@available(iOS 11.0, *)) insets = host.safeAreaInsets;
    CGRect petInHost = [_box convertRect:_box.bounds toView:host];
    [_bubble anchorAtPetFrame:petInHost hostBounds:host.bounds safeInsets:insets];
}

#pragma mark - S6d 长按菜单

- (void)onLongPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    [self showPetMenu];
}

- (void)showPetMenu {
    UIViewController *root = _window.rootViewController;
    if (!root || root.presentedViewController) return;

    // 用 actionSheet 而不是自绘菜单：系统样式在越狱机上最稳（不乱、不跟 SpringBoard 抢层级），
    // 而且"取消"位置固定，用户不用学。
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"小肥娘"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    __weak DSHPetOverlay *weakSelf = self;

    [sheet addAction:[UIAlertAction actionWithTitle:@"待办清单" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [weakSelf showTodoPanel];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"换个表情" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        // play 桶是上游"玩/杂项"那一堆（67 段），最适合当表情包轮播
        BOOL ok = [[DSHPetAnimator shared] playRandomFromCategory:@"play"]
               || [[DSHPetAnimator shared] playRandomFromCategory:@"eat"];
        [[DSHPetHaptics shared] fire:DSHPetHapticLight key:@"menu" minInterval:0.25];
        DSHPetLog(@"menu", @"shuffle", ok ? @"info" : @"warn", @{ @"ok": @(ok) });
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"连接状态" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [weakSelf showBridgeStatus];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"隐藏 1 小时" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [weakSelf hideForAWhile:3600.0];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    // iPad/横屏上 actionSheet 必须有 popover 锚点，否则 iPhone 也会偶发不弹
    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = _box;
        sheet.popoverPresentationController.sourceRect = _box.bounds;
    }
    [root presentViewController:sheet animated:YES completion:nil];
    [[DSHPetHaptics shared] fire:DSHPetHapticLight key:@"menu" minInterval:0.25];
    DSHPetLog(@"menu", @"open", @"debug", nil);
}

- (CGRect)petFrameInOverlayRoot {
    UIView *rootView = _window.rootViewController.view;
    if (!rootView || !_box) return CGRectZero;
    return [_box convertRect:_box.bounds toView:rootView];
}

- (UIEdgeInsets)overlaySafeInsets {
    UIView *rootView = _window.rootViewController.view;
    UIEdgeInsets insets = UIEdgeInsetsZero;
    if (@available(iOS 11.0, *)) insets = rootView.safeAreaInsets;
    return insets;
}

- (void)showTodoPanel {
    UIView *rootView = _window.rootViewController.view;
    if (!rootView) return;
    if (!_todoPanel) _todoPanel = [[DSHPetTodoPanel alloc] initWithFrame:CGRectZero];

    CGRect anchor = [self petFrameInOverlayRoot];
    UIEdgeInsets sa = [self overlaySafeInsets];
    [_todoPanel showLoadingInHost:rootView anchorFrame:anchor safeInsets:sa];

    __weak DSHPetOverlay *weakSelf = self;
    [[DSHPetBridge shared] fetchTodos:^(NSArray<NSDictionary *> *todos, NSString *err) {
        DSHPetOverlay *s = weakSelf;
        if (!s || !s->_todoPanel) return;
        CGRect a = [s petFrameInOverlayRoot];
        UIEdgeInsets ins = [s overlaySafeInsets];
        UIView *host = s->_window.rootViewController.view;
        if (!host) return;
        if (err.length) {
            [s->_todoPanel showError:err inHost:host anchorFrame:a safeInsets:ins];
        } else {
            [s->_todoPanel showTodos:(todos ?: @[]) inHost:host anchorFrame:a safeInsets:ins];
        }
    }];
}

- (void)showBridgeStatus {
    DSHPetBridge *b = [DSHPetBridge shared];
    NSString *state = b.workState.length ? [self labelForWorkState:b.workState] : @"未知";
    NSString *base = _cfg[@"bridgeBase"] ?: @"https://dsh.vbox.ltd:42429";
    NSString *err = b.lastError.length ? b.lastError : @"无";
    NSString *text = [NSString stringWithFormat:@"会话状态：%@\n会话数：%lu\n宿主：%@\n最近错误：%@",
                      state, (unsigned long)b.sessions.count, base, err];
    [self showSelfStatusBubble:text];
}

- (void)showSelfStatusBubble:(NSString *)text {
    if (!_bubble) return;
    [_bubble showText:text duration:10.0];
    [self anchorBubble];
}

- (void)hideForAWhile:(NSTimeInterval)seconds {
    [self setLayerVisible:NO];
    [_hideTimer invalidate];
    __weak DSHPetOverlay *weakSelf = self;
    _hideTimer = [NSTimer scheduledTimerWithTimeInterval:seconds repeats:NO block:^(NSTimer *t) {
        DSHPetOverlay *s = weakSelf;
        if (!s) return;
        [s setLayerVisible:YES];
        DSHPetLog(@"menu", @"auto-show", @"info", @{ @"after": @(seconds) });
    }];
    DSHPetLog(@"menu", @"hide", @"info", @{ @"seconds": @(seconds) });
}

- (BOOL)attachToScene:(UIWindowScene *)scene {
    if (_window) {
        DSHPetLog(@"render", @"attach-skip", @"debug", @{ @"reason": @"already-attached" });
        return YES;
    }
    _cfg = DSHPetLoadUIConfig();
    // S7：面板（CFPreferences）优先于 ui.json，只覆盖用户可调项，不碰运行时状态。
    if ([DSHPetPrefs applyToUIConfig:_cfg]) DSHPetSaveUIConfig(_cfg);
    [DSHPetPrefs stampVersion:DSHPET_VERSION_STRING];   // 面板「关于 → 版本」显示真实版本
    if (![_cfg[@"enabled"] boolValue]) {
        DSHPetLog(@"render", @"attach-skip", @"info", @{ @"reason": @"disabled-by-config" });
        return NO;
    }

    // 尺寸归属：捏过就永不被自动 1:1 覆盖（注销/重启都算）
    _userSized = [_cfg[@"sizeManual"] boolValue];
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

    // S5：触感总开关 + 力度档（默认开、标准）
    NSDictionary *phc = _cfg[@"physics"];
    BOOL hapticOn = phc[@"hapticEnabled"] ? [phc[@"hapticEnabled"] boolValue] : YES;
    NSString *hapticLevel = [phc[@"hapticLevel"] isKindOfClass:[NSString class]] ? phc[@"hapticLevel"] : @"normal";
    [[DSHPetHaptics shared] setEnabled:hapticOn];
    [[DSHPetHaptics shared] setLevel:hapticLevel];

    [self setupBubbleInRoot:root.view];

    // S6c：会话集合变了（新的 DSH 会话出现 / 久不活跃过期）→ 调整额外宠物数量
    if (!_sessionsObs) {
        __weak DSHPetOverlay *weakSess = self;
        _sessionsObs = [[NSNotificationCenter defaultCenter] addObserverForName:DSHPetSessionsNotification
                                                                        object:nil
                                                                         queue:[NSOperationQueue mainQueue]
                                                                    usingBlock:^(NSNotification *note) {
            DSHPetOverlay *s = weakSess;
            if (!s || !s->_window) return;
            [[DSHPetCrew shared] reconcileWithBounds:s->_window.bounds config:s->_cfg];
        }];
    }

    // S7：从「设置」改完面板退回桌面 → SpringBoard 回前台 → 重读设置。
    __weak DSHPetOverlay *weakPrefs = self;
    if (!_prefsObs) {
        _prefsObs = [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                                     object:nil
                                                                      queue:[NSOperationQueue mainQueue]
                                                                 usingBlock:^(NSNotification *note) {
            [weakPrefs applyPrefsNow];
        }];
    }

    // 自检：8 秒还没上屏就把原因写进气泡（绿方块报障用）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [weakPrefs showSelfCheckBubble];
    });

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
        _box.accessibilityLabel = @"小肥娘";
        // 先把「撤占位块」的规矩立好，再开播——
        // 之前是先 startWithDirectory 再注册观察者，首帧可能在这中间就画完了，
        // 通知没人接，桌面就成了「绿方块里裹着一只小肥娘」（0.1.0-90 真机现象）。
        if (_firstFrameObs) {
            [[NSNotificationCenter defaultCenter] removeObserver:_firstFrameObs];
            _firstFrameObs = nil;
        }
        // 首帧尺寸对齐：图像宽 / 屏幕 scale，正好 1:1，不缩放就不会糊
        // 三档优先级（顺序不可换）：
        //  1) sizeManual=YES（用户捏过）→ 用保存的宽度，注销/重启都不许改；
        //  2) 没捏过 → 按素材原始像素 1:1 定宽（图像宽 / 屏幕 scale），不缩放就不糊；
        //  3) 拿不到素材 → 保持按屏宽算的初值。
        // 之前漏了第 1 档：_userSized 每次启动都是 false，注销后就被第 2 档压回 130pt，
        // 真机表现就是"放大之后注销又变小"。
        if (!_userSized) {
            CGSize nat0 = [[DSHPetPlayer shared] naturalSize];
            CGFloat scr0 = [UIScreen mainScreen].scale > 0 ? [UIScreen mainScreen].scale : 3.0;
            if (nat0.width > 1.0) {
                [self applyPetWidth:round(nat0.width) / scr0];
            }
        } else {
            [self applyPetWidth:_box.frame.size.width];
        }
        _firstFrameObs = [[NSNotificationCenter defaultCenter] addObserverForName:@"DSHPetFirstFrame"
                                                                           object:nil
                                                                            queue:[NSOperationQueue mainQueue]
                                                                        usingBlock:^(NSNotification *note) {
            __strong typeof(self) s = self;
            if (!s || !s->_box) return;
            s->_firstFrameSeen = YES;
            [s hideBoxChrome];
        }];

        // 有素材就别先摆绿底：宁可先空着 200ms，也不要让人看见「方块里长出一只宠物」。
        _box.backgroundColor = [UIColor clearColor];
        _box.layer.cornerRadius = 0.0;
        _box.layer.borderWidth = 0.0;

        if (!_motion) {
        _motion = [[CMMotionManager alloc] init];
        if (_motion.isAccelerometerAvailable) {
            _motion.accelerometerUpdateInterval = 1.0 / 30.0;
            [_motion startAccelerometerUpdates];
        }
    }

    [[DSHPetAnimator shared] startWithDirectory:@"/var/mobile/Library/DSHPet/assets"];

    // S6c：多开管家。主宠仍归本类，这里只负责第 2..N 只（默认 0 只）。
    [[DSHPetCrew shared] startInHost:root.view
                            assetDir:@"/var/mobile/Library/DSHPet/assets"
                              bounds:_window.bounds
                              config:_cfg];
        if ([[DSHPetPlayer shared] isReady]) {
            _firstFrameSeen = YES;
            [self hideBoxChrome];
        }

        // 首帧一到就撤占位块。
        // 以前只在 2 秒后做一次兜底检查，真机表现就是注销后先看到 1~3 秒绿色/蓝色方块，
        
        // 关键：**先别把占位块清掉**。早先一 attach 就设 clearColor，一旦视频解码失败/
        // 素材是坏的，桌面上就什么都没有（0.1.0-56 的真机现象：蓝水母和小肥娘都看不见）。
        // 现在只有首帧真的 ready 才清背景；2 秒还没 ready 就把块亮回来当"看得见的故障态"。
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) s = weakSelf;
            if (!s || !s->_box) return;
            BOOL ready = s->_firstFrameSeen || [[DSHPetPlayer shared] isReady];
            if (s->_firstFrameSeen) ready = YES;
            DSHPetLog(@"render", ready ? @"box-hide" : @"box-keep", ready ? @"debug" : @"warn",
                      @{ @"size": NSStringFromCGSize(s->_box.bounds.size),
                         @"center": NSStringFromCGPoint(s->_box.center),
                         @"window": NSStringFromCGRect(s->_window.frame) });
            if (ready) {
                s->_box.backgroundColor = [UIColor clearColor];
                s->_box.layer.cornerRadius = 0.0;
                s->_box.layer.borderWidth = 0.0;
            } else {
                UIImage *poster = [[DSHPetPlayer shared] posterImage];
                if (poster) {
                    // 视频放不动，但静帧能解 → 先把小肥娘"贴"在桌上，至少看得见
                    UIImageView *iv = [[UIImageView alloc] initWithImage:poster];
                    iv.frame = s->_box.bounds;
                    iv.contentMode = UIViewContentModeScaleAspectFit;
                    iv.userInteractionEnabled = NO;
                    iv.tag = 0x5E7;
                    [s->_box addSubview:iv];
                    s->_box.backgroundColor = [UIColor clearColor];
                    s->_box.layer.cornerRadius = 0.0;
                    s->_box.layer.borderWidth = 0.0;
                    s->_box.accessibilityLabel = @"小肥娘（静帧，视频解码失败）";
                } else {
                    s->_box.backgroundColor = [UIColor colorWithRed:0.85 green:0.25 blue:0.35 alpha:0.85];
                    s->_box.accessibilityLabel = @"小肥娘（素材没解码成功，先显示故障色）";
                }
            }
        });
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

    // S6d：长按弹菜单（待办 / 换表情 / 连接状态 / 隐藏）。
    // 0.45s 比系统默认 0.5s 略短一点：桌面上长按宠物，手感上"按住就出"比"按住半秒还没反应"好。
    UILongPressGestureRecognizer *longPress =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(onLongPress:)];
    longPress.minimumPressDuration = 0.45;
    longPress.allowableMovement = 14.0;
    [_box addGestureRecognizer:longPress];
    // 两个手势各管一段，互相之间**不要**加 requireGestureRecognizerToFail：
    //   · 按住不动 0.45s → 长按命中，pan 还停在 possible，不冲突；
    //   · 手指一开始动就超 allowableMovement → 长按自己失败，pan 立刻接管。
    // 反过来给 pan 加"必须等长按失败"，拖宠物会先卡 0.45 秒，手感直接废掉。

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
    [[DSHPetHaptics shared] fire:DSHPetHapticLight key:@"tap" minInterval:0.10];
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

- (void)onPinch:(UIPinchGestureRecognizer *)g {    if (g.state == UIGestureRecognizerStateBegan) {
        _pinchStartW = CGRectGetWidth(_box.bounds);
    }
    _userSized = YES;
    CGFloat w = _pinchStartW * g.scale;
    if (g.state == UIGestureRecognizerStateChanged || g.state == UIGestureRecognizerStateEnded) {
        [self applyPetWidth:w];
    }
    if (g.state == UIGestureRecognizerStateEnded) {
        CGFloat ratio = CGRectGetWidth(_box.bounds) / CGRectGetWidth([UIScreen mainScreen].bounds);
        _cfg[@"size"] = @(round(CGRectGetWidth(_box.bounds)));
        _cfg[@"sizeRatio"] = @(round(ratio * 1000.0) / 1000.0);
        // 关键：把"这个尺寸是人定的"也存下来。只存 size 不存归属，
        // 下次启动就分不清"用户捏的 118pt"和"默认没配过"，自动 1:1 会把它覆盖掉。
        _cfg[@"sizeManual"] = @YES;
        [self saveConfig];
        DSHPetLog(@"render", @"pet-resize", @"info", @{ @"w": @(round(CGRectGetWidth(_box.bounds))), @"ratio": @(ratio) });
    }
}

- (void)applyPetWidth:(CGFloat)w {
    CGFloat scrW = CGRectGetWidth([UIScreen mainScreen].bounds);
    w = MAX(scrW * 0.16, MIN(scrW * 0.62, w));

    // 对齐到整数设备像素（1/3 pt），否则图层落在半像素上，CA 会插值 → 发虚
    CGFloat scr = [UIScreen mainScreen].scale > 0 ? [UIScreen mainScreen].scale : 3.0;
    w = round(w * scr) / scr;

    CGSize nat = [[DSHPetPlayer shared] naturalSize];
    CGFloat ratio = (nat.width > 1.0) ? (nat.height / nat.width) : (1215.0 / 2160.0);
    CGFloat h = round(w * ratio * scr) / scr;

    CGRect f = _box.frame;
    CGPoint c = _box.center;
    f.size = CGSizeMake(w, h);
    _box.frame = f;
    _box.center = c;

    [[DSHPetPlayer shared] setDisplaySize:CGSizeMake(w, h)];
    [[DSHPetPlayer shared] refreshLayout];   // 尺寸变了立刻按当前帧重排，别等下一帧

    // 记住尺寸本身（是否"用户捏的"由 onPinch 那边置 sizeManual，别在这里判断）
    _cfg[@"size"] = @(w);
    _cfg[@"sizeRatio"] = @(w / MAX(scrW, 1.0));
    DSHPetSaveUIConfig(_cfg);
}

- (void)onPan:(UIPanGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) {
        [[DSHPetHaptics shared] fire:DSHPetHapticLight key:@"drag" minInterval:0.12];
        [[DSHPetAnimator shared] handleDragBegin];
        [self stopPhysics];
        _panStartCenter = _box.center;
        _panLastPoint = [_window convertPoint:[g locationInView:_window] toView:nil];
        _panLastT = CACurrentMediaTime();
    }

    CGPoint t = [g translationInView:_window];

    if (g.state == UIGestureRecognizerStateChanged) {
        _box.center = CGPointMake(_panStartCenter.x + t.x, _panStartCenter.y + t.y);

        // 用最近一次位移/时间算松手速度（pt/s），比 velocityInView 更贴近手感
        CFTimeInterval now = CACurrentMediaTime();
        CGPoint p = [_window convertPoint:[g locationInView:_window] toView:nil];
        CFTimeInterval dt = now - _panLastT;
        if (dt > 0.001) {
            CGPoint d = CGPointMake(p.x - _panLastPoint.x, p.y - _panLastPoint.y);
            _vel = CGPointMake(d.x / dt, d.y / dt);
            _panLastPoint = p;
            _panLastT = now;
        }
        return;
    }

    if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
        [[DSHPetAnimator shared] handleDragEnd];
        CGPoint v = [g velocityInView:_window];
        // 手势速度优先；太慢就当放下（不抛）
        CGFloat speed = hypot(v.x, v.y);
        if (speed < 250.0) { v = _vel; speed = hypot(v.x, v.y); }
        if (speed > 2400.0 && speed > 0) { v.x *= 2400.0 / speed; v.y *= 2400.0 / speed; }
        if (speed > 250.0) {
            [[DSHPetHaptics shared] fire:DSHPetHapticLight key:@"throw" minInterval:0.15];
            [self startPhysicsWithVelocity:v];
        } else {
            [self clampAndPersist];
        }
    }
}

#pragma mark - S5 物理

- (CGFloat)physGravity {
    NSDictionary *ph = _cfg[@"physics"];
    // S7 面板：重力总开关关掉时直接返回 0，掉落/投掷就不动了（宠物停在原地）
    if (ph[@"gravityEnabled"] && ![ph[@"gravityEnabled"] boolValue]) return 0.0;
    CGFloat g = [ph[@"gravity"] doubleValue];
    return g > 0 ? g : 1400.0;
}

- (CGFloat)physRestitution {
    NSDictionary *ph = _cfg[@"physics"];
    CGFloat r = [ph[@"restitution"] doubleValue];
    if (r <= 0) r = 0.62;
    return MIN(MAX(r, 0.1), 0.95);
}

- (void)startPhysicsWithVelocity:(CGPoint)v {
    [self stopPhysics];
    _vel = v;
    _lastPhysT = CACurrentMediaTime();
    _physRunning = YES;
    _physLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(stepPhysics:)];
    [_physLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    DSHPetLog(@"physics", @"throw", @"debug", @{ @"vx": @(v.x), @"vy": @(v.y) });
}

- (void)stopPhysics {
    if (_physLink) { [_physLink invalidate]; _physLink = nil; }
    _physRunning = NO;
}

- (void)stepPhysics:(CADisplayLink *)link {
    if (!_window || !_box) { [self stopPhysics]; return; }

    CFTimeInterval now = CACurrentMediaTime();
    CGFloat dt = now - _lastPhysT;
    _lastPhysT = now;
    if (dt <= 0 || dt > 0.1) dt = 1.0 / 60.0;

    CGSize b = _window.bounds.size;
    CGSize s = _box.bounds.size;
    UIEdgeInsets sa = _window.safeAreaInsets;
    CGFloat left = MAX(20.0, sa.left + 8.0);
    CGFloat right = MAX(20.0, sa.right + 8.0);
    CGFloat top = MAX(40.0, sa.top + 8.0);
    CGFloat bottom = MAX(34.0, sa.bottom + 8.0);

    CGFloat halfW = s.width / 2.0, halfH = s.height / 2.0;
    CGFloat minX = left + halfW, maxX = b.width - right - halfW;
    CGFloat minY = top + halfH, maxY = b.height - bottom - halfH;
    if (minX > maxX) minX = maxX = b.width / 2.0;
    if (minY > maxY) minY = maxY = b.height / 2.0;

    CGFloat gx = 0, gy = [self physGravity];
    NSDictionary *ph = _cfg[@"physics"];
    BOOL tilt = ph[@"tiltGravity"] ? [ph[@"tiltGravity"] boolValue] : YES;
    if (tilt && _motion && _motion.accelerometerData) {
        CMAcceleration a = _motion.accelerometerData.acceleration;
        // 竖屏：a.x 右为正，a.y 上为负（-1 表示正立）
        CGFloat mag = sqrt(a.x * a.x + a.y * a.y);
        if (mag > 0.08) {
            gx = a.x * [self physGravity];
            gy = -a.y * [self physGravity];
        }
    }

    CGFloat chunk = 1.0 / 120.0;
    CGFloat remain = dt;
    while (remain > 0) {
        CGFloat h = MIN(chunk, remain);
        remain -= h;
        _vel.y += gy * h;
        _vel.x += gx * h;
        CGPoint c = _box.center;
        c.x += _vel.x * h;
        c.y += _vel.y * h;

        CGFloat rest = [self physRestitution];

        // 撞边反馈：速度 > 300pt/s 才算"撞"，轻碰不震（方案 §S5 手势矩阵）
        if (c.x < minX) {
            c.x = minX;
            if (fabs(_vel.x) > 300.0) [[DSHPetHaptics shared] fire:DSHPetHapticHeavy key:@"wall" minInterval:0.10];
            _vel.x = -_vel.x * rest;
        }
        if (c.x > maxX) {
            c.x = maxX;
            if (fabs(_vel.x) > 300.0) [[DSHPetHaptics shared] fire:DSHPetHapticHeavy key:@"wall" minInterval:0.10];
            _vel.x = -_vel.x * rest;
        }
        if (c.y < minY) {
            c.y = minY;
            if (fabs(_vel.y) > 300.0) [[DSHPetHaptics shared] fire:DSHPetHapticHeavy key:@"wall" minInterval:0.10];
            _vel.y = -_vel.y * rest;
        }

        BOOL onFloor = NO;
        if (c.y > maxY) {
            c.y = maxY;
            onFloor = YES;
            if (_vel.y > 300.0) [[DSHPetHaptics shared] fire:DSHPetHapticMedium key:@"land" minInterval:0.12];
            if (_vel.y > 0) _vel.y = -_vel.y * rest;
            // 地面摩擦
            CGFloat fr = 1.0 - 2.5 * h;
            _vel.x *= MAX(fr, 0.0);
        }
        _box.center = c;

        if (onFloor && fabs(_vel.y) < 140.0 && fabs(_vel.x) < 12.0) {
            _vel = CGPointZero;
            [self stopPhysics];
            [self clampAndPersist];
            DSHPetLog(@"physics", @"settle", @"debug", @{ @"x": @(c.x), @"y": @(c.y) });
            return;
        }
    }
}

// 手势保护区（方案 §15.1）：顶部 40pt / 左右 20pt / 底部 34pt 不放方块，避免和系统手势抢。
// 用 safeAreaInsets 兜住带刘海/Home 条的机型，取两者更大的那个边距。
- (CGPoint)clampedCenter:(CGPoint)c inSize:(CGSize)b {
    if (b.width <= 0 || b.height <= 0) return c;
    CGFloat half = MAX(_box.bounds.size.width, _box.bounds.size.height) / 2.0;
    UIEdgeInsets sa = _window.safeAreaInsets;
    // S7 面板：贴边间距三档（0 贴紧 / 1 标准 / 2 宽松）。
    // 缺省必须是「标准」，且标准档的数值与面板上线前的老代码逐字一致，
    // 否则老用户升级后宠物会莫名其妙挪位置。
    NSInteger preset = _cfg[@"edgePreset"] ? [_cfg[@"edgePreset"] integerValue] : 1;
    if (preset < 0) preset = 0;
    if (preset > 2) preset = 2;
    CGFloat left, right, top, bottom;
    if (preset == 0) {
        left = MAX(8.0, sa.left + 4.0);
        right = MAX(8.0, sa.right + 4.0);
        top = MAX(40.0, sa.top + 4.0);
        bottom = MAX(34.0, sa.bottom + 4.0);
    } else if (preset == 2) {
        left = MAX(40.0, sa.left + 24.0);
        right = MAX(40.0, sa.right + 24.0);
        top = MAX(56.0, sa.top + 24.0);
        bottom = MAX(50.0, sa.bottom + 24.0);
    } else {
        left = MAX(20.0, sa.left + 8.0);
        right = MAX(20.0, sa.right + 8.0);
        top = MAX(40.0, sa.top + 8.0);
        bottom = MAX(34.0, sa.bottom + 8.0);
    }

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

// 绿方块 / 空桌面 的自检提示。
// 绿方块只说明"没有一帧上屏"，说不出是素材没找到、还是找到了解不出来。
// 8 秒还没上屏就把结论直接写在气泡里，别人截图就能报障，不用教他抓 syslog。
- (void)showSelfCheckBubble {
    if (!_box) return;
    if ([DSHPetPlayer shared].naturalSize.width > 0) return;   // 已经上屏了，什么都不说

    NSString *root = DSHPetFirstAssetRoot();
    NSString *tip = root.length
        ? [NSString stringWithFormat:@"素材找到了（%@），但一帧都没解出来", [root lastPathComponent]]
        : @"没找到素材包 —— 绿方块就是这个原因";
    NSString *text = [NSString stringWithFormat:@"%@\n自检报告：/var/mobile/Library/DSHPet/doctor.txt", tip];
    if (_bubble) {
        [_bubble showText:text duration:14.0];
        [self anchorBubble];
    }
    DSHPetLog(@"assets", @"selfcheck-fail", @"warn",
              @{ @"root": root ?: @"(none)", @"tip": tip });
}

// S7：设置面板改完回桌面时重新读一遍。
// 为什么不做 Darwin 通知热更新：plist-only 面板没有可执行文件，发不出通知；
// 而 Settings 退出时 SpringBoard 会收到 did-become-active，这个时机足够准，也不用常驻定时器。
- (void)applyPrefsNow {
    if (!_cfg) return;
    NSMutableDictionary *fresh = DSHPetLoadUIConfig();
    BOOL changed = [DSHPetPrefs applyToUIConfig:fresh];
    // 运行时状态以内存为准（面板不管这些键，别让磁盘上的旧值把它们盖回去）
    for (NSString *k in @[@"centerX", @"centerY", @"taps", @"windowLevel"]) {
        if (_cfg[k]) fresh[k] = _cfg[k];
    }
    // 尺寸有个例外：面板的滑块一旦存在，就是用户明确表态，必须让它赢；
    // 没有滑块时才用内存值（捏合得来的）回填，免得被磁盘旧值改回去。
    if (![DSHPetPrefs hasKey:@"sizePct"]) {
        for (NSString *k in @[@"sizeRatio", @"sizeManual"]) {
            if (_cfg[k]) fresh[k] = _cfg[k];
        }
    }
    _cfg = fresh;
    if (changed) DSHPetSaveUIConfig(_cfg);

    NSDictionary *ph = _cfg[@"physics"];
    [[DSHPetHaptics shared] setEnabled:ph[@"hapticEnabled"] ? [ph[@"hapticEnabled"] boolValue] : YES];
    [[DSHPetHaptics shared] setLevel:[ph[@"hapticLevel"] isKindOfClass:[NSString class]] ? ph[@"hapticLevel"] : @"normal"];

    // 宠物总开关：关掉只隐藏，不拆窗口——免得再开时又要等 scene 重挂
    BOOL petOn = _cfg[@"enabled"] ? [_cfg[@"enabled"] boolValue] : YES;
    [self setLayerVisible:petOn];

    // 连接：开关或地址变了就重启轮询（stop 是幂等的）
    BOOL bridgeOn = _cfg[@"bridgeEnabled"] ? [_cfg[@"bridgeEnabled"] boolValue] : YES;
    NSString *base = [_cfg[@"bridgeBase"] isKindOfClass:[NSString class]] ? _cfg[@"bridgeBase"] : nil;
    if (!base.length) base = @"https://dsh.vbox.ltd:42429";
    NSTimeInterval iv = _cfg[@"bridgeInterval"] ? [_cfg[@"bridgeInterval"] doubleValue] : 2.5;
    NSString *token = [_cfg[@"bridgeToken"] isKindOfClass:[NSString class]] ? _cfg[@"bridgeToken"] : @"";
    if (bridgeOn) {
        [[DSHPetBridge shared] startWithBase:base token:token interval:iv];
    } else {
        [[DSHPetBridge shared] stop];
    }

    // 尺寸滑块：宽高变了才重排，否则每次回前台都白算一遍（还会多写一次 ui.json）
    if (_box && _window) {
        CGFloat scrW = CGRectGetWidth([UIScreen mainScreen].bounds);
        CGFloat wantW = _cfg[@"sizeRatio"] ? scrW * [_cfg[@"sizeRatio"] doubleValue] : _box.bounds.size.width;
        if (fabs(wantW - _box.bounds.size.width) > 0.5) {
            [self applySizeFromConfig];
        } else {
            // 贴边间距档可能变了：立刻按新档重新夹一次，别等下次拖拽
            [self relayoutAndSettle:NO];
        }
    }
    // S6c：多开配置（开关 / 上限 / 是否每只跟一个会话）变了 → 该生的生、该收的收
    if (_window) {
        [[DSHPetCrew shared] reconcileWithBounds:_window.bounds config:_cfg];
    }

    DSHPetLog(@"prefs", @"reload", @"info", @{ @"pet": @(petOn), @"bridge": @(bridgeOn),
                                                @"edge": _cfg[@"edgePreset"] ?: @"(default)",
                                                @"changed": @(changed) });
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

// S7b：尺寸滑块。attach 只在启动时算一次尺寸，面板改了以后要走这条路重算，
// 再按新尺寸重新夹一次位置（否则宠物变大会顶出屏幕）。
// 高度永远跟随素材真实比例：写死 2160x1215 会在不同比例素材上留大片透明边。
- (void)applySizeFromConfig {
    if (!_box || !_window) return;
    CGFloat scrW = CGRectGetWidth([UIScreen mainScreen].bounds);
    if (scrW < 1.0) return;
    CGFloat minW = scrW * 0.16;
    CGFloat maxW = scrW * 0.62;
    CGFloat w = _cfg[@"sizeRatio"] ? scrW * [_cfg[@"sizeRatio"] doubleValue] : _box.bounds.size.width;
    if (w > maxW) w = maxW;
    if (w < minW) w = minW;
    CGSize nat = [[DSHPetPlayer shared] naturalSize];
    CGFloat h = (nat.width > 1.0 && nat.height > 1.0)
        ? round(w * nat.height / nat.width)
        : round(w * 1215.0 / 2160.0);
    CGRect f = _box.frame;
    f.size = CGSizeMake(w, h);
    _box.frame = f;
    [[DSHPetPlayer shared] setDisplaySize:CGSizeMake(w, h)];

    CGSize b = _window.bounds.size;
    if (b.width > 1.0 && b.height > 1.0) {
        CGPoint c = [self clampedCenter:_box.center inSize:b];
        _box.center = c;
        _cfg[@"centerX"] = @(c.x / b.width);
        _cfg[@"centerY"] = @(c.y / b.height);
    }
    _cfg[@"size"] = @(w);
    DSHPetSaveUIConfig(_cfg);
    DSHPetLog(@"prefs", @"size", @"info", @{ @"w": @(w), @"h": @(h),
                                             @"ratio": _cfg[@"sizeRatio"] ?: @"(none)" });
}

- (CGRect)sceneBoundsIfValid {    if (!_scene) return CGRectZero;
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

    // S6c：额外宠物跟着主宠一起重排（旋转/分屏时它们也得夹回可见区，否则会飘到屏幕外）
    [[DSHPetCrew shared] relayoutInBounds:CGRectMake(0.0, 0.0, b.width, b.height) settle:settle];
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

- (void)hideBoxChrome {
    if (!_box) return;
    _box.backgroundColor = [UIColor clearColor];
    _box.layer.cornerRadius = 0.0;
    _box.layer.borderWidth = 0.0;
    _box.layer.borderColor = [UIColor clearColor].CGColor;
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
        if (!visible) {
        // 总开关关掉：额外宠物一起收掉。窗口藏起来看不到，但它们的播放器和物理还在跑，
        // 不收就是白烧电。
        [[DSHPetCrew shared] stop];
    }
[CATransaction commit];
}

- (void)detach {
    if (!_window) return;
    if (_firstFrameObs) {
        [[NSNotificationCenter defaultCenter] removeObserver:_firstFrameObs];
        _firstFrameObs = nil;
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _window.hidden = YES;
    _window = nil;
    _box = nil;
    DSHPetLog(@"render", @"detach", @"info", nil);
}

@end