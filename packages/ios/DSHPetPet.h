#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class DSHPetPlayer;
@class DSHPetAnimator;

/// S6c：一只「额外」宠物。
///
/// 为什么不把 DSHPetOverlay 整个改成宠物数组：主宠那条链路（窗口、气泡、旋转、
/// safeArea 夹取、尺寸持久化）已经被真机验过 20 多个版本，动它的风险远大于收益。
/// 所以主宠继续由 DSHPetOverlay 自己管，这里只负责第 2..N 只：
/// 每只自带一套 播放器 + 状态机 + 物理 + 手势，彼此独立，互相同步不了。
///
/// 位置不落盘：多开的排布是"每次落下来重新分"，落盘反而会让下次开机叠成一坨。
@interface DSHPetPet : NSObject

@property (nonatomic, strong, readonly) UIView *box;
@property (nonatomic, strong, readonly) DSHPetPlayer *player;
@property (nonatomic, strong, readonly) DSHPetAnimator *animator;

/// 跟随哪个 DSH 会话（nil = 同款多只模式，不绑定会话）
@property (nonatomic, copy, nullable) NSString *sessionId;

@property (nonatomic, assign, readonly) BOOL dragging;
@property (nonatomic, assign, readonly) CGSize petSize;
@property (nonatomic, assign, readonly) CGPoint center;

- (instancetype)initWithHostView:(UIView *)host
                        assetDir:(NSString *)assetDir
                        sizeRatio:(CGFloat)ratio
                           config:(NSDictionary *)cfg;

/// 出生位置：屏幕上方随机 x，从屏幕外往下掉（操作员拍板的"从上方随机落下"）。
- (void)dropIntoBounds:(CGRect)hostBounds;

/// 宿主 bounds 变了（旋转/分屏）：按新 bounds 重新算尺寸并夹回可见区。
- (void)relayoutInBounds:(CGRect)hostBounds settle:(BOOL)settle;

/// 物理一步。返回 YES 表示还在动（crew 用它决定 CADisplayLink 要不要继续跑）。
/// others 是本步要避让的其它宠物 frame（NSValue 包 CGRect），只做轻微排斥，不做刚体碰撞。
- (BOOL)stepWithDt:(CFTimeInterval)dt
            others:(NSArray<NSValue *> *)others
              host:(CGRect)hostBounds
            config:(nullable NSDictionary *)cfg;   // nil = 沿用建实例时那份配置

/// 停掉播放（不销毁视图），用于「关掉多开」时平滑退场。
- (void)pause;
- (void)invalidate;

/// crew 内部用：把统一的倾斜分量（-1..1）灌进来；valid=NO 表示按正立重力算。
- (void)crewSetTilt:(CGPoint)t valid:(BOOL)valid;

/// 当前占位 frame（crew 拿它算互相排斥）
@property (nonatomic, readonly) CGRect frame;

@end

NS_ASSUME_NONNULL_END
