#import "DSHPetScheduler.h"
#import "DSHPetState.h"
#import "DSHPetLines.h"
#import "DSHPetVoice.h"
#import "DSHPetSFX.h"
#import "DSHPetAnimator.h"
#import "DSHPetPrefs.h"
#import "DSHPetBridge.h"
#import "DSHPetBoot.h"
#import <stdlib.h>

// tick 间隔：5 秒一次。再快是浪费电（状态变化是分钟级的），再慢会像卡住。
static const NSTimeInterval kTickInterval = 5.0;
// 沉默概率：约 6 成 tick 什么都不做 —— 这条是"像活物"和"像骚扰"的分界线
static const double kSilenceChance = 0.55;
// 台词冷却（秒）。数字来自方案 §12.6 的候选表。
static const NSTimeInterval kCDWhisper = 300.0;
static const NSTimeInterval kCDDaze = 120.0;
static const NSTimeInterval kCDIdleAction = 20.0;
static const NSTimeInterval kCDTap = 8.0;
static const NSTimeInterval kCDDrag = 12.0;
static const NSTimeInterval kCDDrop = 15.0;
static const NSTimeInterval kCDGreet = 3600.0;

@interface DSHPetScheduler ()
@property (nonatomic, strong, nullable) NSTimer *timer;
@property (nonatomic, strong, nullable) NSDate *lastTickAt;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *lastSpokeAt;
@property (nonatomic, readwrite) BOOL running;
@property (nonatomic, assign) BOOL greetedToday;

- (void)tick;
- (BOOL)isOn:(NSString *)key fallback:(BOOL)fb;
- (BOOL)quietNow;
- (BOOL)cooledDown:(NSString *)key window:(NSTimeInterval)w;
- (void)mark:(NSString *)key;
- (void)sayPath:(NSString *)path;
- (void)sayText:(NSString *)text path:(NSString *)path;
- (NSString *)greetKeyForPhase:(DSHPetPhase)phase;
- (void)maybeGreet;
- (double)weightFor:(NSString *)candidate;
@end

@implementation DSHPetScheduler

+ (instancetype)shared {
    static DSHPetScheduler *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[DSHPetScheduler alloc] init];
    });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }
    _lastSpokeAt = [NSMutableDictionary dictionary];
    _running = NO;
    _greetedToday = NO;
    return self;
}

#pragma mark - 生命周期

- (void)start {
    if (self.running) {
        return;
    }
    self.running = YES;
    self.lastTickAt = [NSDate date];

    // 状态机需要先 load（它自己幂等），台词库也 reload 一次（素材可能刚装上）
    [[DSHPetState shared] load];
    [[DSHPetLines shared] reload];
    if ([self isOn:@"voiceEnabled" fallback:YES]) {
        [[DSHPetVoice shared] configureAudioSession];
    }
    if ([self isOn:@"sfxEnabled" fallback:YES]) {
        [[DSHPetSFX shared] warmUp];
    }

    __weak typeof(self) weakSelf = self;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:kTickInterval
                                                 repeats:YES
                                                   block:^(NSTimer *t) {
        [weakSelf tick];
    }];
    // 容错：让系统在滑动/滚动时也尽量别停我们的 timer
    self.timer.tolerance = 1.0;

    [self maybeGreet];
    DSHPetLog(@"persona", @"scheduler-start", @"info", @{
        @"tick": @(kTickInterval),
        @"phase": [[DSHPetState shared] phaseID],
        @"tone": @([[DSHPetState shared] tone]),
        @"lines": @([[DSHPetLines shared] categoryCount]),
    });
}

- (void)stop {
    [self.timer invalidate];
    self.timer = nil;
    self.running = NO;
    [[DSHPetState shared] saveIfDirty];
    [[DSHPetVoice shared] stopSpeakingNow];
    DSHPetLog(@"persona", @"scheduler-stop", @"info", nil);
}

- (BOOL)isOn:(NSString *)key fallback:(BOOL)fb {
    // 每 tick 重读：用户在设置里改完，下一次 tick 就生效，不用重启 SpringBoard
    return [DSHPetPrefs boolForKey:key fallback:fb];
}

