// 小肥娘 · 设置面板
//
// 这一版**不用** PSListController 了。
//
// 教训链：
//   1) 纯 plist 面板（只有 Info/Root.plist）在 iOS 17 + PreferenceLoader 2.2.8 上：
//      entry 带 detail → 报「未能载入软件包…未能找到其可执行文件的位置」；
//      entry 去掉 detail → 设置里连那一行都不出现。
//   2) 改成代码 bundle（有可执行文件 + NSPrincipalClass）后行能显示、能点进来，
//      但页面一片空白 —— PSListController 的子类并不会自动去读 Root.plist，
//      补了 `-specifiers` 也没救活（Preferences 里那一套私有加载链太脆）。
//
// 所以：这里写成**纯 UIKit** 的 UIViewController + UITableView。
// 不碰任何私有类、不依赖 Root.plist、界面完全由代码生成。
// PreferenceLoader 只要求 detail 指向一个 UIViewController 子类，这一点它一直支持。
// 读写仍然钉在 com.vboxai.littlefatlady.prefs 域上（dylib 侧读的就是这个域）。

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

static NSString *const kDSHPetPrefsDomain = @"com.vboxai.littlefatlady.prefs";
static NSString *const kDSHPetRepoURL = @"https://github.com/vbox-Ai/Little-fat-lady";

#pragma mark - 行模型

typedef NS_ENUM(NSInteger, DSHPetRowKind) {
    DSHPetRowKindSwitch = 0,   // 开关
    DSHPetRowKindChoice,       // 点一下切下一档，右侧显示当前档名
    DSHPetRowKindText,         // 弹输入框改字符串
    DSHPetRowKindInfo,         // 只读
    DSHPetRowKindLink,         // 打开链接
};

@interface DSHPetRow : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *key;
@property (nonatomic, assign) DSHPetRowKind kind;
@property (nonatomic, strong) id defaultValue;              // 没写过时的默认值
@property (nonatomic, copy) NSArray *values;                // choice：真实值（NSNumber/NSString）
@property (nonatomic, copy) NSArray<NSString *> *valueTitles; // choice：显示名
@property (nonatomic, copy) NSString *staticText;           // info：显示内容
@property (nonatomic, copy) NSString *linkURL;              // link
@end

@implementation DSHPetRow
@end

@interface DSHPetPrefsRootListController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@end

@implementation DSHPetPrefsRootListController {
    UITableView *_table;
    NSArray<NSArray<DSHPetRow *> *> *_sections;
    NSArray<NSString *> *_sectionTitles;
}

#pragma mark - 偏好读写

static id DSHPetRead(NSString *key) {
    if (key.length == 0) return nil;
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                    (__bridge CFStringRef)kDSHPetPrefsDomain);
    return v ? CFBridgingRelease(v) : nil;
}

static void DSHPetWrite(NSString *key, id value) {
    if (key.length == 0) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             (__bridge CFStringRef)kDSHPetPrefsDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kDSHPetPrefsDomain);
}

static BOOL DSHPetReadBool(NSString *key, BOOL dflt) {
    id v = DSHPetRead(key);
    return [v isKindOfClass:[NSNumber class]] ? [v boolValue] : dflt;
}


#pragma mark - 建表

- (DSHPetRow *)rowSwitch:(NSString *)title key:(NSString *)key dflt:(BOOL)dflt {
    DSHPetRow *r = [DSHPetRow new];
    r.title = title; r.key = key; r.kind = DSHPetRowKindSwitch; r.defaultValue = @(dflt);
    return r;
}

- (DSHPetRow *)rowChoice:(NSString *)title key:(NSString *)key
                  values:(NSArray *)values titles:(NSArray<NSString *> *)titles {
    DSHPetRow *r = [DSHPetRow new];
    r.title = title; r.key = key; r.kind = DSHPetRowKindChoice;
    r.values = values; r.valueTitles = titles; r.defaultValue = values.firstObject;
    return r;
}

