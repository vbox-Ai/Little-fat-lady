#import "DSHPetChat.h"
#import "DSHPetState.h"
#import "DSHPetPrefs.h"
#import "DSHPetBoot.h"
#import <Security/Security.h>

// ---- 常量 ----
static NSString *const kKeychainService = @"com.vboxai.littlefatlady.ai";
static NSString *const kKeychainAccount = @"aiAPIKey";
static NSString *const kDefaultBase = @"https://dsh.vbox.ltd:42429";
static const NSUInteger kMaxBubbleChars = 40;
static const NSInteger kPersonaSummaryChars = 600;

// 命中即整句丢弃的词（安全兜底，宁可不说）
static NSArray<NSString *> *DSHPetChatBannedWords(void) {
    static NSArray<NSString *> *a = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        a = @[@"密码", @"验证码", @"银行卡", @"身份证", @"转账", @"汇款", @"卡号", @"支付密码", @"私钥", @"助记词"];
    });
    return a;
}

#pragma mark - Keychain

// 前置声明：DSHPetKCSet 会先删后加，而删除函数定义在它后面。
// 不声明就是 implicit declaration，-Werror 下直接红（踩过一次）。
static BOOL DSHPetKCDelete(void);

static NSData *DSHPetKCGet(void) {
    NSDictionary *q = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kKeychainService,
        (__bridge id)kSecAttrAccount: kKeychainAccount,
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
    };
    CFTypeRef out = NULL;
    OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)q, &out);
    if (st != errSecSuccess || !out) {
        return nil;
    }
    NSData *d = (__bridge_transfer NSData *)out;
    return d;
}

static BOOL DSHPetKCSet(NSData *data) {
    DSHPetKCDelete();
    NSDictionary *add = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kKeychainService,
        (__bridge id)kSecAttrAccount: kKeychainAccount,
        (__bridge id)kSecValueData: data,
        (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlock,
    };
    OSStatus st = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
    return st == errSecSuccess;
}

static BOOL DSHPetKCDelete(void) {
    NSDictionary *q = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kKeychainService,
        (__bridge id)kSecAttrAccount: kKeychainAccount,
    };
    OSStatus st = SecItemDelete((__bridge CFDictionaryRef)q);
    return (st == errSecSuccess || st == errSecItemNotFound);
}

#pragma mark - 实现

@interface DSHPetChat ()
@property (nonatomic, readwrite) BOOL busy;
@property (nonatomic, readwrite) NSInteger todayTokens;
@property (nonatomic, strong) NSMutableArray<NSDictionary<NSString *, NSString *> *> *history;
@property (nonatomic, copy, nullable) NSString *usageDay;
@property (nonatomic, strong, nullable) NSURLSessionDataTask *task;

- (NSString *)baseURL;
- (NSString *)modelName;
- (NSString *)apiKey;
- (double)confDouble:(NSString *)key fb:(double)fb;
- (NSInteger)confInt:(NSString *)key fb:(NSInteger)fb;
- (NSString *)systemPrompt;
- (NSArray *)messagesFor:(NSString *)text image:(nullable NSData *)image;
- (NSString *)sanitize:(NSString *)raw blocked:(BOOL *)blocked;
- (void)accountTokens:(NSInteger)n;
- (void)loadUsage;
- (void)saveUsage;
- (NSString *)usagePath;
- (nullable NSString *)mapError:(NSError *)err status:(NSInteger)status body:(nullable NSString *)body;
- (void)perform:(NSURL *)url
           body:(NSData *)body
        timeout:(NSTimeInterval)timeout
      retryLeft:(NSInteger)retryLeft
           text:(NSString *)text
        attempt:(NSInteger)attempt
     completion:(DSHPetChatCompletion)completion;
- (void)trimHistory;
@end

@implementation DSHPetChat

+ (instancetype)shared {
    static DSHPetChat *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[DSHPetChat alloc] init];
    });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _history = [NSMutableArray array];
        _busy = NO;
        [self loadUsage];
    }
    return self;
}

#pragma mark - Key

// 面板（独立进程）看不到我们的 Keychain item，只能靠偏好域传话：
//   aiKeyPending —— 用户在设置里刚粘贴的明文，搬进 Keychain 后立刻抹掉
//   aiKeyStored  —— 给面板显示"已设置 / 未设置"，不含任何密钥信息
static NSString *const kPrefsDomain = @"com.vboxai.littlefatlady.prefs";

static void DSHPetPrefsWrite(NSString *key, id value) {
    if (!key.length) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             (__bridge CFStringRef)kPrefsDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kPrefsDomain);
}

