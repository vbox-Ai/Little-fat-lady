#import <Foundation/Foundation.h>

// S-AI0：大模型接入（方案 §十四）
//
// 这一层只做一件事：**把一句话发出去，把一句话收回来**，并且保证——
//   1. 任何失败都不打扰用户（不弹窗、不报错、气泡里不出现 http 500 这种字）；
//   2. Key 只在 Keychain，绝不进 plist / 日志 / 崩溃报告；
//   3. 回复一定清洗过（去 markdown、去括号动作、去 AI 腔、截断到气泡装得下）；
//   4. 花钱有账（每日 token 上限，超了自动停用，回落台词库）。
//
// "什么时候该说话" 不在这里，那是 DSHPetScheduler 的事（§12.6）。
// 这一层被调用时才动网络；不被调用就一个字节都不发。

NS_ASSUME_NONNULL_BEGIN

typedef void (^DSHPetChatCompletion)(NSString *_Nullable reply, NSString *_Nullable error);

@interface DSHPetChat : NSObject

@property (nonatomic, readonly) BOOL busy;          // 有请求在飞（避免连点打爆）
@property (nonatomic, readonly) NSInteger todayTokens;

+ (instancetype)shared;

// 配置就绪判定：开关开 + baseURL + model + key 四样齐
- (BOOL)isConfigured;

// 问一句。reply 一定是清洗过、可直接进气泡的短句；失败时 reply=nil 且 error 给机器码。
// 机器码：not-configured / budget-exhausted / busy / offline / timeout / http-401 /
//         http-403 / http-429 / http-5xx / http-4xx / empty / blocked / parse
- (void)ask:(NSString *)text completion:(DSHPetChatCompletion)completion;

// 带上图片问（§14.8）。imageData 传 nil 等价于 ask:。
- (void)ask:(NSString *)text imageData:(nullable NSData *)imageData completion:(DSHPetChatCompletion)completion;

// 清空上下文与今日计数（面板「清除对话记录」用）
- (void)resetConversation;

// Key 管理（面板「设置/替换/留空删除」走这三个）
+ (BOOL)hasAPIKey;
+ (BOOL)setAPIKey:(nullable NSString *)key;   // nil 或空串 = 删除
+ (void)clearAPIKey;

@end

NS_ASSUME_NONNULL_END
