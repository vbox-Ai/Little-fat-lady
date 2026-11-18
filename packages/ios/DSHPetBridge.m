#import "DSHPetBridge.h"
#import "DSHPetBoot.h"

NSString *const DSHPetSayNotification = @"DSHPetSay";
NSString *const DSHPetStatusNotification = @"DSHPetStatus";
NSString *const DSHPetSessionsNotification = @"DSHPetSessions";

// S6c：会话多久没动静就算"结束"（不再给它分配宠物）。
static const NSTimeInterval kDSHPetSessionTTL = 15.0 * 60.0;

@interface DSHPetBridge ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, copy) NSString *base;
@property (nonatomic, copy) NSString *token;
@property (nonatomic, assign) NSTimeInterval interval;
@property (nonatomic, assign) double lastCounter;
@property (nonatomic, assign) BOOL inFlight;
@property (nonatomic, assign) NSInteger failures;
@property (nonatomic, copy) NSString *lastNotifyCounter;
@property (nonatomic, readwrite, copy) NSString *lastError;
@property (nonatomic, readwrite, copy) NSString *workState;
// S6c：sessionId -> @{id,lastSeen,text}
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *sessionMap;
@end

@implementation DSHPetBridge

+ (instancetype)shared {
    static DSHPetBridge *one = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ one = [[DSHPetBridge alloc] init]; });
    return one;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    cfg.timeoutIntervalForRequest = 6.0;
    cfg.timeoutIntervalForResource = 12.0;
    cfg.HTTPShouldUsePipelining = NO;
    _session = [NSURLSession sessionWithConfiguration:cfg];
    _lastCounter = -1.0;
    _failures = 0;
    _sessionMap = [NSMutableDictionary dictionary];
    return self;
}

#pragma mark - S6c 会话集合

- (void)touchSession:(NSString *)sid text:(NSString *)text {
    if (!sid.length) return;
    NSMutableDictionary *rec = self.sessionMap[sid];
    BOOL isNew = (rec == nil);
    if (isNew) rec = [NSMutableDictionary dictionary];
    rec[@"id"] = sid;
    rec[@"lastSeen"] = @([[NSDate date] timeIntervalSince1970]);
    if (text.length) rec[@"text"] = text;
    self.sessionMap[sid] = rec;
    if (isNew) {
        DSHPetLog(@"bridge", @"session-new", @"info", @{ @"id": sid,
                                                         @"n": @(self.sessionMap.count) });
        [self notifySessionsChanged];
    }
}

- (void)pruneSessions {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSMutableArray<NSString *> *dead = [NSMutableArray array];
    for (NSString *k in self.sessionMap) {
        double seen = [self.sessionMap[k][@"lastSeen"] doubleValue];
        if (now - seen > kDSHPetSessionTTL) [dead addObject:k];
    }
    if (!dead.count) return;
    [self.sessionMap removeObjectsForKeys:dead];
    DSHPetLog(@"bridge", @"session-expire", @"info", @{ @"n": @(dead.count),
                                                        @"left": @(self.sessionMap.count) });
    [self notifySessionsChanged];
}

- (void)notifySessionsChanged {
    [[NSNotificationCenter defaultCenter] postNotificationName:DSHPetSessionsNotification
                                                         object:nil
                                                       userInfo:@{ @"count": @(self.sessionMap.count) }];
}

- (NSArray<NSDictionary *> *)sessions {
    [self pruneSessions];
    NSArray *sorted = [self.sessionMap.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        double ta = [a[@"lastSeen"] doubleValue], tb = [b[@"lastSeen"] doubleValue];
        if (ta > tb) return NSOrderedAscending;
        if (ta < tb) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    return sorted ?: @[];
}

- (void)startWithBase:(NSString *)base token:(NSString *)token interval:(NSTimeInterval)interval {
    [self stop];
    if (!base.length) return;
    self.base = [base hasSuffix:@"/"] ? [base substringToIndex:base.length - 1] : base;
    self.token = token ?: @"";
    self.interval = interval > 0.2 ? interval : 2.5;
    self.failures = 0;
    self.lastError = nil;
    DSHPetLog(@"bridge", @"start", @"info", @{ @"base": self.base, @"sec": @(self.interval) });
    [self pollOnce];
    __weak DSHPetBridge *weakSelf = self;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:self.interval repeats:YES block:^(NSTimer *t) {
        [weakSelf pollOnce];
    }];
}

