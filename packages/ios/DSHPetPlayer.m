#import "DSHPetPlayer.h"
#import <math.h>
#import "DSHPetAssets.h"
#import <AVFoundation/AVAudioSession.h>
#import "DSHPetBoot.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <QuartzCore/QuartzCore.h>
#import <ImageIO/ImageIO.h>

static NSString *const kPetAssetDir = @"/var/mobile/Library/DSHPet/assets";
static NSString *const kPetAssetDirFallback = @"/var/jb/Library/Application Support/DSHPet";

@interface DSHPetPlayer () {
    AVPlayer *_mattePlayer;
    AVPlayerItemVideoOutput *_colorOut;
    AVPlayerItemVideoOutput *_matteOut;
    CADisplayLink *_link;
    CIContext *_ci;
    BOOL _compositeReady;
    CGSize _naturalSize;
    CGImageSourceRef _webpSrc;
    NSArray *_webpFrames;
    BOOL _webpFirstPosted;
    NSInteger _webpCount;
    NSInteger _webpIndex;
    CFTimeInterval _webpNext;
    NSTimeInterval _webpDur;
}
@property (nonatomic, strong) UIView *host;
@property (nonatomic, strong) CALayer *contentLayer;
@property (nonatomic, strong) NSURL *matteURL;
- (void)startCompositeWithColorURL:(NSURL *)curl matteURL:(NSURL *)murl;
- (void)stopComposite;
- (void)layoutContentsForImage:(CGImageRef)img;
- (void)onTick:(CADisplayLink *)link;
@property (nonatomic, strong) AVPlayerLayer *layer;
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) NSURL *currentURL;
@property (nonatomic, assign) CGSize displaySize;
@property (nonatomic, assign) BOOL observing;
- (void)onAudioInterruption:(NSNotification *)n;
- (void)onAppActive;
- (void)onWatchdog:(NSTimer *)t;
@end

@implementation DSHPetPlayer {
    id _curFrame;   // 当前帧 CGImage，尺寸变化后用它重排
    NSInteger _webpToken;  // 解码任务身份号：后台解码回切时对不上就丢弃，防快速换片竞态
}

+ (instancetype)shared {
    static DSHPetPlayer *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[DSHPetPlayer alloc] init]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _displaySize = CGSizeMake(130, 100);
    }
    return self;
}

#pragma mark - 素材

- (nullable NSURL *)pickInDirectory:(NSString *)dir {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *names = [fm contentsOfDirectoryAtPath:dir error:NULL];
    if (!names.count) return nil;

    // 两种落盘方式都要认：
    //  A) 平铺：main.mov / idle.mov
    //  B) 分桶：idle/001-idle.mov、play/012-play.mov（上游素材包 + 0.1.0-53 起只有这种）
    // 早先只扫顶层，分桶布局下返回 nil → hasPet=NO → 桌面只剩绿色占位方块。
    NSMutableArray<NSString *> *top = [NSMutableArray array];
    NSMutableArray<NSString *> *deep = [NSMutableArray array];
    for (NSString *n in names) {
        NSString *low = n.lowercaseString;
        NSString *full = [dir stringByAppendingPathComponent:n];
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:full isDirectory:&isDir] && isDir) {
            NSArray<NSString *> *inner = [fm contentsOfDirectoryAtPath:full error:NULL] ?: @[];
            for (NSString *m in [inner sortedArrayUsingSelector:@selector(compare:)]) {
                NSString *mlow = m.lowercaseString;
                if ([mlow hasSuffix:@".mov"] || [mlow hasSuffix:@".mp4"] || [mlow hasSuffix:@".m4v"]) {
                    [deep addObject:[n stringByAppendingPathComponent:m]];
                }
            }
            continue;
        }
        if ([low hasSuffix:@".mov"] || [low hasSuffix:@".mp4"] || [low hasSuffix:@".m4v"]) {
            [top addObject:n];
        }
    }
    if (!top.count && !deep.count) return nil;
    [top sortUsingSelector:@selector(compare:)];

    // 优先级：顶层 main.* > 任意层 main.* > 顶层非 demo > 分桶（idle 优先，其余按名字）> 顶层其余
    NSString *picked = nil;
    for (NSString *n in top) {
        if ([n.lowercaseString hasPrefix:@"main."]) { picked = n; break; }
    }
    if (!picked) {
        for (NSString *n in deep) {
            if ([n.lowercaseString containsString:@"/main."]) { picked = n; break; }
        }
    }
    // 分桶素材优先于平铺文件：平铺的是早期演示片（320x314，方形画布），
    // 被放进 130pt 宿主里等于放大 1.4 倍 —— 真机"待机时糊一下"就是抽到它。
    if (!picked && deep.count) {
        NSArray<NSString *> *sorted = [deep sortedArrayUsingSelector:@selector(compare:)];
        for (NSString *n in sorted) {
            if ([n.lowercaseString hasPrefix:@"idle/"]) { picked = n; break; }
        }
        if (!picked) picked = sorted.firstObject;
    }
    if (!picked) {
        for (NSString *n in top) {
            if (![n.lowercaseString isEqualToString:@"demo.mov"]) { picked = n; break; }
        }
    }
    if (!picked) {
        NSArray<NSString *> *sorted = [deep sortedArrayUsingSelector:@selector(compare:)];
        for (NSString *n in sorted) {
            if ([n.lowercaseString hasPrefix:@"idle/"]) { picked = n; break; }
        }
        if (!picked) picked = sorted.firstObject;
    }
    if (!picked) picked = top.firstObject;
    return [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:picked]];
}