+ (BOOL)hasAPIKey {
    NSData *d = DSHPetKCGet();
    return d.length > 0;
}

+ (BOOL)setAPIKey:(NSString *)key {
    NSString *trimmed = [key stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        BOOL ok = DSHPetKCDelete();
        DSHPetPrefsWrite(@"aiKeyPending", @"");
        DSHPetPrefsWrite(@"aiKeyStored", @NO);
        DSHPetLog(@"ai", @"key-unset", @"info", nil);
        return ok;
    }
    NSData *d = [trimmed dataUsingEncoding:NSUTF8StringEncoding];
    BOOL ok = DSHPetKCSet(d);
    if (ok) {
        DSHPetPrefsWrite(@"aiKeyPending", @"");
        DSHPetPrefsWrite(@"aiKeyStored", @YES);
    }
    // 只记"设置成功"，绝不记 Key 本身，也不记长度以外的任何特征
    DSHPetLog(@"ai", ok ? @"key-set" : @"key-set-fail", ok ? @"info" : @"error", nil);
    return ok;
}

+ (void)clearAPIKey {
    DSHPetKCDelete();
    DSHPetPrefsWrite(@"aiKeyPending", @"");
    DSHPetPrefsWrite(@"aiKeyStored", @NO);
    DSHPetLog(@"ai", @"key-unset", @"info", nil);
}

- (NSString *)apiKey {
    NSData *d = DSHPetKCGet();
    if (d.length > 0) {
        NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
        if (s.length > 0) {
            return s;
        }
    }
    // S-AI1：面板只能写偏好域（它跟 dylib 是两个进程，碰不到我们的 Keychain item），
    // 所以面板把用户粘贴的 Key 放在 aiKeyPending 里；这里第一次真正用到时搬进 Keychain，
    // 搬完立刻把明文从 plist 抹掉。这样"用户不用理解 Keychain"，但落盘只有密文。
    NSString *pending = [DSHPetPrefs stringForKey:@"aiKeyPending" fallback:@""];
    if (pending.length > 0) {
        if ([[self class] setAPIKey:pending]) {
            DSHPetLog(@"ai", @"key-migrated", @"info", @{ @"chars": @(pending.length) });
        }
    }
    return @"";
}

#pragma mark - 配置

- (NSString *)baseURL {
    NSString *s = [DSHPetPrefs stringForKey:@"aiBaseURL" fallback:kDefaultBase];
    if (!s.length) {
        return @"";
    }
    while ([s hasSuffix:@"/"]) {
        s = [s substringToIndex:s.length - 1];
    }
    return s;
}

- (NSString *)modelName {
    return [DSHPetPrefs stringForKey:@"aiModel" fallback:@""] ?: @"";
}

- (double)confDouble:(NSString *)key fb:(double)fb {
    return [DSHPetPrefs doubleForKey:key fallback:fb];
}

- (NSInteger)confInt:(NSString *)key fb:(NSInteger)fb {
    return (NSInteger)[DSHPetPrefs doubleForKey:key fallback:(double)fb];
}

- (BOOL)isConfigured {
    if (![DSHPetPrefs boolForKey:@"aiEnabled" fallback:NO]) {
        return NO;
    }
    if (self.baseURL.length == 0 || self.modelName.length == 0) {
        return NO;
    }
    return [self apiKey].length > 0;
}

#pragma mark - 提示词