- (void)stop {
    [self.timer invalidate];
    self.timer = nil;
}

- (void)pollOnce {
    if (self.inFlight || !self.base.length) return;
    NSString *urlStr = [self.base stringByAppendingString:@"/dsh-pet-7340/state"];
    if (self.lastCounter > 0) {
        urlStr = [urlStr stringByAppendingFormat:@"?since=%.0f", self.lastCounter];
    }
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) return;

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"GET";
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    if (self.token.length) {
        [req setValue:self.token forHTTPHeaderField:@"X-DSHPet-Token"];
        [req setValue:[@"Bearer " stringByAppendingString:self.token] forHTTPHeaderField:@"Authorization"];
    }

    self.inFlight = YES;
    __weak DSHPetBridge *weakSelf = self;
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf handleData:data response:resp error:err];
        });
    }];
    [task resume];
}

- (void)handleData:(NSData *)data response:(NSURLResponse *)resp error:(NSError *)err {
    self.inFlight = NO;
    if (err || !data.length) {
        self.failures += 1;
        self.lastError = err.localizedDescription ?: @"empty";
        if (self.failures == 1 || self.failures % 20 == 0) {
            DSHPetLog(@"bridge", @"fail", @"warn", @{ @"n": @(self.failures), @"err": self.lastError ?: @"" });
        }
        return;
    }
    NSInteger code = 200;
    if ([resp isKindOfClass:[NSHTTPURLResponse class]]) code = ((NSHTTPURLResponse *)resp).statusCode;
    if (code != 200) {
        self.failures += 1;
        self.lastError = [NSString stringWithFormat:@"http-%ld", (long)code];
        DSHPetLog(@"bridge", @"http", @"warn", @{ @"code": @(code) });
        return;
    }

    NSError *jerr = nil;
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jerr];
    if (![root isKindOfClass:[NSDictionary class]]) {
        self.failures += 1;
        self.lastError = @"bad-json";
        return;
    }
    if (self.failures) {
        DSHPetLog(@"bridge", @"recover", @"info", @{ @"n": @(self.failures) });
        self.failures = 0;
        self.lastError = nil;
    }
    [self consumeState:(NSDictionary *)root];
}

- (void)fetchTodos:(void (^)(NSArray<NSDictionary *> *_Nullable, NSString *_Nullable))done {
    if (!done) return;
    if (!self.base.length) { done(nil, @"未配置宿主地址"); return; }

    NSString *urlStr = [self.base stringByAppendingString:@"/dsh-pet-7340/todos"];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) { done(nil, @"地址不合法"); return; }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"GET";
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    if (self.token.length) {
        [req setValue:self.token forHTTPHeaderField:@"X-DSHPet-Token"];
        [req setValue:[@"Bearer " stringByAppendingString:self.token] forHTTPHeaderField:@"Authorization"];
    }

    __weak DSHPetBridge *weakSelf = self;
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:req
                                                 completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSInteger code = 200;
        if ([resp isKindOfClass:[NSHTTPURLResponse class]]) code = ((NSHTTPURLResponse *)resp).statusCode;

        NSArray<NSDictionary *> *list = nil;
        NSString *fail = nil;
        if (err) {
            fail = err.localizedDescription ?: @"网络错误";
        } else if (code != 200) {
            fail = [NSString stringWithFormat:@"宿主返回 %ld", (long)code];
        } else {
            id root = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
            // 上游 GET /todos 的形状是 { ok: true, todos: [...] }（services/host/routes/todos.ts）。
            // 兼容两种：顶层就是数组，或者包一层。字段名不做假设，交给上层按 TodoItem 读。
            id arr = root;
            if ([root isKindOfClass:[NSDictionary class]]) arr = ((NSDictionary *)root)[@"todos"];
            if ([arr isKindOfClass:[NSArray class]]) {
                NSMutableArray<NSDictionary *> *keep = [NSMutableArray array];
                for (id it in (NSArray *)arr) {
                    if ([it isKindOfClass:[NSDictionary class]]) [keep addObject:it];
                }
                list = keep;
            } else {
                fail = @"返回里没有 todos 数组";
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            DSHPetBridge *s = weakSelf;
            if (fail) DSHPetLog(@"bridge", @"todos-fail", @"warn", @{ @"err": fail ?: @"" });
            else DSHPetLog(@"bridge", @"todos-ok", @"info", @{ @"n": @(list.count), @"base": s.base ?: @"" });
            done(list, fail);
        });
    }];
    [task resume];
}