- (nullable NSURL *)findFirstMovie {
    // 逐个候选根目录找：运行目录 → /var/jb/... → /Library/...（roothide 假根）。
    // 之前在设备上 postinst 拷素材没成，assets 目录是空的，于是只有绿方块；
    // 现在不再依赖 postinst，谁看见素材就用谁。
    for (NSString *dir in DSHPetAssetRoots()) {
        NSURL *u = [self pickInDirectory:dir];
        if (u) {
            DSHPetLog(@"player", @"asset-root", @"debug", @{ @"dir": dir, @"file": u.lastPathComponent });
            return u;
        }
    }
    return nil;
}

- (BOOL)playClipAtURL:(NSURL *)url {
    // 一律走合成：有蒙版就用蒙版，没有就用亮度键把黑底抠掉。
    // 早期版本这里直接挂 AVPlayerLayer，黑底素材会把黑块一起画上桌面。
    if (!url) return NO;
    return [self playClipAtURL:url matteURL:nil];
}

- (void)startCompositeWithColorURL:(NSURL *)curl matteURL:(NSURL *)murl {
    [self stopComposite];
    _matteURL = murl;

    NSDictionary *attrs = @{ (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA) };
    _colorOut = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:attrs];
    _matteOut = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:attrs];

    AVPlayerItem *cItem = [AVPlayerItem playerItemWithAsset:[AVURLAsset URLAssetWithURL:curl options:nil]];
    AVPlayerItem *mItem = murl ? [AVPlayerItem playerItemWithAsset:[AVURLAsset URLAssetWithURL:murl options:nil]] : nil;
    [cItem addOutput:_colorOut];
    if (mItem) [mItem addOutput:_matteOut];
    else _matteOut = nil;

    if (!_player) {
        _player = [AVPlayer playerWithPlayerItem:cItem];
        _player.muted = YES;
        _player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
        _player.allowsExternalPlayback = NO;
    } else {
        [_player replaceCurrentItemWithPlayerItem:cItem];
    }
    if (mItem) {
        if (!_mattePlayer) {
            _mattePlayer = [AVPlayer playerWithPlayerItem:mItem];
            _mattePlayer.muted = YES;
            _mattePlayer.actionAtItemEnd = AVPlayerActionAtItemEndNone;
        } else {
            [_mattePlayer replaceCurrentItemWithPlayerItem:mItem];
        }
        _mattePlayer.automaticallyWaitsToMinimizeStalling = NO;
        [_mattePlayer play];
    } else if (_mattePlayer) {
        [_mattePlayer pause];
    }
    _player.automaticallyWaitsToMinimizeStalling = NO;

    if (!_contentLayer) {
        _contentLayer = [CALayer layer];
        _contentLayer.opaque = NO;
        _contentLayer.backgroundColor = [UIColor clearColor].CGColor;
        _contentLayer.contentsGravity = kCAGravityResizeAspect;
        _contentLayer.magnificationFilter = kCAFilterLinear;
        _contentLayer.minificationFilter = kCAFilterLinear;
    }
    if (_contentLayer.superlayer == nil && _host) {
        [_host.layer addSublayer:_contentLayer];
        [self syncLayerFrame];
    }

    _compositeReady = NO;
    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(onTick:)];
    _link.preferredFramesPerSecond = 12;
    [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

    [_player play];
    [self observeEnd];
}

