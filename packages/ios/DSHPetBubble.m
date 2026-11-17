#import "DSHPetBubble.h"
#import "DSHPetBoot.h"

static const CGFloat kBubbleMaxWidthRatio = 0.74;
static const CGFloat kBubblePadH = 12.0;
static const CGFloat kBubblePadV = 9.0;
static const CGFloat kBubbleGap = 8.0;

@interface DSHPetBubble ()
@property (nonatomic, weak) UIView *host;
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) NSTimer *hideTimer;
@property (nonatomic, assign) CGRect petFrame;
@property (nonatomic, assign) UIEdgeInsets safeInsets;
@property (nonatomic, copy) NSString *fullText;   // S6b：展开用全文
@property (nonatomic, assign) BOOL expanded;      // 已展开（不再自动收）
@property (nonatomic, assign) BOOL expandable;    // 三行装不下 → 可点击展开
@end

// S6b 文本清洗：宿主那边可能是多行 markdown/日志，
// 换行合并成空格、连续空白压成一个、去掉零宽字符；超长截断到 240 字，
// 免得一条长日志把气泡撑到半屏、也免得 UILabel 排版卡主线程。
static NSString *DSHPetCleanBubbleText(NSString *raw) {
    if (![raw isKindOfClass:[NSString class]] || !raw.length) return @"";
    NSMutableString *s = [raw mutableCopy];
    [s replaceOccurrencesOfString:@"\r\n" withString:@"\n" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"\u200b" withString:@"" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"\n" withString:@" " options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"\t" withString:@" " options:0 range:NSMakeRange(0, s.length)];
    while ([s rangeOfString:@"  "].location != NSNotFound) {
        [s replaceOccurrencesOfString:@"  " withString:@" " options:0 range:NSMakeRange(0, s.length)];
    }
    NSString *t = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (t.length > 240) t = [[t substringToIndex:240] stringByAppendingString:@"…"];
    return t;
}

@implementation DSHPetBubble

- (instancetype)initWithHostView:(UIView *)host {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _host = host;
    self.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.88];
    self.layer.cornerRadius = 14.0;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.borderWidth = 1.0 / [UIScreen mainScreen].scale;
    self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.14].CGColor;
    self.clipsToBounds = YES;
    self.userInteractionEnabled = YES;
    self.alpha = 0.0;
    self.hidden = YES;
    self.isAccessibilityElement = NO;
    self.accessibilityLabel = @"小肥娘气泡";

    _label = [[UILabel alloc] initWithFrame:CGRectZero];
    _label.numberOfLines = 3;
    _label.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightMedium];
    _label.textColor = [UIColor whiteColor];
    _label.textAlignment = NSTextAlignmentNatural;
    _label.lineBreakMode = NSLineBreakByTruncatingTail;
    [self addSubview:_label];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onTap)];
    [self addGestureRecognizer:tap];

    [host addSubview:self];
    return self;
}

- (BOOL)visible { return !self.hidden && self.alpha > 0.01; }

- (void)showText:(NSString *)text duration:(NSTimeInterval)duration {
    NSString *t = DSHPetCleanBubbleText(text);
    if (!t.length) { [self dismissAnimated:YES]; return; }

    self.fullText = t;
    self.expanded = NO;
    self.label.numberOfLines = 3;
    self.label.lineBreakMode = NSLineBreakByTruncatingTail;
    self.label.text = t;
    self.accessibilityLabel = t;
    // 三行装不下才允许点开全文；短句点一下就收，符合直觉
    CGFloat maxW = MIN(floor(CGRectGetWidth(self.host.bounds) * kBubbleMaxWidthRatio), 330.0);
    CGFloat textW = MAX(maxW - kBubblePadH * 2.0, 40.0);
    CGRect full = [t boundingRectWithSize:CGSizeMake(textW, 1e9)
                                  options:NSStringDrawingUsesLineFragmentOrigin
                               attributes:@{ NSFontAttributeName: self.label.font }
                                  context:nil];
    self.expandable = (full.size.height > self.label.font.lineHeight * 3.0 + 0.5);
    [self layoutBubble];

    [self.hideTimer invalidate];
    self.hideTimer = nil;
    self.hidden = NO;
    [UIView animateWithDuration:0.18 animations:^{
        self.alpha = 1.0;
    }];
    if (duration > 0.0) {
        __weak DSHPetBubble *weakSelf = self;
        self.hideTimer = [NSTimer scheduledTimerWithTimeInterval:duration repeats:NO block:^(NSTimer *timer) {
            [weakSelf dismissAnimated:YES];
        }];
    }
    DSHPetLog(@"bubble", @"show", @"debug", @{ @"len": @(t.length), @"sec": @(duration) });
}