- (void)consumeState:(NSDictionary *)root {
    NSDictionary *sections = root[@"sections"];
    if (![sections isKindOfClass:[NSDictionary class]]) sections = @{};

    id counter = root[@"counter"];
    if ([counter isKindOfClass:[NSNumber class]]) self.lastCounter = [counter doubleValue];

    // 1) 工作状态：working / thinking / idle …，只在前台播报变化
    NSDictionary *work = sections[@"workStatus"];
    if ([work isKindOfClass:[NSDictionary class]]) {
        NSDictionary *d = work[@"data"];
        if ([d isKindOfClass:[NSDictionary class]]) {
            // S6c：工作状态里若带 sessionId 也记一笔——多开时这只宠物就归这个会话
            NSString *wsid = d[@"sessionId"];
            if ([wsid isKindOfClass:[NSString class]] && wsid.length) [self touchSession:wsid text:nil];
            NSString *st = d[@"state"];
            if ([st isKindOfClass:[NSString class]] && st.length && ![st isEqualToString:self.workState ?: @""]) {
                self.workState = st;
                [[NSNotificationCenter defaultCenter] postNotificationName:DSHPetStatusNotification
                                                                    object:nil
                                                                  userInfo:@{ @"state": st }];
                DSHPetLog(@"bridge", @"workstate", @"info", @{ @"state": st });
            }
        }
    }

    // 2) 会话信息：notify.data.event.data.text（turn 结束时那句），用 counter 去重
    NSDictionary *notify = sections[@"notify"];
    if ([notify isKindOfClass:[NSDictionary class]]) {
        NSString *nkey = [NSString stringWithFormat:@"%@", notify[@"counter"] ?: @""];
        if (nkey.length && ![nkey isEqualToString:self.lastNotifyCounter ?: @""]) {
            NSDictionary *d = notify[@"data"];
            NSString *text = nil;
            if ([d isKindOfClass:[NSDictionary class]]) {
                NSDictionary *ev = d[@"event"];
                if ([ev isKindOfClass:[NSDictionary class]]) {
                    NSDictionary *evData = ev[@"data"];
                    if ([evData isKindOfClass:[NSDictionary class]]) text = evData[@"text"];
                }
                if (![text isKindOfClass:[NSString class]]) text = d[@"text"];
            // S6c：会话身份。上游把 sessionId 放在 data 同层（也可能是顶层），两处都认。
            NSString *sid = d[@"sessionId"];
            if (![sid isKindOfClass:[NSString class]] || !sid.length) sid = root[@"sessionId"];
            if ([sid isKindOfClass:[NSString class]] && sid.length) {
                [self touchSession:sid text:[text isKindOfClass:[NSString class]] ? text : nil];
            }
            }
            if ([text isKindOfClass:[NSString class]] && text.length) {
                self.lastNotifyCounter = nkey;
                [[NSNotificationCenter defaultCenter] postNotificationName:DSHPetSayNotification
                                                                    object:nil
                                                                  userInfo:@{ @"text": text, @"kind": @"notify" }];
                DSHPetLog(@"bridge", @"say", @"info", @{ @"len": @(text.length) });
            }
        }
    }
}

@end
