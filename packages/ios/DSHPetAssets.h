#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// 素材根候选（按优先级，已过滤成「真实存在的目录」）
NSArray<NSString *> *DSHPetAssetRoots(void);
// 第一个确实含素材的根；找不到返回 nil
NSString *_Nullable DSHPetFirstAssetRoot(void);
// 启动时把随包素材自拷到运行目录（/var/mobile/Library/DSHPet/assets）
void DSHPetEnsureAssets(void);
// 把「这台机器上到底找了哪些路径、哪个有素材」写进 /var/mobile/Library/DSHPet/doctor.txt
// 目的：绿方块（素材没找到）时让用户直接把这一份发回来，不用抓 syslog。
void DSHPetWriteDoctor(NSString *_Nullable note);

NS_ASSUME_NONNULL_END
