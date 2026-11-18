#import "DSHPetSFX.h"
#import "DSHPetVoice.h"
#import "DSHPetBoot.h"
#import <AVFoundation/AVFoundation.h>

// 同名音效节流：连点不该爆音
static const NSTimeInterval kThrottle = 0.12;
// 每种音效备几路：允许轻微重叠（连续两下点击），再多就是噪音
static const NSUInteger kVoicesPerName = 2;

static NSArray<NSString *> *DSHPetSFXRoots(void) {
    static NSArray<NSString *> *roots = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray<NSString *> *arr = [NSMutableArray array];
        NSString *rel = @"Library/Application Support/DSHPet/sfx";
        [arr addObject:[NSHomeDirectory() stringByAppendingPathComponent:rel]];
        [arr addObject:[@"/var/mobile" stringByAppendingPathComponent:rel]];
        [arr addObject:[@"/var/jb" stringByAppendingPathComponent:rel]];
        [arr addObject:[@"/var/jb/var/mobile" stringByAppendingPathComponent:rel]];

        NSString *apps = @"/private/var/containers/Bundle/Application";
        NSArray<NSString *> *entries = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:apps error:nil];
        for (NSString *e in entries) {
            if (![e hasPrefix:@".jbroot-"]) continue;
            NSString *base = [apps stringByAppendingPathComponent:e];
            [arr addObject:[base stringByAppendingPathComponent:rel]];
            [arr addObject:[base stringByAppendingPathComponent:
                              @"var/mobile/Library/Application Support/DSHPet/sfx"]];
        }
        roots = [arr copy];
    });
    return roots;
}

@interface DSHPetSFX ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<AVAudioPlayer *> *> *pool;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *lastPlay;
@property (nonatomic, strong) NSMutableSet<NSString *> *missing;   // 找不到的只记一次日志，别刷屏
- (nullable AVAudioPlayer *)makePlayerFor:(NSString *)name;
- (nullable NSString *)pathForName:(NSString *)name;
@end

@implementation DSHPetSFX

+ (instancetype)shared {
    static DSHPetSFX *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[DSHPetSFX alloc] init];
    });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }
    _enabled = YES;
    _baseVolume = 1.0f;
    _pool = [NSMutableDictionary dictionary];
    _lastPlay = [NSMutableDictionary dictionary];
    _missing = [NSMutableSet set];
    return self;
}

- (void)warmUp {
    for (NSString *name in @[@"tap", @"pickup", @"land", @"bump"]) {
        if (!self.pool[name]) {
            AVAudioPlayer *p = [self makePlayerFor:name];
            if (p) {
                self.pool[name] = [NSMutableArray arrayWithObject:p];
            }
        }
    }
}

- (void)play:(NSString *)name {
    [self play:name volume:1.0f];
}

- (void)play:(NSString *)name volume:(float)volume {
    if (!self.enabled || name.length == 0) {
        return;
    }
    // 与语音共用会话；说话时自动压低到 0.4
    float v = self.baseVolume * volume * [[DSHPetVoice shared] sfxScale];
    if (v <= 0.01f) {
        return;
    }

    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    NSNumber *last = self.lastPlay[name];
    if (last && now - last.doubleValue < kThrottle) {
        return;
    }
    self.lastPlay[name] = @(now);

    NSMutableArray<AVAudioPlayer *> *voices = self.pool[name];
    if (!voices) {
        voices = [NSMutableArray array];
        self.pool[name] = voices;
    }

    AVAudioPlayer *player = nil;
    for (AVAudioPlayer *p in voices) {
        if (!p.isPlaying) {
            player = p;
            break;
        }
    }
    if (!player && voices.count < kVoicesPerName) {
        player = [self makePlayerFor:name];
        if (player) {
            [voices addObject:player];
        }
    }
    if (!player) {
        return;   // 素材缺失或都在播：静默跳过，不影响交互
    }

    @try {
        player.volume = MAX(0.0f, MIN(1.0f, v));
        player.currentTime = 0;
        [player play];
    } @catch (NSException *e) {
        DSHPetLog(@"sfx", @"play-exception", @"warn", @{@"name": name, @"err": e.name ?: @"?"});
    }
}

- (void)stopAll {
    for (NSMutableArray<AVAudioPlayer *> *voices in self.pool.allValues) {
        for (AVAudioPlayer *p in voices) {
            if (p.isPlaying) {
                [p stop];
            }
        }
    }
}

- (nullable NSString *)pathForName:(NSString *)name {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *root in DSHPetSFXRoots()) {
        for (NSString *ext in @[@"caf", @"wav", @"m4a", @"mp3"]) {
            NSString *p = [root stringByAppendingPathComponent:
                           [NSString stringWithFormat:@"%@.%@", name, ext]];
            if ([fm fileExistsAtPath:p]) {
                return p;
            }
        }
    }
    return nil;
}

- (nullable AVAudioPlayer *)makePlayerFor:(NSString *)name {
    NSString *path = [self pathForName:name];
    if (!path) {
        if (![self.missing containsObject:name]) {
            [self.missing addObject:name];
            // 素材缺失是常态（音效包可选），记一次就够
            DSHPetLog(@"sfx", @"missing", @"debug", @{@"name": name});
        }
        return nil;
    }
    @try {
        NSError *err = nil;
        AVAudioPlayer *p = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path]
                                                                  error:&err];
        if (!p) {
            DSHPetLog(@"sfx", @"load-fail", @"warn", @{@"name": name, @"err": err.localizedDescription ?: @"?"});
            return nil;
        }
        [p prepareToPlay];
        return p;
    } @catch (NSException *e) {
        DSHPetLog(@"sfx", @"load-exception", @"warn", @{@"name": name, @"err": e.name ?: @"?"});
        return nil;
    }
}

@end
