//
//  DSHPetTTS.m
//  小肥娘 · 远端语音合成
//

#import "DSHPetTTS.h"
#import "DSHPetPrefs.h"
#import "DSHPetBoot.h"
#import <Security/Security.h>

static NSString *const kTTSKeychainService = @"com.vboxai.littlefatlady.tts";
static NSString *const kTTSAccountToken    = @"accessToken";
static NSString *const kTTSAccountAPIKey   = @"apiKey";

static const NSTimeInterval kTTSTimeout    = 20.0;
static const NSTimeInterval kTTSCacheTTL   = 30 * 24 * 3600.0;
static const NSUInteger     kTTSMaxChars   = 300;   // 单次合成上限，超了截断（宁短勿失败）

static BOOL DSHPetTTSKCDelete(NSString *account);

#pragma mark - 偏好域写穿透（面板只能写、读不回来，写完立刻抹掉明文）

static void DSHPetTTSClearPref(NSString *key) {
    if (key.length == 0) {
        return;
    }
    for (NSString *domain in @[@"com.vboxai.littlefatlady.prefs", @"com.vboxai.littlefatlady"]) {
        CFPreferencesSetAppValue((__bridge CFStringRef)key,
                                 (__bridge CFStringRef)@"",
                                 (__bridge CFStringRef)domain);
        CFPreferencesAppSynchronize((__bridge CFStringRef)domain);
    }
}

#pragma mark - Keychain 基础

static NSMutableDictionary *DSHPetTTSBaseQuery(NSString *account) {
    NSMutableDictionary *q = [NSMutableDictionary dictionary];
    q[(__bridge id)kSecClass]       = (__bridge id)kSecClassGenericPassword;
    q[(__bridge id)kSecAttrService] = kTTSKeychainService;
    q[(__bridge id)kSecAttrAccount] = account ?: @"";
    return q;
}

static NSString *DSHPetTTSKCGet(NSString *account) {
    NSMutableDictionary *q = DSHPetTTSBaseQuery(account);
    q[(__bridge id)kSecReturnData] = @YES;
    q[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef out = NULL;
    OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)q, &out);
    if (st != errSecSuccess || out == NULL) {
        return nil;
    }
    NSData *d = (__bridge_transfer NSData *)out;
    NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    return s.length > 0 ? s : nil;
}

