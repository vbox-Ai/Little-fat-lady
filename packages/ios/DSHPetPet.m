#import "DSHPetPet.h"
#import "DSHPetBoot.h"
#import "DSHPetPlayer.h"
#import "DSHPetAnimator.h"
#import "DSHPetHaptics.h"
#import "DSHPetCrew.h"

#pragma mark - 边缘间距（与主宠同一套三档，数值逐字一致，别单独改）

static UIEdgeInsets DSHPetPetMargins(UIEdgeInsets sa, NSInteger preset) {
    if (preset < 0) preset = 0;
    if (preset > 2) preset = 2;
    UIEdgeInsets m;
    if (preset == 0) {
        m.left = MAX(8.0, sa.left + 4.0);
        m.right = MAX(8.0, sa.right + 4.0);
        m.top = MAX(40.0, sa.top + 4.0);
        m.bottom = MAX(34.0, sa.bottom + 4.0);
    } else if (preset == 2) {
        m.left = MAX(40.0, sa.left + 24.0);
        m.right = MAX(40.0, sa.right + 24.0);
        m.top = MAX(56.0, sa.top + 24.0);
        m.bottom = MAX(50.0, sa.bottom + 24.0);
    } else {
        m.left = MAX(20.0, sa.left + 8.0);
        m.right = MAX(20.0, sa.right + 8.0);
        m.top = MAX(40.0, sa.top + 8.0);
        m.bottom = MAX(34.0, sa.bottom + 8.0);
    }
    return m;
}

@interface DSHPetPet ()
@property (nonatomic, strong, readwrite) UIView *box;
@property (nonatomic, strong, readwrite) DSHPetPlayer *player;
@property (nonatomic, strong, readwrite) DSHPetAnimator *animator;
@property (nonatomic, assign, readwrite) CGSize petSize;
@property (nonatomic, assign) CGPoint center;
@property (nonatomic, copy) NSString *assetDir;
@property (nonatomic, assign) CGFloat sizeRatio;
@property (nonatomic, strong) NSDictionary *cfg;
@property (nonatomic, weak) UIView *hostView;
/// 归一化倾斜分量（-1..1），crew 的 accelerometer 回调写进来；nil 时按"正立"算。
@property (nonatomic, assign) CGPoint tilt;
@property (nonatomic, assign) BOOL tiltValid;
@end

@implementation DSHPetPet {
    CGPoint _center;        // 自己在下面实现了 setCenter:/center，所以 ivar 得手写
    CGPoint _vel;
    BOOL _falling;          // 出生下落中：落地前不参与排斥，免得刚出生就被推歪
    BOOL _panning;
    CGPoint _panStartCenter;
    CGPoint _panLastPoint;
    CFTimeInterval _panLastT;
    BOOL _sizedOnce;
}

- (instancetype)initWithHostView:(UIView *)host
                        assetDir:(NSString *)assetDir
                       sizeRatio:(CGFloat)ratio
                          config:(NSDictionary *)cfg {
    self = [super init];
    if (!self) return nil;
    _hostView = host;
    _assetDir = [assetDir copy];
    _sizeRatio = ratio > 0.05 ? ratio : 0.30;
    _cfg = cfg ?: @{};
    _center = CGPointMake(-999, -999);

    _box = [[UIView alloc] initWithFrame:CGRectMake(-999, -999, 10, 10)];
    _box.backgroundColor = [UIColor clearColor];
    _box.opaque = NO;
    _box.userInteractionEnabled = YES;
    _box.layer.opaque = NO;
    _box.layer.shouldRasterize = NO;
    _box.hidden = YES;

    _player = [[DSHPetPlayer alloc] init];
    _animator = [[DSHPetAnimator alloc] initWithPlayer:_player];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onTap:)];
    [_box addGestureRecognizer:tap];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPan:)];
    [_box addGestureRecognizer:pan];

    [host addSubview:_box];

    CGSize sz = [self sizeForHostWidth:CGRectGetWidth(host.bounds)];
    _petSize = sz;
    _box.frame = CGRectMake(0, 0, sz.width, sz.height);

    [_player attachToHostView:_box size:sz];
    [_animator startWithDirectory:_assetDir ?: @"/var/mobile/Library/DSHPet/assets"];
    return self;
}

#pragma mark - 尺寸

