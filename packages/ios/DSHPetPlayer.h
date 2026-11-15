#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 宠物本体播放器：AVPlayerLayer + HEVC-alpha 视频，循环播放。
/// S3 先只负责"能放、能循环、能消失时停"，动画状态机在 S4 接。
@interface DSHPetPlayer : NSObject

+ (instancetype)shared;

/// 把播放层挂到宿主 view 上；size 是宠物在屏幕上的显示尺寸。
- (BOOL)attachToHostView:(UIView *)host size:(CGSize)size;

/// 素材目录：/var/mobile/Library/DSHPet/assets（S9 下载器会往这里灌）
- (void)reloadAsset;

- (void)setDisplaySize:(CGSize)size;
- (void)play;
- (void)pause;

@property (nonatomic, readonly, nullable) NSURL *currentURL;
@property (nonatomic, readonly) BOOL hasAsset;

@end

NS_ASSUME_NONNULL_END
