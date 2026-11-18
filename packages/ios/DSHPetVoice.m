#import "DSHPetVoice.h"
#import "DSHPetState.h"
#import "DSHPetTTS.h"
#import "DSHPetBoot.h"
#import <AVFoundation/AVFoundation.h>
#import <math.h>

NSString *const DSHPetVoiceDidStartNotification = @"DSHPetVoiceDidStart";
NSString *const DSHPetVoiceDidFinishNotification = @"DSHPetVoiceDidFinish";


// 分段阈值：一次念超过 40 字会喘不上气，按标点切开分段播
static const NSUInteger kChunkChars = 40;// 预估超过这个时长才 duck 音乐（短句直接叠在歌上，不打断用户）
static const NSTimeInterval kDuckThreshold = 3.0;
// 口型刷新间隔（10Hz 够用，再快人眼看不出）
static const NSTimeInterval kMouthTick = 0.10;

#pragma mark - 数字转中文（只需要覆盖价格与百分比）

static NSString *DSHPetCNInteger(NSInteger n) {
    static NSString *const d[] = {@"零", @"一", @"二", @"三", @"四", @"五", @"六", @"七", @"八", @"九"};
    if (n < 0) {
        return @"负";
    }
    if (n < 10) {
        return d[n];
    }
    if (n < 20) {
        return n == 10 ? @"十" : [@"十" stringByAppendingString:d[n - 10]];
    }
    if (n < 100) {
        NSInteger t = n / 10, o = n % 10;
        if (o == 0) {
            return [NSString stringWithFormat:@"%@十", d[t]];
        }
        return [NSString stringWithFormat:@"%@十%@", d[t], d[o]];
    }
    if (n < 1000) {
        NSInteger h = n / 100, rest = n % 100;
        if (rest == 0) {
            return [NSString stringWithFormat:@"%@百", d[h]];
        }
        if (rest < 10) {
            return [NSString stringWithFormat:@"%@百零%@", d[h], d[rest]];
        }
        return [NSString stringWithFormat:@"%@百%@", d[h], DSHPetCNInteger(rest)];
    }
    if (n < 10000) {
        NSInteger k = n / 1000, rest = n % 1000;
        if (rest == 0) {
            return [NSString stringWithFormat:@"%@千", d[k]];
        }
        if (rest < 100) {
            return [NSString stringWithFormat:@"%@千零%@", d[k], DSHPetCNInteger(rest)];
        }
        return [NSString stringWithFormat:@"%@千%@", d[k], DSHPetCNInteger(rest)];
    }
    // 上万的价格在桌宠台词里不存在，保底走原数字，别硬编
    return [NSString stringWithFormat:@"%ld", (long)n];
}

// 小数部分逐位念：0.67 -> 六七
static NSString *DSHPetCNDigits(NSString *digits) {
    static NSString *const d[] = {@"零", @"一", @"二", @"三", @"四", @"五", @"六", @"七", @"八", @"九"};
    NSMutableString *out = [NSMutableString string];
    for (NSUInteger i = 0; i < digits.length; i++) {
        unichar c = [digits characterAtIndex:i];
        if (c >= '0' && c <= '9') {
            [out appendString:d[c - '0']];
        }
    }
    return out;
}

static NSString *DSHPetCNMoney(NSString *intPart, NSString *decPart) {
    NSInteger yuan = intPart.integerValue;
    NSMutableString *out = [NSMutableString stringWithFormat:@"%@块", DSHPetCNInteger(yuan)];
    if (decPart.length == 0) {
        return out;
    }
    unichar jiao = [decPart characterAtIndex:0];
    if (jiao != '0') {
        [out appendFormat:@"%@毛", DSHPetCNDigits([decPart substringWithRange:NSMakeRange(0, 1)])];
    }
    if (decPart.length > 1) {
        unichar fen = [decPart characterAtIndex:1];
        if (fen != '0') {
            [out appendFormat:@"%@", DSHPetCNDigits([decPart substringWithRange:NSMakeRange(1, 1)])];
        }
    }
    return out;
}

