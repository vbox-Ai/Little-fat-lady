#import <Foundation/Foundation.h>

// S-P1：内部状态机（方案 §12.3）
//
// 为什么要有这一层：台词库只能「随机抽」，抽出来的话跟「她此刻什么感觉」无关，
// 玩两天就露馅。把 mood / energy / affinity / boredom / focus 做成会随时间与事件
// 连续变化的内部状态，同一个事件在不同状态下选不同台词——这才是「像有思想」的根。
//
// 三条纪律（照抄，别改）：
//   1. 全部是廉价整数/浮点运算，不进网络、不碰渲染，每 tick 必须 < 1ms；
//   2. 落盘节流（默认 30s 一次），绝不每 tick 写盘；
//   3. 读盘失败/字段缺失一律回落默认值，宁可失忆也不许崩 SpringBoard。

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, DSHPetActivity) {
    DSHPetActivityIdle = 0,
    DSHPetActivityWander,
    DSHPetActivityWorking,
    DSHPetActivitySleeping,
    DSHPetActivityDragged,
    DSHPetActivityTalking,
    DSHPetActivityPlaying,
};

typedef NS_ENUM(NSInteger, DSHPetPhase) {
    DSHPetPhaseDawn = 0,
    DSHPetPhaseMorning,
    DSHPetPhaseNoon,
    DSHPetPhaseAfternoon,
    DSHPetPhaseEvening,
    DSHPetPhaseLateNight,
};

// 情绪四象限（方案 §12.3.3）：台词按这四档选，缺档回落 default
typedef NS_ENUM(NSInteger, DSHPetTone) {
    DSHPetToneGenki = 0,   // 心情好 + 精力足
    DSHPetToneLazy,        // 心情好 + 精力低（撒娇）
    DSHPetToneGrumpy,      // 心情差 + 精力足（炸毛）
    DSHPetToneDown,        // 心情差 + 精力低（蔫了）
};

// 事件名（applyEvent 用）。做成常量避免各处手写字符串写错。
extern NSString *const DSHPetEventTap;
extern NSString *const DSHPetEventDrag;
extern NSString *const DSHPetEventDrop;
extern NSString *const DSHPetEventCollide;
extern NSString *const DSHPetEventChat;
extern NSString *const DSHPetEventPraise;
extern NSString *const DSHPetEventWorkDone;
extern NSString *const DSHPetEventWorkError;
extern NSString *const DSHPetEventBalanceUp;
extern NSString *const DSHPetEventBalanceDown;
extern NSString *const DSHPetEventTodoDone;
extern NSString *const DSHPetEventIdleLong;

@interface DSHPetState : NSObject

@property (nonatomic, readonly) double mood;      // -100..+100
@property (nonatomic, readonly) double energy;    // 0..100
@property (nonatomic, readonly) double affinity;  // 0..100
@property (nonatomic, readonly) double boredom;   // 0..100
@property (nonatomic, readonly) double focus;     // 0..100
@property (nonatomic, assign) DSHPetActivity activity;
@property (nonatomic, readonly) DSHPetPhase phase;

// 派生标志（tick 时重算，供 Decider / Lines 直接读）
@property (nonatomic, readonly) BOOL drowsy;      // energy < 25
@property (nonatomic, readonly) BOOL grumpy;      // mood < -40
@property (nonatomic, readonly) BOOL wantPlay;    // boredom > 75 且 focus < 40

+ (instancetype)shared;

// 每 tick 推进（dt 秒）。内部会按需 saveIfDirty。
- (void)tick:(double)dt;

// 事件加减。amount 可为负。内部 clamp 到区间。
- (void)applyEvent:(NSString *)event amount:(double)amount;

// 外部（桥接/面板）同步用
- (void)setFocusLevel:(double)focus;
- (void)setActivity:(DSHPetActivity)activity;   // 同时处理睡觉时的精力回复

- (DSHPetTone)tone;
- (NSString *)phaseID;          // dawn / morning / noon / afternoon / evening / lateNight
- (NSString *)activityID;       // idle / wander / working / sleeping / dragged / talking / playing

// 持久化
- (void)load;
- (void)save;
- (void)saveIfDirty;

// 一行摘要，给日志与气泡调试用
- (NSString *)debugSummary;

@end

NS_ASSUME_NONNULL_END
