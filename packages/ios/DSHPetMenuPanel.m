#import "DSHPetMenuPanel.h"
#import "DSHPetBoot.h"

// 一行一个按钮，最后一行固定是「取消」（红色），跟系统 actionSheet 的读法一致。
static const CGFloat kPadH = 6.0;
static const CGFloat kPadV = 6.0;
static const CGFloat kRowH = 44.0;
static const CGFloat kTitleH = 34.0;
static const CGFloat kMinW = 200.0;

@interface DSHPetMenuPanel ()
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) NSArray<UIButton *> *buttons;
@property (nonatomic, copy) DSHPetMenuHandler handler;
@property (nonatomic, copy) NSArray<NSString *> *titles;
@end

@implementation DSHPetMenuPanel

- (instancetype)initWithTitle:(NSString *)title
                       titles:(NSArray<NSString *> *)titles
                      handler:(DSHPetMenuHandler)handler {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;

    _titles = [titles copy] ?: @[];
    _handler = [handler copy];

    self.backgroundColor = [UIColor colorWithWhite:0.11 alpha:0.97];
    self.layer.cornerRadius = 14.0;
    self.layer.borderWidth = 0.5;
    self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.16].CGColor;
    self.layer.masksToBounds = YES;
    self.userInteractionEnabled = YES;

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    _titleLabel.textColor = [UIColor colorWithWhite:0.66 alpha:1.0];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    _titleLabel.text = title;
    [self addSubview:_titleLabel];

    NSMutableArray<UIButton *> *bs = [NSMutableArray array];
    for (NSUInteger i = 0; i < _titles.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        [b setTitle:_titles[i] forState:UIControlStateNormal];
        BOOL isCancel = (i + 1 == _titles.count);
        b.titleLabel.font = [UIFont systemFontOfSize:16.0
                                              weight:isCancel ? UIFontWeightSemibold : UIFontWeightRegular];
        [b setTitleColor:(isCancel ? [UIColor colorWithRed:1.0 green:0.36 blue:0.34 alpha:1.0]
                                   : [UIColor colorWithWhite:0.97 alpha:1.0])
                forState:UIControlStateNormal];
        b.tag = (NSInteger)i;
        [b addTarget:self action:@selector(onButton:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:b];
        [bs addObject:b];
    }
    _buttons = bs;
    return self;
}

#pragma mark - 布局

- (void)showInHost:(UIView *)host anchorFrame:(CGRect)anchor safeInsets:(UIEdgeInsets)sa {
    if (!host || self.titles.count == 0) return;
    if (self.superview != host) {
        [self removeFromSuperview];
        [host addSubview:self];
    }

    CGFloat maxW = MIN(host.bounds.size.width - 24.0, 300.0);
    CGFloat w = MAX(kMinW, MIN(maxW, 240.0));
    CGFloat h = kTitleH + kRowH * (CGFloat)self.titles.count + kPadV * 2.0;

    // 优先摆宠物上方；放不下翻下方；左右夹进安全区
    CGFloat x = CGRectGetMidX(anchor) - w / 2.0;
    CGFloat y = CGRectGetMinY(anchor) - h - 10.0;
    if (y < sa.top + 8.0) y = CGRectGetMaxY(anchor) + 10.0;
    if (y + h > host.bounds.size.height - sa.bottom - 8.0) {
        y = MAX(sa.top + 8.0, host.bounds.size.height - sa.bottom - 8.0 - h);
    }
    x = MAX(12.0, MIN(x, host.bounds.size.width - 12.0 - w));

    self.frame = CGRectMake(round(x), round(y), round(w), round(h));
    self.titleLabel.frame = CGRectMake(kPadH, kPadV, w - kPadH * 2.0, kTitleH);
    CGFloat by = kPadV + kTitleH;
    for (UIButton *b in self.buttons) {
        b.frame = CGRectMake(kPadH, by, w - kPadH * 2.0, kRowH);
        by += kRowH;
    }

    self.alpha = 0.0;
    self.transform = CGAffineTransformMakeScale(0.94, 0.94);
    [UIView animateWithDuration:0.16 animations:^{
        self.alpha = 1.0;
        self.transform = CGAffineTransformIdentity;
    }];

    DSHPetLog(@"menu", @"panel-show", @"debug",
              @{ @"rows": @(self.titles.count), @"frame": NSStringFromCGRect(self.frame) });
}

- (BOOL)isShowing {
    return self.superview != nil;
}

- (void)dismiss {
    if (!self.superview) return;
    [UIView animateWithDuration:0.12 animations:^{
        self.alpha = 0.0;
        self.transform = CGAffineTransformMakeScale(0.96, 0.96);
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
        self.alpha = 1.0;
        self.transform = CGAffineTransformIdentity;
    }];
}

#pragma mark - 点击

- (void)onButton:(UIButton *)b {
    NSInteger idx = b.tag;
    BOOL isCancel = (idx + 1 == (NSInteger)self.titles.count);
    DSHPetMenuHandler cb = self.handler;
    DSHPetLog(@"menu", @"panel-tap", @"debug", @{ @"index": @(idx), @"cancel": @(isCancel) });
    [self dismiss];
    if (!isCancel && cb) cb(idx);
}

@end
