#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "DSHPetBoot.h"

// S1 只做一件事：证明"注入成功 + 能落盘"。
// 日志格式与方案 §8 的 runtime.jsonl 一致（JSONL，一行一条）。
// 注意：这里刻意不碰网络、不建窗口、不注册任何 hook 之外的东西。

void DSHPetBootLog(NSString *event, NSDictionary *kv);

static NSString *DSHPetLogDir(void) {
    return @"/var/mobile/Library/DSHPet/logs";
}

static NSString *DSHPetLogPath(void) {
    return [DSHPetLogDir() stringByAppendingPathComponent:@"runtime.jsonl"];
}

void DSHPetBootLog(NSString *event, NSDictionary *kv) {
    @autoreleasepool {
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm createDirectoryAtPath:DSHPetLogDir() withIntermediateDirectories:YES attributes:nil error:NULL];

        NSMutableDictionary *rec = [NSMutableDictionary dictionary];
        NSISO8601DateFormatter *df = [[NSISO8601DateFormatter alloc] init];
        rec[@"ts"] = [df stringFromDate:[NSDate date]];
        rec[@"lvl"] = @"info";
        rec[@"mod"] = @"boot";
        rec[@"evt"] = event;
        rec[@"pid"] = @(getpid());
        rec[@"ver"] = @"0.1.0-s1";
        if (kv) [rec addEntriesFromDictionary:kv];

        NSData *json = [NSJSONSerialization dataWithJSONObject:rec options:0 error:NULL];
        if (!json) return;
        NSMutableData *line = [json mutableCopy];
        [line appendBytes:"\n" length:1];

        NSString *path = DSHPetLogPath();
        if (![fm fileExistsAtPath:path]) {
            [line writeToFile:path atomically:YES];
            return;
        }
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!fh) return;
        @try {
            [fh seekToEndOfFile];
            [fh writeData:line];
        } @finally {
            [fh closeFile];
        }
    }
}
