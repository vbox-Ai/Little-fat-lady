#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 素材可能落在这几个位置，按优先级返回（只返回真实存在的目录）。
/// 为什么不止一个：rootless 包把 layout 装到 /var/jb 下，但 roothide 类越狱的
/// dpkg / postinst 跑在"假根"里，看到的路径可能是 /Library/...；
/// 而 SpringBoard 进程里 /var/jb 又是真的。谁看见哪个不确定，全部试一遍最省事。
NSArray<NSString *> *DSHPetAssetRoots(void);

/// 第一个真正含有 .mov/.mp4 的素材根目录；没有就返回 nil。
NSString *_Nullable DSHPetFirstAssetRoot(void);

NS_ASSUME_NONNULL_END
