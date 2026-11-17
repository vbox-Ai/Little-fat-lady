#import <UIKit/UIKit.h>

// 会话信息气泡：宠物头顶那一小块深色圆角条，显示 DSH 的碎碎念 / 工作状态 / 待办提醒。
// 纯 UIKit，不依赖第三方；文字由 DSHPetBridge 从 /dsh-pet-7340/state 里取。
@interface DSHPetBubble : UIView

- (instancetype)initWithHostView:(UIView *)host;

// 显示一段文字；duration<=0 表示长驻（直到 dismiss）。
- (void)showText:(NSString *)text duration:(NSTimeInterval)duration;
- (void)dismissAnimated:(BOOL)animated;

// 宠物左上角在宿主坐标系里的位置 + 尺寸，用于把气泡摆到头顶。
- (void)anchorAtPetFrame:(CGRect)petFrame hostBounds:(CGRect)hostBounds safeInsets:(UIEdgeInsets)insets;

@property (nonatomic, readonly) BOOL visible;

@end
