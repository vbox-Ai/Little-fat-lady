#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "DSHPetBoot.h"
#import "DSHPetAssets.h"
#import <math.h>

// 日志层（方案 §8）：JSONL，一行一条，按 mod 分文件。
// 设计约束：
//   1. 任何情况下不许抛异常、不许阻塞调用方（写失败就丢这一条，不重试）；
//   2. 不打印 token / 完整 URL 查询串（诊断包导出时另有脱敏，这层先不写敏感值）；
//   3. 目录固定 /var/mobile/Library/DSHPet/logs，卸载由 postrm 清。

static NSString *DSHPetDataDir(void) {
    return @"/var/mobile/Library/DSHPet";
}

static NSString *DSHPetLogDir(void) {
    return [DSHPetDataDir() stringByAppendingPathComponent:@"logs"];
}

NSString *DSHPetLogPathForModule(NSString *mod) {
    return [DSHPetLogDir() stringByAppendingPathComponent:[mod stringByAppendingString:@".jsonl"]];
}

// 任何值都先转成"JSON 能装得下"的东西。
// 触发过真机崩溃：NSJSONSerialization 遇到 NaN/Inf 或 CGSize 之类的 NSValue 会抛
// NSInvalidArgumentException，而这个异常在 SpringBoard 里没人接 → abort() → 安全模式。
static id DSHPetJSONSafe(id v, int depth) {
    if (!v || v == [NSNull null]) return [NSNull null];
    if (depth > 4) return [v description] ?: @"";
    if ([v isKindOfClass:[NSString class]]) return v;
    if ([v isKindOfClass:[NSNumber class]]) {
        double d = [v doubleValue];
        if (isnan(d) || isinf(d)) return @"NaN";
        return v;
    }
    if ([v isKindOfClass:[NSArray class]]) {
        NSMutableArray *out = [NSMutableArray array];
        for (id o in (NSArray *)v) [out addObject:DSHPetJSONSafe(o, depth + 1)];
        return out;
    }
    if ([v isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *out = [NSMutableDictionary dictionary];
        [(NSDictionary *)v enumerateKeysAndObjectsUsingBlock:^(id k, id o, BOOL *stop) {
            NSString *key = [k isKindOfClass:[NSString class]] ? k : [k description];
            if (key) out[key] = DSHPetJSONSafe(o, depth + 1);
        }];
        return out;
    }
    if ([v isKindOfClass:[NSDate class]]) {
        return [v description] ?: @"";
    }
    // CGSize / CGRect / NSValue / 自定义对象：一律退成字符串
    NSString *s = [v description];
    return s ?: @"";
}

void DSHPetLog(NSString *mod, NSString *evt, NSString *lvl, NSDictionary *kv) {
    @autoreleasepool {
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm createDirectoryAtPath:DSHPetLogDir() withIntermediateDirectories:YES attributes:nil error:NULL];
    // 没有 postinst 了（roothide 的 dpkg 有时执行不了维护脚本），目录由代码自己建
    for (NSString *d in @[ @"/var/mobile/Library/DSHPet/config",
                           @"/var/mobile/Library/DSHPet/assets" ]) {
        [fm createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:NULL];
    }
    {
        static BOOL ensured = NO;
        if (!ensured) { ensured = YES; DSHPetEnsureAssets(); }
    }
    // 诊断先落一份（拷贝还在后台跑，绿方块的机器要能马上把原因发回来）
    {
        static BOOL doctored = NO;
        if (!doctored) { doctored = YES; DSHPetWriteDoctor(@"boot"); }
    }
    // 旧版本残留清理 —— 只清「确定是老东西」的那几样，不再按白名单横扫：
    //   · 根级散放的 .mp4/.mov/.m4v（单路 ProRes 演示片 / 双路时代的散片）
    //   · color/ 与 matte/ 两个目录（双路合成时代产物，里面全是 320×180 的 mp4，
    //     留着会被索引器当成候选根，抽到就糊成一片——发虚问题的老根就在这）
    // 之前这里写的是「不是 color/matte/main.* 就删」，等于每写一条日志
    // 就把新素材的 idle/ move/ 分桶全删一遍：谁的分桶被删，谁就绿方块。
    {
        NSString *aroot = @"/var/mobile/Library/DSHPet/assets";
        NSArray<NSString *> *kids = [fm contentsOfDirectoryAtPath:aroot error:NULL] ?: @[];
        for (NSString *k in kids) {
            NSString *low = k.lowercaseString;
            NSString *full = [aroot stringByAppendingPathComponent:k];
            BOOL isDir = NO;
            if (![fm fileExistsAtPath:full isDirectory:&isDir]) continue;
            if (isDir) {
                if ([low isEqualToString:@"color"] || [low isEqualToString:@"matte"]) {
                    [fm removeItemAtPath:full error:NULL];
                }
                continue;
            }
            if ([low hasSuffix:@".mp4"] || [low hasSuffix:@".mov"] || [low hasSuffix:@".m4v"]) {
                [fm removeItemAtPath:full error:NULL];
            }
        }
    }
    for (NSString *n in @[ @"idle.mov", @"turn.mov", @"click.mov", @"drag.mov", @"sleep.mov", @"demo.mov" ]) {
        NSString *q = [@"/var/mobile/Library/DSHPet/assets" stringByAppendingPathComponent:n];
        if ([fm fileExistsAtPath:q]) { [fm removeItemAtPath:q error:NULL]; }
    }

        NSMutableDictionary *rec = [NSMutableDictionary dictionary];
        NSISO8601DateFormatter *df = [[NSISO8601DateFormatter alloc] init];
        rec[@"ts"] = [df stringFromDate:[NSDate date]];
        rec[@"lvl"] = lvl ?: @"info";
        rec[@"mod"] = mod ?: @"app";
        rec[@"evt"] = evt ?: @"?";
        rec[@"pid"] = @(getpid());
        rec[@"ver"] = DSHPET_VERSION_STRING;
        if (kv) [rec addEntriesFromDictionary:kv];

        NSData *json = nil;
        @try {
            json = [NSJSONSerialization dataWithJSONObject:DSHPetJSONSafe(rec, 0) options:0 error:NULL];
        } @catch (NSException *e) {
            // 序列化再失败也别抛：写一条最简记录就行
            NSString *fallback = [NSString stringWithFormat:
                @"{\"ts\":\"%@\",\"lvl\":\"%@\",\"mod\":\"%@\",\"evt\":\"%@\",\"pid\":%d,\"ver\":\"%@\",\"note\":\"serialize-failed\"}\n",
                rec[@"ts"], rec[@"lvl"], rec[@"mod"], rec[@"evt"], (int)getpid(), DSHPET_VERSION_STRING];
            [[fallback dataUsingEncoding:NSUTF8StringEncoding] writeToFile:DSHPetLogPathForModule(mod ?: @"app") atomically:YES];
            return;
        }
        if (!json) return;

        NSMutableData *line = [json mutableCopy];
        [line appendBytes:"\n" length:1];

        NSString *path = DSHPetLogPathForModule(mod ?: @"app");
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!fh) {
            [line writeToFile:path atomically:YES];
            return;
        }
        @try {
            [fh seekToEndOfFile];
            [fh writeData:line];
        } @catch (__unused NSException *e) {
            // 写日志永远不许影响主流程
        } @finally {
            [fh closeFile];
        }
    }
}

void DSHPetBootLog(NSString *event, NSDictionary *kv) {
    DSHPetLog(@"boot", event, @"info", kv);
}
