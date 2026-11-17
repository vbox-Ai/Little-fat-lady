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
@end

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
    NSString *t = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!t.length) { [self dismissAnimated:YES]; return; }

    self.label.text = t;
    self.accessibilityLabel = t;
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