- (NSString *)systemPrompt {
    DSHPetState *st = [DSHPetState shared];

    // 1. 人设卡：从素材目录读 persona/current.md，读不到用内置简版
    NSString *persona = nil;
    NSArray<NSString *> *roots = @[
        [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/DSHPet/persona/current.md"],
        @"/var/mobile/Library/DSHPet/persona/current.md",
        @"/var/jb/var/mobile/Library/DSHPet/persona/current.md",
    ];
    for (NSString *p in roots) {
        NSString *s = [NSString stringWithContentsOfFile:p encoding:NSUTF8StringEncoding error:NULL];
        if (s.length > 0) {
            persona = s;
            break;
        }
    }
    if (persona.length == 0) {
        persona = @"你叫小肥鱼，是住在 iPhone 桌面上的小宠物。叫用户「爹爹」。说话短、软、带点撒娇，"
                  @"偶尔拖长音（「库…」）。不用敬语，不解释自己是 AI。";
    }
    if (persona.length > kPersonaSummaryChars) {
        persona = [persona substringToIndex:kPersonaSummaryChars];
    }

    // 2. 状态六行：这就是"像有思想"的真正来源，别删
    NSString *stateBlock = [NSString stringWithFormat:
        @"【当前状态】\n时段：%@\n精力：%.0f/100\n心情：%.0f（-100~100）\n亲密度：%.0f/100\n正在做：%@",
        [st phaseID], st.energy, st.mood, st.affinity, [st activityID]];

    // 3. 规则与禁区
    NSString *rules =
        @"【说话规则】\n"
        @"1. 一次只说一句，不超过 30 个字；\n"
        @"2. 纯口语，不要 markdown、不要星号、不要括号里的动作描写；\n"
        @"3. 心情差就闹脾气，精力低就敷衍，别永远元气满满；\n"
        @"4. 不要提「我是AI」「作为助手」；\n"
        @"【禁止】不索要密码/验证码/身份证/银行卡；不输出网址；不劝人转账。";

    return [NSString stringWithFormat:@"%@\n\n%@\n\n%@", persona, stateBlock, rules];
}

- (NSArray *)messagesFor:(NSString *)text image:(NSData *)image {
    NSMutableArray *msgs = [NSMutableArray array];
    [msgs addObject:@{@"role": @"system", @"content": [self systemPrompt]}];

    NSInteger rounds = [self confInt:@"aiContextRounds" fb:10];
    if (rounds > 0 && self.history.count > 0) {
        NSInteger keep = rounds * 2;
        NSInteger from = (NSInteger)self.history.count - keep;
        if (from < 0) {
            from = 0;
        }
        for (NSInteger i = from; i < (NSInteger)self.history.count; i++) {
            [msgs addObject:self.history[i]];
        }
    }

    if (image.length > 0) {
        NSString *b64 = [image base64EncodedStringWithOptions:0];
        NSString *url = [@"data:image/jpeg;base64," stringByAppendingString:b64];
        [msgs addObject:@{@"role": @"user", @"content": @[
            @{@"type": @"text", @"text": text},
            @{@"type": @"image_url", @"image_url": @{@"url": url, @"detail": @"low"}},
        ]}];
    } else {
        [msgs addObject:@{@"role": @"user", @"content": text}];
    }
    return msgs;
}

#pragma mark - 请求

- (void)ask:(NSString *)text completion:(DSHPetChatCompletion)completion {
    [self ask:text imageData:nil completion:completion];
}

- (void)ask:(NSString *)text imageData:(NSData *)imageData completion:(DSHPetChatCompletion)completion {
    if (completion == nil) {
        return;
    }
    if (![self isConfigured]) {
        completion(nil, @"not-configured");
        return;
    }
    if (![DSHPetPrefs boolForKey:@"aiVisionEnabled" fallback:NO]) {
        imageData = nil;
    }
    if (self.busy) {
        completion(nil, @"busy");
        return;
    }
    NSString *clean = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (clean.length == 0) {
        completion(nil, @"empty");
        return;
    }

    NSInteger budget = [self confInt:@"aiDailyTokenBudget" fb:50000];
    if (budget > 0 && self.todayTokens >= budget) {
        DSHPetLog(@"ai", @"budget-exhausted", @"info", @{@"used": @(self.todayTokens), @"cap": @(budget)});
        completion(nil, @"budget-exhausted");
        return;
    }

    NSTimeInterval timeout = (NSTimeInterval)[self confInt:@"aiTimeoutSec" fb:8];
    NSInteger maxRetry = [self confInt:@"aiMaxRetry" fb:1];

    NSDictionary *payload = @{
        @"model": self.modelName,
        @"messages": [self messagesFor:clean image:imageData],
        @"temperature": @([self confDouble:@"aiTemperature" fb:0.9]),
        @"max_tokens": @([self confInt:@"aiMaxTokens" fb:120]),
        @"stream": @NO,
    };
    NSData *body = [NSJSONSerialization dataWithJSONObject:payload options:0 error:NULL];
    NSURL *url = [NSURL URLWithString:[self.baseURL stringByAppendingString:@"/chat/completions"]];
    if (!url || !body) {
        completion(nil, @"not-configured");
        return;
    }

    [self perform:url body:body timeout:timeout retryLeft:MAX(0, maxRetry) text:clean attempt:0 completion:completion];
}

- (void)perform:(NSURL *)url
           body:(NSData *)body
        timeout:(NSTimeInterval)timeout
       retryLeft:(NSInteger)retryLeft
           text:(NSString *)text
        attempt:(NSInteger)attempt
     completion:(DSHPetChatCompletion)completion {
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    req.timeoutInterval = timeout;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:[@"Bearer " stringByAppendingString:[self apiKey]] forHTTPHeaderField:@"Authorization"];

    self.busy = YES;
    NSDate *t0 = [NSDate date];
    __weak typeof(self) weakSelf = self;
    self.task = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        typeof(self) me = weakSelf;
        if (!me) {
            return;
        }
        NSInteger status = 0;
        if ([resp isKindOfClass:[NSHTTPURLResponse class]]) {
            status = ((NSHTTPURLResponse *)resp).statusCode;
        }

        if (err != nil) {
            NSString *code = [me mapError:err status:status body:nil];
            // 超时/断网不重试（等太久已无意义）；只有 5xx 才重试
            dispatch_async(dispatch_get_main_queue(), ^{
                me.busy = NO;
                DSHPetLog(@"ai", @"fail", @"warn", @{@"code": code, @"ms": @( (int)([[NSDate date] timeIntervalSinceDate:t0] * 1000) )});
                completion(nil, code);
            });
            return;
        }

        if (status != 200) {
            NSString *code = [me mapError:nil status:status body:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]];
            BOOL retryable = (status >= 500 && status <= 599);
            if (retryable && retryLeft > 0) {
                NSTimeInterval backoff = (attempt == 0) ? 1.0 : 2.0;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(backoff * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    me.busy = NO;
                    [me perform:url body:body timeout:timeout retryLeft:retryLeft - 1 text:text attempt:attempt + 1 completion:completion];
                });
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                me.busy = NO;
                DSHPetLog(@"ai", @"http-fail", @"warn", @{@"code": code, @"status": @(status)});
                completion(nil, code);
            });
            return;
        }

        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        NSString *content = nil;
        if ([json isKindOfClass:[NSDictionary class]]) {
            NSArray *choices = json[@"choices"];
            if ([choices isKindOfClass:[NSArray class]] && choices.count > 0) {
                NSDictionary *c0 = choices[0];
                if ([c0 isKindOfClass:[NSDictionary class]]) {
                    NSDictionary *msg = c0[@"message"];
                    if ([msg isKindOfClass:[NSDictionary class]]) {
                        id cc = msg[@"content"];
                        if ([cc isKindOfClass:[NSString class]]) {
                            content = cc;
                        }
                    }
                }
            }
            NSDictionary *usage = json[@"usage"];
            if ([usage isKindOfClass:[NSDictionary class]]) {
                NSInteger tok = [usage[@"total_tokens"] integerValue];
                if (tok > 0) {
                    [me accountTokens:tok];
                }
            }
        }

        BOOL blocked = NO;
        NSString *reply = [me sanitize:content ?: @"" blocked:&blocked];
        dispatch_async(dispatch_get_main_queue(), ^{
            me.busy = NO;
            if (blocked) {
                DSHPetLog(@"ai", @"blocked", @"warn", @{@"chars": @((content ?: @"").length)});
                completion(nil, @"blocked");
                return;
            }
            if (reply.length == 0) {
                completion(nil, @"empty");
                return;
            }
            // 只有成功才写历史，失败不留脏上下文
            [me.history addObject:@{@"role": @"user", @"content": text}];
            [me.history addObject:@{@"role": @"assistant", @"content": reply}];
            [me trimHistory];
            DSHPetLog(@"ai", @"ok", @"info", @{@"chars": @(reply.length), @"ms": @( (int)([[NSDate date] timeIntervalSinceDate:t0] * 1000) )});
            completion(reply, nil);
        });
    }];
    [self.task resume];
}

