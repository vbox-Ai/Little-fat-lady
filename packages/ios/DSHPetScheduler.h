#import <Foundation/Foundation.h>

// S-P2：调度器 + 决策器（方案 §12.6 / §12.9 / §12.11）
//
// 这一层只回答一个问题：**现在该不该说话、说什么、做什么小动作**。
// 它不渲染、不合成音频，只做三件事：
//   1. 每 5 秒 tick 一次：推进状态机（mood/energy/…）→ 攒够"想说"的概率就开口；
//   2. 收到触摸事件时立刻反应（这条不等 tick，手感要 100ms 级）；
//   3. 开口这一步统一走 say:：气泡走 DSHPetSayNotification，声音走 DSHPetVoice。
//
// 三条设计纪律（照抄自方案第十二章，别改）：
//   · **沉默也是表演**：约 6 成 tick 什么都不做，否则变成骚扰；
//   · 同类台词有冷却（whisper 300s / 发呆 120s / 点击 8s），冷却存在内存里，重启即清；
//   · 面板开关每 tick 重新读一次 —— 用户在设置里改完立刻生效，不用重启 SpringBoard。

NS_ASSUME_NONNULL_BEGIN

@interface DSHPetScheduler : NSObject

@property (nonatomic, readonly) BOOL running;

+ (instancetype)shared;

// 启动/停止 tick。重复调用安全。
- (void)start;
- (void)stop;

// 触摸等外部事件：传 DSHPetEvent* 常量（Tap / Drag / Drop / Collide / Chat …）。
// 内部会先 applyEvent 改状态，再按事件类型决定要不要立刻说一句。
- (void)handleEvent:(NSString *)event;

// 外部（桥接）拿到会话状态时也可以推一条，走「状态」台词
- (void)noteStatus:(NSString *)state;

// 外部已经拿到一句可直接显示的话（大模型回复、聊天兜底）时，从这里出去：
// 气泡 ＋ 语音一次走完，开关与免打扰规则照样生效。
- (void)sayReply:(NSString *)text;

@end

NS_ASSUME_NONNULL_END