static BOOL DSHPetTTSKCSet(NSString *account, NSString *value) {
    if (value.length == 0) {
        return DSHPetTTSKCDelete(account);
    }
    NSData *d = [value dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableDictionary *q = DSHPetTTSBaseQuery(account);
    OSStatus st = SecItemUpdate((__bridge CFDictionaryRef)q,
                                (__bridge CFDictionaryRef)@{ (__bridge id)kSecValueData: d });
    if (st == errSecItemNotFound) {
        q[(__bridge id)kSecValueData] = d;
        q[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlock;
        st = SecItemAdd((__bridge CFDictionaryRef)q, NULL);
    }
    return st == errSecSuccess;
}

static BOOL DSHPetTTSKCDelete(NSString *account) {
    NSMutableDictionary *q = DSHPetTTSBaseQuery(account);
    OSStatus st = SecItemDelete((__bridge CFDictionaryRef)q);
    return st == errSecSuccess || st == errSecItemNotFound;
}

#pragma mark - 哈希 / 路径

static NSString *DSHPetTTSHash(NSString *s) {
    // FNV-1a 64：不引 CommonCrypto，够用来做缓存键。
    const char *p = s.UTF8String ?: "";
    unsigned long long h = 1469598103934665603ULL;
    for (size_t i = 0; p[i] != '\0'; i++) {
        h ^= (unsigned long long)(unsigned char)p[i];
        h *= 1099511628211ULL;
    }
    return [NSString stringWithFormat:@"%016llx", h];
}

#pragma mark - DSHPetTTS

static void DSHPetTTSOnPurge(CFNotificationCenterRef center,
                             void *observer,
                             CFNotificationName name,
                             const void *object,
                             CFDictionaryRef info) {
    (void)center; (void)name; (void)object; (void)info;
    DSHPetTTS *me = (__bridge DSHPetTTS *)observer;
    [me purgeCache];
}

@interface DSHPetTTS ()
@property (nonatomic, readwrite) DSHPetTTSEngine engine;
@property (nonatomic, copy) NSString *appID;
@property (nonatomic, copy) NSString *cluster;
@property (nonatomic, copy) NSString *voiceType;
@property (nonatomic, copy) NSString *baseURL;
@property (nonatomic, copy) NSString *model;
@property (nonatomic, copy) NSString *voice;
@property (nonatomic, assign) double speed;
@property (nonatomic, assign) double pitch;
- (NSString *)cacheDirectory;
- (void)purgeCache;
- (void)ensureCacheDirectory;
- (void)finishWith:(void (^)(NSURL *, NSError *))completion file:(NSURL *)file error:(NSError *)error;
- (NSError *)errorWithCode:(NSInteger)code reason:(NSString *)reason;
- (NSData *)synthesizeSynchronously:(NSString *)text error:(NSError **)outError;
- (NSData *)requestVolcSync:(NSString *)text error:(NSError **)outError;
- (NSData *)requestOpenAISync:(NSString *)text error:(NSError **)outError;
- (NSData *)postJSON:(NSString *)url body:(NSData *)body headers:(NSDictionary *)headers error:(NSError **)outError;
@end

@implementation DSHPetTTS

+ (instancetype)shared {
    static DSHPetTTS *inst = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        inst = [[DSHPetTTS alloc] init];
        [inst reloadConfig];
    });
    return inst;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _engine    = DSHPetTTSEngineNative;
        _cluster   = @"volcano_tts";
        _speed     = 1.0;
        _pitch     = 1.0;
        _model     = @"tts-1";
        _voice     = @"alloy";
        // 面板「清空语音缓存」→ 跨进程通知（面板跟 dylib 不是一个进程，够不着单例）
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        (__bridge const void *)(self),
                                        DSHPetTTSOnPurge,
                                        CFSTR("com.vboxai.littlefatlady.tts.purge"),
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
    return self;
}

#pragma mark 配置

- (void)reloadConfig {
    NSString *eng = [DSHPetPrefs stringForKey:@"ttsEngine" fallback:@"native"];
    if ([eng isEqualToString:@"volc"]) {
        self.engine = DSHPetTTSEngineVolc;
    } else if ([eng isEqualToString:@"openai"]) {
        self.engine = DSHPetTTSEngineOpenAI;
    } else {
        self.engine = DSHPetTTSEngineNative;
    }

    self.appID     = [DSHPetPrefs stringForKey:@"ttsAppID" fallback:@""];
    self.cluster   = [DSHPetPrefs stringForKey:@"ttsCluster" fallback:@"volcano_tts"];
    self.voiceType = [DSHPetPrefs stringForKey:@"ttsVoiceType" fallback:@""];
    self.baseURL   = [DSHPetPrefs stringForKey:@"ttsBaseURL" fallback:@""];
    self.model     = [DSHPetPrefs stringForKey:@"ttsModel" fallback:@"tts-1"];
    self.voice     = [DSHPetPrefs stringForKey:@"ttsVoice" fallback:@"alloy"];
    self.speed     = [DSHPetPrefs doubleForKey:@"ttsSpeed" fallback:1.0];
    self.pitch     = [DSHPetPrefs doubleForKey:@"ttsPitch" fallback:1.0];

    if (self.cluster.length == 0) {
        self.cluster = @"volcano_tts";
    }
    if (self.speed < 0.5 || self.speed > 2.0) {
        self.speed = 1.0;
    }
    if (self.pitch < 0.5 || self.pitch > 2.0) {
        self.pitch = 1.0;
    }

    // 面板写入的明文键 → Keychain，读完立刻抹掉（面板只能写、不能读回）。
    NSString *pendingToken = [DSHPetPrefs stringForKey:@"ttsToken" fallback:@""];
    if (pendingToken.length > 0) {
        DSHPetTTSKCSet(kTTSAccountToken, pendingToken);
        DSHPetTTSClearPref(@"ttsToken");
        DSHPetLog(@"tts", @"token-migrated", @"info", nil);
    }
    NSString *pendingKey = [DSHPetPrefs stringForKey:@"ttsAPIKey" fallback:@""];
    if (pendingKey.length > 0) {
        DSHPetTTSKCSet(kTTSAccountAPIKey, pendingKey);
        DSHPetTTSClearPref(@"ttsAPIKey");
        DSHPetLog(@"tts", @"apikey-migrated", @"info", nil);
    }
}

