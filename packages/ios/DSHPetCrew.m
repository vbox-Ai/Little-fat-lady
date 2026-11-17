#import "DSHPetCrew.h"
#import "DSHPetBoot.h"
#import "DSHPetPet.h"
#import "DSHPetBridge.h"
#import <CoreMotion/CoreMotion.h>

NSString *const DSHPetCrewWakeNotification = @"DSHPetCrewWake";

@interface DSHPetCrew ()
@property (nonatomic, strong) NSMutableArray<DSHPetPet *> *pets;
@property (nonatomic, weak) UIView *host;
@property (nonatomic, copy) NSString *assetDir;
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic, strong) CMMotionManager *motion;
@property (nonatomic, copy) NSDictionary *cfg;
@end

@implementation DSHPetCrew {
    CFTimeInterval _lastT;
    NSUInteger _idleTicks;
    CGPoint _tilt;
    BOOL _tiltValid;
    id _wakeObs;
}

+ (instancetype)shared {
    static DSHPetCrew *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[DSHPetCrew alloc] init]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _pets = [NSMutableArray array];
    return self;
}

#pragma mark - 生命周期

- (void)startInHost:(UIView *)host assetDir:(NSString *)assetDir bounds:(CGRect)bounds config:(NSDictionary *)cfg {
    self.host = host;
    self.assetDir = assetDir ?: @"/var/mobile/Library/DSHPet/assets";
    self.cfg = cfg ?: @{};

    if (!_motion) {
        _motion = [[CMMotionManager alloc] init];
        if (_motion.isAccelerometerAvailable) {
            _motion.accelerometerUpdateInterval = 1.0 / 30.0;
            __weak DSHPetCrew *weakSelf = self;
            [_motion startAccelerometerUpdatesToQueue:[NSOperationQueue mainQueue]
                                         withHandler:^(CMAccelerometerData *data, NSError *err) {
                [weakSelf onAccel:data];
            }];
        }
    }

    if (!_wakeObs) {
        __weak DSHPetCrew *weakSelf = self;
        _wakeObs = [[NSNotificationCenter defaultCenter] addObserverForName:DSHPetCrewWakeNotification
                                                                    object:nil
                                                                     queue:[NSOperationQueue mainQueue]
                                                                usingBlock:^(NSNotification *n) {
            [weakSelf ensureLink];
        }];
    }

    [self reconcileWithBounds:bounds config:cfg];
}

- (void)onAccel:(CMAccelerometerData *)data {
    if (!data) return;
    CMAcceleration a = data.acceleration;
    // 与主宠同语义：mag 太小视为"正立"，否则按倾斜方向加横向重力
    CGFloat mag = fabs(a.x) + fabs(a.y);
    if (mag > 0.08) {
        _tilt = CGPointMake(a.x, -a.y);
        _tiltValid = YES;
    } else {
        _tilt = CGPointZero;
        _tiltValid = NO;
    }
    for (DSHPetPet *p in self.pets) [p crewSetTilt:_tilt valid:_tiltValid];
    [self ensureLink];   // 倾斜变了，宠物得动起来
}

- (void)stop {
    [_link invalidate];
    _link = nil;
    for (DSHPetPet *p in self.pets) {
        [p invalidate];
    }
    [self.pets removeAllObjects];
    [_motion stopAccelerometerUpdates];
    _motion = nil;
    if (_wakeObs) {
        [[NSNotificationCenter defaultCenter] removeObserver:_wakeObs];
        _wakeObs = nil;
    }
    DSHPetLog(@"crew", @"stop", @"info", @{});
}

- (NSUInteger)count { return self.pets.count; }

#pragma mark - 增减

