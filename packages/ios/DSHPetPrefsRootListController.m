// 小肥娘 · 设置面板
//
// 闪退修复（v0.1.0-137）：detail 指向的类必须是 PSListController 子类。
//
// 崩溃链（真机日志，Preferences 进程 EXC_CRASH / SIGABRT，abort() called）：
//   UITableView 选中行 → PSListController tableView:didSelectRowAtIndexPath:
//   → PSListController controllerForSpecifier: → doesNotRecognizeSelector
//   → ___forwarding___ → objc_exception_throw → abort()
// Preferences 拿到入口 plist 的 detail 类名后，按 PSController / PSSpecifier 那套
// 私有协议给实例发选择子。上一版把控制器写成纯 UIViewController，不响应这些选择子，
// forwarding 抛异常直接把整个「设置」App 打挂。
//
// 教训链：
//   1) 纯 plist 面板（只有 Info/Root.plist）在 iOS 17 + PreferenceLoader 2.2.8 上：
//      entry 带 detail → 报「未能载入软件包…未能找到其可执行文件的位置」；
//      entry 去掉 detail → 设置里连那一行都不出现。
//   2) 改成代码 bundle 后行能显示、能点进来，但 PSListController 子类不会自动读
//      Root.plist，补 `-specifiers` 也救不活（私有加载链太脆）→ 页面空白。
//   3) 于是上一版改成纯 UIViewController，结果撞上上面的闪退。
//
// 现在：继承 PSListController（私有选择子全部接住，不再 forwarding 抛异常），
// 但界面仍然完全自绘 —— 在 -loadView 里建自己的 UITableView，不调 super 的
// viewDidLoad（那条 specifier 建表链不依赖），不碰 Root.plist。
// 读写钉在 com.vboxai.littlefatlady.prefs 域上（dylib 侧读的就是这个域）。

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// PSListController 是 Preferences 私有框架里的类，SDK 没有头文件。
// 这里给它一个最小接口声明（父类 UIViewController，声明用到的 specifiers），
// 让编译器看到完整类链 —— view / title / presentViewController: 等 UIViewController
// 成员才能解析。只写 @class 前向声明会让编译器以为新类没有基类，全部 -Werror 报错。
// 链接期用 -undefined dynamic_lookup，运行期由宿主 Preferences 进程提供真实实现。
@interface PSListController : UIViewController
- (NSArray *)specifiers;
@end

static NSString *const kDSHPetPrefsDomain = @"com.vboxai.littlefatlady.prefs";
static NSString *const kDSHPetRepoURL = @"https://github.com/vbox-Ai/Little-fat-lady";

#pragma mark - 行模型

