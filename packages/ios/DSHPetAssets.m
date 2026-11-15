#import "DSHPetAssets.h"

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
                if ([low hasSuffix:@".mov"] || [low hasSuffix:@".mp4"] || [low hasSuffix:@".m4v"]) return YES;
            }
            continue;
        }
        NSString *low = n.lowercaseString;
        if ([low hasSuffix:@".mov"] || [low hasSuffix:@".mp4"] || [low hasSuffix:@".m4v"]) return YES;
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
