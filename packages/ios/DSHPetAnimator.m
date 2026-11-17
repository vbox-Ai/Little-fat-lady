#import "DSHPetAnimator.h"
#import "DSHPetAssets.h"
#import "DSHPetPlayer.h"
#import "DSHPetBoot.h"

    // 选素材段数最多的那个根：旧占位片只有 5 段，真素材有 114 段
    // 选素材段数最多的那个根：旧占位片只有 5 段，真素材有 114 段
static NSString *const kCatIdle = @"idle";
static NSString *const kCatTurn = @"turn";
static NSString *const kCatMove = @"move";
static NSString *const kCatClick = @"click";
static NSString *const kCatDrag = @"drag";
static NSString *const kCatSleep = @"sleep";
static NSString *const kCatOther = @"other";

@interface DSHPetAnimator ()
@property (nonatomic, copy) NSString *dir;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *groups;
@property (nonatomic, strong) NSTimer *idleTimer;
@property (nonatomic, assign) BOOL sleeping;
@property (nonatomic, assign) BOOL dragging;
@property (nonatomic, assign) NSUInteger clickCursor;
@property (nonatomic, copy, nullable) NSString *currentClip;
@end

@implementation DSHPetAnimator {
    BOOL _started;
}

+ (instancetype)shared {
    static DSHPetAnimator *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[DSHPetAnimator alloc] init]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _groups = [NSMutableDictionary dictionary];
        _clickCursor = 0;
    }
    return self;
}

#pragma mark - 索引

- (NSString *)categoryForFile:(NSString *)name {
    NSString *low = name.lowercaseString;
    NSArray<NSString *> *cats = @[kCatIdle, kCatTurn, kCatMove, kCatClick, kCatDrag, kCatSleep];
    for (NSString *c in cats) {
        if ([low hasPrefix:c]) return c;
    }
    return kCatOther;
}

- (void)buildIndex {
    [self.groups removeAllObjects];
    NSMutableArray<NSString *> *scanDirs = [NSMutableArray array];
    if (self.dir.length) [scanDirs addObject:self.dir];
    for (NSString *r in DSHPetAssetRoots()) {
        if (![scanDirs containsObject:r]) [scanDirs addObject:r];
        NSString *c = [r stringByAppendingPathComponent:@"color"];
        if (![scanDirs containsObject:c] &&
            [[NSFileManager defaultManager] fileExistsAtPath:c]) {
            [scanDirs addObject:c];
        }
    }
    NSMutableDictionary<NSString *, NSMutableDictionary *> *perRoot = [NSMutableDictionary dictionary];
    NSUInteger bestCount = 0;
    NSString *bestDir = nil;
    for (NSString *scanDir in scanDirs) {
        [self.groups removeAllObjects];
        [self buildIndexFromDir:scanDir];
        NSUInteger n = 0;
        for (NSString *k in self.groups) n += self.groups[k].count;
        perRoot[scanDir] = [self.groups copy] ?: @{};
        // 带 color/ 的根是"彩色+蒙版"新素材，优先级压过旧的单路 .mov 包：
        // 旧包没 alpha，播上去就是一块黑底。
        BOOL isColorRoot = [[scanDir lastPathComponent] isEqualToString:@"color"];
        NSUInteger score = n + (isColorRoot ? 100000 : 0);
        if (score > bestCount) { bestCount = score; bestDir = scanDir; }
    }
    [self.groups removeAllObjects];
    if (bestDir) {
        NSDictionary *picked = perRoot[bestDir];
        for (NSString *k in picked) self.groups[k] = [picked[k] mutableCopy];
    }

    // 只要索引里出现 webp（当前引擎），就把 .mp4/.mov 全部丢掉。
    // 它们是 0.1.0-63~84 时期"彩色 + 蒙版双路"留下的 320x180 演示片：
    // 尺寸只有 320px，塞进 130pt(=390px) 宿主会放大 1.22 倍 —— 真机"偶尔发虚"。
    BOOL hasWebP = NO;
    for (NSString *k in self.groups) {
        for (NSString *p in self.groups[k]) {
            if ([p.lowercaseString hasSuffix:@".webp"]) { hasWebP = YES; break; }
        }
        if (hasWebP) break;
    }
    if (hasWebP) {
        NSArray<NSString *> *keys = [self.groups allKeys];
        for (NSString *k in keys) {
            NSMutableArray *keep = [NSMutableArray array];
            for (NSString *p in self.groups[k]) {
                if ([p.lowercaseString hasSuffix:@".webp"]) [keep addObject:p];
            }
            if (keep.count) self.groups[k] = keep; else [self.groups removeObjectForKey:k];
        }
    }

    NSMutableDictionary *counts = [NSMutableDictionary dictionary];
    for (NSString *k in self.groups) counts[k] = @(self.groups[k].count);
    // 每个候选根实际扫到几段：真机日志里这一项能直接判定"路径对不对"
    NSMutableArray<NSString *> *probe = [NSMutableArray array];
    for (NSString *d in scanDirs) {
        NSDictionary *g = perRoot[d] ?: @{};
        NSUInteger n = 0;
        for (NSString *k in g) n += [g[k] count];
        [probe addObject:[NSString stringWithFormat:@"%@=%lu", d, (unsigned long)n]];
    }
    DSHPetLog(@"anim", @"index", @"info", @{ @"dir": self.dir,
                                            @"picked": bestDir ?: @"none",
                                            @"clips": @(bestCount),
                                            @"scan": probe,
                                            @"groups": counts });
    if (bestCount == 0) {
        DSHPetLog(@"anim", @"index-empty", @"error", @{ @"scan": probe });
    }
}

