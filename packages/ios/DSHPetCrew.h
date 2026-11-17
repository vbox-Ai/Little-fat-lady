#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// S6c：多开时第 2..N 只宠物的管家。
///
/// 分工：
/// - 主宠仍归 DSHPetOverlay（窗口、气泡、旋转、尺寸持久化都在那边，不动它）；
/// - 这里的每一只都是独立实例（自带播放器 + 状态机 + 物理 + 手势）；
/// - 一个 accelerometer 订阅算倾斜，一个 CADisplayLink 统一驱动所有额外宠物的物理，
///   全部静止就自动停表，避免白白烧电。
///
/// 想要几只由面板决定：`multiPetsEnabled`（总开关）+ `multiPetsMax`（1–8）+
/// `perSession`（每只跟一个会话 / 同款多只）。
@interface DSHPetCrew : NSObject

+ (instancetype)shared;

/// 挂到宿主窗口上，并按当前配置决定要不要多开。
- (void)startInHost:(UIView *)host
           assetDir:(NSString *)assetDir
             bounds:(CGRect)bounds
             config:(NSDictionary *)cfg;

/// 配置或会话集合变了就调这个：该生的生、该收的收，不多不少。
- (void)reconcileWithBounds:(CGRect)bounds config:(NSDictionary *)cfg;

/// 旋转 / 分屏 / 面板改间距：所有额外宠物重排 + 夹回可见区。
- (void)relayoutInBounds:(CGRect)bounds settle:(BOOL)settle;

/// 关掉多开 / 宠物总开关关掉时用。
- (void)stop;

@property (nonatomic, readonly) NSUInteger count;

@end

/// 宠物被拖起来 / 被抛出去时发这个，让 crew 把物理表重新跑起来。
extern NSString *const DSHPetCrewWakeNotification;

NS_ASSUME_NONNULL_END
