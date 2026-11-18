#import "DSHPetTodoPanel.h"
#import "DSHPetBoot.h"

// 视觉基调跟气泡一致（深色圆角 + 细边框），只是多了行数。
// 字号比气泡小一点：待办条目要一次看 5 条，13pt 会撑爆宽度。
static const CGFloat kPadH = 12.0;
static const CGFloat kPadV = 10.0;
static const CGFloat kRowGap = 7.0;
static const CGFloat kTitleFontSize = 13.0;
static const CGFloat kRowFontSize = 12.5;
static const NSInteger kMaxRows = 6;

@interface DSHPetTodoPanel ()
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *bodyLabel;
@property (nonatomic, strong) NSTimer *hideTimer;
@end

@implementation DSHPetTodoPanel

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.backgroundColor = [UIColor colorWithWhite:0.09 alpha:0.94];
    self.layer.cornerRadius = 13.0;
    self.layer.borderWidth = 0.5;
    self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.14].CGColor;
    self.layer.masksToBounds = YES;
    self.userInteractionEnabled = YES;

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.font = [UIFont systemFontOfSize:kTitleFontSize weight:UIFontWeightSemibold];
    _titleLabel.textColor = [UIColor colorWithWhite:0.72 alpha:1.0];
    _titleLabel.text = @"待办";
    [self addSubview:_titleLabel];

    _bodyLabel = [[UILabel alloc] init];
    _bodyLabel.font = [UIFont systemFontOfSize:kRowFontSize weight:UIFontWeightRegular];
    _bodyLabel.textColor = [UIColor colorWithWhite:0.96 alpha:1.0];
    _bodyLabel.numberOfLines = 0;
    _bodyLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self addSubview:_bodyLabel];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onTap:)];
    [self addGestureRecognizer:tap];

    return self;
}

#pragma mark - 文案

// 到期时间的说法要"当人话"：今天/明天/周几，比 2026-11-19 23:00 好读得多。
static NSString *DSHPetDueText(NSNumber *dueAt) {
    if (![dueAt isKindOfClass:[NSNumber class]]) return @"";
    double ms = dueAt.doubleValue;
    if (ms <= 0) return @"";
    // 上游是 epoch 毫秒；万一哪天改成秒，这里用阈值兜一下
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:(ms > 1e11 ? ms / 1000.0 : ms)];
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];

    if ([cal isDateInToday:date]) {
        fmt.dateFormat = @"今天 HH:mm";
    } else if ([cal isDateInTomorrow:date]) {
        fmt.dateFormat = @"明天 HH:mm";
    } else {
        NSInteger days = [cal components:NSCalendarUnitDay
                                fromDate:[cal startOfDayForDate:[NSDate date]]
                                  toDate:[cal startOfDayForDate:date]
                                 options:0].day;
        if (days < 0) fmt.dateFormat = @"已过期 M/d";
        else if (days < 7) fmt.dateFormat = @"E HH:mm";
        else fmt.dateFormat = @"M/d";
    }
    NSString *s = [fmt stringFromDate:date];
    if ([cal compareDate:date toDate:[NSDate date] toUnitGranularity:NSCalendarUnitMinute] == NSOrderedAscending
        && ![s hasPrefix:@"已过期"]) {
        s = [@"已过期 " stringByAppendingString:s];
    }
    return s;
}

- (NSString *)bodyTextForItems:(NSArray<NSDictionary *> *)items {
    if (items.count == 0) return @"没有未完成的待办。";

    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    NSInteger shown = 0;
    for (NSDictionary *it in items) {
        if (shown >= kMaxRows) break;
        NSString *text = it[@"text"];
        if (![text isKindOfClass:[NSString class]] || !text.length) continue;
        BOOL done = [it[@"done"] isKindOfClass:[NSNumber class]] ? [it[@"done"] boolValue] : NO;

        NSString *mark = done ? @"✓ " : @"· ";
        NSString *due = DSHPetDueText([it[@"dueAt"] isKindOfClass:[NSNumber class]] ? it[@"dueAt"] : nil);
        NSString *line = [NSString stringWithFormat:@"%@%@", mark, text];
        if (due.length) line = [line stringByAppendingFormat:@"　%@", due];
        [lines addObject:line];
        shown += 1;
    }
    if (lines.count == 0) return @"没有未完成的待办。";

    NSInteger rest = (NSInteger)items.count - lines.count;
    if (rest > 0) [lines addObject:[NSString stringWithFormat:@"…还有 %ld 条", (long)rest]];
    return [lines componentsJoinedByString:@"\n"];
}

