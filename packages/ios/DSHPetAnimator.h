#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// S4 动画链与状态机（第一版）
///
/// 职责：把素材目录里的一堆视频按"动作类别"分组，然后按粗规则决定下一秒放哪段。
/// 不做的那部分（上游那套 categories/weights/events 全量调度）留给后续阶段。
@class DSHPetPlayer;

@interface DSHPetAnimator : NSObject

+ (instancetype)shared;

/// S6c：多开时每只宠物要有自己的状态机（否则 8 只动作同步、点击互相抢），
/// 所以除了单例还能自己 new 一个，并把"播到哪个播放器"注入进来。
- (instancetype)initWithPlayer:(DSHPetPlayer *)player;

/// 这只状态机把片子交给谁播。默认 [DSHPetPlayer shared]。
@property (nonatomic, strong) DSHPetPlayer *player;

/// 扫描目录、建索引、起调度。clips 为空时会一直处于"无素材"状态，只写一次日志。
- (void)startWithDirectory:(NSString *)dir;

- (void)stop;

/// 用户点一下：在 click 组里轮播（没有 click 组就播 idle）
- (void)handleTap;

/// S6d：长按菜单「换个表情」用。cat 取 "play"/"eat"/"idle"/"turn" 等分桶名，
/// 分桶是上游按文件名归类出来的（见 buildIndex），这里不做二次挑拣。
- (BOOL)playRandomFromCategory:(NSString *)cat;

/// 开始拖动 / 结束拖动
- (void)handleDragBegin;
- (void)handleDragEnd;

/// 睡觉开关（S4 只影响选片，不影响其它逻辑）
- (void)setSleeping:(BOOL)sleeping;

/// 当前在播的文件名（没有则 nil），日志与设置面板会读
@property (nonatomic, readonly, copy, nullable) NSString *currentClip;

@end

NS_ASSUME_NONNULL_END