- (BOOL)quietNow {
    if (![self isOn:@"quietHours" fallback:NO]) {
        return NO;
    }
    NSInteger hour = [[NSCalendar currentCalendar] component:NSCalendarUnitHour fromDate:[NSDate date]];
    return (hour >= 23 || hour < 8);
}

#pragma mark - tick 与决策

- (void)tick {
    NSDate *now = [NSDate date];
    NSTimeInterval dt = self.lastTickAt ? [now timeIntervalSinceDate:self.lastTickAt] : kTickInterval;
    self.lastTickAt = now;

    // 1) 先推进状态：即使不说话，energy/boredom 也要照走，否则"她一直没变"就露馅了
    [[DSHPetState shared] tick:dt];
    [[DSHPetState shared] saveIfDirty];

    if (![self isOn:@"personaEnabled" fallback:YES]) {
        return;
    }
    if ([self quietNow]) {
        return;
    }

    // 2) 沉默优先：这一条挡在前面，后面的候选才有意义
    double r = (double)arc4random_uniform(10000) / 10000.0;
    if (r < kSilenceChance) {
        return;
    }

    // 3) 加权抽一个候选
    NSArray<NSString *> *cands = @[@"whisper", @"idleAction", @"daze", @"wantPlay", @"drowsy", @"sleep"];
    double total = 0.0;
    NSMutableArray<NSNumber *> *ws = [NSMutableArray array];
    for (NSString *c in cands) {
        double w = [self weightFor:c];
        [ws addObject:@(w)];
        total += w;
    }
    if (total <= 0.0) {
        return;
    }
    double pick = ((double)arc4random_uniform(10000) / 10000.0) * total;
    double acc = 0.0;
    NSString *chosen = @"daze";
    for (NSUInteger i = 0; i < cands.count; i++) {
        acc += ws[i].doubleValue;
        if (pick <= acc) {
            chosen = cands[i];
            break;
        }
    }

    DSHPetState *st = [DSHPetState shared];

    if ([chosen isEqualToString:@"whisper"]) {
        if ([self cooledDown:@"whisper" window:kCDWhisper]) {
            [self mark:@"whisper"];
            [self sayPath:@"whisper"];
        }
        return;
    }

    if ([chosen isEqualToString:@"daze"]) {
        if ([self cooledDown:@"daze" window:kCDDaze]) {
            [self mark:@"daze"];
            [[DSHPetAnimator shared] playRandomFromCategory:@"idle"];
            [self sayPath:@"whisper"];
        }
        return;
    }

    if ([chosen isEqualToString:@"idleAction"]) {
        if ([self cooledDown:@"idleAction" window:kCDIdleAction]) {
            [self mark:@"idleAction"];
            // S-M1c 动作库：不再是"先 play 再 eat"的硬编码两档，
            // 按权重从 play/eat/idle/turn 四类里抽，抽到哪类就从哪类随机一段。
            // 权重参考上游 animations.categories（小动作/玩耍/吃什么/时节），
            // 移植版的素材只分了这四桶，所以按桶给权：
            //   play(玩/杂项) 5 · eat(吃什么) 4 · idle(小动作) 3 · turn(转身) 2
            // 小动作不发台词：动作本身就是表达，配台词反而吵。
            NSArray<NSString *> *cats = @[@"play", @"eat", @"idle", @"turn"];
            NSArray<NSNumber *> *weights = @[@5, @4, @3, @2];
            NSInteger total = 0;
            for (NSNumber *w in weights) {
                total += w.integerValue;
            }
            NSInteger pick = (NSInteger)arc4random_uniform((uint32_t)MAX(total, 1));
            NSInteger acc = 0;
            NSString *picked = nil;
            for (NSUInteger i = 0; i < cats.count; i++) {
                acc += weights[i].integerValue;
                if (pick < acc) {
                    picked = cats[i];
                    break;
                }
            }
            BOOL ok = NO;
            if (picked) {
                ok = [[DSHPetAnimator shared] playRandomFromCategory:picked];
            }
            if (!ok) {
                // 抽中的桶没素材（比如只装了 idle），按顺序兜底，全空就静默
                for (NSString *fallback in cats) {
                    if ([fallback isEqualToString:picked ?: @""]) continue;
                    if ([[DSHPetAnimator shared] playRandomFromCategory:fallback]) {
                        picked = fallback;
                        ok = YES;
                        break;
                    }
                }
            }
            DSHPetLog(@"persona", @"action-lib", ok ? @"debug" : @"warn", @{ @"cat": picked ?: @"none" });
        }
        return;
    }

    if ([chosen isEqualToString:@"wantPlay"]) {
        if ([self cooledDown:@"wantPlay" window:180.0]) {
            [self mark:@"wantPlay"];
            [self sayPath:@"affinity"];
        }
        return;
    }

    if ([chosen isEqualToString:@"drowsy"]) {
        if ([self cooledDown:@"drowsy" window:240.0]) {
            [self mark:@"drowsy"];
            [[DSHPetAnimator shared] playRandomFromCategory:@"idle"];
            [self sayPath:@"sleepTalk"];
        }
        return;
    }

    if ([chosen isEqualToString:@"sleep"]) {
        if ([self cooledDown:@"sleep" window:600.0] && st.energy < 12.0) {
            [self mark:@"sleep"];
            [self sayPath:@"sleepTalk"];
        }
    }
}

