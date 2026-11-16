#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 宠物本体播放器：AVPlayerLayer + 透明视频（HEVC-alpha / ProRes-4444-alpha），循环播放。
/// S3 只负责"能放、能循环、消失时停"，动画状态机在 S4。
@interface DSHPetPlayer : NSObject {
    NSTimer *_watchdog;
}

/// S4：切到指定片段（状态机用）。不会重建 layer，只换 AVPlayerItem。
- (BOOL)playClipAtURL:(NSURL *)url;
- (BOOL)playWebPAtURL:(NSURL *)url;

/// 方案 A：彩色路 + 蒙版路，两路同时在播放器里跑，用 CoreImage 合成出真透明。
/// 上游没给 HEVC-alpha，ProRes 4444-alpha 在 iOS 播放链路又不稳，所以自己合。
- (BOOL)playClipAtURL:(NSURL *)url matteURL:(nullable NSURL *)matteURL;

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

/// 首帧是否已可播（item.status == readyToPlay）。没 ready 就说明素材是坏的/解码失败，
/// 这种情况浮层必须把占位块亮回来，否则桌面上什么都看不到。
@property (nonatomic, readonly) BOOL isReady;

/// 取当前素材的第一帧（带 alpha 的静帧）。
/// 用途：ProRes/HEVC 的透明通道在播放链路上失效时，至少还能把宠物"照片"贴在桌上，
/// 而不是留一个方块 —— 同时把"能解码但放不动"这个事实写进日志。
- (nullable UIImage *)posterImage;

/// 当前素材的原始像素尺寸（无素材时返回 CGSizeZero）。
/// 宿主尺寸要按这个比例算，写死 2160x1215 会让不同素材出现大片透明边。
@property (nonatomic, readonly) CGSize naturalSize;

/// S4：3s 看门狗，第三方播放器/来电把 AVPlayer 停了之后自动恢复。
- (void)startWatchdog;

@end

NS_ASSUME_NONNULL_END
