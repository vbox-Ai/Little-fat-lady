#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "DSHPetBoot.h"
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
    // 旧版本留下的 5 段占位演示片，会在真素材之外插一脚（"有时冒出蓝水母"）；
    // 只删这几个固定名字，用户自己放的 main.* 不动。
    // 旧包（单路 ProRes，无 alpha）整个清掉：留着会被索引器当成候选根，
    // 抽到就播成一块黑底。只保留 color/ matte/ 与用户自己的 main.*。
    {
        NSString *aroot = @"/var/mobile/Library/DSHPet/assets";
        NSArray<NSString *> *kids = [fm contentsOfDirectoryAtPath:aroot error:NULL] ?: @[];
        for (NSString *k in kids) {
            if ([k isEqualToString:@"color"] || [k isEqualToString:@"matte"]) continue;
            if ([k.lowercaseString hasPrefix:@"main."]) continue;
            [fm removeItemAtPath:[aroot stringByAppendingPathComponent:k] error:NULL];
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
