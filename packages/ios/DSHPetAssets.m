#import "DSHPetAssets.h"
#import "DSHPetBoot.h"

static BOOL DSHPetHasMovie(NSString *dir) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *names = [fm contentsOfDirectoryAtPath:dir error:NULL];
    for (NSString *n in names) {
        NSString *full = [dir stringByAppendingPathComponent:n];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:full isDirectory:&isDir]) continue;
        if (isDir) {
            NSArray<NSString *> *inner = [fm contentsOfDirectoryAtPath:full error:NULL] ?: @[];
            for (NSString *x in inner) {
                NSString *low = x.lowercaseString;
                if ([low hasSuffix:@".mov"] || [low hasSuffix:@".mp4"] || [low hasSuffix:@".m4v"] || [low hasSuffix:@".webp"]) return YES;
            }
            continue;
        }
        NSString *low = n.lowercaseString;
        if ([low hasSuffix:@".mov"] || [low hasSuffix:@".mp4"] || [low hasSuffix:@".m4v"] || [low hasSuffix:@".webp"]) return YES;
    }
    return NO;
}

NSArray<NSString *> *DSHPetAssetRoots(void) {
    NSMutableArray<NSString *> *roots = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];

    // 1) 运行目录：任何 rootfs 布局下都固定不变，也是唯一保证可写的位置。
    [roots addObject:@"/var/mobile/Library/DSHPet/assets"];

    // 2) 随包目录：rootless 装到 /var/jb 下；roothide 的假根里是 /Library；再兜一层。
    [roots addObject:@"/var/jb/Library/Application Support/DSHPet"];
    [roots addObject:@"/Library/Application Support/DSHPet"];
    [roots addObject:@"/var/jb/var/mobile/Library/DSHPet/assets"];

    // 3) roothide 的真实越狱根是随机命名的假根（.jbroot-XXXXXXXX），
    //    未链接 libroot 的 dylib 无法把 /var/jb 重定向过去，必须自己去容器目录里找。
    NSArray<NSString *> *containers = @[ @"/var/containers/Bundle/Application",
                                         @"/private/preboot" ];
    for (NSString *base in containers) {
        NSArray<NSString *> *items = [fm contentsOfDirectoryAtPath:base error:NULL] ?: @[];
        for (NSString *it in items) {
            NSString *low = it.lowercaseString;
            BOOL looksJb = [low hasPrefix:@".jbroot-"] || [low hasPrefix:@"jb-"] || [low containsString:@"jbroot"];
            if (!looksJb) continue;
            NSString *sub = [base stringByAppendingPathComponent:it];
            [roots addObject:[sub stringByAppendingPathComponent:@"var/jb/Library/Application Support/DSHPet"]];
            [roots addObject:[sub stringByAppendingPathComponent:@"Library/Application Support/DSHPet"]];
            [roots addObject:[sub stringByAppendingPathComponent:@"var/jb/var/mobile/Library/DSHPet/assets"]];
        }
    }

    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (NSString *r in roots) {
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:r isDirectory:&isDir] && isDir) [out addObject:r];
    }
    return out;
}

NSString *_Nullable DSHPetFirstAssetRoot(void) {
    for (NSString *r in DSHPetAssetRoots()) {
        if (DSHPetHasMovie(r)) return r;
    }
    return nil;
}

#pragma mark - 自拷贝（不依赖 dpkg 维护脚本）

static NSString * const kRunAssets = @"/var/mobile/Library/DSHPet/assets";

static BOOL DSHPetDirHasMovies(NSString *dir) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *names = [fm contentsOfDirectoryAtPath:dir error:NULL] ?: @[];
    for (NSString *n in names) {
        NSString *low = n.lowercaseString;
        if ([low hasSuffix:@".mov"] || [low hasSuffix:@".mp4"] || [low hasSuffix:@".m4v"] || [low hasSuffix:@".webp"]) return YES;
        BOOL isDir = NO;
        NSString *full = [dir stringByAppendingPathComponent:n];
        if ([fm fileExistsAtPath:full isDirectory:&isDir] && isDir) {
            if (DSHPetDirHasMovies(full)) return YES;
        }
    }
    return NO;
}

void DSHPetEnsureAssets(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    // 目标目录里已经有素材（color/ 或平铺片）就不动，避免覆盖用户自己放的素材
    if ([fm fileExistsAtPath:[kRunAssets stringByAppendingPathComponent:@"color"]]) return;
    if (DSHPetDirHasMovies(kRunAssets)) return;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSFileManager *fm2 = [NSFileManager defaultManager];
        NSMutableDictionary<NSString *, NSNumber *> *report = [NSMutableDictionary dictionary];
        BOOL done = NO;
        for (NSString *root in DSHPetAssetRoots()) {
            if (done) break;
            if (![fm2 fileExistsAtPath:root]) continue;
            NSArray<NSString *> *names = [fm2 contentsOfDirectoryAtPath:root error:NULL] ?: @[];
            for (NSString *n in names) {
                NSString *src = [root stringByAppendingPathComponent:n];
                BOOL isDir = NO;
                if (!([fm2 fileExistsAtPath:src isDirectory:&isDir] && isDir)) continue;
                if (!DSHPetDirHasMovies(src)) continue;
                NSString *dst = [kRunAssets stringByAppendingPathComponent:n];
                [fm2 removeItemAtPath:dst error:NULL];
                NSError *err = nil;
                if ([fm2 copyItemAtPath:src toPath:dst error:&err]) {
                    report[n] = @(1);
                    done = YES;
                } else {
                    report[n] = @(-1);
                    DSHPetLog(@"assets", @"copy-fail", @"warn", @{ @"src": src, @"err": err.localizedDescription ?: @"?" });
                }
            }
        }
        DSHPetLog(@"assets", done ? @"copy-ok" : @"copy-none", done ? @"info" : @"warn",
                  @{ @"dst": kRunAssets, @"detail": report });
        if (done) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:@"DSHPetAssetsCopied" object:nil];
            });
        }
    });
}
