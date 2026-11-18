#import "DSHPetWalk.h"
#import "DSHPetBoot.h"
#import <QuartzCore/QuartzCore.h>

// 到点判定：2pt 以内就算到了。太小会在目标附近抖，太大看着像瞬移。
static const CGFloat kArriveDist = 2.0;
// 走路刷新率：30Hz 足够（人眼对匀速直线运动的抖动不敏感），
// 比 60Hz 省一半唤醒次数 —— 桌宠是常驻进程，这个账要算。
static const NSTimeInterval kTickInterval = 1.0 / 30.0;
// 两次行走之间的间隔（秒）。上游是 8～18s 的休息，这里按自己的节奏给宽一点，
// 太频繁会像"抽筋"，太稀疏用户以为坏了。
static const CGFloat kRestMin = 6.0;
static const CGFloat kRestMax = 16.0;

@interface DSHPetWalk ()
@property (nonatomic, weak, nullable) UIView *pet;
@property (nonatomic, weak, nullable) UIView *host;
@property (nonatomic, strong, nullable) NSTimer *tickTimer;
// S-FIX3：休息用一次性定时器。以前是"一个 30Hz 常开定时器，没到点就 return"，
// 等于呆着也每秒醒 30 次 —— 常驻进程里这是白烧电，也是最容易被忽略的发热源。
// 改成：走路时才开 30Hz；到达就停表，改由一个 6～16s 的一次性定时器把下一次叫醒。
@property (nonatomic, strong, nullable) NSTimer *restTimer;
@property (nonatomic, assign) BOOL walking;
@property (nonatomic, assign) BOOL paused;
@property (nonatomic, assign) CGFloat targetX;
@property (nonatomic, assign) CGFloat targetY;
@property (nonatomic, assign) CFTimeInterval nextWalkAt;
- (void)tick;
- (void)beginWalk;
- (void)finishWalk;
- (CGFloat)clampX:(CGFloat)x;
- (CGFloat)clampY:(CGFloat)y;
- (void)scheduleNextWalk;
- (void)startTickTimer;
- (void)stopTickTimer;
- (void)scheduleRestTimer;
- (void)onRestTimer:(NSTimer *)t;
@end

@implementation DSHPetWalk

- (instancetype)initWithPetView:(UIView *)petView hostView:(UIView *)hostView {
    self = [super init];
    if (self) {
        _pet = petView;
        _host = hostView;
        _enabled = YES;
        _speed = 76.0;
        _margin = 24.0;
        _minDist = 60.0;
        _maxDist = 240.0;
        _nextWalkAt = 0;
    }
    return self;
}

- (void)dealloc {
    [_tickTimer invalidate];
    _tickTimer = nil;
    [_restTimer invalidate];
    _restTimer = nil;
}

- (BOOL)isWalking {
    return self.walking;
}

- (void)start {
    if (_tickTimer != nil || _restTimer != nil) {
        return;
    }
    [self scheduleRestTimer];
    DSHPetLog(@"walk", @"start", @"info", nil);
}

- (void)startTickTimer {
    if (_tickTimer) return;
    _tickTimer = [NSTimer scheduledTimerWithTimeInterval:kTickInterval
                                                  target:self
                                                selector:@selector(onTimer:)
                                                userInfo:nil
                                                 repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:_tickTimer forMode:NSRunLoopCommonModes];
}

- (void)stopTickTimer {
    [_tickTimer invalidate];
    _tickTimer = nil;
}

- (void)scheduleRestTimer {
    [_restTimer invalidate];
    CGFloat rest = kRestMin + (CGFloat)arc4random_uniform(10000) / 10000.0 * (kRestMax - kRestMin);
    _nextWalkAt = CACurrentMediaTime() + rest;
    _restTimer = [NSTimer scheduledTimerWithTimeInterval:rest
                                                 target:self
                                               selector:@selector(onRestTimer:)
                                               userInfo:nil
                                                repeats:NO];
    [[NSRunLoop mainRunLoop] addTimer:_restTimer forMode:NSRunLoopCommonModes];
}

- (void)onRestTimer:(NSTimer *)t {
    _restTimer = nil;
    if (_paused || !self.enabled) {
        return;
    }
    [self beginWalk];
    if (_walking) {
        [self startTickTimer];
    } else {
        // 被挤住 / 太短，没走成：再歇一轮
        [self scheduleRestTimer];
    }
}