typedef NS_ENUM(NSInteger, DSHPetRowKind) {
    DSHPetRowKindSwitch = 0,   // 开关
    DSHPetRowKindChoice,       // 点一下切下一档，右侧显示当前档名
    DSHPetRowKindText,         // 弹输入框改字符串
    DSHPetRowKindInfo,         // 只读
    DSHPetRowKindLink,         // 打开链接
    DSHPetRowKindSecret,       // 输入密钥：写进「待迁移」键，dylib 首次用到时搬进 Keychain
    DSHPetRowKindAction,       // 点一下执行动作（测试连接 / 清除密钥）
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
@property (nonatomic, copy) NSString *actionName;           // action：动作名
@end

@implementation DSHPetRow
@end

@interface DSHPetPrefsRootListController : PSListController <UITableViewDataSource, UITableViewDelegate>
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
    // S-M1a：行走开关。关掉她就钉在原地（想截图/录屏时很有用）
    DSHPetRow *wander = [self rowSwitch:@"自动漫游（自己走来走去）" key:@"wanderEnabled" dflt:YES];
    // S-M1b 漫游分区：她只在选定那一段来回走（嫌她乱跑就锁一边）
    DSHPetRow *zone = [self rowChoice:@"漫游范围" key:@"wanderZone"
                               values:@[@0, @1, @2, @3]
                               titles:@[@"全屏", @"左半边", @"中间", @"右半边"]];
    zone.defaultValue = @0;
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

    // S-P2：人格与语音。这三项都是运行时每 tick 重读，改完立刻生效，不用重启。
    DSHPetRow *persona = [self rowSwitch:@"自主性格（自己说话/会闹脾气）" key:@"personaEnabled" dflt:YES];
    DSHPetRow *voice = [self rowSwitch:@"说话出声" key:@"voiceEnabled" dflt:YES];
    DSHPetRow *sfx = [self rowSwitch:@"动作音效" key:@"sfxEnabled" dflt:YES];
    DSHPetRow *quiet = [self rowSwitch:@"免打扰（23:00–08:00 不说话）" key:@"quietHours" dflt:NO];

    // S-AI1：大模型（方案 §十四）。这里每一项 dylib 侧都真的读：
    //   aiEnabled / aiBaseURL / aiModel / aiTemperature / aiMaxTokens / aiVisionEnabled。
    // Key 例外：面板跟 dylib 不是一个进程，碰不到 Keychain item，所以只写 aiKeyPending，
    // dylib 第一次调用时搬进 Keychain 并把明文抹掉（见 DSHPetChat -apiKey）。
    DSHPetRow *aiOn = [self rowSwitch:@"接大模型回话" key:@"aiEnabled" dflt:NO];
    DSHPetRow *aiBase = [DSHPetRow new];
    aiBase.title = @"服务地址"; aiBase.key = @"aiBaseURL"; aiBase.kind = DSHPetRowKindText;
    // 不写死任何地址：仓库是公开的，塞私网 IP 等于把自己的网关贴出去。
    // 局域网示例 http://192.168.1.230:3425/v1；出门要用能公网访问的那个。
    aiBase.defaultValue = @"";
    DSHPetRow *aiModel = [DSHPetRow new];
    aiModel.title = @"模型名"; aiModel.key = @"aiModel"; aiModel.kind = DSHPetRowKindText;
    aiModel.defaultValue = @"";
    DSHPetRow *aiKey = [DSHPetRow new];
    aiKey.title = @"API Key"; aiKey.key = @"aiKeyPending"; aiKey.kind = DSHPetRowKindSecret;
    aiKey.defaultValue = @"";
    DSHPetRow *aiTemp = [self rowChoice:@"说话活跃度（温度）" key:@"aiTemperature"
                                 values:@[@0.5, @0.9, @1.2]
                                 titles:@[@"稳", @"中", @"活"]];
    aiTemp.defaultValue = @0.9;
    DSHPetRow *aiTokens = [self rowChoice:@"最长回复" key:@"aiMaxTokens"
                                   values:@[@80, @120, @200]
                                   titles:@[@"短（80）", @"中（120）", @"长（200）"]];
    aiTokens.defaultValue = @120;
    DSHPetRow *aiVision = [self rowSwitch:@"允许看截图（多模态，费钱）" key:@"aiVisionEnabled" dflt:NO];
    DSHPetRow *aiTest = [DSHPetRow new];
    aiTest.title = @"测试连接"; aiTest.kind = DSHPetRowKindAction; aiTest.actionName = @"aiTest";
    DSHPetRow *aiClear = [DSHPetRow new];
    aiClear.title = @"清除 API Key"; aiClear.kind = DSHPetRowKindAction; aiClear.actionName = @"aiClearKey";

    // S-TTS2：语音合成（方案 §11.7 / §十三）。
    // engine=native 时下面几项都不生效（走系统 AVSpeechSynthesizer）；
    // 选 volc 要 AppID + Access Token（Cluster 默认 volcano_tts）；选 openai 要地址 + Key。
    // 面板不做联动灰化：PSListController 的 reloadData 在这套自绘面板上容易踩 estimatedHeight 的坑，
    // 改成「填了才用」，填错也不崩——dylib 侧失败一律静默回落系统合成。
    DSHPetRow *ttsEngine = [self rowChoice:@"语音引擎" key:@"ttsEngine"
                                    values:@[@"native", @"volc", @"openai"]
                                    titles:@[@"系统原生", @"豆包·火山", @"OpenAI 兼容"]];
    ttsEngine.defaultValue = @"native";
    DSHPetRow *ttsAppID = [DSHPetRow new];
    ttsAppID.title = @"豆包 AppID"; ttsAppID.key = @"ttsAppID"; ttsAppID.kind = DSHPetRowKindText;
    ttsAppID.defaultValue = @"";
    DSHPetRow *ttsToken = [DSHPetRow new];
    ttsToken.title = @"豆包 Access Token"; ttsToken.key = @"ttsToken"; ttsToken.kind = DSHPetRowKindSecret;
    ttsToken.defaultValue = @"";
    DSHPetRow *ttsCluster = [DSHPetRow new];
    ttsCluster.title = @"Cluster"; ttsCluster.key = @"ttsCluster"; ttsCluster.kind = DSHPetRowKindText;
    ttsCluster.defaultValue = @"volcano_tts";
    DSHPetRow *ttsVoiceType = [DSHPetRow new];
    ttsVoiceType.title = @"音色码"; ttsVoiceType.key = @"ttsVoiceType"; ttsVoiceType.kind = DSHPetRowKindText;
    ttsVoiceType.defaultValue = @"BV700_streaming";
    DSHPetRow *ttsBase = [DSHPetRow new];
    ttsBase.title = @"接口地址（OpenAI 兼容）"; ttsBase.key = @"ttsBaseURL"; ttsBase.kind = DSHPetRowKindText;
    ttsBase.defaultValue = @"";
    DSHPetRow *ttsModel = [DSHPetRow new];
    ttsModel.title = @"模型名"; ttsModel.key = @"ttsModel"; ttsModel.kind = DSHPetRowKindText;
    ttsModel.defaultValue = @"tts-1";
    DSHPetRow *ttsVoice = [DSHPetRow new];
    ttsVoice.title = @"音色"; ttsVoice.key = @"ttsVoice"; ttsVoice.kind = DSHPetRowKindText;
    ttsVoice.defaultValue = @"alloy";
    DSHPetRow *ttsAPIKey = [DSHPetRow new];
    ttsAPIKey.title = @"接口 Key"; ttsAPIKey.key = @"ttsAPIKey"; ttsAPIKey.kind = DSHPetRowKindSecret;
    ttsAPIKey.defaultValue = @"";
    DSHPetRow *ttsSpeed = [self rowChoice:@"语速" key:@"ttsSpeed"
                                   values:@[@0.8, @1.0, @1.2]
                                   titles:@[@"慢", @"正常", @"快"]];
    ttsSpeed.defaultValue = @1.0;
    DSHPetRow *ttsPitch = [self rowChoice:@"音调" key:@"ttsPitch"
                                   values:@[@0.9, @1.0, @1.1]
                                   titles:@[@"低", @"正常", @"高"]];
    ttsPitch.defaultValue = @1.0;
    DSHPetRow *ttsTest = [DSHPetRow new];
    ttsTest.title = @"试听一句"; ttsTest.kind = DSHPetRowKindAction; ttsTest.actionName = @"ttsTest";
    DSHPetRow *ttsPurge = [DSHPetRow new];
    ttsPurge.title = @"清空语音缓存"; ttsPurge.kind = DSHPetRowKindAction; ttsPurge.actionName = @"ttsPurge";
    DSHPetRow *ttsHint = [DSHPetRow new];
    ttsHint.title = @"未配置或合成失败时"; ttsHint.kind = DSHPetRowKindInfo;
    ttsHint.staticText = @"自动用系统声音";

    DSHPetRow *multi = [self rowSwitch:@"多开（多只小肥娘）" key:@"multiPetsEnabled" dflt:NO];    DSHPetRow *multiMax = [self rowChoice:@"最多几只" key:@"multiPetsMax"
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

    _sectionTitles = @[@"宠物", @"物理与触感", @"人格与语音", @"会话气泡", @"大模型", @"语音合成", @"多开", @"关于"];
    _sections = @[@[petOn, wander, zone, edge, size],
                 @[grav, tilt, haptic, hapticLevel],
                 @[persona, voice, sfx, quiet],
                 @[bubble, bubbleStatus, bridge, base],
                 @[aiOn, aiBase, aiModel, aiKey, aiTemp, aiTokens, aiVision, aiTest, aiClear],
                 @[ttsEngine, ttsAppID, ttsToken, ttsCluster, ttsVoiceType,
                   ttsBase, ttsModel, ttsVoice, ttsAPIKey, ttsSpeed, ttsPitch,
                   ttsHint, ttsTest, ttsPurge],
                 @[multi, multiMax, perSession],
                 @[ver, link, doctor]];
}

#pragma mark - 生命周期

// 自绘界面。不调 [super loadView]：PSListController / UITableViewController 的
// loadView 会按 specifier 建表，那条私有链在 iOS 17 + PreferenceLoader 2.2.8 上
// 不可靠，而且会跟我们自建的表抢同一块视图。
- (void)loadView {
    UIView *root = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 480)];
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    _table = [[UITableView alloc] initWithFrame:root.bounds style:UITableViewStyleInsetGrouped];
    _table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _table.dataSource = self;
    _table.delegate = self;
    _table.rowHeight = UITableViewAutomaticDimension;
    _table.estimatedRowHeight = 46.0;
    [root addSubview:_table];

    self.view = root;
}