- (BOOL)isReady {
    switch (self.engine) {
        case DSHPetTTSEngineNative:
            return NO;   // native 不走本类，由 DSHPetVoice 直接合成
        case DSHPetTTSEngineVolc:
            return self.appID.length > 0 && DSHPetTTSKCGet(kTTSAccountToken).length > 0;
        case DSHPetTTSEngineOpenAI:
            return self.baseURL.length > 0 && DSHPetTTSKCGet(kTTSAccountAPIKey).length > 0;
    }
    return NO;
}

#pragma mark Keychain 对外

+ (BOOL)hasAccessToken { return DSHPetTTSKCGet(kTTSAccountToken).length > 0; }
+ (BOOL)setAccessToken:(NSString *)token { return DSHPetTTSKCSet(kTTSAccountToken, token); }
+ (BOOL)clearAccessToken { return DSHPetTTSKCDelete(kTTSAccountToken); }
+ (BOOL)hasAPIKey { return DSHPetTTSKCGet(kTTSAccountAPIKey).length > 0; }
+ (BOOL)setAPIKey:(NSString *)key { return DSHPetTTSKCSet(kTTSAccountAPIKey, key); }
+ (BOOL)clearAPIKey { return DSHPetTTSKCDelete(kTTSAccountAPIKey); }

#pragma mark 缓存

- (NSString *)cacheDirectory {
    NSString *base = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/DSHPet/tts"];
    return base;
}

- (void)ensureCacheDirectory {
    NSString *dir = [self cacheDirectory];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:dir]) {
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    }
}

- (void)purgeCache {
    NSString *dir = [self cacheDirectory];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *items = [fm contentsOfDirectoryAtPath:dir error:NULL];
    NSUInteger n = 0;
    for (NSString *name in items) {
        if ([name hasSuffix:@".mp3"] || [name hasSuffix:@".tmp"]) {
            if ([fm removeItemAtPath:[dir stringByAppendingPathComponent:name] error:NULL]) {
                n += 1;
            }
        }
    }
    DSHPetLog(@"tts", @"cache-purged", @"info", @{ @"files": @(n) });
}

#pragma mark 合成

- (NSError *)errorWithCode:(NSInteger)code reason:(NSString *)reason {
    return [NSError errorWithDomain:@"DSHPetTTS"
                               code:code
                           userInfo:@{ NSLocalizedDescriptionKey: reason ?: @"tts-error" }];
}

- (void)finishWith:(void (^)(NSURL *, NSError *))completion file:(NSURL *)file error:(NSError *)error {
    if (!completion) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(file, error);
    });
}