- (void)stopComposite {
    [_link invalidate];
    _link = nil;
    [_player pause];
    [_mattePlayer pause];
    _colorOut = nil;
    _matteOut = nil;
    _compositeReady = NO;
}

- (void)onTick:(CADisplayLink *)link {
    if (_webpSrc) { [self advanceWebP:link.timestamp force:NO]; return; }
    if (!_colorOut) return;
    AVPlayerItem *cItem = _player.currentItem;
    AVPlayerItem *mItem = _matteOut ? _mattePlayer.currentItem : nil;
    if (!cItem) return;
    if (cItem.status != AVPlayerItemStatusReadyToPlay) return;
    if (_matteOut && (!mItem || mItem.status != AVPlayerItemStatusReadyToPlay)) return;

    CMTime t = cItem.currentTime;
    if ([cItem duration].flags && CMTimeCompare(t, cItem.duration) >= 0) {
        // 循环：两路同时回零，避免音画/影音错位
        [cItem seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
        if (mItem) [mItem seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
        return;
    }
    CVPixelBufferRef cb = [_colorOut copyPixelBufferForItemTime:t itemTimeForDisplay:NULL];
    CVPixelBufferRef mb = _matteOut ? [_matteOut copyPixelBufferForItemTime:t itemTimeForDisplay:NULL] : NULL;
    if (!cb) {
        if (mb) CVPixelBufferRelease(mb);
        return;
    }

    if (!_ci) _ci = [CIContext contextWithOptions:@{ kCIContextUseSoftwareRenderer: @NO }];

    CIImage *color = [CIImage imageWithCVPixelBuffer:cb];

    // 关键：CIBlendWithMask 按蒙版的**亮度**做遮罩，不是按 alpha。
    // 之前把值塞进 alpha、RGB 清零（inputAVector=(1,0,0,0)），亮度恒为 0
    // → 整只小肥娘永远全透明，真机就是"太透明/忽隐忽现/看不见"。
    // 正确做法：先得到灰度图，再用 CIMaskToAlpha 把灰度变成"白底 + alpha"，
    // 最后用 CISourceInCompositing 按 alpha 取色。
    CIImage *gray = nil;
    if (mb) {
        // 独立蒙版：蒙版本身就是灰度
        gray = [CIImage imageWithCVPixelBuffer:mb];
    } else {
        // 没有蒙版：拿彩色画面的亮度当键源（黑底素材可用）
        gray = [color imageByApplyingFilter:@"CIColorMatrix" withInputParameters:@{
            @"inputRVector": [CIVector vectorWithX:0.299 Y:0.587 Z:0.114 W:0],
            @"inputGVector": [CIVector vectorWithX:0.299 Y:0.587 Z:0.114 W:0],
            @"inputBVector": [CIVector vectorWithX:0.299 Y:0.587 Z:0.114 W:0],
            @"inputAVector": [CIVector vectorWithX:0 Y:0 Z:0 W:1],
        }];
    }
    // 视频编码的灰边会让角色整体半透明：加对比、轻微压暗，把中间调推向 0/1
    gray = [gray imageByApplyingFilter:@"CIColorControls" withInputParameters:@{
        @"inputContrast": @2.4,
        @"inputBrightness": @(-0.22),
        @"inputSaturation": @0,
    }];
    CIImage *mask = [gray imageByApplyingFilter:@"CIMaskToAlpha" withInputParameters:@{}];

    CIImage *out = [[CIFilter filterWithName:@"CISourceInCompositing" keysAndValues:
                     kCIInputImageKey, color,
                     kCIInputBackgroundImageKey, mask, nil] outputImage];

    // 首帧把蒙版平均 alpha 记下来：接近 0 说明蒙版方向错，接近 1 说明蒙版全白，
    // 正常角色素材一般在 0.15~0.5。
    if (!_compositeReady) {
        CIFilter *avg = [CIFilter filterWithName:@"CIAreaAverage" keysAndValues:
                         kCIInputImageKey, mask,
                         @"inputExtent", [CIVector vectorWithCGRect:color.extent], nil];
        CIImage *avgOut = avg.outputImage;
        uint8_t px[4] = {0, 0, 0, 0};
        if (avgOut) {
            [_ci render:avgOut toBitmap:px rowBytes:4 bounds:CGRectMake(0, 0, 1, 1)
                  format:kCIFormatRGBA8 colorSpace:NULL];
        }
        DSHPetLog(@"render", @"mask-stat", @"debug", @{
            @"a": @(px[3] / 255.0), @"mode": mb ? @"matte" : @"lumakey" });
    }

    CGImageRef cg = [_ci createCGImage:out fromRect:color.extent];
    if (cg) {
        _contentLayer.contents = (__bridge_transfer id)cg;
        if (!_compositeReady) {
            _compositeReady = YES;
            _naturalSize = CGSizeMake(CGImageGetWidth(cg), CGImageGetHeight(cg));
            DSHPetLog(@"render", @"composite-ok", @"info", @{
                @"w": @(_naturalSize.width), @"h": @(_naturalSize.height),
                @"mode": _matteOut ? @"matte" : @"lumakey" });
        }
    }
    CVPixelBufferRelease(cb);
    if (mb) CVPixelBufferRelease(mb);
}

- (BOOL)playClipAtURL:(NSURL *)url matteURL:(nullable NSURL *)matteURL {
    if ([[[url pathExtension] lowercaseString] isEqualToString:@"webp"]) {
        return [self playWebPAtURL:url];
    }
    if (!url) return NO;
    if (_currentURL && [_currentURL.path isEqualToString:url.path] &&
        _matteURL && [_matteURL.path isEqualToString:matteURL.path] && _link) {
        [_player play];
        [_mattePlayer play];
        return YES;
    }
    _currentURL = url;
    [self startCompositeWithColorURL:url matteURL:matteURL];
    DSHPetLog(@"render", @"player-load", @"info", @{
        @"file": url.lastPathComponent ?: @"",
        @"matte": matteURL.lastPathComponent ?: @"",
        @"mode": @"composite" });
    return YES;
}

- (nullable UIImage *)posterImage {
    if (!_currentURL) return nil;
    AVAsset *asset = [AVURLAsset URLAssetWithURL:_currentURL options:nil];
    AVAssetImageGenerator *gen = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    gen.appliesPreferredTrackTransform = YES;
    gen.requestedTimeToleranceBefore = kCMTimeZero;
    gen.requestedTimeToleranceAfter = kCMTimeZero;
    NSError *err = nil;
    CGImageRef img = [gen copyCGImageAtTime:CMTimeMakeWithSeconds(0.5, 600) actualTime:NULL error:&err];
    if (!img) {
        DSHPetLog(@"render", @"poster-failed", @"error", @{ @"err": err.localizedDescription ?: @"nil" });
        return nil;
    }
    UIImage *out = [UIImage imageWithCGImage:img scale:[UIScreen mainScreen].scale orientation:UIImageOrientationUp];
    CGImageRelease(img);
    DSHPetLog(@"render", @"poster-ok", @"info", @{ @"w": @(out.size.width), @"h": @(out.size.height) });
    return out;
}


// 让「一个源像素 = 一个屏幕像素」，且**不许拉伸**。
// 做法：按图像自身比例在宿主 bounds 里做 aspect-fit，得到 rect；
// 把 contentLayer.frame 设成 rect，contentsScale = 图像宽/rect 宽，gravity 用 Resize 填满 rect。
// 只改 contentsScale 不改 frame 的话，Resize 会按图层比例拉伸（0.1.0-94 的"拉长"）；
// 用 ResizeAspect 不拉伸，但又会二次缩放导致发糊。
- (void)layoutContentsForImage:(CGImageRef)img {
    if (!img) return;
    CGFloat imgW = (CGFloat)CGImageGetWidth(img);
    CGFloat imgH = (CGFloat)CGImageGetHeight(img);
    if (imgW < 1.0 || imgH < 1.0) return;

    CGRect box = self.host ? self.host.bounds : self.contentLayer.superlayer.bounds;
    if (CGRectGetWidth(box) < 1.0 || CGRectGetHeight(box) < 1.0) return;

    CGFloat sc = [UIScreen mainScreen].scale;
    if (sc < 1.0) sc = 2.0;

    // 绘制策略：**按宠物框铺满，但绝不超过 1:1**。
    //  - 框比画布小（默认 130pt vs 390px 画布）→ 缩小采样，CA 的降采样质量好，锐。
    //  - 框比画布大 → 夹在 1:1 上限，宁可宠物比框小一点，也不许放大（放大必糊）。
    // 关键：尺寸和 position 都落在 1/scale 的整数倍上，否则合成器仍会重采样。
    CGFloat maxW = imgW / sc;
    CGFloat boxW = CGRectGetWidth(box);
    CGFloat boxH = CGRectGetHeight(box);
    CGFloat w = boxW < maxW ? boxW : maxW;
    CGFloat h = w * (imgH / imgW);
    if (h > boxH) { h = boxH; w = h * (imgW / imgH); }
    if (w > maxW) { w = maxW; h = w * (imgH / imgW); }
    w = round(w * sc) / sc;
    h = round(h * sc) / sc;

    CGFloat cx = CGRectGetMidX(box);
    CGFloat cy = CGRectGetMidY(box);
    cx = round(cx * sc) / sc;
    cy = round(cy * sc) / sc;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.contentLayer.bounds = CGRectMake(0, 0, w, h);
    self.contentLayer.position = CGPointMake(cx, cy);
    self.contentLayer.contentsGravity = kCAGravityResize;
    self.contentLayer.contentsScale = sc;
    [CATransaction commit];
}

- (void)refreshLayout {
    // 宿主尺寸变了（捏合/旋转/换屏）→ 立刻按当前帧重排，别等下一帧动画推进
    if (_curFrame) {
        [self layoutContentsForImage:(__bridge CGImageRef)_curFrame];
    }
}

- (BOOL)isReady {
    if (_compositeReady) return YES;
    AVPlayerItem *item = _player.currentItem;
    return item != nil && item.status == AVPlayerItemStatusReadyToPlay;
}

- (void)watchItemStatus:(AVPlayerItem *)item {
    __weak DSHPetPlayer *weakSelf = self;
    [item addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:NULL];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        DSHPetPlayer *s = weakSelf;
        if (!s) return;
        AVPlayerItem *cur = s->_player.currentItem;
        if (!cur) return;
        DSHPetLog(@"render", cur.status == AVPlayerItemStatusReadyToPlay ? @"player-ready" : @"player-not-ready",
                  cur.status == AVPlayerItemStatusFailed ? @"error" : @"info",
                  @{ @"status": @(cur.status),
                     @"url": cur.asset ? @"yes" : @"no",
                     @"err": cur.error.localizedDescription ?: @"none",
                     @"dur": (CFTimeInterval)isfinite(CMTimeGetSeconds(cur.duration)) ? @(CMTimeGetSeconds(cur.duration)) : @(-1) });
    });
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"status"] && [object isKindOfClass:[AVPlayerItem class]]) {
        AVPlayerItem *item = (AVPlayerItem *)object;
        if (item.status == AVPlayerItemStatusFailed) {
            DSHPetLog(@"render", @"player-failed", @"error", @{ @"err": item.error.localizedDescription ?: @"?" });
        } else if (item.status == AVPlayerItemStatusReadyToPlay) {
            DSHPetLog(@"render", @"player-ok", @"info", @{ @"w": @(item.presentationSize.width), @"h": @(item.presentationSize.height) });
        }
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)reloadAsset {
    NSURL *url = [self findFirstMovie];
    if (!url) {
        DSHPetLog(@"render", @"player-no-asset", @"info", @{ @"dir": kPetAssetDir });
        [self teardown];
        return;
    }
    [self playClipAtURL:url];
}

