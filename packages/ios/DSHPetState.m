#import "DSHPetState.h"
#import "DSHPetBoot.h"

#import <math.h>

NSString *const DSHPetEventTap = @"tap";
NSString *const DSHPetEventDrag = @"drag";
NSString *const DSHPetEventDrop = @"drop";
NSString *const DSHPetEventCollide = @"collide";
NSString *const DSHPetEventChat = @"chat";
NSString *const DSHPetEventPraise = @"praise";
NSString *const DSHPetEventWorkDone = @"workDone";
NSString *const DSHPetEventWorkError = @"workError";
NSString *const DSHPetEventBalanceUp = @"balanceUp";
NSString *const DSHPetEventBalanceDown = @"balanceDown";
NSString *const DSHPetEventTodoDone = @"todoDone";
NSString *const DSHPetEventIdleLong = @"idleLong";

// ---- 调参区（改手感只动这里，别散落在逻辑里）----

static const double kMoodMin = -100.0;
static const double kMoodMax = 100.0;
static const double kEnergyMin = 0.0;
static const double kEnergyMax = 100.0;
static const double kAffinityMax = 100.0;
static const double kBoredomMax = 100.0;
static const double kFocusMax = 100.0;

static const double kMoodInit = 20.0;
static const double kEnergyInit = 80.0;

// 自然变化速率
static const double kBoredomRate = 0.35;      // /s，约 +21/min
static const double kEnergyDrainRate = 0.06;  // /s，约 -3.6/h
static const double kEnergySleepRate = 0.004; // /s，整夜 8h 正好回满
static const double kMoodDecayBase = 0.9995;  // 每秒向 0 回归的底数（缓慢）
static const double kAffinityRate = 0.00004;  // /s，约 +3.5/天 → 30 天满

// 落盘节流
static const double kSaveInterval = 30.0;

// 事件默认增减表：正数加，负数减。数值就是「一次事件值得多少情绪」。
static NSDictionary<NSString *, NSNumber *> *DSHPetEventDeltas(void) {
    static NSDictionary<NSString *, NSNumber *> *map = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            // 被戳：一次一点开心，但由 Decider 侧做「连续戳递减」，这里给基础值
            DSHPetEventTap: @2.0,
            DSHPetEventDrag: @(-1.5),
            DSHPetEventDrop: @(-1.0),
            DSHPetEventCollide: @(-0.8),
            DSHPetEventChat: @3.0,
            DSHPetEventPraise: @8.0,
            DSHPetEventWorkDone: @5.0,
            DSHPetEventWorkError: @(-4.0),
            DSHPetEventBalanceUp: @2.0,
            DSHPetEventBalanceDown: @(-2.0),
            DSHPetEventTodoDone: @3.0,
            DSHPetEventIdleLong: @(-6.0),
        };
    });
    return map;
}

static NSString *DSHPetStateDirectory(void) {
    // 运行期状态一律写真实数据分区。/var/jb 与 .jbroot-* 是「读素材」用的假根，
    // 往里写会随越狱环境重建而丢（S3 踩过：素材装错根导致整只宠物不显示）。
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/DSHPet"];
}

static NSString *DSHPetStateFilePath(void) {
    return [DSHPetStateDirectory() stringByAppendingPathComponent:@"state.json"];
}

@interface DSHPetState ()
@property (nonatomic, readwrite) double mood;
@property (nonatomic, readwrite) double energy;
@property (nonatomic, readwrite) double affinity;
@property (nonatomic, readwrite) double boredom;
@property (nonatomic, readwrite) double focus;
@property (nonatomic, readwrite) DSHPetPhase phase;
@property (nonatomic, readwrite) BOOL drowsy;
@property (nonatomic, readwrite) BOOL grumpy;
@property (nonatomic, readwrite) BOOL wantPlay;
@property (nonatomic, assign) BOOL dirty;
@property (nonatomic, assign) NSTimeInterval lastSaveAt;

// 私有方法必须先声明：写在 @implementation 后半段又被前半段调用，
// 会触发 "instance method not found" 警告，CI 是 -Werror，警告即失败。
- (double)clamp:(double)v lo:(double)lo hi:(double)hi;
- (void)recomputeFlags;
- (DSHPetPhase)computePhase;
- (double)doubleFrom:(NSDictionary *)d key:(NSString *)key fb:(double)fb lo:(double)lo hi:(double)hi;
@end

@implementation DSHPetState

+ (instancetype)shared {
    static DSHPetState *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[DSHPetState alloc] init];
        [s load];
    });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _mood = kMoodInit;
        _energy = kEnergyInit;
        _affinity = 0;
        _boredom = 0;
        _focus = 0;
        _activity = DSHPetActivityIdle;
        _phase = DSHPetPhaseMorning;
        _lastSaveAt = 0;
    }
    return self;
}

#pragma mark - 推进