// 同样不调 [super viewDidLoad]：PSListController 的 viewDidLoad 会走 specifier 建表，
// 我们已经完全自绘，跳过它避免空表 / 视图冲突。
- (void)viewDidLoad {
    self.title = @"小肥娘";
    [self buildModel];
    [_table reloadData];

    NSLog(@"[DSHPetPrefs] panel loaded, sections=%lu", (unsigned long)_sections.count);
}

// 兜底：任何仍走 specifier 的路径拿到空数组，没有内容可渲染，也不会崩。
- (NSArray *)specifiers {
    return @[];
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
        case DSHPetRowKindSecret: {
            // 只显示"有没有"，永远不回显内容（回显就等于把 Key 摊在屏幕上）
            BOOL stored = DSHPetReadBool(@"aiKeyStored", NO);
            NSString *pending = DSHPetRead(@"aiKeyPending");
            if (stored) return @"已设置";
            if ([pending isKindOfClass:[NSString class]] && [(NSString *)pending length] > 0) return @"待保存";
            return @"未设置";
        }
        case DSHPetRowKindAction:
            return @"";
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

// ── 覆盖 PSListController 私有 delegate 实现（防空 specifier 崩溃）──────────────
// 崩溃根因（真机 2026-11-18 19:25，Preferences EXC_BAD_ACCESS KERN_INVALID_ADDRESS 0x38）：
//   _table.estimatedRowHeight=46 非 0 → reloadData 调 delegate 的
//   tableView:estimatedHeightForRowAtIndexPath:，而 delegate 是 self（PSListController 子类），
//   iOS 17 的 PSListController 实现了这个方法，内部走 PSListControllerDefaultAppearanceProvider，
//   provider 读不存在的 specifier（空指针 +0x38）→ SIGSEGV。
// 修法：显式实现以下方法覆盖父类，全部走自绘表的固定/自动值，永不进 specifier 渲染链。

- (CGFloat)tableView:(UITableView *)tv estimatedHeightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 46.0;
}

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewAutomaticDimension;
}