- (void)reconcileWithBounds:(CGRect)bounds config:(NSDictionary *)cfg {
    if (cfg) self.cfg = cfg;
    if (!self.host) return;

    NSDictionary *c = self.cfg ?: @{};
    BOOL on = c[@"multiPetsEnabled"] ? [c[@"multiPetsEnabled"] boolValue] : NO;
    NSInteger maxN = c[@"multiPetsMax"] ? [c[@"multiPetsMax"] integerValue] : 3;
    if (maxN < 1) maxN = 1;
    if (maxN > 8) maxN = 8;
    BOOL perSession = c[@"perSession"] ? [c[@"perSession"] boolValue] : YES;
    CGFloat ratio = c[@"sizeRatio"] ? [c[@"sizeRatio"] doubleValue] : 0.30;

    NSInteger want = 0;
    NSArray<NSDictionary *> *sessions = nil;
    if (on) {
        if (perSession) {
            sessions = [[DSHPetBridge shared] sessions];
            // 主宠占一个会话，多出来的才交给额外宠物；会话不够就先只留 1 只"陪跑"
            want = (NSInteger)MAX((NSUInteger)1, sessions.count);
            if (want > maxN) want = maxN;
        } else {
            want = maxN;
        }
    }

    // 收：多出来的从尾部撤掉
    while ((NSInteger)self.pets.count > want) {
        DSHPetPet *p = self.pets.lastObject;
        [p invalidate];
        [self.pets removeLastObject];
        DSHPetLog(@"crew", @"remove", @"info", @{ @"left": @(self.pets.count) });
    }

    // 生：缺的补上，每只从屏幕上方随机位置落下
    while ((NSInteger)self.pets.count < want) {
        DSHPetPet *p = [[DSHPetPet alloc] initWithHostView:self.host
                                                  assetDir:self.assetDir
                                                 sizeRatio:ratio
                                                    config:c];
        if (perSession && sessions.count) {
            NSUInteger idx = self.pets.count % sessions.count;
            p.sessionId = sessions[idx][@"id"];
        }
        [p crewSetTilt:_tilt valid:_tiltValid];
        [self.pets addObject:p];
        [p dropIntoBounds:bounds];
        DSHPetLog(@"crew", @"spawn", @"info", @{ @"n": @(self.pets.count),
                                                 @"session": p.sessionId ?: @"-" });
    }

    for (DSHPetPet *p in self.pets) [p crewSetTilt:_tilt valid:_tiltValid];
    [self ensureLink];
    if (self.pets.count)
        DSHPetLog(@"crew", @"reconcile", @"info", @{ @"on": @(on), @"want": @(want),
                                                     @"now": @(self.pets.count),
                                                     @"sessions": @((int)(sessions ? sessions.count : 0)) });
}

- (void)relayoutInBounds:(CGRect)bounds settle:(BOOL)settle {
    for (DSHPetPet *p in self.pets) {
        [p relayoutInBounds:bounds settle:settle];
    }
}

#pragma mark - 驱动

- (void)ensureLink {
    if (_link || !self.pets.count) return;
    _lastT = 0;
    _idleTicks = 0;
    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    if ([_link respondsToSelector:@selector(setPreferredFramesPerSecond:)]) {
        _link.preferredFramesPerSecond = 60;
    }
    [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)tick:(CADisplayLink *)l {
    CFTimeInterval now = l.timestamp;
    CFTimeInterval dt = (_lastT > 0) ? (now - _lastT) : (1.0 / 60.0);
    _lastT = now;
    if (dt > 0.1) dt = 1.0 / 60.0;

    NSMutableArray<NSValue *> *frames = [NSMutableArray arrayWithCapacity:self.pets.count];
    for (DSHPetPet *p in self.pets) [frames addObject:[NSValue valueWithCGRect:p.frame]];

    CGRect host = self.host ? self.host.bounds : CGRectZero;
    BOOL anyMoving = NO;
    for (NSUInteger i = 0; i < self.pets.count; i++) {
        DSHPetPet *p = self.pets[i];
        NSMutableArray<NSValue *> *others = [frames mutableCopy];
        [others removeObjectAtIndex:i];
        if ([p stepWithDt:dt others:others host:host config:nil]) anyMoving = YES;
    }

    if (anyMoving) {
        _idleTicks = 0;
    } else if (++_idleTicks > 12) {
        // 全部静止：停表。谁被拖动/抛出会发 DSHPetCrewWakeNotification 把它叫醒。
        [_link invalidate];
        _link = nil;
        _lastT = 0;
        DSHPetLog(@"crew", @"idle-stop", @"debug", @{ @"n": @(self.pets.count) });
    }
}

@end