- (void)onTimer:(NSTimer *)t {
    [self tick];
}

- (void)stop {
    [self stopTickTimer];
    [_restTimer invalidate];
    _restTimer = nil;
    if (_walking) {
        _walking = NO;
        if (_onStopWalking) {
            _onStopWalking();
        }
    }
    DSHPetLog(@"walk", @"stop", @"info", nil);
}

- (void)pause {
    if (_paused) {
        return;
    }
    _paused = YES;
    [_restTimer invalidate];
    _restTimer = nil;
    [self stopTickTimer];
    if (_walking) {
        _walking = NO;
        if (_onStopWalking) {
            _onStopWalking();
        }
    }
    DSHPetLog(@"walk", @"pause", @"debug", nil);
}

- (void)resume {
    if (!_paused) {
        return;
    }
    _paused = NO;
    // 落地后别立刻又走，先喘口气
    [self scheduleRestTimer];
    DSHPetLog(@"walk", @"resume", @"debug", nil);
}

- (void)scheduleNextWalk {
    CGFloat rest = kRestMin + (CGFloat)arc4random_uniform(10000) / 10000.0 * (kRestMax - kRestMin);
    _nextWalkAt = CACurrentMediaTime() + rest;
}

- (CGFloat)clampX:(CGFloat)x {
    UIView *host = _host;
    UIView *pet = _pet;
    if (!host || !pet) {
        return x;
    }
    CGRect b = host.bounds;
    CGFloat halfW = pet.bounds.size.width * 0.5;
    CGFloat lo = _margin + halfW;
    CGFloat hi = b.size.width - _margin - halfW;

    // S-M1b：按分区再收一次边界。收完发现区间反了（宠物太大 / 分区太窄）
    // 就退回全屏，宁可分区不生效，也别让她卡在边界上来回抖。
    if (_zone != 0) {
        CGFloat fullLo = lo;
        CGFloat fullHi = hi;
        if (_zone == 1) {
            hi = MIN(hi, b.size.width * 0.5 - halfW);
        } else if (_zone == 2) {
            lo = MAX(lo, b.size.width / 3.0 + halfW);
            hi = MIN(hi, b.size.width * 2.0 / 3.0 - halfW);
        } else if (_zone == 3) {
            lo = MAX(lo, b.size.width * 0.5 + halfW);
        }
        if (hi < lo) {
            lo = fullLo;
            hi = fullHi;
        }
    }
    if (hi < lo) {
        // 宠物比可用宽度还大（用户拉到 62%），居中就好，别乱跳
        return b.size.width * 0.5;
    }
    return MIN(MAX(x, lo), hi);
}

// 纵向边界。只有 zone 4/5 用得上，而且必须配合「悬停模式」——
// 否则物理层每帧把她拉回地面，这里算得再准也没用。
- (CGFloat)clampY:(CGFloat)y {
    UIView *host = _host;
    UIView *pet = _pet;
    if (!host || !pet) {
        return y;
    }
    CGRect b = host.bounds;
    CGFloat halfH = pet.bounds.size.height * 0.5;
    CGFloat lo = _margin + halfH;
    CGFloat hi = b.size.height - _margin - halfH;
    if (hi < lo) {
        return b.size.height * 0.5;
    }
    if (_zone == 4) {
        // 上半屏
        hi = MIN(hi, b.size.height * 0.55 - halfH);
    } else if (_zone == 5) {
        // 下半屏
        lo = MAX(lo, b.size.height * 0.45 + halfH);
    }
    if (hi < lo) {
        lo = _margin + halfH;
        hi = b.size.height - _margin - halfH;
    }
    return MIN(MAX(y, lo), hi);
}