- (void)buildIndexFromDir:(NSString *)scanDir {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *names = [fm contentsOfDirectoryAtPath:scanDir error:NULL] ?: @[];

    // 先探一遍：只要存在"装着媒体的子目录"（分桶素材），就完全忽略同级的平铺文件。
    // 平铺那些是 0.1.0-31 时代的演示片（320x314），和真素材混在一个类别里轮播，
    // 抽到它就会被放大 1.4 倍 —— 真机上表现为"待机时偶尔糊一下，过会儿又清楚"。
    BOOL hasBuckets = NO;
    for (NSString *n in names) {
        BOOL d = NO;
        NSString *full = [scanDir stringByAppendingPathComponent:n];
        if ([fm fileExistsAtPath:full isDirectory:&d] && d) {
            NSArray<NSString *> *inner = [fm contentsOfDirectoryAtPath:full error:NULL] ?: @[];
            for (NSString *m in inner) {
                NSString *ml = m.lowercaseString;
                if ([ml hasSuffix:@".mov"] || [ml hasSuffix:@".mp4"] || [ml hasSuffix:@".m4v"] || [ml hasSuffix:@".webp"]) {
                    hasBuckets = YES;
                    break;
                }
            }
        }
        if (hasBuckets) break;
    }

    for (NSString *n in [names sortedArrayUsingSelector:@selector(compare:)]) {
        NSString *full = [scanDir stringByAppendingPathComponent:n];
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:full isDirectory:&isDir] && isDir) {
            NSArray<NSString *> *inner = [fm contentsOfDirectoryAtPath:full error:NULL] ?: @[];
            for (NSString *m in [inner sortedArrayUsingSelector:@selector(compare:)]) {
                NSString *low = m.lowercaseString;
                if (!([low hasSuffix:@".mov"] || [low hasSuffix:@".mp4"] || [low hasSuffix:@".m4v"] || [low hasSuffix:@".webp"])) continue;
                NSString *cat = n.lowercaseString;
                NSMutableArray<NSString *> *bucket = self.groups[cat];
                if (!bucket) { bucket = [NSMutableArray array]; self.groups[cat] = bucket; }
                [bucket addObject:[full stringByAppendingPathComponent:m]];
            }
            continue;
        }
        if (hasBuckets) continue;   // 有分桶就不索引平铺占位片
        NSString *low = n.lowercaseString;
        if (!([low hasSuffix:@".mov"] || [low hasSuffix:@".mp4"] || [low hasSuffix:@".m4v"] || [low hasSuffix:@".webp"])) continue;
        NSString *cat = [self categoryForFile:n];
        NSMutableArray<NSString *> *bucket = self.groups[cat];
        if (!bucket) { bucket = [NSMutableArray array]; self.groups[cat] = bucket; }
        [bucket addObject:full];
    }

    NSMutableDictionary *counts = [NSMutableDictionary dictionary];
    for (NSString *k in self.groups) counts[k] = @(self.groups[k].count);
    DSHPetLog(@"anim", @"index", @"info", @{ @"dir": scanDir, @"groups": counts });
}

- (nullable NSString *)pickFrom:(NSString *)cat {
    NSArray<NSString *> *bucket = self.groups[cat];
    if (!bucket.count) return nil;
    return bucket[arc4random_uniform((uint32_t)bucket.count)];
}

