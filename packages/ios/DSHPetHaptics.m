#import "DSHPetHaptics.h"
#import <UIKit/UIKit.h>
#import "DSHPetBoot.h"

@implementation DSHPetHaptics {
    BOOL _enabled;
    NSInteger _shift;              // -1 轻 / 0 标准 / +1 重
    UIImpactFeedbackGenerator *_light;
    UIImpactFeedbackGenerator *_medium;
    UIImpactFeedbackGenerator *_heavy;
    NSMutableDictionary<NSString *, NSNumber *> *_lastFire;
}

+ (instancetype)shared {
    static DSHPetHaptics *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[DSHPetHaptics alloc] init]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _enabled = YES;
        _shift = 0;
        _lastFire = [NSMutableDictionary dictionary];
        _light = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        _medium = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        _heavy = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
        [_light prepare];
        [_medium prepare];
        [_heavy prepare];
    }
    return self;
}

- (void)setEnabled:(BOOL)on {
    _enabled = on;
}

- (void)setLevel:(NSString *)level {
    if ([level isEqualToString:@"light"]) _shift = -1;
    else if ([level isEqualToString:@"heavy"]) _shift = 1;
    else _shift = 0;
}

- (BOOL)available {
    if (!_enabled) return NO;
    // 低电量模式 / 系统关了触感 → 不震（省电优先，也让"没反应"有解释）
    if ([NSProcessInfo processInfo].isLowPowerModeEnabled) return NO;
    return YES;
}

- (void)fire:(DSHPetHapticKind)kind key:(NSString *)key minInterval:(NSTimeInterval)sec {
    if (![self available]) return;

    NSString *k = key.length ? key : @"default";
    CFTimeInterval now = CACurrentMediaTime();
    NSNumber *last = _lastFire[k];
    if (last && (now - last.doubleValue) < sec) return;
    _lastFire[k] = @(now);

    NSInteger idx = (NSInteger)kind + _shift;
    if (idx < 0) idx = 0;
    if (idx > 2) idx = 2;

    UIImpactFeedbackGenerator *g = (idx == 0 ? _light : (idx == 1 ? _medium : _heavy));
    [g prepare];
    [g impactOccurred];
    DSHPetLog(@"haptic", @"fire", @"debug", @{ @"kind": @(idx), @"key": k });
}

@end
