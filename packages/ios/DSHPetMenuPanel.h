#import <UIKit/UIKit.h>

// S6d：长按宠物弹出的操作菜单。
//
// 为什么不用 UIAlertController：
// 这个菜单得挂在"盖住整个桌面"的越狱窗口里，而那个窗口为了让触摸穿透到 SpringBoard，
// 重写了 hitTest 只放行宠物框。系统的 actionSheet 是另一个 VC 的视图，落在宠物框外面，
// 结果就是「菜单画得出来，但按钮点不动、取消也点不掉」（0.1.0-135 的实机现象）。
// 自绘一个普通视图，位置由我们自己决定，触摸也由我们自己放行，不依赖系统的展示流程。
typedef void (^DSHPetMenuHandler)(NSInteger index);

@interface DSHPetMenuPanel : UIView

/// titles 最后一项惯例是「取消」；handler 只在非取消项上回调。
- (instancetype)initWithTitle:(NSString *)title
                       titles:(NSArray<NSString *> *)titles
                      handler:(DSHPetMenuHandler)handler;

- (void)showInHost:(UIView *)host anchorFrame:(CGRect)anchor safeInsets:(UIEdgeInsets)safeInsets;
- (void)dismiss;
- (BOOL)isShowing;

@end
