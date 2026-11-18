#import <Foundation/Foundation.h>

// 与宿主 DSH 的桥：轮询 /dsh-pet-7340/state，把会话信息抛给气泡。
// 只读，绝不调 /quit、不写 /config（见方案 §19 红线）。
//
// 注意：这个头文件必须有 nullability 区间（NS_ASSUME_NONNULL_BEGIN/END）。
// 仓库开着 -Werror，`-Wnullability-completeness` 会因为「一个头里混用了带标记与不带标记的指针」
// 直接编译失败 —— 上一版就是漏了这个区间、CI 红了。
// 真的可能为 nil 的属性/参数，逐个标 _Nullable，别指望默认值。
NS_ASSUME_NONNULL_BEGIN

extern NSString *const DSHPetSayNotification;    // userInfo: {text, kind}
extern NSString *const DSHPetStatusNotification; // userInfo: {state, task}
// S6c：最近活跃会话集合变了（新增/过期），userInfo: {count}
extern NSString *const DSHPetSessionsNotification;

@interface DSHPetBridge : NSObject

+ (instancetype)shared;
- (void)startWithBase:(NSString *)base token:(nullable NSString *)token interval:(NSTimeInterval)interval;
- (void)stop;
- (void)pollOnce;

/// 最近一次失败原因；成功时为 nil。
@property (nonatomic, readonly, nullable) NSString *lastError;
/// 宿主报上来的工作状态（working / thinking / idle …）；还不知道时为 nil。
@property (nonatomic, readonly, nullable) NSString *workState;

/// S6c 多开：最近活跃的会话（`@[@{@"id":…, @"lastSeen":…, @"text":…}, …]`，按最近活跃排序）。
/// 依据是 `/state` 里 notify 事件带的 `sessionId` —— 上游没有单独的"会话列表"接口，
/// 所以这里只认"最近真的有动静"的会话。多开时一只宠物跟一个会话，靠它来分工。
@property (nonatomic, readonly, copy) NSArray<NSDictionary *> *sessions;

/// S6d 待办面板：GET {base}/dsh-pet-7340/todos（上游 `{ ok, todos: [...] }`）。
/// 只读。传回原始条目字典，字段按上游 TodoItem：id/text/dueAt/done/createdAt/updatedAt/completedAt。
/// 写操作（勾选、新建）在手机上不做 —— 改宿主状态属于红线外的事，先只读展示。
- (void)fetchTodos:(void (^)(NSArray<NSDictionary *> *_Nullable todos,
                            NSString *_Nullable errorText))done;

@end

NS_ASSUME_NONNULL_END