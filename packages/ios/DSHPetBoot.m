#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "DSHPetBoot.h"

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

void DSHPetLog(NSString *mod, NSString *evt, NSString *lvl, NSDictionary *kv) {
    @autoreleasepool {
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm createDirectoryAtPath:DSHPetLogDir() withIntermediateDirectories:YES attributes:nil error:NULL];

        NSMutableDictionary *rec = [NSMutableDictionary dictionary];
        NSISO8601DateFormatter *df = [[NSISO8601DateFormatter alloc] init];
        rec[@"ts"] = [df stringFromDate:[NSDate date]];
        rec[@"lvl"] = lvl ?: @"info";
        rec[@"mod"] = mod ?: @"app";
        rec[@"evt"] = evt ?: @"?";
        rec[@"pid"] = @(getpid());
        rec[@"ver"] = DSHPET_VERSION_STRING;
        if (kv) [rec addEntriesFromDictionary:kv];

        NSData *json = [NSJSONSerialization dataWithJSONObject:rec options:0 error:NULL];
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
