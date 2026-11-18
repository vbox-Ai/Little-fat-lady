#import "DSHPetAssets.h"
#import "DSHPetBoot.h"
#import <UIKit/UIKit.h>
#import <unistd.h>

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
    // Dopamine / 老 rootless：/var/jb 有时只是个软链，真实内容在 preboot 里；
    // 也有打包工具把 rootless 前缀写成 /usr/local 的情况，一起兜上。
    [roots addObject:@"/var/jb/usr/share/DSHPet"];
    [roots addObject:@"/usr/share/DSHPet"];
    [roots addObject:@"/usr/local/share/DSHPet"];
    [roots addObject:@"/var/mobile/DSHPet/assets"];

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
    // 目标目录里已经有素材就不动，避免覆盖用户自己放的素材。
    // （老版本这里还额外判一次 color/ 目录 —— 那是双路合成时代的产物，
    //   留着它会让「只剩旧 color mp4」的机器永远不再补新 webp，已删。）
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
        DSHPetWriteDoctor(done ? @"copied" : @"copy-none");
    });
}

#pragma mark - 诊断落盘（doctor.txt）

// 绿方块 = 素材没找到时的占位底色。以前只能靠 syslog 猜，别人一报就断在那。
// 这里把「找过哪些路径 / 哪个存在 / 哪个真有素材 / 运行目录里有什么」一次性写盘：
// 用户拿 Filza 打开 /var/mobile/Library/DSHPet/doctor.txt 就能直接回传。
void DSHPetWriteDoctor(NSString *_Nullable note) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableString *s = [NSMutableString string];
    [s appendString:@"# 小肥娘 自检报告\n"];
    [s appendFormat:@"version: %@\n", DSHPET_VERSION_STRING];
    [s appendFormat:@"system: %@ (build %@)\n", [UIDevice currentDevice].systemVersion, [UIDevice currentDevice].model];
    [s appendFormat:@"device: %@\n", [UIDevice currentDevice].name];
    [s appendFormat:@"process: %@\n", NSProcessInfo.processInfo.processName];
    [s appendFormat:@"uid: %d\n", (int)getuid()];
    [s appendFormat:@"when: %@\n", [NSDate date]];
    if (note.length) [s appendFormat:@"note: %@\n", note];

    [s appendString:@"\n## 素材根候选（已过滤成存在的目录，按优先级）\n"];
    NSArray<NSString *> *roots = DSHPetAssetRoots();
    for (NSString *r in roots) {
        BOOL has = DSHPetHasMovie(r);
        NSArray *kids = [fm contentsOfDirectoryAtPath:r error:NULL] ?: @[];
        [s appendFormat:@"- %@  hasMovie=%@  children=%lu\n", r, has ? @"Y" : @"N", (unsigned long)kids.count];
        if (!has) continue;
        for (NSString *k in kids) {
            NSString *sub = [r stringByAppendingPathComponent:k];
            BOOL isDir = NO;
            if (![fm fileExistsAtPath:sub isDirectory:&isDir] || !isDir) continue;
            NSArray *inner = [fm contentsOfDirectoryAtPath:sub error:NULL] ?: @[];
            [s appendFormat:@"    · %@/%lu 项\n", k, (unsigned long)inner.count];
        }
    }
    [s appendFormat:@"候选命中数: %lu\n", (unsigned long)roots.count];

    [s appendString:@"\n## 运行素材目录\n"];
    [s appendFormat:@"path: %@  exists=%@\n", kRunAssets, [fm fileExistsAtPath:kRunAssets] ? @"Y" : @"N"];
    NSArray *runKids = [fm contentsOfDirectoryAtPath:kRunAssets error:NULL] ?: @[];
    for (NSString *k in runKids) {
        NSString *sub = [kRunAssets stringByAppendingPathComponent:k];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:sub isDirectory:&isDir] || !isDir) continue;
        NSArray *inner = [fm contentsOfDirectoryAtPath:sub error:NULL] ?: @[];
        NSUInteger webp = 0, mp4 = 0;
        for (NSString *x in inner) {
            NSString *low = x.lowercaseString;
            if ([low hasSuffix:@".webp"]) webp++;
            else if ([low hasSuffix:@".mp4"] || [low hasSuffix:@".mov"]) mp4++;
        }
        [s appendFormat:@"- %@  webp=%lu mp4=%lu\n", k, (unsigned long)webp, (unsigned long)mp4];
    }

    [s appendString:@"\n## 面板配置域 com.vboxai.littlefatlady.prefs\n"];
    CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("petEnabled"), CFSTR("com.vboxai.littlefatlady.prefs"));
    [s appendFormat:@"petEnabled=%@\n", v ? @"(已写)" : @"(未写，用默认)"];
    if (v) CFRelease(v);

    [s appendString:@"\n## 程序目录\n"];
    [s appendFormat:@"exec: %@\n", NSProcessInfo.processInfo.arguments.firstObject ?: @"?"];
    [s appendFormat:@"/var/jb 是否可读: %@\n", [fm isReadableFileAtPath:@"/var/jb"] ? @"Y" : @"N"];
    [s appendFormat:@"/Library/Application Support 是否存在: %@\n",
                   [fm fileExistsAtPath:@"/Library/Application Support"] ? @"Y" : @"N"];

    NSString *dir = @"/var/mobile/Library/DSHPet";
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *path = [dir stringByAppendingPathComponent:@"doctor.txt"];
    NSError *err = nil;
    [s writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err];
    DSHPetLog(@"assets", @"doctor", err ? @"warn" : @"info",
              @{ @"path": path, @"roots": @(roots.count), @"err": err.localizedDescription ?: @"" });
}
