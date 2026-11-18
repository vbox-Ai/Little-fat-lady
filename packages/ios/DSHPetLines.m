#import "DSHPetLines.h"
#import "DSHPetBoot.h"

// 去重窗口：记住最近 N 条，抽到就重抽（最多重抽 8 次，抽不出就认了，避免死循环）
static const NSInteger kRecentWindow = 3;
static const NSInteger kMaxRetry = 8;

static NSString *DSHPetToneKey(DSHPetTone tone) {
    switch (tone) {
        case DSHPetToneGenki: return @"genki";
        case DSHPetToneLazy: return @"lazy";
        case DSHPetToneGrumpy: return @"grumpy";
        case DSHPetToneDown: return @"down";
    }
    return @"genki";
}

// 素材根候选。顺序有意义：
//   1) 真实数据分区（运行时热更新写这里）
//   2) rootless 的 /var/jb 映射
//   3) roothide 的 .jbroot-XXXXXXXX 随机假根（**不能写死**，每次重装都会变）
static NSArray<NSString *> *DSHPetLinesRoots(void) {
    static NSArray<NSString *> *roots = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray<NSString *> *arr = [NSMutableArray array];
        NSString *rel = @"Library/Application Support/DSHPet/lines";
        NSString *relMobile = @"var/mobile/Library/Application Support/DSHPet/lines";

        // 1) 运行时数据分区（用户热更新、素材包解压都写这里）
        [arr addObject:[NSHomeDirectory() stringByAppendingPathComponent:rel]];
        [arr addObject:[@"/var/mobile" stringByAppendingPathComponent:rel]];
        // 2) rootless：/var/jb 映射，两种前缀都要试
        [arr addObject:[@"/var/jb" stringByAppendingPathComponent:rel]];
        [arr addObject:[@"/var/jb" stringByAppendingPathComponent:relMobile]];
        // 3) 只读根（roothide 有时把真根挂出来）
        [arr addObject:[@"/" stringByAppendingPathComponent:rel]];

        // 4) roothide：/private/var/containers/Bundle/Application/.jbroot-xxxx/（**不能写死**，每次重装都会变）
        NSString *apps = @"/private/var/containers/Bundle/Application";
        NSArray<NSString *> *entries = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:apps error:nil];
        for (NSString *e in entries) {
            if (![e hasPrefix:@".jbroot-"]) continue;
            NSString *base = [apps stringByAppendingPathComponent:e];
            [arr addObject:[base stringByAppendingPathComponent:rel]];
            [arr addObject:[base stringByAppendingPathComponent:relMobile]];
        }
        roots = [arr copy];
    });
    return roots;
}

// 内置兜底：素材没装上时也不至于变成哑巴。
// 只放最少几条，够「还能说话」，正式台词走磁盘 JSON。
static NSDictionary *DSHPetFallbackLines(void) {
    static NSDictionary *d = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        d = @{
            @"click": @{
                @"genki": @[@"欸嘿，戳我干嘛呀{user}", @"在的在的，我一直在呢"],
                @"lazy": @[@"唔…让我再靠一会儿"],
                @"grumpy": @[@"别戳了，烦着呢"],
                @"down": @[@"…嗯"],
            },
            @"drag": @[@"哇——放我下来！", @"飞起来啦——库…"],
            @"collide": @[@"哎哟…撞到了"],
            @"whisper": @{
                @"genki": @[@"（哼歌）今天也元气满满～"],
                @"lazy": @[@"（发呆）爹爹在忙什么呢…"],
                @"grumpy": @[@"（背对你）哼"],
                @"down": @[@"（蹲在角落）…"],
            },
            @"timeGreet": @{
                @"lateNight": @[@"爹爹…大晚上别戳我嘛…库…"],
                @"morning": @[@"早呀{user}"],
            },
            @"edge": @{
                @"modelFail": @[@"我这会儿脑子有点糊…等下再说好吗"],
                @"dontUnderstand": @[@"唔…我没听懂"],
            },
        };
    });
    return d;
}

@interface DSHPetLines ()
@property (nonatomic, strong) NSDictionary *lib;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *recent;
@property (nonatomic, readwrite) BOOL loadedFromDisk;
@property (nonatomic, readwrite) NSUInteger categoryCount;
@property (nonatomic, readwrite, nullable) NSString *loadedPath;

// 私有方法前置声明：`pickFrom:key:` 写在 @implementation 后半段、
// 却被 lineForPath:tone:vars: 先调用，不声明就是 "instance method not found"，-Werror 下直接红。
- (NSString *)pickFrom:(NSArray<NSString *> *)pool key:(NSString *)key;
@end

@implementation DSHPetLines

+ (instancetype)shared {
    static DSHPetLines *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[DSHPetLines alloc] init];
        [s reload];
    });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _userName = @"爹爹";
        _lib = DSHPetFallbackLines();
        _recent = [NSMutableDictionary dictionary];
        _loadedFromDisk = NO;
    }
    return self;
}

#pragma mark - 载入

