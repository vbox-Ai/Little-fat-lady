#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "DSHPetBoot.h"

// S1 空壳：只验证三件事
//   1. dylib 能被注入到 SpringBoard（进程里能跑到这里）
//   2. 能往 /var/mobile/Library/DSHPet/logs/runtime.jsonl 写日志（权限对）
//   3. 卸载后不残留（由 postrm 负责）
// 不建窗口、不发网络请求、不 hook 任何控件 —— 万一有问题，卸载即可，不会把 SpringBoard 搞挂。

__attribute__((constructor))
static void dshpet_ctor(void) {
    @autoreleasepool {
        DSHPetBootLog(@"boot", @{
            @"exe": [[NSBundle mainBundle] bundleIdentifier] ?: @"?",
            @"os": [[UIDevice currentDevice] systemVersion] ?: @"?",
            @"model": [[UIDevice currentDevice] model] ?: @"?",
        });
    }
}

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    DSHPetBootLog(@"springboard-ready", @{ @"stage": @"s1" });
}

%end
