#import <UIKit/UIKit.h>

// S-M1a：行走（moves）
//
// 上游 dsh-pet 的 `animations.moves.default` 里本来就有一组参数：
//   minDist 60 / maxDist 240 / margin 20 / leadSec 2 / tailSec 2
// 意思是：每隔一段时间挑一个 60–240px 远的目标，留 20px 边距，
// 走之前先播 2 秒"起步"动作，到了再播 2 秒"收尾"。
//
// 移植版之前完全没实现这段（只在 animator 里留了个 move 分桶），
// 所以宠物是钉在原地的。这个类就是补这一段。
//
// 设计取舍：
//   - **只管 x**。y 交给物理（重力/落地），两边都改 y 会打架；
//   - **物理停着才走**。被甩出去还没落地时走路，会像在空中蹬腿；
//   - **不改 frame 只改 center**。MEMORY 里那条"设 frame 会转两次、横屏丢方块"的坑。
//   - 用独立 NSTimer 而不是共享 CADisplayLink：走路要能被拖拽随时打断，
//     共享时钟会让"暂停/恢复"互相牵连。

NS_ASSUME_NONNULL_BEGIN

@interface DSHPetWalk : NSObject

- (instancetype)initWithPetView:(UIView *)petView hostView:(UIView *)hostView;

@property (nonatomic, assign) BOOL enabled;      // 总开关（面板「自动漫游」）
@property (nonatomic, assign) CGFloat speed;     // pt/s，默认 76（慢走感）
@property (nonatomic, assign) CGFloat margin;    // 距屏幕边，默认 24
@property (nonatomic, assign) CGFloat minDist;   // 单次最短距离，默认 60
@property (nonatomic, assign) CGFloat maxDist;   // 单次最长距离，默认 240

// 开始走 / 到了（渲染层拿这两个回调播 move 与 idle）
@property (nonatomic, copy, nullable) void (^onStartWalking)(void);
@property (nonatomic, copy, nullable) void (^onStopWalking)(void);

- (void)start;                 // 开始计时（不是马上走）
- (void)stop;                  // 彻底停（卸载时）
- (void)pause;                 // 被拖拽/被甩出时暂停
- (void)resume;                // 落地静止后恢复
- (BOOL)isWalking;

@end

NS_ASSUME_NONNULL_END