- (void)buildModel {
    DSHPetRow *petOn = [self rowSwitch:@"显示小肥娘" key:@"petEnabled" dflt:YES];
    DSHPetRow *edge = [self rowChoice:@"贴边间距" key:@"edgePreset"
                               values:@[@0, @1, @2]
                               titles:@[@"贴紧", @"标准", @"宽松"]];
    edge.defaultValue = @1;
    DSHPetRow *size = [self rowChoice:@"尺寸" key:@"sizePct"
                               values:@[@0.16, @0.20, @0.24, @0.28, @0.30, @0.34, @0.38, @0.46, @0.54]
                               titles:@[@"很小", @"小", @"偏小", @"较小", @"标准", @"偏大", @"大", @"很大", @"巨大"]];
    size.defaultValue = @0.30;

    DSHPetRow *grav = [self rowSwitch:@"重力（松手下落）" key:@"gravityEnabled" dflt:YES];
    DSHPetRow *tilt = [self rowSwitch:@"倾斜重力（随手机倾斜滑动）" key:@"tiltGravityEnabled" dflt:YES];
    DSHPetRow *haptic = [self rowSwitch:@"震动反馈" key:@"hapticEnabled" dflt:YES];
    DSHPetRow *hapticLevel = [self rowChoice:@"震动强度" key:@"hapticLevel"
                                      values:@[@"light", @"normal", @"heavy"]
                                      titles:@[@"轻", @"标准", @"重"]];

    DSHPetRow *bubble = [self rowSwitch:@"气泡提示" key:@"bubbleEnabled" dflt:YES];
    DSHPetRow *bubbleStatus = [self rowSwitch:@"状态气泡（会话在忙/空闲）" key:@"bubbleStatusEnabled" dflt:YES];
    DSHPetRow *bridge = [self rowSwitch:@"连接宿主（读会话状态）" key:@"bridgeEnabled" dflt:YES];
    DSHPetRow *base = [DSHPetRow new];
    base.title = @"宿主地址"; base.key = @"bridgeBase"; base.kind = DSHPetRowKindText;
    base.defaultValue = @"https://dsh.vbox.ltd:42429";

    DSHPetRow *multi = [self rowSwitch:@"多开（多只小肥娘）" key:@"multiPetsEnabled" dflt:NO];
    DSHPetRow *multiMax = [self rowChoice:@"最多几只" key:@"multiPetsMax"
                                   values:@[@1, @2, @3, @4, @5, @6, @7, @8]
                                   titles:@[@"1 只", @"2 只", @"3 只", @"4 只", @"5 只", @"6 只", @"7 只", @"8 只"]];
    multiMax.defaultValue = @3;
    DSHPetRow *perSession = [self rowSwitch:@"每只跟一个会话" key:@"perSession" dflt:YES];

    DSHPetRow *ver = [DSHPetRow new];
    ver.title = @"已装版本"; ver.kind = DSHPetRowKindInfo; ver.staticText = @"(未知)";
    DSHPetRow *link = [DSHPetRow new];
    link.title = @"项目主页"; link.kind = DSHPetRowKindLink; link.linkURL = kDSHPetRepoURL;
    DSHPetRow *doctor = [DSHPetRow new];
    doctor.title = @"自检报告路径"; doctor.kind = DSHPetRowKindInfo;
    doctor.staticText = @"/var/mobile/Library/DSHPet/doctor.txt";

    _sectionTitles = @[@"宠物", @"物理与触感", @"会话气泡", @"多开", @"关于"];
    _sections = @[@[petOn, edge, size],
                 @[grav, tilt, haptic, hapticLevel],
                 @[bubble, bubbleStatus, bridge, base],
                 @[multi, multiMax, perSession],
                 @[ver, link, doctor]];
}

#pragma mark - 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"小肥娘";
    [self buildModel];

    _table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _table.dataSource = self;
    _table.delegate = self;
    _table.rowHeight = UITableViewAutomaticDimension;
    _table.estimatedRowHeight = 46.0;
    [self.view addSubview:_table];

    NSLog(@"[DSHPetPrefs] panel loaded, sections=%lu", (unsigned long)_sections.count);
}

#pragma mark - 取值/显示

- (id)valueForRow:(DSHPetRow *)row {
    id v = DSHPetRead(row.key);
    if (v) return v;
    return row.defaultValue;
}