- (void)synthesize:(NSString *)text completion:(void (^)(NSURL *, NSError *))completion {
    NSString *clean = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (clean.length == 0) {
        [self finishWith:completion file:nil error:[self errorWithCode:1 reason:@"empty-text"]];
        return;
    }
    if (![self isReady]) {
        [self finishWith:completion file:nil error:[self errorWithCode:2 reason:@"not-ready"]];
        return;
    }
    if (clean.length > kTTSMaxChars) {
        clean = [clean substringToIndex:kTTSMaxChars];
    }

    [self ensureCacheDirectory];
    NSString *key = [NSString stringWithFormat:@"%ld|%@|%@|%.2f|%.2f|%@",
                     (long)self.engine,
                     self.engine == DSHPetTTSEngineVolc ? (self.voiceType ?: @"") : (self.voice ?: @""),
                     self.engine == DSHPetTTSEngineVolc ? (self.cluster ?: @"") : (self.model ?: @""),
                     self.speed, self.pitch, clean];
    NSString *file = [[self cacheDirectory] stringByAppendingPathComponent:
                      [DSHPetTTSHash(key) stringByAppendingString:@".mp3"]];

    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:file]) {
        NSDictionary *attrs = [fm attributesOfItemAtPath:file error:NULL];
        NSDate *mtime = attrs[NSFileModificationDate];
        NSTimeInterval age = mtime ? -[mtime timeIntervalSinceNow] : 0;
        if (age >= 0 && age < kTTSCacheTTL) {
            DSHPetLog(@"tts", @"cache-hit", @"debug", @{ @"chars": @(clean.length) });
            [self finishWith:completion file:[NSURL fileURLWithPath:file] error:nil];
            return;
        }
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSError *err = nil;
        NSData *audio = [self synthesizeSynchronously:clean error:&err];
        if (audio.length == 0) {
            DSHPetLog(@"tts", @"synth-fail", @"warn", @{
                @"engine": @(self.engine),
                @"reason": err.localizedDescription ?: @"?",
            });
            [self finishWith:completion file:nil
                       error:err ?: [self errorWithCode:9 reason:@"empty-audio"]];
            return;
        }
        NSString *tmp = [file stringByAppendingString:@".tmp"];
        if (![audio writeToFile:tmp atomically:YES]) {
            [self finishWith:completion file:nil error:[self errorWithCode:10 reason:@"write-fail"]];
            return;
        }
        [fm removeItemAtPath:file error:NULL];
        NSError *mvErr = nil;
        if (![fm moveItemAtPath:tmp toPath:file error:&mvErr]) {
            [fm removeItemAtPath:tmp error:NULL];
            [self finishWith:completion file:nil
                       error:mvErr ?: [self errorWithCode:11 reason:@"move-fail"]];
            return;
        }
        DSHPetLog(@"tts", @"synth-ok", @"info", @{
            @"engine": @(self.engine),
            @"chars": @(clean.length),
            @"bytes": @(audio.length),
        });
        [self finishWith:completion file:[NSURL fileURLWithPath:file] error:nil];
    });
}

- (NSData *)synthesizeSynchronously:(NSString *)text error:(NSError **)outError {
    if (self.engine == DSHPetTTSEngineVolc) {
        return [self requestVolcSync:text error:outError];
    }
    if (self.engine == DSHPetTTSEngineOpenAI) {
        return [self requestOpenAISync:text error:outError];
    }
    if (outError) {
        *outError = [self errorWithCode:3 reason:@"native-engine"];
    }
    return nil;
}

#pragma mark 火山 / 豆包

- (NSData *)requestVolcSync:(NSString *)text error:(NSError **)outError {
    NSString *token = DSHPetTTSKCGet(kTTSAccountToken);
    if (token.length == 0) {
        if (outError) { *outError = [self errorWithCode:4 reason:@"no-token"]; }
        return nil;
    }
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"app"] = @{
        @"appid": self.appID ?: @"",
        @"token": token,
        @"cluster": self.cluster ?: @"volcano_tts",
    };
    payload[@"user"] = @{ @"uid": @"dshpet" };
    payload[@"audio"] = @{
        @"voice_type": self.voiceType.length > 0 ? self.voiceType : @"BV700_streaming",
        @"encoding": @"mp3",
        @"speed_ratio": @(self.speed),
        @"pitch_ratio": @(self.pitch),
        @"volume_ratio": @1.0,
    };
    payload[@"request"] = @{
        @"reqid": [[NSUUID UUID] UUIDString],
        @"text": text,
        @"text_type": @"plain",
        @"operation": @"query",
    };
    NSData *body = [NSJSONSerialization dataWithJSONObject:payload options:0 error:NULL];
    if (!body) {
        if (outError) { *outError = [self errorWithCode:5 reason:@"json-fail"]; }
        return nil;
    }
    // 火山这一版的鉴权头是 `Bearer;<token>`（分号不是笔误），值里也带 token。
    NSDictionary *headers = @{
        @"Authorization": [@"Bearer;" stringByAppendingString:token],
        @"Content-Type": @"application/json",
    };
    NSData *resp = [self postJSON:@"https://openspeech.bytedance.com/api/v1/tts"
                             body:body
                          headers:headers
                            error:outError];
    if (resp.length == 0) {
        return nil;
    }
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:resp options:0 error:NULL];
    if (![json isKindOfClass:[NSDictionary class]]) {
        if (outError) { *outError = [self errorWithCode:6 reason:@"resp-not-json"]; }
        return nil;
    }
    NSInteger code = [json[@"code"] respondsToSelector:@selector(integerValue)]
                     ? [json[@"code"] integerValue] : -1;
    NSString *b64 = json[@"data"];
    if (code != 3000 || ![b64 isKindOfClass:[NSString class]] || b64.length == 0) {
        NSString *msg = [json[@"message"] isKindOfClass:[NSString class]] ? json[@"message"] : @"?";
        DSHPetLog(@"tts", @"volc-code", @"warn", @{ @"code": @(code), @"msg": msg });
        if (outError) { *outError = [self errorWithCode:7 reason:[@"volc:" stringByAppendingString:msg]]; }
        return nil;
    }
    NSData *audio = [[NSData alloc] initWithBase64EncodedString:b64 options:0];
    if (audio.length == 0 && outError) {
        *outError = [self errorWithCode:8 reason:@"b64-decoded-empty"];
    }
    return audio;
}

