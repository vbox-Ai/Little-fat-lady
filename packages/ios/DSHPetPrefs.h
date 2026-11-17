#import <Foundation/Foundation.h>

// S7：设置面板的数据面。
// 面板是 plist-only 的 PreferenceLoader bundle（没有可执行文件），
// Settings 把开关写进它自己的 CFPreferences 域；这里负责把域里的值读出来，
// 合并进 ui.json 的运行时配置字典，让 S2–S6 的既有代码一行不改就能吃到新设置。
//
// 两条铁律：
//   1. 面板只管「用户可调项」，运行时状态（centerX/centerY/taps/sizeManual）不许覆盖；
//   2. 用户没在面板里动过的键，不许写默认值进去——否则老用户升级后被悄悄改设置。

@interface DSHPetPrefs : NSObject

+ (BOOL)hasKey:(NSString *)key;
+ (BOOL)boolForKey:(NSString *)key fallback:(BOOL)fb;
+ (double)doubleForKey:(NSString *)key fallback:(double)fb;
+ (NSString *)stringForKey:(NSString *)key fallback:(NSString *)fb;

// 把面板里已设置的值合并进 cfg（就地改），返回是否发生了变化。
+ (BOOL)applyToUIConfig:(NSMutableDictionary *)cfg;

@end
