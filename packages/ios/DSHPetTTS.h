//
//  DSHPetTTS.h
//  小肥娘 · 远端语音合成（可插拔引擎）
//
//  设计约束（见《小肥娘_总纲开发方案.md》§11.7 / §13）：
//  1. 本类只负责「文字 → 本地音频文件」，不负责播放；播放归 DSHPetVoice。
//  2. 任何失败都必须能被上层静默忽略并回落到系统原生合成，绝不把错误抛给用户。
//  3. 密钥只进 Keychain，面板写入的明文键（ttsToken / ttsAPIKey）首次读取即迁移并抹掉。
//  4. 合成结果落盘缓存，同一句话第二次说不再走网络（桌宠会重复说同几句）。
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, DSHPetTTSEngine) {
    DSHPetTTSEngineNative = 0,   // 系统 AVSpeechSynthesizer（DSHPetVoice 内部实现，不经过本类网络）
    DSHPetTTSEngineVolc   = 1,   // 火山引擎 / 豆包 语音合成大模型（openspeech.bytedance.com）
    DSHPetTTSEngineOpenAI = 2,   // OpenAI 兼容 /audio/speech 网关
};

@interface DSHPetTTS : NSObject

+ (instancetype)shared;

/// 从 DSHPetPrefs 重新读一遍配置（引擎、音色、语速、地址…）。每次说话前调用，热生效。
- (void)reloadConfig;

/// 配置是否足以发起一次远端合成（引擎非 native 且该引擎需要的密钥/地址齐全）。
- (BOOL)isReady;

/// 当前引擎（reloadConfig 后有效）。
@property (nonatomic, readonly) DSHPetTTSEngine engine;

/// 合成：成功回传本地 mp3 文件 URL（可能是缓存），失败回传 error。
/// completion 一定在主线程回调，且只会回调一次。
- (void)synthesize:(NSString *)text completion:(void (^)(NSURL *file, NSError *err))completion;

/// Keychain 三件套（豆包 access token）
+ (BOOL)hasAccessToken;
+ (BOOL)setAccessToken:(NSString *)token;
+ (BOOL)clearAccessToken;

/// Keychain 三件套（OpenAI 兼容网关 Key）
+ (BOOL)hasAPIKey;
+ (BOOL)setAPIKey:(NSString *)key;
+ (BOOL)clearAPIKey;

/// 清空音频缓存（面板「清理语音缓存」用）。
- (void)purgeCache;

/// 缓存目录（日志/调试用）。
- (NSString *)cacheDirectory;

@end