#pragma mark - 布局

- (void)renderWithTitle:(NSString *)title body:(NSString *)body
                 inHost:(UIView *)host anchorFrame:(CGRect)anchor safeInsets:(UIEdgeInsets)sa {
    if (!host) return;
    if (self.superview != host) {
        [self removeFromSuperview];
        [host addSubview:self];
    }

    self.titleLabel.text = title;
    self.bodyLabel.text = body;

    CGFloat maxW = MIN(host.bounds.size.width - 24.0, 320.0);
    CGFloat innerW = maxW - kPadH * 2;
    CGSize titleSize = [self.titleLabel sizeThatFits:CGSizeMake(innerW, CGFLOAT_MAX)];
    CGSize bodySize = [self.bodyLabel sizeThatFits:CGSizeMake(innerW, CGFLOAT_MAX)];

    CGFloat w = MIN(maxW, MAX(titleSize.width, bodySize.width) + kPadH * 2);
    CGFloat h = titleSize.height + kRowGap * 2 + bodySize.height + kPadV * 2;
    h = MIN(h, host.bounds.size.height - sa.top - sa.bottom - 24.0);

    // 优先放宠物上方，放不下翻到下方；左右夹在安全区里
    CGFloat x = CGRectGetMidX(anchor) - w / 2.0;
    CGFloat y = CGRectGetMinY(anchor) - h - 10.0;
    if (y < sa.top + 8.0) y = CGRectGetMaxY(anchor) + 10.0;
    if (y + h > host.bounds.size.height - sa.bottom - 8.0) {
        y = MAX(sa.top + 8.0, host.bounds.size.height - sa.bottom - 8.0 - h);
    }
    x = MAX(12.0, MIN(x, host.bounds.size.width - 12.0 - w));

    self.frame = CGRectMake(round(x), round(y), round(w), round(h));
    self.titleLabel.frame = CGRectMake(kPadH, kPadV, innerW, titleSize.height);
    self.bodyLabel.frame = CGRectMake(kPadH, kPadV + titleSize.height + kRowGap * 2, innerW, bodySize.height);

    self.alpha = 0.0;
    [UIView animateWithDuration:0.16 animations:^{ self.alpha = 1.0; }];

    // 15 秒自动收：这玩意儿是"看一眼"，不是常驻面板（常驻得进设置页）
    [self.hideTimer invalidate];
    __weak DSHPetTodoPanel *weakSelf = self;
    self.hideTimer = [NSTimer scheduledTimerWithTimeInterval:15.0 repeats:NO block:^(NSTimer *t) {
        [weakSelf dismiss];
    }];
    DSHPetLog(@"todo", @"show", @"info", @{ @"title": title, @"len": @(body.length),
                                            @"frame": NSStringFromCGRect(self.frame) });
}

#pragma mark - 对外

- (void)showTodos:(NSArray<NSDictionary *> *)items
           inHost:(UIView *)host
      anchorFrame:(CGRect)anchor
       safeInsets:(UIEdgeInsets)safeInsets {
    NSString *title = items.count ? [NSString stringWithFormat:@"待办（%lu）", (unsigned long)items.count] : @"待办";
    [self renderWithTitle:title body:[self bodyTextForItems:items] inHost:host anchorFrame:anchor safeInsets:safeInsets];
}

- (void)showLoadingInHost:(UIView *)host anchorFrame:(CGRect)anchor safeInsets:(UIEdgeInsets)safeInsets {
    [self renderWithTitle:@"待办" body:@"正在从宿主读取…" inHost:host anchorFrame:anchor safeInsets:safeInsets];
}

- (void)showError:(NSString *)text inHost:(UIView *)host anchorFrame:(CGRect)anchor safeInsets:(UIEdgeInsets)safeInsets {
    NSString *body = text.length ? text : @"读取失败";
    [self renderWithTitle:@"待办" body:body inHost:host anchorFrame:anchor safeInsets:safeInsets];
}

- (void)dismiss {
    [self.hideTimer invalidate];
    self.hideTimer = nil;
    [UIView animateWithDuration:0.14 animations:^{
        self.alpha = 0.0;
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
    }];
}

- (void)onTap:(UITapGestureRecognizer *)g {
    [self dismiss];
}

@end