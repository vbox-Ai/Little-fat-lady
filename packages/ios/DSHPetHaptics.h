#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, DSHPetHapticKind) {
    DSHPetHapticLight = 0,
    DSHPetHapticMedium = 1,
    DSHPetHapticHeavy = 2,
};

/// S5 触感反馈：点击/拖拽/落地/撞边各有轻重，
/// 总开关走 physics.hapticEnabled，整体力度走 physics.hapticLevel。
@interface DSHPetHaptics : NSObject

+ (instancetype)shared;

- (void)setEnabled:(BOOL)on;
- (void)setLevel:(NSString *)level;   // light / normal / heavy

/// key 用于节流（同一 key 在 minInterval 秒内只触发一次）
- (void)fire:(DSHPetHapticKind)kind key:(NSString *)key minInterval:(NSTimeInterval)sec;

/// 系统层面能不能震（低电量模式 / 关闭触感时降级为不震）
- (BOOL)available;

@end
