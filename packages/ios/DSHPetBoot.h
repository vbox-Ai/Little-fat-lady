#import <Foundation/Foundation.h>

// Tweak.xm 由 Logos 以 ObjC++ 编译，C 函数必须走 extern "C"，否则链接期名字被 mangle。
#ifdef __cplusplus
extern "C" {
#endif

void DSHPetBootLog(NSString *event, NSDictionary *kv);

#ifdef __cplusplus
}
#endif