- (void)observeEnd {
    if (_observing) return;
    _observing = YES;
    __weak DSHPetPlayer *weakSelf = self;
    [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        DSHPetPlayer *s = weakSelf;
        if (!s || !s->_player) return;
        if (note.object != s->_player.currentItem) return;
        [s->_player seekToTime:kCMTimeZero];
        [s->_player play];
    }];
}

- (void)teardown {
    [_player pause];
    [_layer removeFromSuperlayer];
    _layer = nil;
    _player = nil;
    _currentURL = nil;
}

#pragma mark - 展示

- (BOOL)attachToHostView:(UIView *)host size:(CGSize)size {
    if (!host) return NO;
    _host = host;
    _displaySize = size;
    [self reloadAsset];

    if (_contentLayer) {
        [_host.layer addSublayer:_contentLayer];
        [self syncLayerFrame];
    }
    if (_layer) {
        [_host.layer addSublayer:_layer];
        [self syncLayerFrame];
    }
    if (_player) [self play];
    return _layer != nil || _contentLayer != nil;
}

- (void)setDisplaySize:(CGSize)size {
    if (CGSizeEqualToSize(size, _displaySize)) return;
    _displaySize = size;
    [self syncLayerFrame];
    [self refreshLayout];
}

- (void)syncLayerFrame {
    // 注意：不能因为 _layer 为 nil 就直接 return。
    // 0.1.0-70 起所有素材都走合成，_layer 根本不会被创建，
    // 早退会让 _contentLayer.frame 一直是零尺寸 —— 方块藏起来后桌面上什么都没有。
    if (!_layer && !_contentLayer) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CGRect b = self.host ? self.host.bounds : CGRectMake(0, 0, _displaySize.width, _displaySize.height);
    if (b.size.width < 1.0 || b.size.height < 1.0) {
        b = CGRectMake(0, 0, _displaySize.width, _displaySize.height);
    }
    if (_layer) _layer.frame = b;
    if (_contentLayer) _contentLayer.frame = b;
    [CATransaction commit];

    // 关键：frame 铺满宿主后必须按图像比例重新 fit。
    // 只铺不收的话，contentsGravity=Resize 会按图层比例拉伸——这就是"注销后拉长、
    // 捏一下又好了"的真因（pinch 走 applyPetWidth → refreshLayout 才重算 rect）。
    if (_curFrame) [self layoutContentsForImage:(__bridge CGImageRef)_curFrame];
}

