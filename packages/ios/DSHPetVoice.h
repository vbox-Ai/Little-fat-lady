#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// S-V0 / S-V2：语音输出总调度（方案 §十三）
//
// 四件事里，这一层管三件：**播放、会话、打断**，外加进 TTS 之前的文本预处理。
// 合成本身（引擎）是可插拔的：native 走系统 AVSpeechSynthesizer 保底，
// 豆包 / edge 这类远端引擎以后从 DSHPetTTSProvider 接进来，本层只认「一段文字 → 出不出声」。
//
// 三条硬纪律（都是真机踩出来的）：
//   1. 会话一律 Ambient + MixWithOthers —— 用 Playback 会把用户的歌掐了，这是桌宠被卸载的头号原因；
//   2. 任何 AVFoundation 调用都包 @try —— 在 SpringBoard 里抛异常 = 直接安全模式；
//   3. 新语音打断旧语音（单通道），不排队 —— 桌宠不该像导航一样把话说完。

NS_ASSUME_NONNULL_BEGIN

@interface DSHPetVoice : NSObject

// 开关与参数（面板「语音」组直接绑这几个）
@property (nonatomic, assign) BOOL enabled;             // 对话声音总开关，默认 YES
@property (nonatomic, assign) BOOL duckWhenLong;        // 长句压低音乐，默认 YES
@property (nonatomic, assign) BOOL respectSilentSwitch; // 遵守静音键（Ambient 天然遵守，置 NO 时用 Playback）
@property (nonatomic, copy, nullable) NSString *voiceIdentifier; // 系统音色 identifier，nil = 用默认中文女声
@property (nonatomic, assign) float baseRate;    // 语速倍率 1.0
@property (nonatomic, assign) float basePitch;   // 音调倍率 1.0
@property (nonatomic, assign) float baseVolume;  // 音量 1.0

@property (nonatomic, readonly) BOOL speaking;
@property (nonatomic, readonly) NSInteger speakCount;   // 统计用：这次启动说了几句

+ (instancetype)shared;

// 会话：首次使用前调一次；之后每次说话也会兜底调（幂等）
- (void)configureAudioSession;

// 说一句话。path 只用于日志与去重（如 @"click" / @"whisper"），可传 nil。
// 内部会自动：预处理 → 按 state 调语速音调 → 打断旧的 → 播 → 通知口型。
- (void)speak:(NSString *)text path:(nullable NSString *)path;
- (void)speak:(NSString *)text path:(nullable NSString *)path volume:(float)volume;

// 停止
- (void)stopSpeakingNow;          // 立刻停（来电、面板关闭、进后台）
- (void)stopSpeakingIfIdle;       // 只在没在说话时做清理，安全可重入

// 文本预处理（把 ¥3.33 读成「三块三毛三」那种）。
// 单独暴露是为了能单元测试 —— 这层最容易出错，也最容易验证。
- (NSString *)preprocess:(NSString *)text;

// 说话时音效要压低：返回 0.4，否则 1.0
- (float)sfxScale;

// 口型回调：正在说话时以 ~10Hz 给出口型帧号 0/1/2（闭/半开/全开）
@property (nonatomic, copy, nullable) void (^mouthFrameHandler)(NSInteger frame);

@end

NS_ASSUME_NONNULL_END