- (double)weightFor:(NSString *)candidate {
    DSHPetState *st = [DSHPetState shared];
    BOOL late = (st.phase == DSHPetPhaseLateNight);

    if ([candidate isEqualToString:@"whisper"]) {
        return late ? 0.3 : 1.0;
    }
    if ([candidate isEqualToString:@"idleAction"]) {
        return st.energy < 25 ? 0.6 : 1.2;
    }
    if ([candidate isEqualToString:@"daze"]) {
        return late ? 0.9 : 0.6;
    }
    if ([candidate isEqualToString:@"wantPlay"]) {
        if (!st.wantPlay) {
            return 0.0;
        }
        // 越熟越爱找你玩
        return 0.3 + (st.affinity / 100.0) * 0.7;
    }
    if ([candidate isEqualToString:@"drowsy"]) {
        return st.drowsy ? 0.3 : 0.0;
    }
    if ([candidate isEqualToString:@"sleep"]) {
        return st.energy < 12.0 ? 0.2 : 0.0;
    }
    return 0.0;
}

- (BOOL)cooledDown:(NSString *)key window:(NSTimeInterval)w {
    NSNumber *t = self.lastSpokeAt[key];
    if (!t) {
        return YES;
    }
    return ([NSDate date].timeIntervalSince1970 - t.doubleValue) >= w;
}

- (void)mark:(NSString *)key {
    self.lastSpokeAt[key] = @([NSDate date].timeIntervalSince1970);
}

#pragma mark - 即时事件

- (void)handleEvent:(NSString *)event {
    if (![self isOn:@"personaEnabled" fallback:YES]) {
        return;
    }
    DSHPetState *st = [DSHPetState shared];
    [st applyEvent:event amount:0.0];

    if (![self quietNow] && [self isOn:@"sfxEnabled" fallback:YES]) {
        if ([event isEqualToString:DSHPetEventTap]) {
            [[DSHPetSFX shared] play:@"tap"];
        } else if ([event isEqualToString:DSHPetEventDrag]) {
            [[DSHPetSFX shared] play:@"pickup"];
        } else if ([event isEqualToString:DSHPetEventDrop]) {
            [[DSHPetSFX shared] play:@"land"];
        } else if ([event isEqualToString:DSHPetEventCollide]) {
            [[DSHPetSFX shared] play:@"bump"];
        }
    }

    // 触摸反应是"手感"的核心，走独立冷却，不受沉默概率影响
    if ([event isEqualToString:DSHPetEventTap]) {
        if ([self cooledDown:@"tap" window:kCDTap]) {
            [self mark:@"tap"];
            [self sayPath:@"click"];
        }
        return;
    }
    if ([event isEqualToString:DSHPetEventDrag]) {
        if ([self cooledDown:@"drag" window:kCDDrag]) {
            [self mark:@"drag"];
            [self sayPath:@"drag"];
        }
        return;
    }
    if ([event isEqualToString:DSHPetEventDrop]) {
        if ([self cooledDown:@"drop" window:kCDDrop]) {
            [self mark:@"drop"];
            [self sayPath:@"drag"];
        }
        return;
    }
    if ([event isEqualToString:DSHPetEventCollide]) {
        if ([self cooledDown:@"collide" window:20.0]) {
            [self mark:@"collide"];
            [self sayPath:@"collide"];
        }
    }
}

