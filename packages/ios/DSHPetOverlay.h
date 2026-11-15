#import <UIKit/UIKit.h>

// S2 浮层入口。调用方（Tweak.xm）拿到 SpringBoard 的 UIWindowScene 后调 attachToScene:。
@interface DSHPetOverlay : NSObject

+ (instancetype)shared;
+ (BOOL)attachToScene:(UIWindowScene *)scene;
- (void)detach;

@end
