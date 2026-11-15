#import <Foundation/Foundation.h>
#import "DSHPetVersion.h"

// 统一日志入口（方案 §8）：一行一条 JSONL 写 /var/mobile/Library/DSHPet/logs/<mod>.jsonl
// mod：boot / render / physics / bubble / net / prefs / assets …
// lvl：debug / info / warn / error

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

void DSHPetLog(NSString *mod, NSString *evt, NSString *lvl, NSDictionary *_Nullable kv);
void DSHPetBootLog(NSString *event, NSDictionary *_Nullable kv);
NSString *DSHPetLogPathForModule(NSString *mod);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
