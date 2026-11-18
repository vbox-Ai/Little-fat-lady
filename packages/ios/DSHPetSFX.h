#import <Foundation/Foundation.h>

// S-V4：音效池（方案 §13.5）
//
// 桌宠的「手感」一半来自声音：戳一下有 80ms 轻响、拎起来有 pickup、落地有 bump。
// 但音效也是最容易变成噪音的东西，所以三条纪律写死在这一层：
//   1. 和语音共用一个 AVAudioSession（各建一个会互相 deactivate，声音断续）；
//   2. 语音在播时音量 ×0.4（问 DSHPetVoice.sfxScale），不许盖住台词；
//   3. 同名音效 120ms 内只响一次（连点十下不是要听十次爆音）。

NS_ASSUME_NONNULL_BEGIN

@interface DSHPetSFX : NSObject

@property (nonatomic, assign) BOOL enabled;      // 默认 YES
@property (nonatomic, assign) float baseVolume;  // 默认 1.0

+ (instancetype)shared;

// 名字对应素材文件名（不带扩展名）：tap / pickup / land / bump / chime
- (void)play:(NSString *)name;
- (void)play:(NSString *)name volume:(float)volume;

// 预热：把常用音效先读进内存，避免第一次点击有几十毫秒延迟
- (void)warmUp;
- (void)stopAll;

@end

NS_ASSUME_NONNULL_END