- (void)dismissAnimated:(BOOL)animated {
    [self.hideTimer invalidate];
    self.hideTimer = nil;
    if (self.hidden) return;
    if (!animated) { self.alpha = 0.0; self.hidden = YES; return; }
    [UIView animateWithDuration:0.16 animations:^{
        self.alpha = 0.0;
    } completion:^(BOOL finished) {
        self.hidden = YES;
    }];
}

- (void)onTap {
    // S6b：一是短句直接收；二是长句第一次点开全文并停掉自动收起计时，第二次点才收。
    if (self.expandable && !self.expanded) {
        self.expanded = YES;
        self.label.numberOfLines = 0;
        self.label.lineBreakMode = NSLineBreakByWordWrapping;
        [self.hideTimer invalidate];
        self.hideTimer = nil;
        [self layoutBubble];
        DSHPetLog(@"bubble", @"expand", @"debug", @{ @"len": @(self.fullText.length) });
        return;
    }
    [self dismissAnimated:YES];
}

- (void)anchorAtPetFrame:(CGRect)petFrame hostBounds:(CGRect)hostBounds safeInsets:(UIEdgeInsets)insets {
    self.petFrame = petFrame;
    self.safeInsets = insets;
    [self layoutBubble];
}

- (void)layoutBubble {
    UIView *host = self.host;
    if (!host) return;
    CGRect hostBounds = host.bounds;
    if (CGRectGetWidth(hostBounds) < 1.0) return;

    CGFloat maxW = MIN(floor(CGRectGetWidth(hostBounds) * kBubbleMaxWidthRatio), 330.0);
    CGSize fit = [self.label sizeThatFits:CGSizeMake(maxW - kBubblePadH * 2.0, 1e9)];
    CGFloat textW = ceil(MIN(fit.width, maxW - kBubblePadH * 2.0));
    CGFloat textH = ceil(fit.height);
    // 展开态再长也不许吃掉半屏以上：超了就夹到 55% 屏高并尾部省略，
    // 否则一条超长日志会把气泡顶到状态栏、把宠物整个人盖住。
    CGFloat maxTextH = MAX(floor(CGRectGetHeight(hostBounds) * 0.55) - kBubblePadV * 2.0, 60.0);
    if (textH > maxTextH) {
        textH = maxTextH;
        self.label.lineBreakMode = NSLineBreakByTruncatingTail;
    }
    CGFloat w = textW + kBubblePadH * 2.0;
    CGFloat h = textH + kBubblePadV * 2.0;

    CGRect pet = self.petFrame;
    CGFloat cx = CGRectGetMidX(pet);
    if (CGRectGetWidth(pet) < 1.0) cx = CGRectGetMidX(hostBounds);

    // 默认摆头顶；头顶放不下就摆到下方。
    CGFloat top = CGRectGetMinY(pet) - kBubbleGap - h;
    CGFloat minTop = self.safeInsets.top + 6.0;
    if (top < minTop) {
        top = CGRectGetMaxY(pet) + kBubbleGap;
        if (top + h > CGRectGetMaxY(hostBounds) - self.safeInsets.bottom - 6.0) {
            top = MAX(minTop, CGRectGetMinY(pet) - kBubbleGap - h);
        }
    }

    CGFloat left = cx - w / 2.0;
    CGFloat minLeft = 8.0 + self.safeInsets.left;
    CGFloat maxLeft = CGRectGetWidth(hostBounds) - 8.0 - self.safeInsets.right - w;
    if (maxLeft < minLeft) { left = (CGRectGetWidth(hostBounds) - w) / 2.0; }
    else { left = MIN(MAX(left, minLeft), maxLeft); }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.frame = CGRectMake(round(left), round(top), w, h);
    self.label.frame = CGRectMake(kBubblePadH, kBubblePadV, textW, textH);
    [CATransaction commit];
}

@end