- (void)reload {
    NSString *fileName = @"zh-Hans.json";

    for (NSString *root in DSHPetLinesRoots()) {
        NSString *path = [root stringByAppendingPathComponent:fileName];
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (data.length < 2) continue;

        NSError *err = nil;
        id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
        if (err || ![obj isKindOfClass:[NSDictionary class]]) {
            DSHPetLog(@"lines", @"parse-fail", @"warn",
                      @{@"path": path, @"err": err.localizedDescription ?: @"not-a-dict"});
            continue;
        }

        self.lib = (NSDictionary *)obj;
        self.loadedFromDisk = YES;
        self.loadedPath = path;
        self.categoryCount = self.lib.count;
        [self.recent removeAllObjects];
        DSHPetLog(@"lines", @"loaded", @"info",
                  @{@"path": path, @"categories": @(self.categoryCount), @"bytes": @(data.length)});
        return;
    }

    self.lib = DSHPetFallbackLines();
    self.loadedFromDisk = NO;
    self.loadedPath = nil;
    self.categoryCount = self.lib.count;
    [self.recent removeAllObjects];
    DSHPetLog(@"lines", @"fallback", @"warn",
              @{@"reason": @"no lines json found", @"roots": @(DSHPetLinesRoots().count)});
}

#pragma mark - 取词

- (NSString *)lineForPath:(NSString *)path {
    return [self lineForPath:path tone:DSHPetState.shared.tone vars:nil];
}

- (NSString *)lineForPath:(NSString *)path tone:(DSHPetTone)tone {
    return [self lineForPath:path tone:tone vars:nil];
}

- (NSString *)lineForPath:(NSString *)path vars:(NSDictionary<NSString *, NSString *> *)vars {
    return [self lineForPath:path tone:DSHPetState.shared.tone vars:vars];
}

- (NSString *)lineForPath:(NSString *)path
                     tone:(DSHPetTone)tone
                     vars:(NSDictionary<NSString *, NSString *> *)vars {
    if (path.length == 0) return @"";

    // 1. 按点号走层级
    id node = self.lib;
    for (NSString *seg in [path componentsSeparatedByString:@"."]) {
        if (![node isKindOfClass:[NSDictionary class]]) { node = nil; break; }
        node = ((NSDictionary *)node)[seg];
    }

    // 2. 是字典 → 说明分语气档，先取 tone，再回 default，再取任意第一档
    if ([node isKindOfClass:[NSDictionary class]]) {
        NSDictionary *byTone = (NSDictionary *)node;
        id pick = byTone[DSHPetToneKey(tone)] ?: byTone[@"default"] ?: byTone.allValues.firstObject;
        node = pick;
    }

    if (![node isKindOfClass:[NSArray class]] || ((NSArray *)node).count == 0) {
        DSHPetLog(@"lines", @"missing", @"debug", @{@"path": path});
        node = @[@"…"];
    }

    NSArray<NSString *> *pool = (NSArray<NSString *> *)node;
    NSString *chosen = [self pickFrom:pool key:path];
    return [self render:chosen vars:vars];
}

- (NSString *)pickFrom:(NSArray<NSString *> *)pool key:(NSString *)key {
    NSMutableArray<NSString *> *recent = self.recent[key];
    if (!recent) {
        recent = [NSMutableArray array];
        self.recent[key] = recent;
    }

    NSString *chosen = pool.firstObject ?: @"…";
    for (NSInteger i = 0; i < kMaxRetry; i++) {
        NSUInteger idx = arc4random_uniform((uint32_t)pool.count);
        chosen = pool[idx];
        if (![recent containsObject:chosen]) break;
    }

    [recent addObject:chosen];
    while ((NSInteger)recent.count > kRecentWindow) {
        [recent removeObjectAtIndex:0];
    }
    return chosen;
}

#pragma mark - 插槽

- (NSString *)render:(NSString *)tpl vars:(NSDictionary<NSString *, NSString *> *)vars {
    if (tpl.length == 0) return @"";

    NSMutableDictionary<NSString *, NSString *> *all = [NSMutableDictionary dictionary];
    all[@"user"] = self.userName.length ? self.userName : @"爹爹";
    all[@"pet"] = @"小肥鱼";
    if (vars) [all addEntriesFromDictionary:vars];

    NSString *out = tpl;
    for (NSString *k in all) {
        NSString *token = [NSString stringWithFormat:@"{%@}", k];
        if ([out rangeOfString:token].location == NSNotFound) continue;
        out = [out stringByReplacingOccurrencesOfString:token withString:all[k]];
    }

    // 残留的未知插槽统一清掉，不要在气泡里露出 {xxx}
    if ([out rangeOfString:@"{"].location != NSNotFound &&
        [out rangeOfString:@"}"].location != NSNotFound) {
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\\{[a-zA-Z0-9_]+\\}"
                                                                          options:0 error:nil];
        out = [re stringByReplacingMatchesInString:out
                                           options:0
                                             range:NSMakeRange(0, out.length)
                                      withTemplate:@""];
    }
    return out;
}

@end
