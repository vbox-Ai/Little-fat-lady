#import "DSHPetPlayer.h"
#import <AVFoundation/AVAudioSession.h>
#import "DSHPetBoot.h"
#import <AVFoundation/AVFoundation.h>

static NSString *const kPetAssetDir = @"/var/mobile/Library/DSHPet/assets";
static NSString *const kPetAssetDirFallback = @"/var/jb/Library/Application Support/DSHPet";

@interface DSHPetPlayer ()
@property (nonatomic, strong) UIView *host;
@property (nonatomic, strong) AVPlayerLayer *layer;
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) NSURL *currentURL;
@property (nonatomic, assign) CGSize displaySize;
@property (nonatomic, assign) BOOL observing;
- (void)onAudioInterruption:(NSNotification *)n;
- (void)onAppActive;
- (void)onWatchdog:(NSTimer *)t;
@end

@implementation DSHPetPlayer

+ (instancetype)shared {
    static DSHPetPlayer *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[DSHPetPlayer alloc] init]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _displaySize = CGSizeMake(462, 260);
    }
    return self;
}

#pragma mark - 素材

- (nullable NSURL *)pickInDirectory:(NSString *)dir {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *names = [fm contentsOfDirectoryAtPath:dir error:NULL];
    if (!names.count) return nil;

    NSMutableArray<NSString *> *cands = [NSMutableArray array];
    for (NSString *n in names) {
        NSString *low = n.lowercaseString;
        if ([low hasSuffix:@".mov"] || [low hasSuffix:@".mp4"] || [low hasSuffix:@".m4v"]) {
            [cands addObject:n];
        }
    }
    if (!cands.count) return nil;
    [cands sortUsingSelector:@selector(compare:)];

    // 优先级：main.*（真素材约定名）> 任何非 demo 文件 > 内置 demo.mov
    NSString *picked = nil;
    for (NSString *n in cands) {
        if ([n.lowercaseString hasPrefix:@"main."]) { picked = n; break; }
    }
    if (!picked) {
        for (NSString *n in cands) {
            if (![n.lowercaseString isEqualToString:@"demo.mov"]) { picked = n; break; }
        }
    }
    if (!picked) picked = cands.firstObject;
    return [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:picked]];
}

- (nullable NSURL *)findFirstMovie {
    // 运行目录优先（用户可写）；找不到再看随包目录（rootless 下 /var/jb 前缀，postinst 正常会拷过来，
    // 这里兜底，避免 postinst 失败时整个 S3 只能看到占位方块）
    NSURL *url = [self pickInDirectory:kPetAssetDir];
    if (!url) url = [self pickInDirectory:kPetAssetDirFallback];
    return url;
}

- (BOOL)playClipAtURL:(NSURL *)url {
    if (!url) return NO;
    if (_currentURL && [_currentURL.path isEqualToString:url.path] && _player) {
        [self play];
        return YES;
    }
    _currentURL = url;

    AVAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:asset];
    if (!_player) {
        _player = [AVPlayer playerWithPlayerItem:item];
        _player.muted = YES;
        _player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
        _player.allowsExternalPlayback = NO;
    } else {
        [_player replaceCurrentItemWithPlayerItem:item];
    }

    if (!_layer) {
        _layer = [AVPlayerLayer playerLayerWithPlayer:_player];
        _layer.videoGravity = AVLayerVideoGravityResizeAspect;
        _layer.backgroundColor = [UIColor clearColor].CGColor;
        _layer.opaque = NO;
    }
    if (_layer.superlayer == nil && _host) {
        [_host.layer addSublayer:_layer];
    }

    [self observeEnd];
    [self syncLayerFrame];

    DSHPetLog(@"render", @"player-load", @"info", @{
        @"file": url.lastPathComponent ?: @"",
        @"bytes": @([[NSFileManager defaultManager] attributesOfItemAtPath:url.path error:NULL].fileSize),
        @"tracks": @(asset.tracks.count),
    });
    [self play];
    return YES;
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

    if (_layer) {
        [_host.layer addSublayer:_layer];
        [self syncLayerFrame];
        [self play];
    }
    return _layer != nil;
}

- (void)setDisplaySize:(CGSize)size {
    if (CGSizeEqualToSize(size, _displaySize)) return;
    _displaySize = size;
    [self syncLayerFrame];
}

- (void)syncLayerFrame {
    if (!_layer) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CGRect b = self.host ? self.host.bounds : CGRectMake(0, 0, _displaySize.width, _displaySize.height);
    _layer.frame = b;
    [CATransaction commit];
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
    if (!_player) return;
    [_player pause];
    DSHPetLog(@"render", @"player-pause", @"debug", nil);
}

- (BOOL)hasAsset { return _layer != nil; }

- (CGSize)naturalSize {
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

@end