- (void)tick:(double)dt {
    if (dt <= 0 || dt > 600) {
        // 后台/断点回来可能给一个巨大的 dt，钳到 10 分钟，避免一帧把精力抽干
        dt = MIN(MAX(dt, 0.0), 600.0);
    }

    double rate = (self.activity == DSHPetActivitySleeping) ? kEnergySleepRate : -kEnergyDrainRate;
    _energy = [self clamp:_energy + rate * dt lo:kEnergyMin hi:kEnergyMax];

    _boredom = [self clamp:_boredom + kBoredomRate * dt lo:0 hi:kBoredomMax];
    _mood = [self clamp:_mood * pow(kMoodDecayBase, dt) lo:kMoodMin hi:kMoodMax];
    _affinity = [self clamp:_affinity + kAffinityRate * dt lo:0 hi:kAffinityMax];

    _phase = [self computePhase];
    [self recomputeFlags];
    [self saveIfDirty];
}

- (double)clamp:(double)v lo:(double)lo hi:(double)hi {
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

- (void)recomputeFlags {
    _drowsy = (_energy < 25.0);
    _grumpy = (_mood < -40.0);
    _wantPlay = (_boredom > 75.0 && _focus < 40.0);
}

- (DSHPetPhase)computePhase {
    NSInteger hour = [[NSCalendar currentCalendar] component:NSCalendarUnitHour fromDate:[NSDate date]];
    if (hour >= 5 && hour < 8) return DSHPetPhaseDawn;
    if (hour >= 8 && hour < 11) return DSHPetPhaseMorning;
    if (hour >= 11 && hour < 14) return DSHPetPhaseNoon;      // 含午休
    if (hour >= 14 && hour < 18) return DSHPetPhaseAfternoon;
    if (hour >= 18 && hour < 23) return DSHPetPhaseEvening;
    return DSHPetPhaseLateNight;                              // 23:00–05:00
}

- (void)applyEvent:(NSString *)event amount:(double)amount {
    if (event.length == 0) return;

    double delta = amount;
    if (delta == 0) {
        NSNumber *d = DSHPetEventDeltas()[event];
        delta = d ? d.doubleValue : 0;
    }
    if (delta == 0) return;

    _mood = [self clamp:_mood + delta lo:kMoodMin hi:kMoodMax];

    // 事件顺带影响其它维度：戳与被拖会打断无聊；聊天会降无聊
    if ([event isEqualToString:DSHPetEventTap] ||
        [event isEqualToString:DSHPetEventDrag] ||
        [event isEqualToString:DSHPetEventChat]) {
        _boredom = [self clamp:_boredom - 8.0 lo:0 hi:kBoredomMax];
    }
    // 夸她、聊得久 → 亲密度；被拖、撞 → 略降
    if ([event isEqualToString:DSHPetEventPraise] ||
        [event isEqualToString:DSHPetEventChat]) {
        _affinity = [self clamp:_affinity + 0.6 lo:0 hi:kAffinityMax];
    } else if ([event isEqualToString:DSHPetEventDrag] ||
               [event isEqualToString:DSHPetEventCollide]) {
        _affinity = [self clamp:_affinity - 0.1 lo:0 hi:kAffinityMax];
    }

    [self recomputeFlags];
    self.dirty = YES;
    DSHPetLog(@"state", @"event", @"debug", @{@"evt": event, @"delta": @(delta), @"summary": [self debugSummary]});
}

- (void)setFocusLevel:(double)focus {
    _focus = [self clamp:focus lo:0 hi:kFocusMax];
    [self recomputeFlags];
    self.dirty = YES;
}

- (void)setActivity:(DSHPetActivity)activity {
    if (_activity == activity) return;
    _activity = activity;
    if (activity == DSHPetActivitySleeping) {
        // 刚睡着：心情回一点（睡个好觉）
        _mood = [self clamp:_mood + 5.0 lo:kMoodMin hi:kMoodMax];
    }
    [self recomputeFlags];
    self.dirty = YES;
    DSHPetLog(@"state", @"activity", @"info", @{@"activity": [self activityID]});
}

#pragma mark - 派生值

- (DSHPetTone)tone {
    BOOL good = (self.mood >= 0);
    BOOL lively = (self.energy >= 50);
    if (good && lively) return DSHPetToneGenki;
    if (good && !lively) return DSHPetToneLazy;
    if (!good && lively) return DSHPetToneGrumpy;
    return DSHPetToneDown;
}

- (NSString *)phaseID {
    switch (self.phase) {
        case DSHPetPhaseDawn: return @"dawn";
        case DSHPetPhaseMorning: return @"morning";
        case DSHPetPhaseNoon: return @"noon";
        case DSHPetPhaseAfternoon: return @"afternoon";
        case DSHPetPhaseEvening: return @"evening";
        case DSHPetPhaseLateNight: return @"lateNight";
    }
    return @"morning";
}

- (NSString *)activityID {
    switch (self.activity) {
        case DSHPetActivityIdle: return @"idle";
        case DSHPetActivityWander: return @"wander";
        case DSHPetActivityWorking: return @"working";
        case DSHPetActivitySleeping: return @"sleeping";
        case DSHPetActivityDragged: return @"dragged";
        case DSHPetActivityTalking: return @"talking";
        case DSHPetActivityPlaying: return @"playing";
    }
    return @"idle";
}

- (NSString *)debugSummary {
    return [NSString stringWithFormat:@"mood=%.0f energy=%.0f aff=%.0f bore=%.0f focus=%.0f act=%@ phase=%@",
            self.mood, self.energy, self.affinity, self.boredom, self.focus,
            [self activityID], [self phaseID]];
}

#pragma mark - 持久化

- (void)load {
    NSString *path = DSHPetStateFilePath();
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data.length == 0) {
        [self recomputeFlags];
        return;
    }

    NSError *err = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    if (err || ![obj isKindOfClass:[NSDictionary class]]) {
        // 坏了就当没存过：宁可失忆，也不要带着半截状态跑
        DSHPetLog(@"state", @"load-fail", @"warn", @{@"err": err.localizedDescription ?: @"not-a-dict"});
        [self recomputeFlags];
        return;
    }

    NSDictionary *d = (NSDictionary *)obj;
    _mood = [self doubleFrom:d key:@"mood" fb:kMoodInit lo:kMoodMin hi:kMoodMax];
    _energy = [self doubleFrom:d key:@"energy" fb:kEnergyInit lo:kEnergyMin hi:kEnergyMax];
    _affinity = [self doubleFrom:d key:@"affinity" fb:0 lo:0 hi:kAffinityMax];
    _boredom = [self doubleFrom:d key:@"boredom" fb:0 lo:0 hi:kBoredomMax];
    _focus = [self doubleFrom:d key:@"focus" fb:0 lo:0 hi:kFocusMax];

    NSInteger act = [self doubleFrom:d key:@"activity" fb:0 lo:0 hi:6];
    _activity = (DSHPetActivity)act;

    // 离线折算：离开多久就按「睡了一觉」补精力（最多补满）
    double ts = [self doubleFrom:d key:@"savedAt" fb:0 lo:0 hi:1e12];
    if (ts > 0) {
        double elapsed = [NSDate date].timeIntervalSince1970 - ts;
        if (elapsed > 60) {
            double hours = MIN(elapsed / 3600.0, 12.0);
            _energy = [self clamp:_energy + hours * 12.5 lo:kEnergyMin hi:kEnergyMax];
            DSHPetLog(@"state", @"offline-recover", @"info", @{@"hours": @(hours), @"energy": @(_energy)});
        }
    }

    // 冷启动不应该还停在「被拖着」或「说话中」
    if (_activity == DSHPetActivityDragged || _activity == DSHPetActivityTalking) {
        _activity = DSHPetActivityIdle;
    }

    _phase = [self computePhase];
    [self recomputeFlags];
}