- (CGSize)sizeForHostWidth:(CGFloat)hostW {
    if (hostW < 1.0) hostW = 393.0;
    CGFloat scr = [UIScreen mainScreen].scale > 0 ? [UIScreen mainScreen].scale : 3.0;
    CGFloat w = round(hostW * _sizeRatio * scr) / scr;
    CGSize nat = [_player naturalSize];
    CGFloat ratio = (nat.width > 1.0) ? (nat.height / nat.width) : (1215.0 / 2160.0);
    CGFloat h = round(w * ratio * scr) / scr;
    return CGSizeMake(w, h);
}

- (void)applySizeForHostWidth:(CGFloat)hostW {
    CGSize sz = [self sizeForHostWidth:hostW];
    if (CGSizeEqualToSize(sz, _petSize) && _sizedOnce) return;
    _sizedOnce = YES;
    _petSize = sz;
    CGRect f = _box.frame;
    f.size = sz;
    _box.frame = f;
    [_player setDisplaySize:sz];
    [_player refreshLayout];
}

- (UIEdgeInsets)margins {
    UIEdgeInsets sa = UIEdgeInsetsZero;
    if ([_hostView isKindOfClass:[UIWindow class]]) sa = ((UIWindow *)_hostView).safeAreaInsets;
    NSInteger preset = _cfg[@"edgePreset"] ? [_cfg[@"edgePreset"] integerValue] : 1;
    return DSHPetPetMargins(sa, preset);
}

- (CGPoint)clampCenter:(CGPoint)c inBounds:(CGRect)b {
    if (b.size.width <= 1.0 || b.size.height <= 1.0) return c;
    UIEdgeInsets m = [self margins];
    CGFloat halfW = _petSize.width / 2.0, halfH = _petSize.height / 2.0;
    CGFloat minX = m.left + halfW, maxX = b.size.width - m.right - halfW;
    CGFloat minY = m.top + halfH, maxY = b.size.height - m.bottom - halfH;
    if (minX > maxX) minX = maxX = b.size.width / 2.0;
    if (minY > maxY) minY = maxY = b.size.height / 2.0;
    c.x = MAX(minX, MIN(maxX, c.x));
    c.y = MAX(minY, MIN(maxY, c.y));
    return c;
}

- (CGPoint)center { return _center; }

- (void)setCenter:(CGPoint)center {
    _center = center;
    _box.center = center;
}

#pragma mark - 出生 / 布局

- (void)dropIntoBounds:(CGRect)hostBounds {
    if (hostBounds.size.width <= 1.0) return;
    [self applySizeForHostWidth:hostBounds.size.width];

    UIEdgeInsets m = [self margins];
    CGFloat halfW = _petSize.width / 2.0, halfH = _petSize.height / 2.0;
    CGFloat minX = m.left + halfW + 8.0;
    CGFloat maxX = hostBounds.size.width - m.right - halfW - 8.0;
    if (maxX < minX) minX = maxX = hostBounds.size.width / 2.0;

    uint32_t span = (uint32_t)MIN(100000.0, MAX(1.0, floor(maxX - minX)));
    CGFloat x = minX + (CGFloat)arc4random_uniform(span);
    CGFloat y = -halfH - 24.0;   // 屏幕外正上方 → 掉进来

    _box.hidden = NO;
    self.center = CGPointMake(x, y);
    _vel = CGPointMake(0, 260.0);
    _falling = YES;
    DSHPetLog(@"crew", @"drop", @"info", @{ @"x": @(round(x)), @"y": @(round(y)),
                                            @"w": @(round(_petSize.width)), @"h": @(round(_petSize.height)) });
}

- (void)relayoutInBounds:(CGRect)hostBounds settle:(BOOL)settle {
    if (hostBounds.size.width <= 1.0) return;
    [self applySizeForHostWidth:hostBounds.size.width];
    self.center = [self clampCenter:_center inBounds:hostBounds];
    if (settle) { _vel = CGPointZero; _falling = NO; }
}

#pragma mark - 物理

- (CGFloat)gravity {
    NSDictionary *ph = _cfg[@"physics"];
    if (ph[@"gravityEnabled"] && ![ph[@"gravityEnabled"] boolValue]) return 0.0;
    CGFloat g = [ph[@"gravity"] doubleValue];
    return g > 0 ? g : 1400.0;
}