#pragma mark -

@interface DSHPetVoice () <AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate>
@property (nonatomic, strong) AVSpeechSynthesizer *synth;
@property (nonatomic, readwrite) BOOL speaking;
@property (nonatomic, readwrite) NSInteger speakCount;
@property (nonatomic, assign) NSInteger liveUtterances;   // 还没念完的段数
@property (nonatomic, assign) BOOL ducked;
@property (nonatomic, strong, nullable) NSTimer *duckRestoreTimer;
@property (nonatomic, strong, nullable) NSTimer *mouthTimer;
@property (nonatomic, assign) NSInteger mouthPhase;
// 远端 TTS：一个播放器 + 一个序号（防旧请求回来把新话掐掉）
@property (nonatomic, strong, nullable) AVAudioPlayer *remotePlayer;
@property (nonatomic, assign) NSInteger remoteSeq;

- (void)handleInterruption:(NSNotification *)note;
- (void)applyCategoryDucked:(BOOL)ducked;
- (void)beginDuck;
- (void)endDuckSoon;
- (void)startMouth;
- (void)stopMouth;
- (NSArray<NSString *> *)chunksOf:(NSString *)text;
- (float)rateForTone:(DSHPetTone)tone;
- (float)pitchForTone:(DSHPetTone)tone;
- (float)volumeForTone:(DSHPetTone)tone base:(float)base;
- (void)speakNative:(NSString *)text path:(nullable NSString *)path volume:(float)volume;
- (void)speakRemote:(NSString *)text path:(nullable NSString *)path volume:(float)volume;
- (void)finishRemoteWithNotification:(BOOL)notify;
@end

@implementation DSHPetVoice

// 面板「试听一句」回调：走的是同一条 speak: 通路，远端引擎通不通一耳朵就听出来。
static void DSHPetVoiceOnProbe(CFNotificationCenterRef center,
                               void *observer,
                               CFNotificationName name,
                               const void *object,
                               CFDictionaryRef info) {
    (void)center; (void)name; (void)object; (void)info;
    DSHPetVoice *me = (__bridge DSHPetVoice *)observer;
    [me speak:@"爹爹，我是小肥娘，库…这句是试听。" path:@"probe" volume:1.0f];
}

+ (instancetype)shared {
    static DSHPetVoice *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[DSHPetVoice alloc] init];
    });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }
    _enabled = YES;
    _duckWhenLong = YES;
    _respectSilentSwitch = YES;
    _baseRate = 1.0f;
    _basePitch = 1.0f;
    _baseVolume = 1.0f;
    _speakCount = 0;
    _liveUtterances = 0;
    _synth = [[AVSpeechSynthesizer alloc] init];
    _synth.delegate = self;

    // 来电 / Siri / 闹钟：立刻静音，且**不自动续播**（插进通话里比不说话更糟）
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleInterruption:)
                                                 name:AVAudioSessionInterruptionNotification
                                               object:nil];

    // 面板「试听一句」：面板在另一个进程里，用 Darwin 通知喊我说话。
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    (__bridge const void *)(self),
                                    DSHPetVoiceOnProbe,
                                    CFSTR("com.vboxai.littlefatlady.tts.test"),
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_mouthTimer invalidate];
    [_duckRestoreTimer invalidate];
}

#pragma mark - 会话

- (void)configureAudioSession {
    @try {
        AVAudioSession *s = [AVAudioSession sharedInstance];
        AVAudioSessionCategory cat = self.respectSilentSwitch ? AVAudioSessionCategoryAmbient
                                                              : AVAudioSessionCategoryPlayback;
        NSError *err = nil;
        // MixWithOthers：绝不掐用户的歌。这是桌宠和音乐 App 共存的唯一正确姿势。
        if (![s setCategory:cat withOptions:AVAudioSessionCategoryOptionMixWithOthers error:&err]) {
            DSHPetLog(@"voice", @"session-category-fail", @"warn", @{@"err": err.localizedDescription ?: @"?"});
        }
        err = nil;
        if (![s setActive:YES withOptions:0 error:&err]) {
            DSHPetLog(@"voice", @"session-active-fail", @"warn", @{@"err": err.localizedDescription ?: @"?"});
        }
    } @catch (NSException *e) {
        // SpringBoard 里这个异常不能冒泡，冒泡就是安全模式
        DSHPetLog(@"voice", @"session-exception", @"error", @{@"name": e.name ?: @"?"});
    }
}

