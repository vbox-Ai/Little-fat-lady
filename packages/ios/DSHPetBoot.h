#import <Foundation/Foundation.h>
#import "DSHPetVersion.h"

// 统一日志入口（方案 §8）：一行一条 JSONL 写 /var/mobile/Library/DSHPet/logs/<mod>.jsonl
// mod：boot / render / physics / bubble / net / prefs / assets …
// lvl：debug / info / warn / error

#ifdef __cplusplus
extern "C" {
#endif

void DSHPetLog(NSString *mod, NSString *evt, NSString *lvl, NSDictionary *_Nullable kv);
void DSHPetBootLog(NSString *event, NSDictionary *_Nullable kv);

#ifdef __cplusplus
}
#endif

// 日志文件路径（mod 维度），导出/清理页会用
NSString *DSHPetLogPathForModule(NSString *mod);