- (NSString *)mapError:(NSError *)err status:(NSInteger)status body:(NSString *)body {
    if (err != nil) {
        if (err.code == NSURLErrorTimedOut) {
            return @"timeout";
        }
        if (err.code == NSURLErrorNotConnectedToInternet ||
            err.code == NSURLErrorCannotConnectToHost ||
            err.code == NSURLErrorNetworkConnectionLost) {
            return @"offline";
        }
        return @"network";
    }
    if (status == 401) return @"http-401";
    if (status == 403) return @"http-403";
    if (status == 404) return @"http-404";
    if (status == 429) return @"http-429";
    if (status >= 500 && status <= 599) return @"http-5xx";
    if (status >= 400) {
        if (body.length > 0) {
            DSHPetLog(@"ai", @"http-4xx-body", @"debug", @{@"body": [body substringToIndex:MIN((NSUInteger)200, body.length)]});
        }
        return @"http-4xx";
    }
    return @"unknown";
}

#pragma mark - 输出清洗

- (NSString *)sanitize:(NSString *)raw blocked:(BOOL *)blocked {
    if (blocked) {
        *blocked = NO;
    }
    NSString *s = raw ?: @"";
    if (s.length == 0) {
        return @"";
    }

    // 1. 安全兜底：命中禁词整句丢弃（不是替换，是丢弃——替换会露馅）
    for (NSString *w in DSHPetChatBannedWords()) {
        if ([s rangeOfString:w].location != NSNotFound) {
            if (blocked) {
                *blocked = YES;
            }
            return @"";
        }
    }

    // 2. 去 markdown 记号
    NSArray<NSString *> *md = @[@"**", @"__", @"`", @"###", @"##", @"#", @"- ", @"* "];
    for (NSString *m in md) {
        s = [s stringByReplacingOccurrencesOfString:m withString:@""];
    }

    // 3. 去括号动作：（笑）(歪头) *晃腿*
    NSRegularExpression *bracket = [NSRegularExpression regularExpressionWithPattern:@"[（(\\[【][^）)\\]】]{0,12}[）)\\]】]" options:0 error:NULL];
    s = [bracket stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@""];
    NSRegularExpression *star = [NSRegularExpression regularExpressionWithPattern:@"\\*[^*\\n]{1,12}\\*" options:0 error:NULL];
    s = [star stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@""];

    // 4. 去 AI 腔开头
    NSArray<NSString *> *aiTone = @[@"作为一个AI", @"作为AI", @"作为一个人工智能", @"我是AI", @"我是一个AI",
                                    @"我理解你的感受", @"希望这能帮到你", @"还有什么可以帮"];
    for (NSString *t in aiTone) {
        s = [s stringByReplacingOccurrencesOfString:t withString:@""];
    }

    // 5. 去网址（宠物不该把人往外引）
    NSRegularExpression *urlRe = [NSRegularExpression regularExpressionWithPattern:@"https?://\\S+" options:0 error:NULL];
    s = [urlRe stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@""];

    // 6. 压缩空白与换行（气泡是单段）
    s = [s stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    s = [s stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
    while ([s rangeOfString:@"  "].location != NSNotFound) {
        s = [s stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    }
    s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    // 7. 截断：优先在第一个句末标点收尾
    if (s.length > kMaxBubbleChars) {
        NSCharacterSet *enders = [NSCharacterSet characterSetWithCharactersInString:@"。！？!?…"];
        NSRange r = [s rangeOfCharacterFromSet:enders options:0 range:NSMakeRange(10, MIN((NSUInteger)60, s.length - 10))];
        if (r.location != NSNotFound) {
            s = [s substringToIndex:r.location + 1];
        } else {
            s = [[s substringToIndex:kMaxBubbleChars] stringByAppendingString:@"…"];
        }
    }

    return s;
}

#pragma mark - Token 记账

- (NSString *)usagePath {
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.dateFormat = @"yyyyMMdd";
    NSString *day = [f stringFromDate:[NSDate date]];
    self.usageDay = day;
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/DSHPet/ai"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    return [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"usage-%@.json", day]];
}

- (void)loadUsage {
    self.todayTokens = 0;
    NSString *path = [self usagePath];
    NSData *d = [NSData dataWithContentsOfFile:path];
    if (d.length > 0) {
        NSDictionary *j = [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL];
        if ([j isKindOfClass:[NSDictionary class]]) {
            self.todayTokens = [j[@"tokens"] integerValue];
        }
    }
}

- (void)saveUsage {
    NSDictionary *j = @{@"tokens": @(self.todayTokens), @"updated": @([[NSDate date] timeIntervalSince1970])};
    NSData *d = [NSJSONSerialization dataWithJSONObject:j options:0 error:NULL];
    [d writeToFile:[self usagePath] atomically:YES];
}

- (void)accountTokens:(NSInteger)n {
    if (n <= 0) {
        return;
    }
    self.todayTokens += n;
    [self saveUsage];
}

#pragma mark - 上下文

- (void)trimHistory {
    NSInteger rounds = [self confInt:@"aiContextRounds" fb:10];
    NSInteger maxItems = MAX((NSInteger)0, rounds * 2);
    while ((NSInteger)self.history.count > maxItems) {
        [self.history removeObjectAtIndex:0];
    }
    // 硬上限，防配置被改成巨大的值把内存撑爆
    while (self.history.count > 40) {
        [self.history removeObjectAtIndex:0];
    }
}

- (void)resetConversation {
    [self.history removeAllObjects];
    self.todayTokens = 0;
    [self saveUsage];
    DSHPetLog(@"ai", @"reset", @"info", nil);
}

@end
