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
@property (nonatomic, assign) BOOL walking;
@property (nonatomic, assign) BOOL paused;
@property (nonatomic, assign) CGFloat targetX;
@property (nonatomic, assign) CFTimeInterval nextWalkAt;
- (void)tick;
- (void)beginWalk;
- (void)finishWalk;
- (CGFloat)clampX:(CGFloat)x;
- (void)scheduleNextWalk;
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
}

- (BOOL)isWalking {
    return self.walking;
}

- (void)start {
    if (_tickTimer != nil) {
        return;
    }
    [self scheduleNextWalk];
    __weak DSHPetWalk *weakSelf = self;
    _tickTimer = [NSTimer scheduledTimerWithTimeInterval:kTickInterval
                                                  target:self
                                                selector:@selector(onTimer:)
                                                userInfo:nil
                                                 repeats:YES];
    // 让 NSTimer 在菜单拖动（UITrackingRunLoopMode）时也走，否则一滑菜单她就僵住
    [[NSRunLoop mainRunLoop] addTimer:_tickTimer forMode:NSRunLoopCommonModes];
    (void)weakSelf;
    DSHPetLog(@"walk", @"start", @"info", nil);
}

- (void)onTimer:(NSTimer *)t {
    [self tick];
}

- (void)stop {
    [_tickTimer invalidate];
    _tickTimer = nil;
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
    [self scheduleNextWalk];
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
    if (hi < lo) {
        // 宠物比可用宽度还大（用户拉到 62%），居中就好，别乱跳
        return b.size.width * 0.5;
    }
    return MIN(MAX(x, lo), hi);
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
    target = [self clampX:target];

    if (fabs(target - curX) < _minDist * 0.5) {
        // 两头都挤着，走不动，等下一轮
        [self scheduleNextWalk];
        return;
    }

    _targetX = target;
    _walking = YES;
    if (_onStartWalking) {
        _onStartWalking();
    }
    DSHPetLog(@"walk", @"begin", @"debug",
              @{ @"from": @((NSInteger)curX), @"to": @((NSInteger)target) });
}

- (void)finishWalk {
    _walking = NO;
    if (_onStopWalking) {
        _onStopWalking();
    }
    [self scheduleNextWalk];
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
    if (fabs(dx) <= kArriveDist) {
        [self finishWalk];
        return;
    }
    CGFloat step = _speed * (CGFloat)kTickInterval;
    if (fabs(dx) < step) {
        step = fabs(dx);
    }
    CGFloat nx = curX + (dx > 0 ? step : -step);
    nx = [self clampX:nx];

    // 只改 x，y 留给物理。见头文件里"两边都改 y 会打架"那条。
    CGPoint c = pet.center;
    c.x = nx;
    pet.center = c;
}

@end
