#import "DSHPetPlayer.h"
#import "DSHPetBoot.h"
#import <AVFoundation/AVFoundation.h>

static NSString *const kPetAssetDir = @"/var/mobile/Library/DSHPet/assets";

@interface DSHPetPlayer ()
@property (nonatomic, strong) UIView *host;
@property (nonatomic, strong) AVPlayerLayer *layer;
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) NSURL *currentURL;
@property (nonatomic, assign) CGSize displaySize;
@property (nonatomic, assign) BOOL observing;
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

- (void)reloadAsset {
    NSURL *url = [self findFirstMovie];
    if (!url) {
        DSHPetLog(@"render", @"player-no-asset", @"info", @{ @"dir": kPetAssetDir });
        [self teardown];
        return;
    }
    if (_currentURL && [_currentURL.path isEqualToString:url.path] && _player) {
        return;
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

@end