- (void)play {
    [self startWatchdog];
    if (_player) {
        // .ambient + mixWithOthers：跟短剧/音乐共存，不打断别人，也不被别人打断后永久静音
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            AVAudioSession *s = [AVAudioSession sharedInstance];
            [s setCategory:AVAudioSessionCategoryAmbient withOptions:AVAudioSessionCategoryOptionMixWithOthers error:NULL];
            [s setActive:YES error:NULL];
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(onAudioInterruption:)
                                                         name:AVAudioSessionInterruptionNotification
                                                       object:nil];
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(onAppActive)
                                                         name:UIApplicationDidBecomeActiveNotification
                                                       object:nil];
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(onAppActive)
                                                         name:UIApplicationWillEnterForegroundNotification
                                                       object:nil];
        });
    }
    if (!_player) return;
    [_player play];
    DSHPetLog(@"render", @"player-play", @"debug", @{ @"rate": @(_player.rate) });
}

- (void)pause {
    if (_mattePlayer) [_mattePlayer pause];
    if (!_player) return;
    [_player pause];
    DSHPetLog(@"render", @"player-pause", @"debug", nil);
}

- (BOOL)hasAsset { return _layer != nil || _contentLayer != nil; }

- (CGSize)naturalSize {
    if (_compositeReady && _naturalSize.width > 1) return _naturalSize;
    AVPlayerItem *item = _player.currentItem;
    AVAssetTrack *t = item.asset.tracks.firstObject;
    if (!t) return CGSizeZero;
    CGSize s = t.naturalSize;
    if (fabs(s.width * s.height) < 1.0) return CGSizeZero;
    return s;
}

