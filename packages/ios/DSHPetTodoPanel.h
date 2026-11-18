#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// S6d 待办面板：长按宠物弹出的只读清单。
///
/// 为什么单独一个类而不是塞进气泡：
///   气泡是"一句话"的载体（最多 3 行、点一下收起），待办是"一列条目"，
///   两者的排版、超时、点击语义都不一样，混在一起会把气泡逻辑撑烂。
///
/// 数据只读：宿主 `/todos` 的写接口（POST/PATCH/DELETE）手机端不碰 ——
/// 改宿主状态属于红线之外，面板只负责"让你看见"。
@interface DSHPetTodoPanel : UIView

/// items 是上游 TodoItem 原始字典（id/text/dueAt/done/…）。
/// 传空数组会显示"没有待办"而不是空白卡片，省得用户以为卡死了。
- (void)showTodos:(NSArray<NSDictionary *> *)items
           inHost:(UIView *)host
      anchorFrame:(CGRect)anchor
        safeInsets:(UIEdgeInsets)safeInsets;

/// 数据还没回来时先占位，别让人以为长按没反应
- (void)showLoadingInHost:(UIView *)host anchorFrame:(CGRect)anchor safeInsets:(UIEdgeInsets)safeInsets;
- (void)showError:(NSString *)text inHost:(UIView *)host anchorFrame:(CGRect)anchor safeInsets:(UIEdgeInsets)safeInsets;

- (void)dismiss;

@end

NS_ASSUME_NONNULL_END
