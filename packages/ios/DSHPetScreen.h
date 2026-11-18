#import <Foundation/Foundation.h>

// S-AI4：读屏（方案 §11.8 的 B 路线 —— 无障碍树，不是截图）
//
// 为什么不做截图：
//   1. 越狱插件跑在 SpringBoard 进程里，拿不到前台 App 的画面（UIScreen 只能截自己）；
//   2. 就算拿到图，还要过一遍视觉模型，慢且贵；
//   3. 文字类界面（股票、聊天、列表）走无障碍树又快又准。
//
// 为什么用 dlopen 而不是直接链接：
//   AXUIElement 这一族符号在 AXRuntime 私有框架里，Theos 的 SDK 没有对应 .tbd；
//   直接链接会在缺符号的机型上让整个 dylib 加载失败 → SpringBoard 起不来。
//   所以运行期 dlsym，找不到就老老实实返回 nil，一步都不往前走。
//
// 隐私：只读文字，不落盘、不上传；读到的内容只用于这一次对话（见 DSHPetChat）。

NS_ASSUME_NONNULL_BEGIN

@interface DSHPetScreen : NSObject

// 当前环境能不能用无障碍树（dlsym 成功 + 系统级元素拿得到）
+ (BOOL)available;

// 读当前屏幕上的文字，拼成一段纯文本；读不到返回 nil。
// maxChars 建议 800～1200（再长会挤掉人设，模型容易只复述不复述判断）。
+ (nullable NSString *)currentScreenTextWithLimit:(NSInteger)maxChars;

@end

NS_ASSUME_NONNULL_END