- (NSInteger)indexOfRow:(DSHPetRow *)row value:(id)value {
    if (value) {
        for (NSUInteger i = 0; i < row.values.count; i++) {
            if ([row.values[i] isEqual:value]) return (NSInteger)i;
        }
    }
    return 0;
}

- (NSString *)trailingTextForRow:(DSHPetRow *)row {
    switch (row.kind) {
        case DSHPetRowKindChoice: {
            NSInteger i = [self indexOfRow:row value:[self valueForRow:row]];
            return i < (NSInteger)row.valueTitles.count ? row.valueTitles[(NSUInteger)i] : @"";
        }
        case DSHPetRowKindText: {
            id v = [self valueForRow:row];
            return [v isKindOfClass:[NSString class]] ? v : @"";
        }
        case DSHPetRowKindInfo:
            return row.staticText;
        case DSHPetRowKindLink:
            return @"";
        default:
            return @"";
    }
}

#pragma mark - TableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return (NSInteger)_sections.count; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_sections[(NSUInteger)section].count;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
    return _sectionTitles[(NSUInteger)section];
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    DSHPetRow *row = _sections[(NSUInteger)indexPath.section][(NSUInteger)indexPath.row];
    static NSString *cid = @"dshpet";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:cid];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cid];
    cell.textLabel.text = row.title;

    // 清掉上一个 cell 复用留下的配件
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    switch (row.kind) {
        case DSHPetRowKindSwitch: {
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = DSHPetReadBool(row.key, [row.defaultValue boolValue]);
            sw.tag = indexPath.section * 1000 + indexPath.row;
            [sw addTarget:self action:@selector(onSwitchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.detailTextLabel.text = nil;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        }
        case DSHPetRowKindChoice:
        case DSHPetRowKindText: {
            cell.detailTextLabel.text = [self trailingTextForRow:row];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        }
        case DSHPetRowKindLink:
            cell.detailTextLabel.text = nil;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        case DSHPetRowKindInfo:
        default: {
            cell.detailTextLabel.text = [self trailingTextForRow:row];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tv deselectRowAtIndexPath:indexPath animated:YES];
    DSHPetRow *row = _sections[(NSUInteger)indexPath.section][(NSUInteger)indexPath.row];

    if (row.kind == DSHPetRowKindChoice) {
        NSInteger i = [self indexOfRow:row value:[self valueForRow:row]];
        NSInteger next = (i + 1) % (NSInteger)row.values.count;
        DSHPetWrite(row.key, row.values[(NSUInteger)next]);
        [tv reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        return;
    }
    if (row.kind == DSHPetRowKindLink) {
        NSURL *u = [NSURL URLWithString:row.linkURL];
        if (u) [[UIApplication sharedApplication] openURL:u options:@{} completionHandler:nil];
        return;
    }
    if (row.kind == DSHPetRowKindText) {
        [self promptForText:row indexPath:indexPath];
    }
}

- (void)onSwitchChanged:(UISwitch *)sw {
    NSInteger section = sw.tag / 1000;
    NSInteger rowIdx = sw.tag % 1000;
    if (section < 0 || section >= (NSInteger)_sections.count) return;
    NSArray<DSHPetRow *> *rows = _sections[(NSUInteger)section];
    if (rowIdx < 0 || rowIdx >= (NSInteger)rows.count) return;
    DSHPetWrite(rows[(NSUInteger)rowIdx].key, @(sw.on));
}

- (void)promptForText:(DSHPetRow *)row indexPath:(NSIndexPath *)indexPath {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:row.title
                                                                message:nil
                                                         preferredStyle:UIAlertControllerStyleAlert];
    id cur = [self valueForRow:row];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = [cur isKindOfClass:[NSString class]] ? cur : @"";
        tf.keyboardType = UIKeyboardTypeURL;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak DSHPetPrefsRootListController *weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *text = ac.textFields.firstObject.text ?: @"";
        DSHPetWrite(row.key, text);
        DSHPetPrefsRootListController *s = weakSelf;
        [s->_table reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

@end