- (void)onAudioInterruption:(NSNotification *)n {
    NSNumber *type = n.userInfo[AVAudioSessionInterruptionTypeKey];
    if (type.unsignedIntegerValue == AVAudioSessionInterruptionTypeEnded) {
        [self play];
        DSHPetLog(@"render", @"audio-resume", @"info", @{});
    }
}

- (void)onAppActive {
    if (_player && _player.rate == 0.0 && _currentURL) {
        [self play];
        DSHPetLog(@"render", @"resume-on-active", @"info", @{ @"clip": _currentURL.lastPathComponent ?: @"" });
    }
}

- (void)startWatchdog {
    if (_watchdog) return;
    _watchdog = [NSTimer scheduledTimerWithTimeInterval:3.0
                                                 target:self
                                               selector:@selector(onWatchdog:)
                                               userInfo:nil
                                                repeats:YES];
}

- (void)onWatchdog:(NSTimer *)t {
    // 只在"有素材、App 在前台、却被系统停了"时才拉一把，避免和用户手动暂停打架
    if (!_player || !_currentURL) return;
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    if (_player.rate == 0.0) {
        [_player play];
        DSHPetLog(@"render", @"watchdog-resume", @"debug", @{ @"clip": _currentURL.lastPathComponent ?: @"" });
    }
}


