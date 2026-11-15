#import "DSHPetPlayer.h"
#import "DSHPetAssets.h"
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