- (CGFloat)tableView:(UITableView *)tv heightForHeaderInSection:(NSInteger)section {
    return UITableViewAutomaticDimension;
}

- (CGFloat)tableView:(UITableView *)tv heightForFooterInSection:(NSInteger)section {
    return 0.0;
}

- (UIView *)tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)section {
    return nil;  // 交给 titleForHeaderInSection 显示默认标题
}

- (UIView *)tableView:(UITableView *)tv viewForFooterInSection:(NSInteger)section {
    return nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section {
    return nil;
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
    cell.textLabel.textColor = [UIColor labelColor];

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
        case DSHPetRowKindText:
        case DSHPetRowKindSecret: {
            cell.detailTextLabel.text = [self trailingTextForRow:row];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        }
        case DSHPetRowKindAction: {
            cell.detailTextLabel.text = nil;
            cell.textLabel.textColor = [UIColor systemBlueColor];
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
    if (row.kind == DSHPetRowKindText || row.kind == DSHPetRowKindSecret) {
        [self promptForText:row indexPath:indexPath];
        return;
    }
    if (row.kind == DSHPetRowKindAction) {
        [self runActionRow:row];
    }
}

// 试听：面板在 Preferences 进程里，碰不到 SpringBoard 里的语音单例，
// 所以发一条 Darwin 通知，让 dylib 侧用当前配置说一句。配置对不对，一耳朵就能听出来。
- (void)probeTTS {
    id rawEngine = DSHPetRead(@"ttsEngine");
    NSString *engine = [rawEngine isKindOfClass:[NSString class]] ? (NSString *)rawEngine : @"native";
    NSString *tip = nil;
    if ([engine isEqualToString:@"volc"]) {
        tip = @"将用「豆包·火山」合成。若没声音：确认 AppID 与 Access Token 已填、Cluster 是 volcano_tts、音色码已开通。";
    } else if ([engine isEqualToString:@"openai"]) {
        tip = @"将用「OpenAI 兼容」合成。若没声音：确认接口地址以 /v1 结尾、模型与音色名有效、Key 正确。";
    } else {
        tip = @"当前是「系统原生」引擎（不联网）。换成豆包或 OpenAI 兼容才会有专属音色。";
    }
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.vboxai.littlefatlady.tts.test"),
                                         NULL, NULL, true);
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"已让小肥娘说一句"
                                                               message:tip
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

// 清缓存：同样走 Darwin 通知，dylib 侧删 ~/Library/Application Support/DSHPet/tts/*.mp3
- (void)purgeTTSCache {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.vboxai.littlefatlady.tts.purge"),
                                         NULL, NULL, true);
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"已清空语音缓存"
                                                               message:@"下次说话会重新合成。缓存只在温度/语速/音色不变时才复用，改过任一项本来也会重合成。"
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)runActionRow:(DSHPetRow *)row {
    if ([row.actionName isEqualToString:@"aiTest"]) {
        [self testAIConnection];
    } else if ([row.actionName isEqualToString:@"ttsTest"]) {
        [self probeTTS];
    } else if ([row.actionName isEqualToString:@"ttsPurge"]) {
        [self purgeTTSCache];
    } else if ([row.actionName isEqualToString:@"aiClearKey"]) {
        DSHPetWrite(@"aiKeyPending", @"");
        DSHPetWrite(@"aiKeyStored", @NO);
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"已清除"
                                                                   message:@"Key 已从本机删除，下次启动后生效。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:ac animated:YES completion:nil];
        [_table reloadData];
    }
}

// 测试连接：面板自己发一次 GET {base}/models。
// 用「待迁移」里的 Key（用户刚粘贴、dylib 还没搬走的那把）；已经搬进 Keychain 之后
// 面板就看不见了，这时只能测「地址通不通」，所以提示语分开写，不糊弄。
- (void)testAIConnection {
    NSString *base = DSHPetRead(@"aiBaseURL");
    if (![base isKindOfClass:[NSString class]] || [(NSString *)base length] == 0) {
        base = @"http://192.168.1.230:3425/v1";
    }
    while ([base hasSuffix:@"/"]) base = [base substringToIndex:base.length - 1];
    NSURL *url = [NSURL URLWithString:[base stringByAppendingString:@"/models"]];
    if (!url) {
        [self showAlertTitle:@"地址不合法" message:base];
        return;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.timeoutInterval = 8.0;
    NSString *pending = DSHPetRead(@"aiKeyPending");
    BOOL hasPending = [pending isKindOfClass:[NSString class]] && [(NSString *)pending length] > 0;
    if (hasPending) {
        [req setValue:[@"Bearer " stringByAppendingString:pending] forHTTPHeaderField:@"Authorization"];
    }
    __weak DSHPetPrefsRootListController *weakSelf = self;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
                                                                completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            DSHPetPrefsRootListController *s = weakSelf;
            if (!s) return;
            if (err) {
                [s showAlertTitle:@"连不上" message:[NSString stringWithFormat:@"%@\n\n检查：地址、端口、是否同一网络。", err.localizedDescription]];
                return;
            }
            NSInteger code = [(NSHTTPURLResponse *)resp statusCode];
            if (code == 401 || code == 403) {
                [s showAlertTitle:[NSString stringWithFormat:@"地址通了，但 Key 无效（%ld）", (long)code]
                          message:hasPending ? @"这把 Key 被拒绝了，换一把再试。" : @"Key 已存进钥匙串，面板看不到；如需重测请先重新粘贴一次。"];
                return;
            }
            if (code >= 200 && code < 300) {
                NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
                NSInteger count = 0;
                id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
                if ([json isKindOfClass:[NSDictionary class]] && [json[@"data"] isKindOfClass:[NSArray class]]) {
                    count = [(NSArray *)json[@"data"] count];
                }
                [s showAlertTitle:@"连接正常"
                          message:count > 0 ? [NSString stringWithFormat:@"发现 %ld 个模型。", (long)count]
                                            : (body.length ? @"服务端有响应。" : @"服务端有响应，但没返回模型列表。")];
                return;
            }
            [s showAlertTitle:[NSString stringWithFormat:@"服务端返回 %ld", (long)code] message:@"地址通了，但这个接口没按 OpenAI 兼容格式返回。"];
        });
    }];
    [task resume];
}

- (void)showAlertTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:title
                                                                message:message
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
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
    BOOL secret = (row.kind == DSHPetRowKindSecret);
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        // 密钥行永远不回显旧值：回显一次就等于把这把 Key 摊在屏幕上被人看到
        tf.text = secret ? @"" : ([cur isKindOfClass:[NSString class]] ? cur : @"");
        tf.placeholder = secret ? @"粘贴 API Key（留空保存＝删除）" : nil;
        tf.secureTextEntry = secret;
        tf.keyboardType = secret ? UIKeyboardTypeASCIICapable : UIKeyboardTypeURL;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak DSHPetPrefsRootListController *weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *text = ac.textFields.firstObject.text ?: @"";
        DSHPetPrefsRootListController *s = weakSelf;
        // 密钥行：空串保存 = 删除（跟面板文案一致），dylib 看到空就不搬进 Keychain
        DSHPetWrite(row.key, text);
        [s->_table reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

@end
