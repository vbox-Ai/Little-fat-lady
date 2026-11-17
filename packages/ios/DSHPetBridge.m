#import "DSHPetBridge.h"
#import "DSHPetBoot.h"

NSString *const DSHPetSayNotification = @"DSHPetSay";
NSString *const DSHPetStatusNotification = @"DSHPetStatus";

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
    return self;
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