- (void)applyCategoryDucked:(BOOL)ducked {
    @try {
        AVAudioSession *s = [AVAudioSession sharedInstance];
        NSError *err = nil;
        if (ducked) {
            // 只有长句才 duck：把别人的音量压到 0.3，自己说完再还回去
            [s setCategory:AVAudioSessionCategoryPlayback
               withOptions:AVAudioSessionCategoryOptionDuckOthers
                     error:&err];
            [s setActive:YES withOptions:0 error:&err];
        } else {
            AVAudioSessionCategory cat = self.respectSilentSwitch ? AVAudioSessionCategoryAmbient
                                                                  : AVAudioSessionCategoryPlayback;
            [s setCategory:cat withOptions:AVAudioSessionCategoryOptionMixWithOthers error:&err];
        }
        self.ducked = ducked;
    } @catch (NSException *e) {
        DSHPetLog(@"voice", @"duck-exception", @"warn", @{@"name": e.name ?: @"?"});
    }
}

- (void)beginDuck {
    [self.duckRestoreTimer invalidate];
    self.duckRestoreTimer = nil;
    if (self.ducked) {
        return;
    }
    [self applyCategoryDucked:YES];
}

- (void)endDuckSoon {
    [self.duckRestoreTimer invalidate];
    if (!self.ducked) {
        return;
    }
    // 0.6s 后再恢复，避免两句之间来回抖动
    __weak typeof(self) weakSelf = self;
    self.duckRestoreTimer = [NSTimer scheduledTimerWithTimeInterval:0.6 repeats:NO block:^(NSTimer *t) {
        [weakSelf applyCategoryDucked:NO];
    }];
}

- (void)handleInterruption:(NSNotification *)note {
    NSNumber *type = note.userInfo[AVAudioSessionInterruptionTypeKey];
    if (type.integerValue == AVAudioSessionInterruptionTypeBegan) {
        [self stopSpeakingNow];
        DSHPetLog(@"voice", @"interrupted", @"info", nil);
    } else {
        // 只重激活会话，不重播
        [self configureAudioSession];
    }
}

#pragma mark - 对外主入口

- (void)speak:(NSString *)text path:(nullable NSString *)path {
    [self speak:text path:path volume:1.0f];
}

- (void)speak:(NSString *)text path:(nullable NSString *)path volume:(float)volume {
    if (!self.enabled) {
        return;
    }
    // 远端 TTS 优先：配置齐全才走，任何一步失败都静默回落系统合成（桌宠不能因为网不好就哑掉）。
    DSHPetTTS *tts = [DSHPetTTS shared];
    [tts reloadConfig];
    if ([tts isReady]) {
        [self speakRemote:text path:path volume:volume];
        return;
    }
    [self speakNative:text path:path volume:volume];
}