- (void)noteStatus:(NSString *)state {
    if (!state.length || ![self isOn:@"personaEnabled" fallback:YES]) {
        return;
    }
    if ([self quietNow]) {
        return;
    }
    if (![self cooledDown:@"status" window:60.0]) {
        return;
    }
    [self mark:@"status"];
    NSDictionary<NSString *, NSString *> *vars = @{@"state": state};
    NSString *text = [[DSHPetLines shared] lineForPath:@"status" vars:vars];
    if (text.length) {
        [self sayText:text path:@"status"];
    }
}

#pragma mark - 开口

- (void)sayReply:(NSString *)text {
    // 外部给的是成品句子，不再过台词库；但气泡/语音开关和免打扰仍然管着它
    if (![self isOn:@"personaEnabled" fallback:YES]) {
        return;
    }
    if ([self quietNow]) {
        return;
    }
    [self sayText:text path:@"chat"];
}

- (void)sayPath:(NSString *)path {
    NSString *text = [[DSHPetLines shared] lineForPath:path];
    if (!text.length) {
        DSHPetLog(@"persona", @"no-line", @"debug", @{@"path": path});
        return;
    }
    [self sayText:text path:path];
}

- (void)sayText:(NSString *)text path:(NSString *)path {
    if (!text.length) {
        return;
    }
    // 气泡：交给既有通知链（DSHPetOverlay 里已经在监听，会自己摆到头顶）
    if ([self isOn:@"bubbleEnabled" fallback:YES]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:DSHPetSayNotification
                                                           object:nil
                                                         userInfo:@{@"text": text, @"kind": path}];
    }
    // 声音：独立开关，气泡关了也能出声
    if ([self isOn:@"voiceEnabled" fallback:YES]) {
        [[DSHPetVoice shared] speak:text path:path];
    }
    DSHPetLog(@"persona", @"say", @"debug", @{
        @"path": path,
        @"chars": @(text.length),
        @"tone": @([[DSHPetState shared] tone]),
    });
}

#pragma mark - 问候

- (NSString *)greetKeyForPhase:(DSHPetPhase)phase {
    switch (phase) {
        case DSHPetPhaseDawn: return @"dawn";
        case DSHPetPhaseMorning: return @"morning";
        case DSHPetPhaseNoon: return @"noon";
        case DSHPetPhaseAfternoon: return @"afternoon";
        case DSHPetPhaseEvening: return @"evening";
        case DSHPetPhaseLateNight: return @"lateNight";
    }
    return @"morning";
}

- (void)maybeGreet {
    if (self.greetedToday) {
        return;
    }
    if (![self isOn:@"personaEnabled" fallback:YES] || [self quietNow]) {
        return;
    }
    // 一小时最多问候一次：进程重启（SpringBoard 重载）不该每次都重打招呼
    if (![self cooledDown:@"greet" window:kCDGreet]) {
        self.greetedToday = YES;
        return;
    }
    self.greetedToday = YES;
    // timeGreet 是嵌套结构（按相位取数组），用通用取值器取不到，直接走 path 形式
    NSString *path = [@"timeGreet." stringByAppendingString:[self greetKeyForPhase:[DSHPetState shared].phase]];
    NSString *text = [[DSHPetLines shared] lineForPath:path];
    if (!text.length) {
        return;
    }
    [self mark:@"greet"];
    [self sayText:text path:@"timeGreet"];
}

@end