- (BOOL)play:(nullable NSString *)file {
    if (!file.length) return NO;
    NSString *path = [file isAbsolutePath] ? file : [self.dir stringByAppendingPathComponent:file];
    NSURL *url = [NSURL fileURLWithPath:path];
    NSURL *matteURL = nil;
    NSRange rng = [path rangeOfString:@"/color/"];
    if (rng.location != NSNotFound) {
        NSString *mp = [path stringByReplacingCharactersInRange:rng withString:@"/matte/"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:mp]) {
            matteURL = [NSURL fileURLWithPath:mp];
        }
    }
    BOOL ok = matteURL ? [[DSHPetPlayer shared] playClipAtURL:url matteURL:matteURL]
                       : [[DSHPetPlayer shared] playClipAtURL:url];
    if (ok) {
        self.currentClip = file;
        DSHPetLog(@"anim", @"play", @"debug", @{ @"clip": file });
    }
    return ok;
}

#pragma mark - 调度

- (void)startWithDirectory:(NSString *)dir {
    if (_started) { DSHPetLog(@"anim", @"start-skip", @"debug", @{ @"reason": @"already-started" }); return; }
    _started = YES;
    self.dir = dir;
    [self buildIndex];
    [self scheduleIdle];
    if (![self play:[self pickFrom:kCatIdle] ?: [self pickFrom:kCatOther]]) {
        DSHPetLog(@"anim", @"no-clip", @"info", @{ @"dir": dir });
    }
}

- (void)onAssetsCopied:(NSNotification *)note {
    // 素材是异步从包里拷到 /var/mobile 的，拷完重建索引再开播，避免一直停在占位块
    [self buildIndex];
    NSString *clip = [self pickFrom:kCatIdle] ?: [self pickFrom:kCatOther];
    if (clip) [self play:clip];
}

- (void)stop {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"DSHPetAssetsCopied" object:nil];
    [self.idleTimer invalidate];
    self.idleTimer = nil;
    self.currentClip = nil;
}

- (void)scheduleIdle {
    [self.idleTimer invalidate];
    NSTimeInterval gap = 6.0 + (double)arc4random_uniform(8000) / 1000.0;
    __weak DSHPetAnimator *weakSelf = self;
    self.idleTimer = [NSTimer scheduledTimerWithTimeInterval:gap
                                                      target:self
                                                    selector:@selector(onIdleTick:)
                                                    userInfo:nil
                                                     repeats:NO];
    (void)weakSelf;
}

- (void)onIdleTick:(NSTimer *)t {
    if (self.dragging) {
        [self scheduleIdle];
        return;
    }
    if (self.sleeping) {
        NSString *s = [self pickFrom:kCatSleep];
        if ([self play:s]) { [self scheduleIdle]; return; }
    }
    uint32_t r = arc4random_uniform(100);
    NSString *file = nil;
    if (r < 55)      file = [self pickFrom:kCatIdle];
    else if (r < 75) file = [self pickFrom:kCatTurn];
    else if (r < 90) file = [self pickFrom:@"play"];
    else             file = [self pickFrom:@"eat"];
    if (!file) file = [self pickFrom:kCatTurn] ?: [self pickFrom:kCatIdle];
    [self play:file];
    [self scheduleIdle];
}

- (void)handleTap {
    NSArray<NSString *> *clicks = self.groups[kCatClick];
    NSString *file = nil;
    if (clicks.count) {
        file = clicks[self.clickCursor % clicks.count];
        self.clickCursor = (self.clickCursor + 1) % clicks.count;
    }
    if (![self play:file]) [self play:[self pickFrom:kCatIdle]];
    [self scheduleIdle];
}

- (void)handleDragBegin {
    self.dragging = YES;
    [self play:[self pickFrom:kCatDrag]];
}

- (void)handleDragEnd {
    self.dragging = NO;
    [self play:[self pickFrom:kCatIdle]];
    [self scheduleIdle];
}

- (void)setSleeping:(BOOL)sleeping {
    if (_sleeping == sleeping) return;
    _sleeping = sleeping;
    if (sleeping) {
        if (![self play:[self pickFrom:kCatSleep]]) [self play:[self pickFrom:kCatIdle]];
    } else {
        [self play:[self pickFrom:kCatIdle]];
    }
    [self scheduleIdle];
}

@end