- (void)speakRemote:(NSString *)text path:(nullable NSString *)path volume:(float)volume {
    NSString *clean = [self preprocess:text ?: @""];
    if (clean.length == 0) {
        return;
    }
    [self stopSpeakingNow];
    [self configureAudioSession];

    DSHPetTone tone = [DSHPetState shared].tone;
    float vol = [self volumeForTone:tone base:volume];
    if (vol <= 0.01f) {
        return;
    }

    self.remoteSeq += 1;
    NSInteger seq = self.remoteSeq;
    self.speaking = YES;
    self.speakCount += 1;
    [self startMouth];
    [[NSNotificationCenter defaultCenter] postNotificationName:DSHPetVoiceDidStartNotification
                                                       object:self
                                                     userInfo:@{@"path": path ?: @"", @"chars": @(clean.length)}];

    __weak DSHPetVoice *weakSelf = self;
    [[DSHPetTTS shared] synthesize:clean completion:^(NSURL *file, NSError *err) {
        DSHPetVoice *me = weakSelf;
        if (!me) {
            return;
        }
        if (seq != me.remoteSeq) {
            return;   // 已经被新的一句顶掉了，别把新话掐了
        }
        if (!file || err) {
            DSHPetLog(@"voice", @"remote-fallback", @"warn", @{
                @"reason": err.localizedDescription ?: @"?",
            });
            [me finishRemoteWithNotification:NO];
            [me speakNative:text path:path volume:volume];
            return;
        }
        NSError *playErr = nil;
        AVAudioPlayer *p = [[AVAudioPlayer alloc] initWithContentsOfURL:file error:&playErr];
        if (!p) {
            DSHPetLog(@"voice", @"remote-play-fail", @"warn", @{
                @"reason": playErr.localizedDescription ?: @"?",
            });
            [me finishRemoteWithNotification:NO];
            [me speakNative:text path:path volume:volume];
            return;
        }
        p.delegate = me;
        p.volume = MAX(0.0f, MIN(1.0f, vol));
        p.enableRate = YES;
        p.rate = MAX(0.5f, MIN(2.0f, [me rateForTone:tone]));
        me.remotePlayer = p;
        [p play];
        DSHPetLog(@"voice", @"speak-remote", @"debug", @{
            @"chars": @(clean.length),
            @"path": path ?: @"-",
        });
    }];
}

- (void)finishRemoteWithNotification:(BOOL)notify {
    [self.remotePlayer stop];
    self.remotePlayer = nil;
    self.speaking = NO;
    [self stopMouth];
    [self endDuckSoon];
    if (notify) {
        [[NSNotificationCenter defaultCenter] postNotificationName:DSHPetVoiceDidFinishNotification
                                                           object:self
                                                         userInfo:@{}];
    }
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    if (player != self.remotePlayer) {
        return;
    }
    [self finishRemoteWithNotification:YES];
}

- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError *)error {
    DSHPetLog(@"voice", @"remote-decode-error", @"warn", @{
        @"reason": error.localizedDescription ?: @"?",
    });
    if (player != self.remotePlayer) {
        return;
    }
    [self finishRemoteWithNotification:YES];
}

- (void)speakNative:(NSString *)text path:(nullable NSString *)path volume:(float)volume {
    if (!self.enabled) {
        return;
    }
    NSString *clean = [self preprocess:text ?: @""];
    if (clean.length == 0) {
        return;
    }

    // 新语音打断旧语音（单通道）。桌宠不该像导航一样非把上一句说完。
    [self stopSpeakingNow];
    [self configureAudioSession];

    DSHPetTone tone = [DSHPetState shared].tone;
    float rate = [self rateForTone:tone];
    float pitch = [self pitchForTone:tone];
    float vol = [self volumeForTone:tone base:volume];
    if (vol <= 0.01f) {
        return;
    }

    NSArray<NSString *> *chunks = [self chunksOf:clean];
    NSTimeInterval estimate = 0.20 * clean.length / MAX(0.5f, rate);
    if (self.duckWhenLong && estimate > kDuckThreshold) {
        [self beginDuck];
    }

    self.liveUtterances = (NSInteger)chunks.count;
    self.speaking = YES;
    self.speakCount += 1;
    [self startMouth];
    // 渲染层靠这条把宠物切成 TALKING（说话手势 + 待机暂停）
    [[NSNotificationCenter defaultCenter] postNotificationName:DSHPetVoiceDidStartNotification
                                                       object:self
                                                     userInfo:@{@"path": path ?: @"", @"chars": @(clean.length)}];

    for (NSString *piece in chunks) {
        AVSpeechUtterance *u = [AVSpeechUtterance speechUtteranceWithString:piece];
        u.rate = (float)AVSpeechUtteranceDefaultSpeechRate * rate;
        u.pitchMultiplier = MAX(0.5f, MIN(2.0f, pitch));
        u.volume = MAX(0.0f, MIN(1.0f, vol));
        NSString *ident = self.voiceIdentifier;
        if (ident.length > 0) {
            AVSpeechSynthesisVoice *v = [AVSpeechSynthesisVoice voiceWithIdentifier:ident];
            if (v) {
                u.voice = v;
            }
        } else {
            AVSpeechSynthesisVoice *zh = [AVSpeechSynthesisVoice voiceWithLanguage:@"zh-CN"];
            if (zh) {
                u.voice = zh;
            }
        }
        @try {
            [self.synth speakUtterance:u];
        } @catch (NSException *e) {
            DSHPetLog(@"voice", @"speak-exception", @"error", @{@"name": e.name ?: @"?"});
            self.liveUtterances = 0;
            self.speaking = NO;
            [self stopMouth];
        }
    }

    DSHPetLog(@"voice", @"speak", @"debug", @{
        @"path": path ?: @"-",
        @"chars": @(clean.length),
        @"chunks": @(chunks.count),
        @"rate": @(rate),
        @"pitch": @(pitch),
        @"vol": @(vol),
        @"duck": @(self.ducked),
    });
}