- (CGFloat)restitution {
    CGFloat r = [_cfg[@"physics"][@"restitution"] doubleValue];
    if (r <= 0) r = 0.62;
    return MIN(MAX(r, 0.1), 0.95);
}

- (BOOL)stepWithDt:(CFTimeInterval)dt others:(NSArray<NSValue *> *)others host:(CGRect)host config:(nullable NSDictionary *)cfg {
    if (!_box || _panning) return NO;
    if (cfg) _cfg = cfg;
    if (host.size.width <= 1.0) return NO;

    if (dt <= 0 || dt > 0.1) dt = 1.0 / 60.0;

    // 首帧还没到的时候 naturalSize 是 0，尺寸只能先按默认比例猜。等真尺寸到了要校正一次，
    // 否则第一只宠物会以错误的宽高比落地（后面拖一下就突然变形，看着像 bug）。
    CGSize nat = [_player naturalSize];
    if (nat.width > 1.0 && nat.height > 1.0) {
        CGFloat scr = [UIScreen mainScreen].scale > 0 ? [UIScreen mainScreen].scale : 3.0;
        CGFloat wantH = round(_petSize.width * nat.height / nat.width * scr) / scr;
        if (fabs(wantH - _petSize.height) > 0.5) [self applySizeForHostWidth:host.size.width];
    }

    CGFloat g = [self gravity];

    // 倾斜重力：和主宠同一套语义（a.x 右为正、a.y 立为正时读 -a.y），
    // 但倾斜值是 crew 的 accelerometer 回调统一算好写进来的，这里只读。
    NSDictionary *ph = _cfg[@"physics"];
    BOOL tilt = ph[@"tiltGravity"] ? [ph[@"tiltGravity"] boolValue] : YES;
    CGFloat gx = 0, gy = g;
    if (tilt && _tiltValid) {
        gx = _tilt.x * g;
        gy = _tilt.y * g;
    }

    UIEdgeInsets m = [self margins];
    CGFloat halfW = _petSize.width / 2.0, halfH = _petSize.height / 2.0;
    CGFloat minX = m.left + halfW, maxX = host.size.width - m.right - halfW;
    CGFloat minY = m.top + halfH, maxY = host.size.height - m.bottom - halfH;
    if (minX > maxX) minX = maxX = host.size.width / 2.0;
    if (minY > maxY) minY = maxY = host.size.height / 2.0;

    // 轻微排斥：和别的宠物太近就往远侧推，推力跟重叠量成正比，不做刚体碰撞（否则会互弹发疯）
    if (!_falling && others.count) {
        for (NSValue *v in others) {
            CGRect o = v.CGRectValue;
            CGFloat dx = _center.x - CGRectGetMidX(o);
            CGFloat dy = _center.y - CGRectGetMidY(o);
            CGFloat needX = (_petSize.width + CGRectGetWidth(o)) * 0.5 + 6.0;
            CGFloat needY = (_petSize.height + CGRectGetHeight(o)) * 0.5 + 6.0;
            CGFloat ox = needX - fabs(dx);
            CGFloat oy = needY - fabs(dy);
            if (ox > 0 && oy > 0) {
                // 只沿"更容易分开"的那个轴推，避免对角互推打转
                if (oy / needY > ox / needX) {
                    gy -= (dy >= 0 ? 1.0 : -1.0) * MIN(oy, 60.0) * 9.0;
                } else {
                    gx -= (dx >= 0 ? 1.0 : -1.0) * MIN(ox, 80.0) * 7.0;
                }
            }
        }
    }

    CGFloat chunk = 1.0 / 120.0;
    CGFloat remain = dt;
    BOOL wallHit = NO, moving = NO;
    while (remain > 0) {
        CGFloat h = MIN(chunk, remain);
        remain -= h;
        _vel.y += gy * h;
        _vel.x += gx * h;
        CGPoint c = _center;
        c.x += _vel.x * h;
        c.y += _vel.y * h;
        CGFloat rest = [self restitution];

        if (c.x < minX) { c.x = minX; if (fabs(_vel.x) > 300.0) wallHit = YES; _vel.x = -_vel.x * rest; }
        if (c.x > maxX) { c.x = maxX; if (fabs(_vel.x) > 300.0) wallHit = YES; _vel.x = -_vel.x * rest; }
        if (c.y < minY) { c.y = minY; _vel.y = -_vel.y * rest; if (_falling) _falling = NO; }

        if (c.y > maxY) {
            c.y = maxY;
            if (_falling) {
                _falling = NO;
                if (_vel.y > 300.0) [[DSHPetHaptics shared] fire:DSHPetHapticMedium key:@"land" minInterval:0.12];
            }
            if (_vel.y > 0) _vel.y = -_vel.y * rest;
            CGFloat fr = 1.0 - 2.5 * h;
            _vel.x *= MAX(fr, 0.0);
        }
        self.center = c;
        if (fabs(_vel.x) > 3.0 || fabs(_vel.y) > 3.0) moving = YES;
    }
    if (wallHit) [[DSHPetHaptics shared] fire:DSHPetHapticHeavy key:@"wall" minInterval:0.10];

    BOOL atFloor = (_center.y >= maxY - 0.5);
    if (atFloor && fabs(_vel.y) < 120.0 && fabs(_vel.x) < 10.0) {
        _vel = CGPointZero;
        moving = NO;
    }
    return moving;
}

