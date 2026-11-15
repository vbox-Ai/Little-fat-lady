#import "DSHPetAnimator.h"
#import "DSHPetAssets.h"
#import "DSHPetPlayer.h"
#import "DSHPetBoot.h"

/// 动作类别。识别方式：文件名（不含扩展名）以类别名开头即归入该类，
/// 例如 idle.mov / idle-2.mov / click.mov / move.crab.mov。
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
    }
    // 选"素材最多"的那个根：运行目录里可能只剩几段老的占位演示片（5 段），
    // 而真素材（114 段）在越狱根里；只认第一个有料的根会导致一直播占位片。
    NSMutableDictionary<NSString *, NSMutableDictionary *> *perRoot = [NSMutableDictionary dictionary];
    NSUInteger bestCount = 0;
    NSString *bestDir = nil;
    for (NSString *scanDir in scanDirs) {
        [self.groups removeAllObjects];
        [self buildIndexFromDir:scanDir];
        NSUInteger n = 0;
        for (NSString *k in self.groups) n += self.groups[k].count;
        perRoot[scanDir] = [self.groups copy] ?: @{};
        if (n > bestCount) { bestCount = n; bestDir = scanDir; }
    }
    [self.groups removeAllObjects];
    if (bestDir) {
        NSDictionary *picked = perRoot[bestDir];
        for (NSString *k in picked) self.groups[k] = [picked[k] mutableCopy];
    }

    NSMutableDictionary *counts = [NSMutableDictionary dictionary];
    for (NSString *k in self.groups) counts[k] = @(self.groups[k].count);
    DSHPetLog(@"anim", @"index", @"info", @{ @"dir": self.dir, @"picked": bestDir ?: @"none", @"clips": @(bestCount), @"groups": counts });
}

- (void)buildIndexFromDir:(NSString *)scanDir {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *names = [fm contentsOfDirectoryAtPath:scanDir error:NULL] ?: @[];

    // 两种组织方式都吃：
    //  A) 平铺：idle.mov / click-2.mov（按文件名前缀分类）
    //  B) 分桶：idle/001-idle.mov、workstatus/007-workstatus.mov（按目录名分类，上游素材包就是这种）
    for (NSString *n in [names sortedArrayUsingSelector:@selector(compare:)]) {
        NSString *full = [self.dir stringByAppendingPathComponent:n];
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:full isDirectory:&isDir] && isDir) {
            NSArray<NSString *> *inner = [fm contentsOfDirectoryAtPath:full error:NULL] ?: @[];
            for (NSString *m in [inner sortedArrayUsingSelector:@selector(compare:)]) {
                NSString *low = m.lowercaseString;
                if (!([low hasSuffix:@".mov"] || [low hasSuffix:@".mp4"] || [low hasSuffix:@".m4v"])) continue;
                NSString *cat = n.lowercaseString;
                NSMutableArray<NSString *> *bucket = self.groups[cat];
                if (!bucket) { bucket = [NSMutableArray array]; self.groups[cat] = bucket; }
                [bucket addObject:[full stringByAppendingPathComponent:m]];
            }
            continue;
        }
        NSString *low = n.lowercaseString;
        if (!([low hasSuffix:@".mov"] || [low hasSuffix:@".mp4"] || [low hasSuffix:@".m4v"])) continue;
        NSString *cat = [self categoryForFile:n];
        NSMutableArray<NSString *> *bucket = self.groups[cat];
        if (!bucket) { bucket = [NSMutableArray array]; self.groups[cat] = bucket; }
        [bucket addObject:full];
    }

    NSMutableDictionary *counts = [NSMutableDictionary dictionary];
    for (NSString *k in self.groups) counts[k] = @(self.groups[k].count);
    DSHPetLog(@"anim", @"index", @"info", @{ @"dir": self.dir, @"groups": counts });
}

- (nullable NSString *)pickFrom:(NSString *)cat {
    NSArray<NSString *> *bucket = self.groups[cat];
    if (!bucket.count) return nil;
    return bucket[arc4random_uniform((uint32_t)bucket.count)];
}

- (BOOL)play:(nullable NSString *)file {
    if (!file.length) return NO;
    // 索引里存的是绝对路径（素材可能来自 /var/jb 或 /Library 假根），别再拼 self.dir
    NSString *path = [file isAbsolutePath] ? file : [self.dir stringByAppendingPathComponent:file];
    NSURL *url = [NSURL fileURLWithPath:path];
    BOOL ok = [[DSHPetPlayer shared] playClipAtURL:url];
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

- (void)stop {
    [self.idleTimer invalidate];
    self.idleTimer = nil;
    self.currentClip = nil;
}

- (void)scheduleIdle {
    [self.idleTimer invalidate];
    // 6~14 秒之间随便一个点，别做成节拍器
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
    // 待机抽签：55% idle、20% 东张西望、15% 玩耍、10% 吃
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