- (void)stopSpeakingNow {
    // 远端播放器也要停，否则系统合成停了、mp3 还在念
    self.remoteSeq += 1;
    @try {
        if (self.remotePlayer) {
            [self.remotePlayer stop];
            self.remotePlayer = nil;
        }
    } @catch (NSException *e) {
        DSHPetLog(@"voice", @"stop-remote-exception", @"warn", @{@"name": e.name ?: @"?"});
    }
    @try {
        if (self.synth.isSpeaking || self.synth.isPaused) {
            [self.synth stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
        }
    } @catch (NSException *e) {
        DSHPetLog(@"voice", @"stop-exception", @"warn", @{@"name": e.name ?: @"?"});
    }
    self.liveUtterances = 0;
    self.speaking = NO;
    [self stopMouth];
    [self endDuckSoon];
}

- (void)stopSpeakingIfIdle {
    if (!self.speaking) {
        [self stopMouth];
        [self endDuckSoon];
    }
}

- (float)sfxScale {
    // 说话时音效压到 0.4，否则音效会盖住台词
    return self.speaking ? 0.4f : 1.0f;
}

#pragma mark - 状态 → 语速/音调/音量（§13.6）

- (float)rateForTone:(DSHPetTone)tone {
    float m = 1.0f;
    DSHPetState *st = [DSHPetState shared];
    if (st.energy < 25) {
        m *= 0.85f;
    }
    if (st.phase == DSHPetPhaseLateNight) {
        m *= 0.80f;
    }
    switch (tone) {
        case DSHPetToneGenki: m *= 1.10f; break;
        case DSHPetToneLazy: m *= 0.90f; break;
        case DSHPetToneGrumpy: m *= 1.00f; break;
        case DSHPetToneDown: m *= 0.90f; break;
    }
    float rate = self.baseRate * m;
    return MAX(0.5f, MIN(1.4f, rate));
}

- (float)pitchForTone:(DSHPetTone)tone {
    float semi = 0.0f;
    DSHPetState *st = [DSHPetState shared];
    if (st.energy < 25) {
        semi -= 2.0f;
    }
    if (st.phase == DSHPetPhaseLateNight) {
        semi -= 3.0f;
    }
    if (st.mood > 40) {
        semi += 1.0f;
    }
    switch (tone) {
        case DSHPetToneGenki: semi += 1.0f; break;
        case DSHPetToneGrumpy: semi -= 1.0f; break;
        case DSHPetToneDown: semi -= 1.0f; break;
        case DSHPetToneLazy: semi -= 1.0f; break;
    }
    // 半音 → 倍率大约 6%/半音，再乘面板基值
    return self.basePitch * powf(1.06f, semi);
}

- (float)volumeForTone:(DSHPetTone)tone base:(float)base {
    float v = self.baseVolume * base;
    DSHPetState *st = [DSHPetState shared];
    if (st.energy < 25) {
        v *= 0.80f;
    }
    if (st.phase == DSHPetPhaseLateNight) {
        v *= 0.70f;
    }
    if (st.mood < -40) {
        v *= 0.90f;
    }
    return MAX(0.0f, MIN(1.0f, v));
}

#pragma mark - 文本预处理（§13.7）

- (NSString *)preprocess:(NSString *)text {
    NSMutableString *s = [text mutableCopy];

    // 1) 括号里的舞台提示不该念出来（语气靠 style 表达，不靠朗读）
    for (NSString *pair in @[@"（）", @"【】", @"()", @"[]"]) {
        NSString *open = [pair substringToIndex:1];
        NSString *close = [pair substringFromIndex:1];
        NSRange o = [s rangeOfString:open];
        while (o.location != NSNotFound) {
            NSRange rest = NSMakeRange(o.location + o.length, s.length - (o.location + o.length));
            NSRange c = [s rangeOfString:close options:0 range:rest];
            if (c.location == NSNotFound) {
                break;
            }
            NSRange whole = NSMakeRange(o.location, c.location + c.length - o.location);
            [s replaceCharactersInRange:whole withString:@""];
            o = [s rangeOfString:open];
        }
    }

    // 2) 金额：¥3.33 -> 三块三毛三；¥4 -> 四块
    NSRegularExpression *money = [NSRegularExpression regularExpressionWithPattern:@"[¥￥]\\s*(\\d+)(?:\\.(\\d{1,2}))?"
                                                                          options:0
                                                                            error:nil];
    NSArray<NSTextCheckingResult *> *ms = [money matchesInString:s options:0 range:NSMakeRange(0, s.length)];
    for (NSTextCheckingResult *r in [ms reverseObjectEnumerator]) {
        NSString *intPart = [s substringWithRange:[r rangeAtIndex:1]];
        NSString *decPart = @"";
        if ([r rangeAtIndex:2].location != NSNotFound) {
            decPart = [s substringWithRange:[r rangeAtIndex:2]];
        }
        [s replaceCharactersInRange:r.range withString:DSHPetCNMoney(intPart, decPart)];
    }

    // 3) 百分比：1.83% -> 百分之一点八三
    NSRegularExpression *pct = [NSRegularExpression regularExpressionWithPattern:@"(\\d+)(?:\\.(\\d+))?\\s*%"
                                                                        options:0
                                                                          error:nil];
    NSArray<NSTextCheckingResult *> *ps = [pct matchesInString:s options:0 range:NSMakeRange(0, s.length)];
    for (NSTextCheckingResult *r in [ps reverseObjectEnumerator]) {
        NSString *intPart = [s substringWithRange:[r rangeAtIndex:1]];
        NSString *out = [@"百分之" stringByAppendingString:DSHPetCNInteger(intPart.integerValue)];
        if ([r rangeAtIndex:2].location != NSNotFound) {
            NSString *dec = [s substringWithRange:[r rangeAtIndex:2]];
            out = [out stringByAppendingFormat:@"点%@", DSHPetCNDigits(dec)];
        }
        [s replaceCharactersInRange:r.range withString:out];
    }

    // 4) 长数字串（股票代码、单号）逐位念，别让它读成「五十一万三千三百一十」
    NSRegularExpression *longNum = [NSRegularExpression regularExpressionWithPattern:@"\\d{6,}"
                                                                            options:0
                                                                              error:nil];
    NSArray<NSTextCheckingResult *> *ns = [longNum matchesInString:s options:0 range:NSMakeRange(0, s.length)];
    for (NSTextCheckingResult *r in [ns reverseObjectEnumerator]) {
        NSString *raw = [s substringWithRange:r.range];
        [s replaceCharactersInRange:r.range withString:DSHPetCNDigits(raw)];
    }

    // 5) 省略号变停顿：念「点点点」很蠢
    [s replaceOccurrencesOfString:@"……" withString:@"，" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"…" withString:@"，" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"--" withString:@"，" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"——" withString:@"，" options:0 range:NSMakeRange(0, s.length)];

    // 6) 空白归一
    while ([s rangeOfString:@"  "].location != NSNotFound) {
        [s replaceOccurrencesOfString:@"  " withString:@" " options:0 range:NSMakeRange(0, s.length)];
    }
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSArray<NSString *> *)chunksOf:(NSString *)text {
    if (text.length <= kChunkChars) {
        return @[text];
    }
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    NSMutableString *cur = [NSMutableString string];
    NSCharacterSet *breaks = [NSCharacterSet characterSetWithCharactersInString:@"。！？!?；;，,\n"];
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        [cur appendFormat:@"%C", c];
        BOOL isBreak = [breaks characterIsMember:c];
        if ((isBreak && cur.length >= 12) || cur.length >= kChunkChars) {
            NSString *piece = [cur stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (piece.length > 0) {
                [out addObject:piece];
            }
            [cur setString:@""];
        }
    }
    if (cur.length > 0) {
        [out addObject:cur];
    }
    return out.count > 0 ? out : @[text];
}

#pragma mark - 口型

- (void)startMouth {
    [self.mouthTimer invalidate];
    if (!self.mouthFrameHandler) {
        return;
    }
    self.mouthPhase = 0;
    __weak typeof(self) weakSelf = self;
    self.mouthTimer = [NSTimer scheduledTimerWithTimeInterval:kMouthTick repeats:YES block:^(NSTimer *t) {
        typeof(self) self_ = weakSelf;
        if (!self_ || !self_.speaking) {
            [t invalidate];
            return;
        }
        // 0 闭 / 1 半开 / 2 全开，走一个不规则的开口节奏，别像机器
        static const NSInteger pattern[] = {2, 1, 2, 0, 1, 2, 1, 2, 0, 1};
        NSInteger idx = pattern[self_.mouthPhase % 10];
        self_.mouthPhase += 1;
        if (self_.mouthFrameHandler) {
            self_.mouthFrameHandler(idx);
        }
    }];
}

- (void)stopMouth {
    [self.mouthTimer invalidate];
    self.mouthTimer = nil;
    self.mouthPhase = 0;
    if (self.mouthFrameHandler) {
        self.mouthFrameHandler(0);
    }
}

#pragma mark - AVSpeechSynthesizerDelegate

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synth didStartSpeechUtterance:(AVSpeechUtterance *)utterance {
    self.speaking = YES;
    if (!self.mouthTimer) {
        [self startMouth];
    }
}

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synth didFinishSpeechUtterance:(AVSpeechUtterance *)utterance {
    if (self.liveUtterances > 0) {
        self.liveUtterances -= 1;
    }
    if (self.liveUtterances <= 0) {
        self.speaking = NO;
        [self stopMouth];
        [self endDuckSoon];
        [[NSNotificationCenter defaultCenter] postNotificationName:DSHPetVoiceDidFinishNotification
                                                            object:self
                                                          userInfo:@{@"reason": @"finish"}];
    }
}

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synth didCancelSpeechUtterance:(AVSpeechUtterance *)utterance {
    // 被打断是常态（新语音覆盖旧语音），不算错误，只清计数
    if (self.liveUtterances > 0) {
        self.liveUtterances -= 1;
    }
    if (self.liveUtterances <= 0) {
        self.speaking = NO;
        [self stopMouth];
        [[NSNotificationCenter defaultCenter] postNotificationName:DSHPetVoiceDidFinishNotification
                                                            object:self
                                                          userInfo:@{@"reason": @"cancel"}];
    }
}

// 拿到「正在念哪几个字」时可以把嘴张到最大，比纯定时器更像在说话
- (void)speechSynthesizer:(AVSpeechSynthesizer *)synth
 willSpeakRangeOfSpeechString:(NSRange)characterRange
                utterance:(AVSpeechUtterance *)utterance {
    if (self.mouthFrameHandler) {
        self.mouthFrameHandler(2);
    }
}

@end