#pragma mark - 动画 WebP（真 alpha，不依赖 AVPlayer / 不依赖蒙版合成）

- (void)stopWebP {
    if (_webpSrc) { CFRelease(_webpSrc); _webpSrc = NULL; }
    _webpFrames = nil; _webpFirstPosted = NO;
    _webpCount = 0; _webpIndex = -1; _webpNext = 0;
}

- (void)advanceWebP:(CFTimeInterval)now force:(BOOL)force {
    if (!_webpSrc || _webpCount <= 0) return;
    if (!force && now < _webpNext) return;
    if (_webpFrames.count == 0) return;
    NSInteger next = (_webpIndex + 1) % (NSInteger)_webpFrames.count;
    id img = _webpFrames[(NSUInteger)next];
    _webpIndex = next;
    _webpNext = now + (_webpDur > 0.01 ? _webpDur : (1.0 / 12.0));
    // 每帧同步真实像素尺寸：素材包里 300/360/390px 混放，
    // 只在首次赋值会让宿主比例一直按最早那段算（偏窄 + 被放大 → 看着糊）。
    _naturalSize = CGSizeMake(CGImageGetWidth((__bridge CGImageRef)img),
                              CGImageGetHeight((__bridge CGImageRef)img));
    _curFrame = img;
    [self layoutContentsForImage:(__bridge CGImageRef)img];
    self.contentLayer.contents = img;
    _compositeReady = YES;
    if (!_webpFirstPosted) {
        _webpFirstPosted = YES;
        DSHPetLog(@"render", @"sharpness", @"info", @{
            @"imgW": @(CGImageGetWidth((__bridge CGImageRef)img)),
            @"imgH": @(CGImageGetHeight((__bridge CGImageRef)img)),
            @"boxW": @(CGRectGetWidth(self.contentLayer.bounds)),
            @"boxH": @(CGRectGetHeight(self.contentLayer.bounds)),
            @"cscale": @(self.contentLayer.contentsScale),
            @"scr": @([UIScreen mainScreen].scale)
        });
        [[NSNotificationCenter defaultCenter] postNotificationName:@"DSHPetFirstFrame" object:nil];
    }
}