- (void)beginWalk {
    UIView *host = _host;
    UIView *pet = _pet;
    if (!host || !pet) {
        return;
    }
    CGFloat curX = pet.center.x;
    CGFloat lo = [self clampX:-1e9];
    CGFloat hi = [self clampX:1e9];

    // 目标：在 minDist～maxDist 之外挑一个方向，撞到边界就反向。
    // 上游是"随机取点再挑选"，这里改成"按距离挑方向"，
    // 好处是每次走的距离可控，不会出现"挪 3pt 也算走一趟"。
    CGFloat dist = _minDist + (CGFloat)arc4random_uniform(10000) / 10000.0 * (_maxDist - _minDist);
    BOOL goRight = (arc4random_uniform(2) == 1);
    CGFloat target = goRight ? (curX + dist) : (curX - dist);
    if (target > hi || target < lo) {
        target = goRight ? (curX - dist) : (curX + dist);
    }

    // 避让气泡：气泡是浮层，不挡点击，但停在她正上方会互相压字。
    // 做法是把落在气泡矩形（左右各外扩 kAvoidPad）里的目标点推到最近的一侧，
    // 而不是整段放弃——放弃会让"想往右边走"变成"原地不动"，看起来像卡住。
    CGRect avoid = CGRectZero;
    if (_avoidRectProvider) {
        avoid = _avoidRectProvider();
    }
    if (!CGRectIsEmpty(avoid)) {
        CGFloat pad = 40.0;
        CGFloat left = avoid.origin.x - pad;
        CGFloat right = avoid.origin.x + avoid.size.width + pad;
        if (target > left && target < right) {
            CGFloat toLeft = target - left;
            CGFloat toRight = right - target;
            target = (toLeft <= toRight) ? left : right;
        }
    }

    target = [self clampX:target];

    // 纵向目标：只有 zone 4/5 才挑新高度。其他分区保持当前 y——
    // y 是物理层的地盘，行走不碰，除非用户显式开了纵向分区（隐含要求悬停模式）。
    CGFloat targetY = pet.center.y;
    if (_zone >= 4) {
        CGFloat yLo = [self clampY:-1e9];
        CGFloat yHi = [self clampY:1e9];
        if (yHi > yLo) {
            targetY = yLo + (CGFloat)arc4random_uniform(10000) / 10000.0 * (yHi - yLo);
        }
    }

    BOOL tooShortX = (fabs(target - curX) < _minDist * 0.5);
    BOOL tooShortY = (_zone < 4) || (fabs(targetY - pet.center.y) < _minDist * 0.5);
    if (tooShortX && tooShortY) {
        // 横向被挤住、纵向也不用走，等下一轮
        [self scheduleNextWalk];
        return;
    }

    _targetX = target;
    _targetY = targetY;
    _walking = YES;
    if (_onStartWalking) {
        _onStartWalking();
    }
    DSHPetLog(@"walk", @"begin", @"debug",
              @{ @"from": @((NSInteger)curX), @"to": @((NSInteger)target),
                 @"y": @((NSInteger)targetY) });
}

- (void)finishWalk {
    _walking = NO;
    // 到了就停表 —— 休息期间不再有任何周期唤醒（S-FIX3）
    [self stopTickTimer];
    if (_onStopWalking) {
        _onStopWalking();
    }
    [self scheduleRestTimer];
}

- (void)tick {
    if (_paused) {
        return;
    }
    if (self.enabled == NO) {
        if (_walking) {
            [self finishWalk];
        }
        return;
    }

    CFTimeInterval now = CACurrentMediaTime();
    if (!_walking) {
        if (now >= _nextWalkAt) {
            [self beginWalk];
        }
        return;
    }

    UIView *pet = _pet;
    if (!pet) {
        [self finishWalk];
        return;
    }

    CGFloat curX = pet.center.x;
    CGFloat dx = _targetX - curX;

    // 纵向（zone 4/5）才改 y。前提是宿主已开「悬停模式」，物理层不再抢 center.y；
    // 没开的时候这里照样只动 x —— 宁可分区不生效，也不能和重力对着拉扯。
    CGFloat dy = 0;
    BOOL vertical = (_zone >= 4);
    if (vertical) {
        dy = _targetY - pet.center.y;
    }

    if (fabs(dx) <= kArriveDist && fabs(dy) <= kArriveDist) {
        [self finishWalk];
        return;
    }
    CGFloat step = _speed * (CGFloat)kTickInterval;
    if (fabs(dx) < step) {
        step = fabs(dx);
    }
    CGFloat nx = curX + (dx > 0 ? step : -step);
    nx = [self clampX:nx];

    CGPoint c = pet.center;
    c.x = nx;
    if (vertical) {
        // 纵向走慢一点：漂浮感靠"慢"，快了像在弹射
        CGFloat vstep = MIN(fabs(dy), step * 0.6);
        CGFloat ny = c.y + (dy > 0 ? vstep : -vstep);
        c.y = [self clampY:ny];
    }
    pet.center = c;
}

@end