- (double)doubleFrom:(NSDictionary *)d key:(NSString *)key fb:(double)fb lo:(double)lo hi:(double)hi {
    id v = d[key];
    double n = ([v isKindOfClass:[NSNumber class]]) ? [v doubleValue] : fb;
    if (isnan(n) || isinf(n)) n = fb;    // NaN/Inf 一旦写进 JSON，NSJSONSerialization 会直接抛，这里先挡
    return [self clamp:n lo:lo hi:hi];
}

- (void)saveIfDirty {
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    if (!self.dirty) return;
    if (now - self.lastSaveAt < kSaveInterval) return;
    [self save];
}

- (void)save {
    NSString *dir = DSHPetStateDirectory();
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:dir]) {
        NSError *mk = nil;
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&mk];
        if (mk) {
            DSHPetLog(@"state", @"mkdir-fail", @"error", @{@"err": mk.localizedDescription});
            return;
        }
    }

    NSDictionary *d = @{
        @"v": @1,
        @"mood": @(self.mood),
        @"energy": @(self.energy),
        @"affinity": @(self.affinity),
        @"boredom": @(self.boredom),
        @"focus": @(self.focus),
        @"activity": @(self.activity),
        @"savedAt": @([NSDate date].timeIntervalSince1970),
    };

    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:d options:0 error:&err];
    if (err || data.length == 0) {
        DSHPetLog(@"state", @"encode-fail", @"error", @{@"err": err.localizedDescription ?: @"empty"});
        return;
    }
    // 原子写：中途被杀不会留下半截文件（半截 JSON 会让下次启动回落默认，等于失忆）
    if (![data writeToFile:DSHPetStateFilePath() options:NSDataWritingAtomic error:&err]) {
        DSHPetLog(@"state", @"write-fail", @"error", @{@"err": err.localizedDescription ?: @"unknown"});
        return;
    }
    self.dirty = NO;
    self.lastSaveAt = [NSDate date].timeIntervalSince1970;
}

@end
