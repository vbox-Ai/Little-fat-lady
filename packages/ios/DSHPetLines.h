#import <Foundation/Foundation.h>
#import "DSHPetState.h"

// S-P0：台词库（方案 §12.4 / 附录 A）
//
// 为什么桌宠必须有本地台词库，而不是每次问模型：
//   1. 触摸反应要 < 100ms，模型往返 1–3s，手感直接死；
//   2. 一天几十次触发，全走模型是电费 + token 双烧；
//   3. 断网 / 宿主没开时不能变哑巴。
// 所以：**表达情绪/状态 → 台词库；需要理解语义 → 模型**（比例大约 8:2）。
//
// 三条硬规则（不照做就是复读机）：
//   1. 同类 ≥ 5 条，且不重复最近 3 条（滚动窗口）；
//   2. 支持插槽 {user} {days} {n} {time}；
//   3. 语气四档 genki/lazy/grumpy/down，缺档回落 default。
//
// 容错：素材缺失 / JSON 损坏 → 用内置兜底台词，绝不静默、绝不崩。

NS_ASSUME_NONNULL_BEGIN

@interface DSHPetLines : NSObject

// 称呼用户的名字（{user} 插槽）。默认「爹爹」。
@property (nonatomic, copy) NSString *userName;

+ (instancetype)shared;

// 重新从磁盘载入（面板改完台词 / 素材下载完成后调）
- (void)reload;

// 本次用的是磁盘台词库还是内置兜底
@property (nonatomic, readonly) BOOL loadedFromDisk;
@property (nonatomic, readonly) NSUInteger categoryCount;
@property (nonatomic, readonly, nullable) NSString *loadedPath;

// 取一条台词。path 用点号表示层级：@"whisper"、@"timeGreet.morning"、@"edge.modelFail"
// 内部自动：按 tone 找档 → 去重 → 填插槽。
- (NSString *)lineForPath:(NSString *)path;
- (NSString *)lineForPath:(NSString *)path tone:(DSHPetTone)tone;
- (NSString *)lineForPath:(NSString *)path vars:(nullable NSDictionary<NSString *, NSString *> *)vars;

// 手动渲染模板里的插槽（给气泡 / 模型提示词复用）
- (NSString *)render:(NSString *)tpl vars:(nullable NSDictionary<NSString *, NSString *> *)vars;

@end

NS_ASSUME_NONNULL_END
