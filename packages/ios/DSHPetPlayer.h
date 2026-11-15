#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 宠物本体播放器：AVPlayerLayer + 透明视频（HEVC-alpha / ProRes-4444-alpha），循环播放。
/// S3 只负责"能放、能循环、消失时停"，动画状态机在 S4。
@interface DSHPetPlayer : NSObject

+ (instancetype)shared;

/// 把播放层挂到宿主 view 上；size 是宠物在屏幕上的显示尺寸。
- (BOOL)attachToHostView:(UIView *)host size:(CGSize)size;

/// 重新扫描素材目录（S9 下载器灌完素材后调）。
- (void)reloadAsset;

- (void)setDisplaySize:(CGSize)size;
- (void)play;
- (void)pause;

@property (nonatomic, readonly, nullable) NSURL *currentURL;
@property (nonatomic, readonly) BOOL hasAsset;

/// 当前素材的原始像素尺寸（无素材时返回 CGSizeZero）。
/// 宿主尺寸要按这个比例算，写死 2160x1215 会让不同素材出现大片透明边。
@property (nonatomic, readonly) CGSize naturalSize;

@end

NS_ASSUME_NONNULL_END