- (BOOL)playWebPAtURL:(NSURL *)url {
    [self stopComposite];
    NSInteger token = ++_webpToken;   // 本次换片的身份号，旧后台任务回切对不上就丢弃

    CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!src) {
        DSHPetLog(@"player", @"webp-open-failed", @"error", @{ @"file": url.lastPathComponent ?: @"" });
        return NO;
    }
    size_t n = CGImageSourceGetCount(src);
    if (n == 0) { CFRelease(src); return NO; }

    // 帧时长属性只解析文件头（快），留在主线程读；解码循环搬后台，避免换片瞬间卡顿。
    double dur = 1.0 / 12.0;
    CFDictionaryRef props = CGImageSourceCopyPropertiesAtIndex(src, 0, NULL);
    if (props) {
        NSDictionary *d = CFBridgingRelease(props);
        NSDictionary *wp = d[(NSString *)kCGImagePropertyWebPDictionary];
        NSNumber *delay = wp[(NSString *)kCGImagePropertyWebPDelayTime];
        if (!delay) {
            NSDictionary *gif = d[(NSString *)kCGImagePropertyGIFDictionary];
            delay = gif[(NSString *)kCGImagePropertyGIFDelayTime];
        }
        if (delay && delay.doubleValue > 0.01) dur = delay.doubleValue;
    }

    if (!self.contentLayer) {
        self.contentLayer = [CALayer layer];
        self.contentLayer.opaque = NO;
        self.contentLayer.backgroundColor = [UIColor clearColor].CGColor;
        self.contentLayer.contentsGravity = kCAGravityResizeAspect;
        self.contentLayer.allowsGroupOpacity = NO;
        self.contentLayer.shouldRasterize = NO;
        // 帧像素 >= 显示像素时才锐：常驻动作按 360px 出图（118pt @3x ≈ 354px），
        // 显示层按屏幕 scale 摆，等于缩小采样；若帧比显示小，则变成放大 → 一定糊。
        self.contentLayer.contentsScale = [UIScreen mainScreen].scale;
        self.contentLayer.contentsFormat = kCAContentsFormatRGBA8Uint;
    }
    if (self.host && self.contentLayer.superlayer != self.host.layer) {
        [self.contentLayer removeFromSuperlayer];
        [self.host.layer addSublayer:self.contentLayer];
    }
    [self syncLayerFrame];

    // 主线程先解第 0 帧立即上屏，消除"换片后空白几百毫秒"的空档；剩余帧后台补。
    NSDictionary *opts = @{ (id)kCGImageSourceShouldCacheImmediately : @YES,
                            (id)kCGImageSourceShouldAllowFloat : @NO };
    CGImageRef first = CGImageSourceCreateImageAtIndex(src, 0, (__bridge CFDictionaryRef)opts);
    if (first) {
        // 必须让 ARC 接管所有权：_curFrame 要用到下一次 refreshLayout，
        // 直接 (__bridge id) 再 CGImageRelease 会留悬空指针，refreshLayout 一碰就崩。
        id firstObj = CFBridgingRelease(first);
        _curFrame = firstObj;
        _naturalSize = CGSizeMake(CGImageGetWidth((__bridge CGImageRef)firstObj),
                                  CGImageGetHeight((__bridge CGImageRef)firstObj));
        [self layoutContentsForImage:(__bridge CGImageRef)firstObj];
        self.contentLayer.contents = (__bridge id)firstObj;
        _compositeReady = YES;   // 第 0 帧已上屏，naturalSize 立即可用
    }

    size_t cap = n > 256 ? 256 : n;
    // src 的所有权交给后台 block。回切主线程且 token 一致时才挂到 _webpSrc；
    // 不一致（期间又换了片）就 CFRelease 丢弃，避免 use-after-free。
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray *frames = [NSMutableArray arrayWithCapacity:cap];
        for (size_t i = 0; i < cap; i++) {
            CGImageRef im = CGImageSourceCreateImageAtIndex(src, i, (__bridge CFDictionaryRef)opts);
            if (!im) continue;
            [frames addObject:(__bridge id)im];
            CGImageRelease(im);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (token != self->_webpToken) {   // 期间已换片，本次结果作废
                CFRelease(src);
                return;
            }
            if (frames.count == 0) { CFRelease(src); return; }
            [self stopWebP];                    // 释放上一段
            self->_webpFrames = frames;
            self->_webpSrc = src;               // src 所有权转交 _webpSrc
            self->_webpCount = (NSInteger)n;
            self->_webpIndex = -1;
            self->_webpDur = dur;
            [self advanceWebP:CACurrentMediaTime() force:YES];
            if (!self->_link) {
                self->_link = [CADisplayLink displayLinkWithTarget:self selector:@selector(onTick:)];
                [self->_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
            }
            DSHPetLog(@"player", @"webp-ok", @"info", @{ @"file": url.lastPathComponent ?: @"",
                @"frames": @(self->_webpCount), @"decoded": @(frames.count),
                @"dur": @(self->_webpDur),
                @"mb": @(round((double)frames.count * (double)(CGImageGetBytesPerRow((__bridge CGImageRef)frames.lastObject) * CGImageGetHeight((__bridge CGImageRef)frames.lastObject)) / 1048576.0 * 10.0) / 10.0) });
            if (frames.count != n) {
                DSHPetLog(@"player", @"webp-truncated", @"warn", @{ @"file": url.lastPathComponent ?: @"",
                    @"src": @(n), @"decoded": @(frames.count) });
            }
        });
    });
    return YES;
}

@end
