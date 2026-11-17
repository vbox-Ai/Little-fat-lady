#import <Foundation/Foundation.h>

// 与宿主 DSH 的桥：轮询 /dsh-pet-7340/state，把会话信息抛给气泡。
// 只读，绝不调 /quit、不写 /config（见方案 §19 红线）。
extern NSString *const DSHPetSayNotification;   // userInfo: {text, kind}
extern NSString *const DSHPetStatusNotification; // userInfo: {state, task}

@interface DSHPetBridge : NSObject

+ (instancetype)shared;
- (void)startWithBase:(NSString *)base token:(NSString *)token interval:(NSTimeInterval)interval;
- (void)stop;
- (void)pollOnce;
@property (nonatomic, readonly) NSString *lastError;
@property (nonatomic, readonly) NSString *workState;

@end