#pragma mark OpenAI 兼容

- (NSData *)requestOpenAISync:(NSString *)text error:(NSError **)outError {
    NSString *key = DSHPetTTSKCGet(kTTSAccountAPIKey);
    if (key.length == 0) {
        if (outError) { *outError = [self errorWithCode:12 reason:@"no-apikey"]; }
        return nil;
    }
    NSString *base = [self.baseURL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    while ([base hasSuffix:@"/"]) {
        base = [base substringToIndex:base.length - 1];
    }
    if (base.length == 0) {
        if (outError) { *outError = [self errorWithCode:13 reason:@"no-baseurl"]; }
        return nil;
    }
    NSDictionary *payload = @{
        @"model": self.model.length > 0 ? self.model : @"tts-1",
        @"input": text,
        @"voice": self.voice.length > 0 ? self.voice : @"alloy",
        @"speed": @(self.speed),
        @"response_format": @"mp3",
    };
    NSData *body = [NSJSONSerialization dataWithJSONObject:payload options:0 error:NULL];
    if (!body) {
        if (outError) { *outError = [self errorWithCode:14 reason:@"json-fail"]; }
        return nil;
    }
    NSDictionary *headers = @{
        @"Authorization": [@"Bearer " stringByAppendingString:key],
        @"Content-Type": @"application/json",
    };
    return [self postJSON:[base stringByAppendingString:@"/audio/speech"]
                     body:body
                  headers:headers
                    error:outError];
}

#pragma mark HTTP

- (NSData *)postJSON:(NSString *)url body:(NSData *)body headers:(NSDictionary *)headers error:(NSError **)outError {
    NSURL *u = [NSURL URLWithString:url];
    if (!u) {
        if (outError) { *outError = [self errorWithCode:20 reason:@"bad-url"]; }
        return nil;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:u];
    req.HTTPMethod = @"POST";
    req.timeoutInterval = kTTSTimeout;
    req.HTTPBody = body;
    for (NSString *k in headers) {
        [req setValue:headers[k] forHTTPHeaderField:k];
    }

    __block NSData *outData = nil;
    __block NSError *outErr = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    NSURLSessionDataTask *task =
    [[NSURLSession sharedSession] dataTaskWithRequest:req
                                    completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSHTTPURLResponse *http = [resp isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)resp : nil;
        if (err) {
            outErr = err;
        } else if (http && (http.statusCode < 200 || http.statusCode >= 300)) {
            NSString *snippet = [[NSString alloc] initWithData:(data ?: [NSData data])
                                                      encoding:NSUTF8StringEncoding];
            if (snippet.length > 120) {
                snippet = [snippet substringToIndex:120];
            }
            outErr = [NSError errorWithDomain:@"DSHPetTTS"
                                         code:http.statusCode
                                     userInfo:@{ NSLocalizedDescriptionKey:
                                                     [NSString stringWithFormat:@"http-%ld %@",
                                                      (long)http.statusCode, snippet ?: @""] }];
        } else {
            outData = data;
        }
        dispatch_semaphore_signal(sem);
    }];
    [task resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)((kTTSTimeout + 5.0) * NSEC_PER_SEC)));

    if (!outData && !outErr) {
        outErr = [self errorWithCode:21 reason:@"timeout"];
    }
    if (outErr && outError) {
        *outError = outErr;
    }
    return outData;
}

@end