#pragma mark - 手势

- (void)onTap:(UITapGestureRecognizer *)g {
    [[DSHPetHaptics shared] fire:DSHPetHapticLight key:@"tap" minInterval:0.10];
    [self.animator handleTap];
    [[NSNotificationCenter defaultCenter] postNotificationName:DSHPetCrewWakeNotification object:nil];
    __weak DSHPetPet *weakSelf = self;
    [UIView animateWithDuration:0.12 animations:^{
        weakSelf.box.transform = CGAffineTransformMakeScale(1.12, 1.12);
    } completion:^(BOOL f) {
        [UIView animateWithDuration:0.12 animations:^{ weakSelf.box.transform = CGAffineTransformIdentity; }];
    }];
}

- (void)onPan:(UIPanGestureRecognizer *)g {
    UIView *host = _hostView;
    if (!host) return;

    if (g.state == UIGestureRecognizerStateBegan) {
        _panning = YES;
        _falling = NO;
        _vel = CGPointZero;
        [[DSHPetHaptics shared] fire:DSHPetHapticLight key:@"drag" minInterval:0.12];
        [self.animator handleDragBegin];
        _panStartCenter = _center;
        _panLastPoint = [g locationInView:host];
        _panLastT = CACurrentMediaTime();
        return;
    }

    if (g.state == UIGestureRecognizerStateChanged) {
        CGPoint t = [g translationInView:host];
        self.center = CGPointMake(_panStartCenter.x + t.x, _panStartCenter.y + t.y);
        CFTimeInterval now = CACurrentMediaTime();
        CGPoint p = [g locationInView:host];
        CFTimeInterval dt = now - _panLastT;
        if (dt > 0.001) {
            _vel = CGPointMake((p.x - _panLastPoint.x) / dt, (p.y - _panLastPoint.y) / dt);
            _panLastPoint = p;
            _panLastT = now;
        }
        return;
    }

    if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
        _panning = NO;
        [self.animator handleDragEnd];
        CGPoint v = [g velocityInView:host];
        CGFloat speed = hypot(v.x, v.y);
        if (speed < 250.0) { v = _vel; speed = hypot(v.x, v.y); }
        if (speed > 2400.0 && speed > 0) { v.x *= 2400.0 / speed; v.y *= 2400.0 / speed; }
        if (speed > 250.0) {
            _vel = v;   // 交给物理继续走，crew 的 displayLink 会接着 step
            [[DSHPetHaptics shared] fire:DSHPetHapticLight key:@"throw" minInterval:0.15];
            [[NSNotificationCenter defaultCenter] postNotificationName:DSHPetCrewWakeNotification object:nil];
        } else {
            _vel = CGPointZero;
        }
    }
}

#pragma mark - crew 内部用

- (void)crewSetTilt:(CGPoint)t valid:(BOOL)valid {
    _tilt = t;
    _tiltValid = valid;
}

- (CGRect)frame {
    return _box ? _box.frame : CGRectZero;
}

- (void)pause {
    [self.player pause];
    _vel = CGPointZero;
    _panning = NO;
}

- (void)invalidate {
    [self.animator stop];
    // 播放器的 layer 挂在 _box.layer 上，_box 一走整套一起没，不用单独拆
    [_box removeFromSuperview];
    _box = nil;
}

@end
