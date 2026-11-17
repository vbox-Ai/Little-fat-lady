# 小肥娘 iOS 越狱插件 · 开发方案 v2.15

> **v2.12 修订（实测 2026-11-15 13:0x）**：`dsh.vbox.ltd:42429` 并不直接指向 DSH —— 它指向本机 **caddy(7789)**，caddy 再按路径分流：`/dsh-pet-7340/*` → DSH Web **52009**，其余（含 `/ws/mobile`）→ mobile-gateway **3081**。上一版"把隧道本地端口改成 52009"的说法**作废**（会切断 Whaleness）。详见 §17。


> 仓库：https://github.com/vbox-Ai/Little-fat-lady （公开，保留上游 LICENSE + 署名）
> 目标机：**iPhone 14 Pro（A16 · arm64e）· iOS 17.0 · Relaxin（RootHide 型）越狱**
> 上游：https://github.com/PC2005-cloud/dsh-pet （代码 MIT / 形象素材 CC BY-NC-SA 4.0）
>
> **变更（v2.15）**：新增 **§20 阶段关闭闸门（硬性）**——每阶段必须依次完成「自检遗漏 → 写记忆点 → 全量推送仓库 → 回报 commit」，四件齐才算关闭，缺一不许开下一步。同时把仓库骨架、CI、探针脚本、双许可证纳入 S0 交付。
> **变更（v2.14）**：上游 `openapi.yaml` 逐条对账（41 路径 / 55 方法），补齐之前漏掉的 13 个端点，新增 **§19**；三条改变设计的发现（`/models` 动态、`/voice/hear` 让手机不必打包本地 ASR、`/config` 顶层是 `{main:{…}}` 命名空间）；更正 §18.12 关于余额 provider 的误判；网络定稿为「全程 42429 + Tailscale 备用」，明文 HTTP 兜底降为 Save 分支。人日净持平 **63**。
> **变更（v2.13）**：本轮遗漏补齐 —— 新增 **§18**：iOS 网络权限与 ATS 对桥接的硬约束（本地网络授权、明文 HTTP 被 SpringBoard 的 ATS 拦、四条对策）、arm64e/PAC 下 hook 与签名现实、生命周期矩阵（锁屏/来电/旋转/动态岛/App 切换器）、热控与低电量降级、与其它越狱插件的 z-order 共存、deb 打包与源索引规范、无障碍与减少动态效果、8 语言与时间格式、与上游插件版共存的锁语义、配置迁移与双向导入。里程碑随之上调（S1 +1、S10 +1、S12 +1），合计 **63 人日**。
> **变更（v2.11）**：确认 **3065 是 Agent2API 的固定端口、不能动** → 新增 §10.1.4 三条共存方案（推荐新建第二条隧道把 52009 单独引出去，原隧道零改动）；新增 **§15 遗漏补齐**（手势冲突矩阵、救援与安全模式、音频会话、通知落地、性能内存预算、测试策略、隐私、发布回滚、上游同步）；新增 **§16 分步执行流程 S0–S12**（每步产出物 / 验收 / 人日 / 记忆点编号），把里程碑细化成可开工的步序，合计 60 人日。
> **变更（v2.10）**：本机把上游 **dsh-pet 0.4.8 → 0.4.9 实测升级完成**（`pnpm add dsh-pet@0.4.9`，profile `~/.dsh/profiles/desktop`，包 116.8MB / 114 条 webm）。对账结果：**动画条目与权重 0 增 0 删**，§10.4 的映射表可原样沿用；新增三个配置键 `speechProvider`（值 `dsh`）、`notifyWhenFocused`、`environmentCity`，`voiceName` 变成 `edge/zh-CN-XiaoyiNeural` 这种 **provider/id** 形式，`pets[]` 多一个 `fixedEnabled`。语音依赖新增 `@andresaya/edge-tts`，也就是 0.4.9 的「语音服务注册制」落地方式。面板代码一律按 0.4.9 的键写，缺键走宿主默认。
> **变更（v2.9）**：**404 真因推翻**——dsh-pet **0.4.8 早就装在这台机器上并在跑**，DSH Web 在 **127.0.0.1:52009**；SakuraFrp 隧道本地端口填的 **3065 是 Agent2API**（`C:\Program Files\Agent2API\agent2api.exe`），所以外部请求根本没打到 DSH。§2.4 全章重写为实测证据链；新增 §10.4 实测配置快照（**103 条动画条目**逐条列出，映射表据此锁定）。R17 从「未装插件」改为「隧道指错服务」。
> **变更（v2.8）**：R16 更正——iOS **能**震动（AudioToolbox / `UIImpactFeedbackGenerator` / CoreHaptics；上游那句只针对 Web `navigator.vibrate`）；R7 按你的决定记为中（隧道**不加**访问密码 → Tailscale 设为首选）；§10.1 明确 A/B/C 是**三条彼此独立的连接**、面板单选 + 优先级回落；§6.2 组10 补「连接存档 / 配对串 / 优先级」，组12 补「按类型+时间筛选导出」；新增 §2.4.1 云电脑装插件三步与双向验收。
> **变更（v2.7）**：定因 404——云电脑**没装 dsh-pet 插件**（Whaleness 走的是另一条腿 mobile-gateway）；新增 §2.4 两条路线对比、§10.1.3 与 dsh-mobile 的取舍、§6.10 三档重置、§6.11 语音目录驱动；按上游 `CONFIG.md` 对账补齐 15 组设置（`sizePercent`/四角双轴/pet pack/10 项物理/动画权重/三类刷新/三类台词/`notifyWhenFocused`/`chatAnimationEnabled`/`environmentCity`），新增 R16–R19。
> **变更（v2.6）**：读上游 `API.md` 校正——**`/dsh-pet-7340` 下没有 `/health`**（`{"error":"not-found"}` 属正常），桥接判据与轮询改 `/state` 长轮询；新增 §10.1.2 上游接口速查与锁纪律；新增 §6.7 底部版本区/检查更新/一键重置、§6.8 尺寸实时滑块、§6.9 面板全中文映射；§4.5 版本注入与更新流程；语音改为优先复用 DSH 的 `/voice/*`。
> **变更（v2.5）**：读 SakuraFrp 隧道截图定死参数——**DSH 本地端口 3065**（面板默认值改 3065）、TCP→42429、自动 HTTPS、访问密码为空（R7 升为高）；自检改为**零终端 Safari 三连**；新增 §10.1.1 实例参数表。
> **变更（v2.4）**：`preferenceloader` **真机确认已装**（R3 关闭，主入口成立）；桥接改为**内网 1 种 + 外网 2 种**（Tailscale P2P / SakuraFrp 隧道域名），支持粘贴 `wss://…/ws/mobile` 自动推导基址、四步传输探测、WSS 只读实验模式；新增 R14/R15；M7 6 人日，合计 55。
> **变更（v2.3）**：素材包**清理/存储管理**（§9.6）、**语音设置页 UI 细化**（§6.6，TTS 主 + STT 实验）、Relaxin 基线锁定 **0.5.7**、**云电脑场景 → 外网优先**的连接向导与预填策略（§10.1）、`preferenceloader` 判定补充实测线索（§2.3）。里程碑 M6/M8 各 +1 天，合计 54。
> **变更（v2.2）**：双包矩阵（roothide + rootless，arm64/arm64e fat）、下载进度条与断点续传 UI、日志保留 1–3 天（默认 1 天）与导出、素材包定 1080p≈100MB、DSH 地址端口设置内自定义 + 外网走 Tailscale、语音路线定为 TTS 先行。
> v2.1 已含：去 TrollStore 伴生 App、设置按真实功能重设 13 组、四类日志与三腿崩溃捕获、素材下载器、Relaxin 站点分析。

---

## 0 TL;DR

- **产物两个 deb，二进制同一份**：roothide 版（给 Relaxin）+ rootless 版（给 Dopamine/palera1n）；dylib 为 **arm64 + arm64e fat**，你的 iPhone 14 Pro 直接命中 arm64e。没有 App、没有 IPA、不需要 TrollStore。
- **宠物住在 SpringBoard 里**：注入 SpringBoard，一层高层级透明 `UIWindow` 铺在所有界面之上，常驻、不抢焦点。
- **渲染**：原生 `AVPlayerLayer` 播 HEVC-alpha `.mov`，透明、流畅、省电；webm 逐帧解码仅作兜底。
- **设置入口**：设置 App →「小肥娘」（PrefsBundle）；没装 `preferenceloader` 时自动降级为「长按宠物 → 设置」，功能一致。
- **日志**：运行 / 调用 / 错误 / 崩溃四类，保留 1–3 天可调（默认 1 天），支持**单文件导出与一键诊断包**。
- **素材**：deb 内置 3 段占位；完整包 **1080p ≈100MB**，设置里一键下载，带**总进度 + 单文件进度 + 速度 + 剩余时间**，可暂停/续传/换节点，内置 `ghfast.top`、`gh-proxy.com`。
- **联动**：地址/端口/Token 全在设置里填；外网两条独立腿（**Tailscale** / **隧道域名**），面板单选 + 存档 + 优先级回落；模型自定义（OpenAI 兼容）。
- **本机实测**：这台机器的 DSH 在 **`127.0.0.1:52009`**（`3065` 是 Agent2API，别混），dsh-pet **0.4.8** 已装并在线，`/state` 与 `/config` 都能直取（§2.4 / §10.4）。
- **工期**：iOS 58 人日（M0–M9），Android 另 16 人日。

---

## 1 目标与非目标

### 1.1 目标

| # | 目标 | 验收口径 |
|---|---|---|
| G1 | 桌面与所有 App 之上可见、透明、可拖动、会动 | 打开任意 App、回桌面，宠物都在且无黑底方框 |
| G2 | 保留上游核心功能 | 状态机、拖拽物理、多开、气泡、待办、余额、天气、工作状态、睡觉、表情包、语音齐备 |
| G3 | 设置面板齐全且热生效 | 13 组，改开关不重启 SpringBoard（标注需重启者除外） |
| G4 | 日志可查、可导出、崩溃可追 | 面板实时日志 + 三种导出 + 崩溃列表 |
| G5 | 素材可扩展、可续传 | 占位即装即用；完整包 1080p 可下、可停、可续、可校验 |
| G6 | 可联动远端 DSH | 局域网 + Tailscale 外网；断线降级不刷屏 |
| G7 | 每步可交付可回滚 | 自动版本号 + CI 出双包 + Release 附 SHA256 |

### 1.2 非目标

- 不做独立 App / 图标 / IPA / TrollStore 包（TrollStore 只在装 Relaxin 本体时用，与本项目无关）。
- 本轮不做 Android（排 M10）、不做 macOS/Windows。
- 不修改上游仓库；改动只进 `vbox-Ai/Little-fat-lady`。
- 不做商业分发（素材 CC BY-NC-SA，禁商用）。

---

## 2 环境事实

### 2.1 Relaxin 是什么（站点分析，Observed）

来源 https://relaxin.owngoal.dev/ 的 SPA bundle（`/assets/index-D8lsZzm5.js`，已拉取解析）：

| 项 | 值 | 证据 |
|---|---|---|
| 类型 | `type: roothide`，RootHide 系越狱 | bundle 常量 `pp=[["product","relaxin"],["type","roothide"],["released","2026-07-29"]]` |
| 最新版 | **0.5.7（2026-11-01）** | changelog 数组末项 |
| 支持表 | A10/A10X 16.1–18.7.1；A11 16.1–16.7.16；A12/A13 16.1–18.7.1 与 26.0–26.0.1；**A14–A16/M1–M2 16.1–17.3.1**；**A17 17.0–17.3.1** | `platforms` 表 |
| 套件 | 捆绑 Sileo 2.5.1-15；Irisin 4.7.2（tweak 转换/包管理）；Umbra 2.1；源为 OwnGoal Stripe | changelog 0.5.4/0.5.5/0.5.7 |
| 17.0 特例 | 出厂 iOS 17.0 需用 TrollStore 装的 TIPA 越狱 | changelog 0.5.1 |
| tweak 兼容 | **Irisin 已移除 rootless 支持** | changelog 0.5.5 |
| 越狱隐藏 | excluded apps / jailbreak hiding，可对指定 App 隐藏 | changelog 0.5.2/0.5.5 |

**目标机确认**：iPhone 14 Pro = **A16 / arm64e**，iOS 17.0 → 落在「A14–A16：16.1–17.3.1」正式支持区间。arm64e 是带 PAC 的 ABI，构建必须显式 `-arch arm64e`，且需要同时保留 arm64 以兼容旧包。

**版本基线**：以官网最新 **0.5.7（2026-11-01）** 为准，文档、探针、兼容性结论全部对齐该版本；后续 Relaxin 升级只复核三处——支持表是否变、Irisin 是否恢复 rootless、是否换 bootstrap 路径。

**`preferenceloader` 状态：✅ 已确认在（真机截图，2026-11-15）**。Sileo 搜索 `PreferenceLoader` 结果中多个源版本带绿色 ✓（已安装）：2.2.8·roothide repo·Dhinak G、2.2.8·BigBoss·Dhinak G、2.2.6-1·Procursus·Dhinak G、2.2.5·搬运工源·Dustin Howell。同时「设置」根页已有**「越狱插件」**与**「应用软件」**两个第三方分组 → 挂载点工作正常。

→ 结论：**主入口「设置 → 越狱插件 → 小肥娘」成立，R3 关闭**；长按宠物菜单仅作备用与快捷入口保留。

> 注意：真机上装了同一 bundle 的多个源版本（roothide/BigBoss/Procursus 各一份）。我们的 deb 只写 `Depends: preferenceloader`，**不锁版本、不写 `Conflicts`**，避免把人家的包搞崩。

**长按桌面弹窗另说**：电话助手那个面板是自己 hook SpringBoard 长按菜单（与我们"长按宠物 → 设置"同类技术），只能证明该机可装第三方 deb 且 hook 生效——现在有了上面两条正面证据，它退居旁证。

### 2.2 由此确定的六条

| # | 结论 | 落地 |
|---|---|---|
| C1 | **出两个 deb**：roothide（Relaxin 主用）+ rootless（Dopamine/palera1n 备用），**同一份 arm64+arm64e fat 二进制** | §4.4 打包矩阵 |
| C2 | 代码不硬编码 `/var/jb`：roothide 用运行时 `JBROOT()`，rootless 用 `/var/jb` | 统一宏 + 编译期分支 |
| C3 | 设置面板依赖 `preferenceloader` —— **已确认存在** | 主入口走「设置 → 越狱插件」；长按菜单作备用 |
| C4 | TrollStore 只是装 Relaxin 本体的工具 | 本项目产物与之解耦 |
| C5 | excluded apps / jailbreak hiding 可能让注入静默失效 | 首次启动自检注入，失败写 errors.log + 面板红条 |
| C6 | 同一设备**只能装一个变体** | 两个包互相 `Conflicts`，文档与面板都提示 |

### 2.3 M0 真机探针（先跑再写业务）

```bash
# P1 机型与系统
uname -a; sysctl -n hw.machine hw.model hw.ncpu hw.memsize; sw_vers
# P2 越狱根形态（roothide 关键目录）
ls -la /var/containers/Bundle/tweaksupport 2>/dev/null | head
ls -la /var/jb 2>/dev/null | head
# P3 已装包（注意是小写 L，不是数字 1）
dpkg -l | awk '{print $2" "$3}' | sort | head -80
dpkg -l | grep -Ei 'preferenceloader|ellekit|substrate|sileo|irisin|umbra'
# P4 注入库
ls -la /var/containers/Bundle/tweaksupport/usr/lib 2>/dev/null | head -40
# P5 设置面板挂载点
ls -la /var/containers/Bundle/tweaksupport/Library/PreferenceBundles 2>/dev/null | head
# P6 崩溃日志目录
ls -lat /var/mobile/Library/Logs/CrashReporter/ 2>/dev/null | head
# P7 arm64e 确认（装完 M1 空 tweak 后）
lipo -info /var/containers/Bundle/tweaksupport/Library/MobileSubstrate/DynamicLibraries/DSHPet.dylib
# P8 隧道可达性 —— 不需要终端，手机 Safari 直接开这三条：
#   https://dsh.vbox.ltd:42429/                        → 能开 DSH 界面 = 隧道通
#   https://dsh.vbox.ltd:42429/dsh-pet-7340/state      → 出 JSON = 桥接走 HTTP（首选）
#   https://dsh.vbox.ltd:42429/dsh-pet-7340/config     → 出 JSON = 同上，可读对方配置
#   注意：/dsh-pet-7340/health 不存在（会回 {"error":"not-found"}），别拿它当判据
#   结果对照：JSON→HTTP / 404 且带 not-found→对方 DSH 没装 dsh-pet / 转圈或报错→隧道或证书
# 有终端时的等价命令（可选）：
#   curl -sS -m 6 -o /dev/null -w '%{http_code}\n' https://dsh.vbox.ltd:42429/dsh-pet-7340/state
```

> `dpkg -l | grep -i preference` 的意思：`dpkg -l`（小写 L，list）列出已安装包，`grep -i preference` 过滤名字里含 preference 的行——用来确认有没有 `preferenceloader`（设置面板的宿主框架）。你之前打成 `-1`（数字一）会报"未知选项"，应是 `-l`。

判定表：

| 探针 | 结果 | 采用 |
|---|---|---|
| P5 有 PreferenceBundles 且 P3 有 preferenceloader | 是 | 设置主入口可用 |
| 同上 | 否 | deb 装 `preferenceloader` 依赖；装不上则用长按兜底 |
| P4 见 ellekit/libhooker | 是 | 按该 API 写；否 → 用 `%hook`（substrate 兼容层），M1 验证 |
| P2 见 tweaksupport | 是 | roothide 布局确认；见到 `/var/jb` 说明版本异动，回站点核对 |

### 2.4 404 真因：隧道指错了服务（v2.9 实测推翻前一版结论）

前一版写"云电脑没装 dsh-pet"，**错了**。我在这台机器上直接摸了现场：

| 事实 | 证据 |
|---|---|
| dsh-pet **已安装并正在运行** | `~/.dsh/profiles/desktop/node_modules/dsh-pet`，版本 **0.4.8**；进程 16492 = `electron.exe …\dsh-pet\runtime\electron-helper\main.js` |
| DSH Web 在 **52009**，不是 3065 | `netstat`：`127.0.0.1:52009 LISTENING` 属 `DeepSeek Harness.exe`（PID 11928） |
| **3065 是 Agent2API** | `127.0.0.1:3065` → PID 4232 = `C:\Program Files\Agent2API\agent2api.exe`；`GET http://127.0.0.1:3065/` 返回 `<title>Agent2API` |
| 宠物 API 在 52009 上**活的** | `GET http://127.0.0.1:52009/dsh-pet-7340/state` → **200**，返回 `{"counter":…,"sections":{balance,workStatus,notify,config,menu,focusSession,env}}` |

**结论**：SakuraFrp 隧道「本地端口」填的是 **3065（Agent2API）**，而 DSH 在 **52009**。外部打进来先落到 Agent2API，它当然没有 `/dsh-pet-7340/*`，于是回一个 `not-found` JSON。**不是插件没装，是隧道指错了门。**

### 2.4.1 正确拓朴（改一个字段）

```
手机 ──▶ dsh.vbox.ltd:42429 ──▶ SakuraFrp 节点 ──▶ 127.0.0.1:【52009】 ──▶ DSH Web + dsh-pet
                                              ✗ 现在填的是 3065 → Agent2API（无关服务）
```

修法（SakuraFrp 后台 → 隧道 #29655552 → 编辑 → 本地端口）：

| 改前 | 改后 |
|---|---|
| `[3065] 自定义` | **`[52009] 自定义`** |

保存后 frpc 会自动重载，无需重启隧道。然后浏览器开 `https://dsh.vbox.ltd:42429/dsh-pet-7340/state`：

| 现象 | 含义 |
|---|---|
| `{"counter":…,"sections":…}` | ✅ 通了，宠物桥接可用 |
| `{"counter":…}` 但 `sections` 少 | 插件版本差异，按实际字段降级 |
| 仍 `not-found` | 端口没生效（frpc 未重载）或隧道指向了别的实例 |
| `401 dsh web authentication required` | 正常——DSH **根路径**要令牌；`/dsh-pet-7340/*` **不需要**，直连这条即可 |

> 不建议反过来把 DSH 改到 3065：3065 已被 Agent2API 占着 `0.0.0.0`，会打架。
> 也不必为此加访问密码：pets 接口本身无鉴权，但只能看到宠物状态（余额档位、工作状态、待办标题），改不了 DSH 会话（R7 已记为中）。

### 2.4.2 升级与回退

- 现装 **0.4.8**，npm 最新 **0.4.9**（2026-11-14）。**先别升**：0.4.9 重做了语音服务注册，动画池可能微调；等手机端映射锁死后再评估。
- 真要升：DSH 插件页点更新，或在该 profile 下 `npm i dsh-pet@0.4.9`，然后**完全退出 DSH 重开**。
- 回退：`npm i dsh-pet@0.4.8` + 重启 DSH。


---

## 3 总体架构

### 3.1 进程内五层

```
┌──────────────────── SpringBoard 进程 ────────────────────┐
│ L5 设置层  PrefsBundle(SwiftUI) ←→ overrides.jsonc（Darwin 热重载）│
│ L4 交互层  手势 / 拖拽 / 长按菜单 / 点击穿透                    │
│ L3 UI 层   气泡 / 台词 / 待办条 / 余额牌 / 表情包                │
│ L2 渲染层  AVPlayerLayer × N（HEVC-alpha，每只一个播放器）      │
│ L1 内核层  状态机 · 物理 · 配置 · 日志 · 网络 · 素材            │
│ L0 注入层  substrate 入口 → 等 UI 就绪 → 建窗                   │
└──────────────────────────────────────────────────────────┘
```

- 只注入 SpringBoard：窗口挂在其 `UIWindowScene` 上，天然压住所有前台 App；切 App 不重建、不占各 App 配额。代价是 SpringBoard 崩溃 = 桌面重载，所以 L1 必须"轻且稳"（§8 的保守策略就是为此）。
- 多开：`PetInstance{window, player, physics, state}`，独立层级、共享素材缓存、位置各自持久化。

### 3.2 渲染与素材

| 项 | 选择 | 理由 |
|---|---|---|
| 主格式 | HEVC with alpha `.mov`（上游 assets-mov） | `AVPlayerLayer` 直出 alpha，硬解，1080p 不烫 |
| 兜底 | webm（VP9-alpha）逐帧 → `CALayer.contents` | 个别机型解码异常时切换 |
| 循环 | `AVPlayerItemDidPlayToEndTime` → `seek(.zero)`；切段前预热下一个 item | 消除接缝抖动 |
| 上限 | 同时活跃播放器 8 路（可配） | 每路 HEVC 约 20–40MB |

### 3.3 为什么砍掉伴生 App

设置只留设置内入口 → 省掉 IPA 构建、TrollStore 分发、App↔tweak 通道、双 UI 同步。代价是麦克风/语音识别不能靠 App 弹 TCC，处理见 R9 与 §6 语音组（结论：**TTS 先行，STT 后置为实验**）。

---

## 4 工程结构与构建

### 4.1 目录树

```
Little-fat-lady/
├─ README.md  LICENSE（上游 MIT）  LICENSE-ASSETS（CC BY-NC-SA + 署名清单）
├─ docs/
│  ├─ ENV.md                 # M0 探针实测（真机填写）
│  ├─ ARCH.md SETTINGS.md LOGGING.md
│  ├─ journal/STEP-01.md …   # 每步记录：目标/改动/验证证据/决策/风险/下一步
│  └─ upstream-sync.md
├─ packages/
│  ├─ core/                  # 平台无关纯逻辑
│  │  ├─ state/ physics/ config/ logging/ net/
│  ├─ ios/                   # Tweak.xm / *.swift / Resources / layout/DEBIAN
│  └─ ui/                    # SwiftUI 设置面板 + Entry.plist
├─ scripts/
│  ├─ version-bump.mjs  build-deb.sh  gen-asset-manifest.mjs  pack-assets.sh  ci-checks.sh
└─ .github/workflows/
   ├─ build.yml              # bump → test → deb×2 → release
   └─ assets.yml             # 上游新 tag → 重打 anim-pack → 发布
```

### 4.2 deb 内容

| 路径 | 内容 |
|---|---|
| `/Library/MobileSubstrate/DynamicLibraries/DSHPet.dylib` + `.plist` | 注入体（arm64+arm64e fat），`Filter: com.apple.springboard` |
| `/Library/PreferenceBundles/DSHPetPrefs.bundle` | 设置面板（SwiftUI + Entry.plist） |
| `/Library/PreferenceLoader/Preferences/DSHPet.plist` | 设置 App 里的行 |
| `/Library/Application Support/DSHPet/builtin/` | 3 段占位素材 + 默认 config.jsonc |
| `DEBIAN/control` | `Package:`、`Depends: mobilesubstrate, preferenceloader`、`Conflicts:` 另一变体 |

用户数据（不进包）：`/var/mobile/Library/DSHPet/`。

### 4.3 版本与 CI

- 版本 `MAJOR.MINOR.PATCH-BUILD`，`BUILD = git rev-list --count HEAD`；tag `v0.1.0-<BUILD>`；机器人提交带 `[skip ci]`。
- 每次 push main：bump → `ci-checks.sh`（core 单测 + 设置 schema + 日志字段字典）→ **并行构建两个 deb** → Release 附 `*.deb`、`SHA256SUMS`、`CHANGELOG.md`、必要时 `anim-pack`。
- 版本一致性断言：面板显示 = `session.json` = `env.json` = dpkg 元数据。

### 4.4 打包矩阵（本版重点）

| 产物 | scheme | 适用越狱 | 包名 | 根路径 |
|---|---|---|---|---|
| `LittleFatLady_<ver>_iphoneos-arm64.deb` | **roothide** | Relaxin（你的机器） | `com.vboxai.littlefatlady` | `JBROOT()` 运行时解析 |
| `LittleFatLady_<ver>_iphoneos-arm64-rootless.deb` | **rootless** | Dopamine / palera1n rootless | `com.vboxai.littlefatlady.rootless` | `/var/jb` |

```make
# 共同部分
export TARGET = iphone:clang:latest:15.0
export ARCHS  = arm64 arm64e          # ← arm64e 必带，iPhone 14 Pro 使用
export DEBUG  = 0
TWEAK_NAME = DSHPet
DSHPet_FILES = Tweak.xm DSHPetWindow.m DSHPetStage.m DSHPetPlayer.m DSHPetLog.m
DSHPet_CFLAGS = -fobjc-arc -fvisibility=hidden
DSHPet_FRAMEWORKS = UIKit AVFoundation QuartzCore WebKit CoreMotion UserNotifications

# rootless 变体
include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
# 构建时：make package THEOS_PACKAGE_SCHEME=rootless FINALPACKAGE=1

# roothide 变体：用 roothide/theos 分支编译，或 rootless 产物过 roothidepatcher
#   make package THEOS_PACKAGE_SCHEME=rootless  →  roothidepatcher packages/*.deb
```

CI 两个 job 各自 `make package`，产物分别命名；Release 同时上传，`SHA256SUMS` 里各一行。
验收命令（装完真机跑）：`lipo -info …/DSHPet.dylib` 必须输出 `Architectures in the fat file: arm64 arm64e`。

> 两个变体 `Conflicts` 互斥；面板顶部会显示"当前变体 + 适配越狱类型"，避免装错。

### 4.5 版本注入与「检查更新」

CI 在构建前生成 `GeneratedVersion.swift`（`let kVersion = "0.1.0-57"`、`kBuild = 57`、`kCommit = "abc1234"`、`kBuildDate`），同一次构建编进 **tweak 与面板两侧**，保证二进制和面板永远同版本。

检查更新（面板底部按钮）：

1. `GET {mirror}{https://api.github.com/repos/vbox-Ai/Little-fat-lady/releases/latest}`（节点不支持 api 域时回落 Release 页面 HTML 解析）；
2. 取 `tag_name` / `assets[].browser_download_url` / `body`（更新说明）；
3. **按 BUILD 号比较**（纯递增整数，比语义版本可靠；`57 > 56`）；
4. 有新版本 → 弹「0.1.x-58 · 更新说明…」+「下载安装」；
5. 下载复用素材那套节点/续传/校验（§9.3），按当前变体自动选 `…-rootless.deb` 或主包；
6. 装完提示重启 SpringBoard；失败给错误码 +「复制诊断信息」。
7. 全程可取消，失败不影响当前版本运行。

---

## 5 上游代码复用映射

| 上游 | 处理 | 说明 |
|---|---|---|
| `shared/physics/*` | 原样移植 | 弹簧/边界/投掷惯性，零依赖 |
| `shared/state.ts`（22.9KB） | → `core/state` | 动画状态机 |
| `client/pet/animation/animation.ts`（13.1KB） | 改播放器实现 | 帧序列 → AVPlayer 段播放 |
| `client/pet/motion/drag.ts`（17.7KB） | 移植 | 含上游 0.2.11 的 busy 否决修复 |
| `client/bubble.ts`（26.3KB） | 移植 | 气泡排版/排队/停留 |
| `host/config/*` | → `core/config` | JSONC + 三层合并 + 校验 |
| `host/routes/*` | → `core/net` 客户端 | 只保留读接口 |
| `standalone/ai-provider/*` | 移植 | 自定义模型走这条 |
| `runtime/electron-helper/*` | 丢弃 | Electron 专用 |
| `assets/*` | 打包成 anim-pack | 见 §9 |

同步：只跟 `shared/` `client/pet/`；上游测试 232 项当回归门。

---

## 6 设置面板

### 6.1 入口

- 主：设置 App →「小肥娘」（PrefsBundle）。
- 兜底：长按宠物 0.6s → 菜单「设置…」→ 同一套 SwiftUI。
- 两者读写同一 `overrides.jsonc`，改完发 `com.vboxai.littlefatlady.reload`，tweak 热重载。

### 6.2 信息架构（15 组，按真实功能）

| 组 | 子项（控件） | 生效 |
|---|---|---|
| 1 总开关 | 启用 · 生效范围（桌面/所有 App/指定 App）· 排除列表 · 暂停全部动画 | 即时 |
| 2 宠物与多开 | 选择/新增（≤8）/删除 · 缩放 0.3–1.5 · 不透明度 · 层级 · 边距 · 位置记忆 · 重置位置 | 即时 |
| 3 外观与动画 | 速度 0.5–2.0 · 随机小动作频率 · 眨眼 · 走路样式 · 口型 · 表情包 · 字体 | 即时 |
| 4 交互与物理 | 点击/双击/长按项 · 刚度·阻尼·重力·反弹（4 滑条）· 投掷 · 落地回弹 · 点击穿透 | 即时 |
| 5 气泡与对话 | 样式 · 最大宽度 · 停留 · 碎碎念频率 · 台词包 · 语言（8）· AI 生成（开关+模型） | 即时 |
| 6 语音 | TTS 开关/服务/voice/语速/音量 · STT（实验）· 通知播报 · **权限状态与修复** | 即时 |
| 7 待办 | 显示 · 条数 · 动效 · 数据源（本地/远端）· 刷新间隔 | 即时 |
| 8 余额 | 显示 · 数据源 · 六档阈值 · 货币 · 刷新 · 脱敏（只显示档位） | 即时 |
| 9 天气与位置 | 显示 · 定位方式（手动城市/IP）· provider · 单位 · 刷新 | 即时 |
| 10 工作状态联动 | **连接方式单选（局域网 / 隧道域名 / Tailscale）** · 地址 · 端口 · Token · **连接存档三档（家里/公司/云电脑，一键切换）** · **粘贴配对串自动填** · 优先级回落 · 轮询 · 六态→动画映射 · 断线降级 · **测试连接** | 即时 |
| 11 睡觉 | 时段 · 夜灯 · 唤醒条件 · 一段/三段动画 | 即时 |
| 12 日志与诊断 ★ | 级别 · 模块过滤 · 实时日志 · 崩溃列表 · **保留天数 1/2/3** · **按类型+时间筛选后导出**（同 dsh-mobile `LogExportView` 的用法）· 诊断包 · 上限 | 即时 |
| 13 高级 | 配置目录 · 重载 · 导入/导出 · 重置 · 调试 HUD · 实验特性 · 变体信息 | 即时/需重启 |
| **14 宠物种类（pet pack）** | 按种类分组的列表 · 新建种类 · 每种类独立动画池与素材目录 · 该种类下多实例 · 删除（每种至少留一只） | 即时 |
| **15 屏宽收口（竖屏关键）** | `sizePercent` 1–100%（px 只作画框上限）· 四角 corner + marginX/marginY 双轴边距 · 单位换算预览 | 即时（重算需刷新） |

> **上游字段覆盖对账**（`CONFIG.md` 实读，逐项都能在面板里改，不用手写 JSONC）：
> `pets[]{id,size,sizePercent,balanceEnabled,display,position}`；物理 `gravity / elasticity / friction / power / topBounce / petCollision / collisionShake / tiltGravity / shakeThrow / hapticEnabled`；`animationWeights{idle,turn,move}`；`eventsRefreshSec{whisper,sleepTalk,balance}`；`notificationsEnabled`、`notifyWhenFocused`、`chatAnimationEnabled`、`environmentCity`；三类台词 `sleepStartTexts / sleepEndTexts / sleepRefuseTexts`；`animations{idle,turn,drag,clicks,moves{default{minDist,maxDist,margin,leadSec,tailSec},actions},categories,events,sleep}`。
> **`hapticEnabled` 更正（v2.8）**：iOS 原生**能震**——上游那句「iOS 不支持振动」只针对 Web 的 `navigator.vibrate`（Safari 不实现），不是原生能力。你的电话助手等插件能震就是证据。我们的实现三档：轻碰撞 `UIImpactFeedbackGenerator(.light)`、重落地 `.heavy`、甩出短震 `AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)`；要自定义波形用 `CoreHaptics`（iPhone 8 及以上）。失效条件只有三种：系统「设置→声音与触感→系统触感反馈」关闭、低电量模式、iPad（无马达）→ 面板给「震动强度：关/轻/中/强」，不可用时自动降级为视觉反馈（碰撞时轻微缩放）。
> `tiltGravity`（倾斜控重力）与 `shakeThrow`（摇一摇抛出）要用 CoreMotion，在 SpringBoard 里能拿到数据，但要单独申请运动权限，M3 实测后再定开关默认值。

> 行样式沿用系统 Inset Grouped（标题左、说明右、开关最右），条目全部按上表重做。

### 6.3 存储与生效

- 扁平 key（`appearance.speed`、`bridge.host`…），面板**只写** `overrides.jsonc`。
- 合并：包内 `config.jsonc`（只读、带注释）→ `overrides.jsonc` → 运行时；未知 key 忽略 + warn。
- 原子写（tmp + rename），schema 校验失败保留旧值并黄条提示。

### 6.4 视觉规格

系统原生分组表 + 自定义头卡（头像/版本/状态灯）；行高 44/60pt；品牌色 `#4C8DFF`；状态 绿`#34C759` 黄`#FF9F0A` 红`#FF3B30`；说明 13pt 次级灰两行；危险操作红色 + 二次确认；深色模式全量。

### 6.5 代码骨架

```swift
struct RootView: View {
    @StateObject var store = SettingsStore()
    var body: some View {
        NavigationStack {
            List {
                HeaderCard(store: store)
                Section { Toggle("启用小肥娘", isOn: $store.enabled) }
                Group {
                    NavigationLink("宠物与多开") { PetsView(store: store) }
                    NavigationLink("外观与动画") { AppearanceView(store: store) }
                    NavigationLink("交互与物理") { PhysicsView(store: store) }
                    NavigationLink("气泡与对话") { BubbleView(store: store) }
                    NavigationLink("语音") { VoiceView(store: store) }
                    NavigationLink("待办") { TodoView(store: store) }
                    NavigationLink("余额") { BalanceView(store: store) }
                    NavigationLink("天气与位置") { WeatherView(store: store) }
                    NavigationLink("工作状态联动") { BridgeView(store: store) }
                    NavigationLink("睡觉") { SleepView(store: store) }
                    NavigationLink("日志与诊断") { DiagnosticsView(store: store) }
                    NavigationLink("高级") { AdvancedView(store: store) }
                }
            }
            .navigationTitle("小肥娘")
        }
    }
}

struct SettingSpec { let key: String; let title: String; let note: String?
                     let kind: Kind; let def: Any
                     enum Kind { case toggle, slider(Double, Double), picker([String]), text, action } }
```

### 6.6 语音页设计（TTS 主 / STT 实验）

原则：**一页两分区，TTS 开箱即用，STT 明标实验**。所有项都有说明行，不让人猜。

```
语音
┌ 状态卡 ────────────────────────────────────────────┐
│ TTS  系统语音包 ✓ 已就绪 · 当前音色「婷婷」          │
│      [试听]                                         │
│ STT  🔴 未授权（麦克风）  [去修复]  ← 实验           │
└────────────────────────────────────────────────────┘
▸ TTS 播报
    播报总开关                      ●───
    引擎              系统语音 ▾（系统语音/DeepSeek TTS/自定义/关闭）
    音色              婷婷 ▸        [试听]
    语速              1.0 ──●────  (0.5–2.0)
    音高              1.0 ──●────
    音量              跟随系统 ▾
    播报范围 ▸        台词 / 通知 / 待办 / 余额变化 / 状态切换 / 睡觉
    打断策略          排到队尾 ▾（排到队尾 / 打断当前）
    静音时段          23:00 – 07:00        ●
    失败降级          系统语音 → 静默 ▾   （并记 E_AI_* 入日志）
▸ 语音输入 STT（实验）
    启用                        ○──      ← 默认关
    说明  越狱环境没有 App 帮你要麦克风权限，需写入 TCC 条目，可能影响稳定性。
    引擎              系统语音识别 ▾（系统 / 自定义 Whisper 兼容 endpoint）
    Endpoint          https://…（引擎=自定义时出现）
    语言               中文（普通话） ▾
    触发方式           长按宠物说话 ▾（长按 / 悬浮按钮 / 双击）
    录音上限           10s ──●────
    识别后             先给我确认再发送 ▾
▸ 高级
    合成缓存           12.3MB  [清理]
    请求超时           15s ──●────
    语音日志           查看（跳「日志与诊断」，已按 mod=voice 过滤）
```

交互细节：

| 场景 | 行为 |
|---|---|
| 切到「DeepSeek TTS / 自定义」但没填 Key | 行内红字「未配置服务 → 去配置」，点进去直接落到填 Key 的子页，不弹错误框 |
| 试听 | 用固定样例句「今天也要好好干活呀」当场播，1s 内出声，失败就地显示错误码 |
| 系统语音包未下载 | 状态卡黄条 + 「前往系统设置下载」 |
| STT 权限缺失 | 只显示红色状态与「去修复」；点了才走 §8 的日志记录与 TCC 写入引导，不静默失败 |
| 任何一项改动 | 立即写 overrides + 热重载，不需要返回上级 |

```swift
struct VoiceView: View {
    @StateObject var s: SettingsStore
    var body: some View {
        List {
            Section { VoiceStatusCard(s: s) }
            Section(header: Text("TTS 播报")) {
                Toggle("播报总开关", isOn: $s.ttsEnabled)
                Picker("引擎", selection: $s.ttsEngine) {
                    Text("系统语音").tag("system"); Text("DeepSeek TTS").tag("deepseek")
                    Text("自定义").tag("custom"); Text("关闭").tag("off")
                }
                NavigationLink("音色") { VoicePickerView(s: s) }
                SliderRow("语速", value: $s.ttsRate, range: 0.5...2.0)
                NavigationLink("播报范围") { SpeakScopeView(s: s) }
                Toggle("静音时段", isOn: $s.quietEnabled)
            }
            Section(header: Text("语音输入 STT（实验）"), footer: Text("越狱环境需写入麦克风权限，可能影响稳定性")) {
                Toggle("启用", isOn: $s.sttEnabled)
                if s.sttEnabled { STTDetailView(s: s) }
            }
            Section("高级") { CacheRow(); SliderRow("请求超时", value: $s.ttsTimeout, range: 5...60) }
        }
        .navigationTitle("语音")
    }
}
```

先做 TTS 的理由见 §14.1 第 14 条；STT 的权限代价见 R9。

---

### 6.7 底部信息区与三个操作

```
│  …设置项…                            │
│  ───────────────────────────────     │
│  版本 0.1.0-57（最新）     [检查更新] │
│  变体 roothide · arm64e · iOS 17.0    │
│  [ 重置所有设置与数据 ]               │
```

- **版本号常显**：`0.1.0-<BUILD>`，**BUILD 跟随仓库自动递增**（CI 注入，见 §4.5）；长按可复制；与 `dpkg -l`、`session.json`、诊断包 `env.json` 四处必须一致（CI 断言）。
- **检查更新**：点一下 → 走镜像节点取仓库最新 Release → 比 BUILD 号 → 弹更新说明 → 一键下 deb 并交给 Sileo/`dpkg` 安装（细节 §4.5）。
- **重置还原**：二次确认 + 输入 `RESET` → 清空 `overrides.jsonc`、日志、崩溃、诊断包、已下载素材、TTS 缓存 → 恢复包内默认配置 → 提示重启 SpringBoard。**只清用户数据，不卸载插件**；"连插件一起删"走 Sileo 卸载。

### 6.8 宠物尺寸（实时滑块）

- 范围 **0.3–1.5**，步进 0.01，右侧实时显示 `0.85×`；
- 拖动过程中节流 16ms **直接改 `pet.scale`**（内存生效，不写盘），松手才落盘 → 所见即所得；
- 快捷档位：小 0.6 / 中 0.85 / 大 1.2；双指捏合同步同一参数；
- 下界保护：< 0.5 时气泡字号、表情包尺寸按下限缩放，避免糊成一团。

### 6.9 文案：全中文

面板（尤其「日志与诊断」）不出现英文原始字段，module / evt / lvl / err_code 一律走映射表，未命中显示「其它（原始值）」。

| 原始 | 中文 | 原始 | 中文 |
|---|---|---|---|
| inject | 注入 | render | 渲染 |
| physics | 物理 | bubble | 气泡 |
| voice | 语音 | ai | 模型 |
| net | 网络 | assets | 素材 |
| config | 配置 | prefs | 设置 |
| sleep | 睡觉 | hud | 性能 |
| crash | 崩溃 | bridge | 联动 |

级别：`debug→调试`、`info→信息`、`warn→提醒`、`error→错误`。
错误码：`E_NET_TIMEOUT→网络超时`、`E_ASSET_404→素材文件不存在`、`E_AI_AUTH→模型鉴权失败`…（CI 校验每个错误码都有中文，缺一个就构建失败）。
时间列用 `HH:mm:ss.SSS`，日期分组显示「今天/昨天/11月14日」。

---

### 6.10 「重置」要分三档（别混一起）

| 档 | 按钮 | 做什么 | 后果 |
|---|---|---|---|
| 轻 | 恢复本项默认 | 只把当前页面字段写回包内默认 | 其它设置不动 |
| 中 | **同步上游默认** | 用包内 `config.jsonc` **原文**（含注释与全部高级字段）整份覆盖本地 overrides | 与上游设置页「同步」等价；文件保留、可继续手改 |
| 重 | **完全重置** | 清 overrides + 日志 + 崩溃 + 诊断包 + 已下载素材 + TTS 缓存 → 回到初始安装态 | 二次确认 + 输入 `RESET`；只清数据，不卸载插件 |

### 6.11 语音：目录来自宿主，绝不硬编码

- 播报与识别**各自独立选实现**：`GET /voice/voices`（音色，`provider/音色` 限定 id）、`GET /voice/hear-providers`（识别实现）。
- 面板是"目录驱动"：拉列表 → 分组渲染 → 只存 id；目录为空时显示「宿主未提供语音服务」，而不是塞个默认值糊过去。
- **选中的实现被卸载后必须明确报错**（上游语义：不自动换一个替代）→ 我们照抄，错误码 `E_VOICE_PROVIDER_GONE`，日志写明原 id。
- 试听：`POST /voice/speak {text,voice}` 拿回音频，面板内即播（不落盘、不进缓存）。
- 说话内容仍走 `POST /broadcast`（第三方投喂，需 `?lock=`）或 `/whisper`（让它自己生成）。

---

## 7 配置系统

```
包内 /Library/Application Support/DSHPet/config.jsonc   ← 只读、带注释
   ↓ merge
用户 /var/mobile/Library/DSHPet/config/overrides.jsonc  ← 面板只写这层
   ↓ merge
运行时 不可变快照
```

`schemaVersion` 迁移；旧配置自动补默认；首次写入前备份 `overrides.bak.jsonc`。

---

## 8 日志与诊断体系 ★

目标：**不连电脑，在手机上就能说清"哪一步、哪个模块、什么错、崩溃前在干什么"，并且能把证据导出去。**

### 8.1 四类日志

| 类 | 文件 | 用途 | 默认级别 |
|---|---|---|---|
| A 运行 | `logs/runtime-YYYYMMDD.log` | 生命周期、模块事件、性能采样 | Info |
| B 调用 | `logs/calls-YYYYMMDD.log` | 每个功能入口：谁触发、参数摘要、耗时、成败 | 全开 |
| C 错误 | `logs/errors-YYYYMMDD.log` | 可恢复错误 + 错误码 | 全开 |
| D 崩溃 | `crash/*.json` + `crash/*.ips` | 自采快照 + 系统报告副本 | 全开 |

分 A/B 的原因：A 是时间线，B 是因果；排查"点了没反应"只看 B，排查"为什么崩"拿 B 的时间戳去 A 对齐。

### 8.2 布局、格式与保留策略

```
/var/mobile/Library/DSHPet/
├─ logs/runtime-20261115.log  calls-…  errors-…
│  ├─ session.json            # sid/bootID/pid/startTs/heartbeatTs/closed
├─ crash/index.json  20261115-041233-sb.json  SpringBoard-….ips
├─ diag/diag-20261115-041500.zip
└─ config/overrides.jsonc
```

行格式（JSONL，一事件一行）：

```json
{"ts":"2026-11-15T04:12:33.512+08:00","lvl":"info","mod":"render","evt":"player.ready","sid":"a1b2c3","dur_ms":12,"kv":{"file":"idle.mov","codec":"hevc"}}
{"ts":"2026-11-15T04:12:34.001+08:00","lvl":"info","mod":"call","evt":"pet.tap","src":"gesture","args":{"pet":"p1","zone":"head"},"dur_ms":3,"ok":true}
{"ts":"2026-11-15T04:13:02.220+08:00","lvl":"error","mod":"assets","evt":"download.fail","err":"HTTP 404","err_code":"E_ASSET_404","kv":{"node":"ghfast","retry":2}}
```

字段字典 `docs/LOGGING.md`（CI 校验）：`ts lvl mod evt sid pid dur_ms ok err err_code kv stack ctx`。
模块枚举：`inject render physics bubble voice ai net assets config prefs sleep hud crash`。
错误码前缀：`E_CFG_ E_ASSET_ E_NET_ E_AI_ E_DEC_ E_PERM_ E_INT_`。

**保留与容量（可配）**：面板 12 组提供「保留 1 天 / 2 天 / 3 天」，**默认 1 天**；按天分文件，过期自动删；单文件 2MB 轮转；每日上限 25MB，总量硬上限 = 天数 × 25MB（默认 25MB，最长 75MB）；到顶先丢最旧、再丢 debug 级。面板实时显示当前占用。
**限流**：同模块同 evt 1 秒内去重只记首次 + 计数；写盘走串行 `Utility` 队列，主线程只入环形缓冲，**日志不得阻塞 UI**。

### 8.3 崩溃捕获三腿

| 腿 | 做法 | 覆盖 |
|---|---|---|
| 1 钩子 | `NSSetUncaughtExceptionHandler` + `signal(SIGABRT/SEGV/BUS/ILL/FPE/TRAP)`：裸 `open/write/close` 写 256 条环形缓冲 + 状态快照（宠物数/播放器数/内存/FPS/最后动作）到 `crash/<ts>-sb.json`，**再 re-raise 交还系统** | 崩溃前上下文 |
| 2 心跳 | 启动写 `session.json`（bootID=kern.boottime+pid），每 5s 更新；正常退出写 `closed:true` | OOM、watchdog 强杀、内核 panic → 用"未闭合会话"反推时间与阶段 |
| 3 系统报告 | 启动 30s 与每 5min 扫 `CrashReporter/`，按时间窗 + `SpringBoard` 匹配，复制并解析 exception type / termination reason / 栈顶 8 帧 / watchdog | 符号化栈与终止原因 |

钩子纪律：只用 async-signal-safe 调用；不 malloc / 不 NSString / 不 NSLog；快照上限 256KB，超了标 `truncated`；失败只丢一次，不重试不递归。

### 8.4 脱敏

Token/apiKey/Cookie → `sk-***`；URL 保留 scheme+host+path，query 去值；诊断包生成前展示文件清单待确认；上传默认关闭；导出包剥离密钥。

### 8.5 面板「日志与诊断」页

```
[级别] Debug │ Info │ Warn │ Error     [模块 ▾] [🔍]   [跟随 ●]
────────────────────────────────────────────────────────
04:12:33.512  ●  render   player.ready idle.mov codec=hevc 12ms
04:12:34.001  ●  call     pet.tap src=gesture zone=head 3ms ok
04:13:02.220  ●  assets   download.fail E_ASSET_404 node=ghfast
────────────────────────────────────────────────────────
[崩溃记录 (2)]  [导出日志]  [生成诊断包]  [清空]
[保留天数] 1天 │ 2天 │ 3天      占用 12.4MB / 25MB
```

**三种导出**：
1. **导出日志**：选类型（运行/调用/错误/全部）+ 时间范围 → 生成 `.jsonl` 或 `.txt`，ShareSheet 分享（隔空投送/文件/微信皆可）。
2. **生成诊断包**：zip = logs + crash + 配置（已脱敏）+ `env.json`（机型/iOS/Relaxin 版本/插件版本与变体/已装包列表/素材校验结果）+ `session.json`。
3. **复制最近 500 行**到剪贴板，方便直接贴给开发者。

崩溃页：时间 / 类型（exception·watchdog·oom·signal·unknown）/ 进程 / 栈顶 /「查看崩溃前日志」。

### 8.6 代码骨架

```swift
actor Logger {
    static let shared = Logger()
    private var ring = RingBuffer<Entry>(capacity: 256)
    func log(_ lvl: Level, _ mod: Module, _ evt: String,
             kv: [String: String] = [:], err: Error? = nil, dur: Int? = nil)
    func flushSyncForCrash()          // 崩溃专用：裸 write
}

func call<T>(_ action: String, src: CallSource, args: [String: String],
             _ body: () throws -> T) rethrows -> T   // 功能调用统一入口
```

### 8.7 验收

1. 面板实时日志延迟 < 1s。
2. `kill -SEGV` 打崩 SpringBoard 后重启，崩溃列表 +1 且带栈顶。
3. 断网下载 → `E_NET_*` 入 errors，面板黄条，恢复后可续。
4. 改保留天数 1→3，旧文件不被立刻删，占用随天数增长不超上限。
5. 导出 `.jsonl` 在电脑上 `jq` 逐行可解析，无密钥。
6. 8h 长跑日志 ≤ 上限，FPS 不低于基线 95%。

---

## 9 素材包与下载器

### 9.1 分层

| 层 | 内容 | 体积 | 时机 |
|---|---|---|---|
| L0 占位 | 待机/移动/点击 3 段（480p HEVC-alpha） | < 8MB | 随 deb |
| L1 完整包 | 上游全量动画 **1080p** + 表情包 27 张 + 字体 | **≈100MB** | 设置里下载 |
| L2 自定义 | 用户自带 .mov/.webm | — | 手动导入 |

提供 720p（≈45MB）/480p（≈20MB）可选档，默认推荐 1080p。

### 9.2 镜像节点

```jsonc
"mirrors": [
  { "id":"ghfast",  "name":"ghfast.top",   "template":"https://ghfast.top/{url}",   "enabled":true },
  { "id":"ghproxy", "name":"gh-proxy.com", "template":"https://gh-proxy.com/{url}", "enabled":true }
]
```

`{url}` = 完整原始地址。可启用/停用、上下排优先级、新增自定义（带示例测试）、删除、一键测速。测速：各节点对同一文件 `Range: 0-102399` 计时，算 KB/s，选最快者；失败自动切下一个（最多 3 个轮换），全失败回落原始 URL。

### 9.3 下载流程

```
拉 manifest（走节点）→ 磁盘/网络预检（≥1.3×体积，蜂窝需确认）
→ 逐文件 Range 续传 → .part → sha256 校验 → rename
→ installed.json（版本/文件数/耗时/节点）→ 热装载素材索引（不重启）
```

并发 3 文件、单文件单连接；限速 0.5/1/2/不限 MB/s；重试退避 1s/3s/8s。

### 9.4 下载界面（进度与可恢复）★

```
素材包 · 完整动画（1080p）
┌──────────────────────────────────────────────┐
│ ████████████████░░░░░░░░  64.3 / 102.4 MB    │
│ 2.1 MB/s · 剩余 18s · 节点 gh-proxy.com       │
├──────────────────────────────────────────────┤
│ ✓ idle.mov            4.2MB   完成            │
│ ✓ walk.mov            5.1MB   完成            │
│ ⟳ sleep-loop.mov     12.8MB   62%  1.4MB/s    │
│ ⏸ talk-03.mov          9.7MB   等待           │
│ ✕ eat-01.mov          3.3MB   失败 E_NET_502  │
├──────────────────────────────────────────────┤
│ [暂停] [取消] [重试失败项] [切换节点 ▾]        │
└──────────────────────────────────────────────┘
```

- 顶层进度条 + 已下载/总量 + 实时速度 + ETA；单文件行显示大小、百分比、状态图标（等待/下载/校验/完成/失败/暂停）。
- 暂停保留 `.part`；取消保留已完成文件；重进页面自动恢复（读 `installed.json` + `.part`）。
- 锁屏/切后台：SpringBoard 常驻，下载继续；显示"正在下载素材 62%"通知；低电量模式自动降速到 512KB/s。
- 完成：toast + 面板徽标 + 自动热装载；校验失败的文件标红并提供"仅重下此项"。

### 9.5 我们的发布物

`pack-assets.sh`：上游新 tag → 转 HEVC-alpha → 生成 manifest（path/size/sha256）→ `anim-pack-<ver>.zip` → 发本项目 Release，用户下载不依赖上游资产可用性。

### 9.6 清理与存储管理（测试友好）

面板里单独一页「素材与存储」，把"占了多少、能删什么、删了会怎样"讲清楚——反复装包/换包测试时最需要这个。

```
素材与存储                                    共 214.6MB
┌ 占用明细 ──────────────────────────────────────────┐
│ 占位素材       7.8MB   ▏                            │
│ 完整包(1080p) 100.2MB  ████████████▏                │
│ 自定义素材     24.0MB  ███▏                         │
│ TTS 合成缓存   12.3MB  █▏                           │
│ 临时 .part     36.5MB  ████▏  ← 上次中断的残留       │
│ 日志+崩溃      13.8MB  █▏                           │
│ 诊断包         20.0MB  ██▏                          │
└────────────────────────────────────────────────────┘
  [清理临时文件]  [删除完整包]  [清理自定义素材]
  [清理 TTS 缓存] [清理日志/崩溃] [清空诊断包]
  [一键清理缓存（保留配置与自定义）]
  [重建素材索引]  [强制重新下载完整包]
```

规则：

| 动作 | 删除内容 | 保留 | 二次确认 | 影响 |
|---|---|---|---|---|
| 清理临时文件 | `*.part`、`tmp/` | 已校验文件 | 否 | 无（未完成的下载会从头开始） |
| 删除完整包 | 1080p 全量 | 3 段占位、配置、自定义 | 是 | 宠物退回占位动画，功能仍可用 |
| 清理自定义素材 | 用户导入的 mov/webm | 内置素材 | 是 | 对应宠物回落占位 |
| 清理 TTS 缓存 | 已合成音频 | — | 否 | 下次重新合成（首句延迟略增） |
| 清理日志/崩溃 | logs + crash | 当前会话日志 | 是 | 事后无法追溯，提示先导出 |
| 一键清理缓存 | 临时 + TTS + 日志 + 诊断包 | 配置、素材、自定义 | 是 | 释放最大空间，不动素材 |

- 每个动作执行前显示"将释放 XX MB"；执行后刷新占用并记 `assets.clean` 事件到 calls 日志（谁清的、清了多少）。
- **测试专用**（高级组里的调试开关打开后可见）：「模拟弱网（1s 限速 200KB/s）」「把节点置为失败」「伪造 sha256 不匹配」——用来验证续传、切换节点、校验失败重下三条链路，不必真拔网。
- 卸载 deb 不删 `/var/mobile/Library/DSHPet`（配置与素材留存），重装可续；彻底重置走高级组「重置全部」。

---

## 10 DSH 桥接与自定义模型

### 10.1 连接方式：内网 1 种 + 外网 2 种

| # | 场景 | 填写什么 | 前置 | 传输 |
|---|---|---|---|---|
| A | 局域网 | `http://192.168.x.x:3065` | 手机与主机同网段；DSH 监听 `0.0.0.0` | HTTP |
| **B** | **外网①·Tailscale（P2P）** | `http://100.x.x.x:3065` 或 MagicDNS `http://<host>.<tailnet>.ts.net:3065` | 两端同 Tailnet、同账号 | HTTP，不经第三方 |
| **C** | **外网②·隧道/域名（SakuraFrp、Cloudflare Tunnel、自建反代）** | `https://dsh.vbox.ltd:42429`（可带路径前缀） | 隧道已建；TLS 由隧道或源站终止 | HTTPS（+ 可选 WSS） |

> **A / B / C 是三条彼此独立的连接，不是同一条链路的三个参数。** 每条各有自己的地址、端口、Token、超时、启用开关与连通状态；**Tailscale 和隧道互不依赖**，可以只开其中一条，也可以两条都存着。
> 面板行为：单选「当前使用」的一条 → 其余按「连接存档」保存（家里 / 公司 / 云电脑三档，一键切）→ 可设**优先级回落**（例：Tailscale 超时 3s → 自动试隧道域名 → 都不通进离线模式，宠物照常动、不刷屏）。全部由你自主选择，面板不替你选。

### 10.1.1 你的 SakuraFrp 实例（截图实读）

| 字段 | 值 | 含义 |
|---|---|---|
| 隧道 | `#29655552 bxf` | 隧道 ID |
| 本地 IP | 本地主机 `127.0.0.1` | 回源地址 |
| 本地端口 | **`[3065]` 自定义** | **云电脑上 DSH 监听 3065**（不是 3080）→ 面板默认端口按 3065 预填 |
| 多端口穿透 | 禁用（默认） | 单端口映射 |
| 自动 HTTPS | 自动 | 节点侧提供 TLS 终止（有域名才生效）→ 表现为 `https/wss` 可用、回源明文 |
| 访问密码 | **空**（你的决定：不加） | 面板保留该字段但默认空、不预填；风险记入 R7（中），补偿见 §10.1.2 安全条 |
| 节点 | 重庆三线 PLUS4 / `frp-gap.com` | 免费节点，可能限速/排队 |
| 类型 · 远程端口 | **TCP · 42429** | 裸 TCP 转发到 3065 |

由此：外网基址 = `https://dsh.vbox.ltd:42429`，DSH 的 Web 与 `/dsh-pet-7340/*` 共用这个端口 → **HTTP 直连大概率可用**，不必先上 WSS。

**你的实测环境（C 类）**：SakuraFrp 隧道终点 `wss://dsh.vbox.ltd:42429/ws/mobile` —— 这是 DSH 移动端客户端连 WebSocket 用的地址。桥接面板**直接粘这个地址就行**，会自动推导。

**URL 自动推导规则**（粘贴即用，不让人改三遍）：

| 粘贴 | 推导结果 |
|---|---|
| `wss://dsh.vbox.ltd:42429/ws/mobile` | 去掉 `/ws/mobile` → 基址 `https://dsh.vbox.ltd:42429` |
| `https://dsh.vbox.ltd:42429/dsh-pet-7340/` | 去尾斜杠；识别已含 `dsh-pet-7340`，不重复拼 |
| `dsh.vbox.ltd:42429` | 补 `https://`（非 80 端口默认 https，可在「高级」改） |
| `http://192.168.1.10` | 补默认端口 **3065** |

**传输探测顺序**（「测试连接」一次跑完，逐条写进 `bridge.probe` 日志）：

> ⚠️ 上游 `API.md` 已证实：**`/dsh-pet-7340` 下没有 `/health`**（`/health` 只存在于"独立模式"的服务根上）。
> 所以你现在看到的 `{"error":"not-found"}` 是**正常现象**，不代表隧道坏——它恰恰证明「隧道通、请求到了 DSH、DSH 回了 JSON」。

1. `GET {base}/dsh-pet-7340/state` → 200 且是 JSON → **HTTP 可用（首选）**，按 §10.1.2 长轮询；
2. 若 `/state` 也 `{"error":"not-found"}` → **云电脑那台 DSH 没装/没启用 dsh-pet 插件**（路由整体不存在），面板提示"对方 DSH 未安装 dsh-pet"，桥接自动降级为离线模式；
3. `wss://{base}/ws/mobile` 握手成功 → **WSS 只读订阅（实验）**；
4. 全不通 → 分层报因：DNS 解析 / 连接被拒 / TLS 证书 / 401 / 404 路径前缀猜错，并给「换路径前缀重试」。

**WSS 模式（实验，默认关）**：直接订阅 DSH 移动端那条 WebSocket，只读事件流，提取「工作状态」「待办变更」两类事件驱动动画，30s 心跳兜底。风险明确：与官方客户端共用同一协议，可能互相踢线或影响会话；因此默认关闭、开启时红字提示、**只读不发命令、不复用客户端 token**（需单独填）。能用 HTTP 就永远不用它。

**路径前缀**可配（默认 `dsh-pet-7340`）；隧道若只映射到宿主根路径，前缀留空即可。

### 10.1.2 上游接口速查（我们真正要用的）

上游 `API.md` 契约完整，前端半侧只消费下面这几条：

| 用途 | 接口 | 要点 |
|---|---|---|
| 状态总口 | `GET /dsh-pet-7340/state` | 所有状态位唯一出口；叶子是 `{counter,data}`，**counter 变了才算更新** |
| 长轮询 | `GET /state?since=<counter>&timeout=<ms>` | 两者成对必填，上限 10s；有变立刻返回 → 用 8s 长轮询代替 2s 死轮询 |
| 工作状态（外部写入） | `POST /work-status {state,task?}` / `DELETE /work-status` | 正是"工作状态联动"要的东西：固定外部槽，最后写入者生效 |
| 待办 | `GET/POST /todos`、`PATCH/DELETE /todos/{id}` | 手机可增删，桌面端同步 |
| 余额 | `POST /balance` | 立即刷新一次，弹气泡 + 档位动画 |
| 天气环境 | `POST /environment` | 城市 + 天气；`?fresh=1` 跳缓存 |
| 说话 | `POST /broadcast?pet=&lock=`、`POST /whisper`、`POST /chat` | 第三方投喂 / 让它自己生成 / 对话 |
| 动作 | `POST /anim?pet=&lock=`、`GET /playback/{id}` | 点播动画 + 播放回执（可 `?wait=`） |
| 睡觉 | `POST /sleep` / `POST /wake` | 睡着期间自动与手动触发一律拒绝 |
| 占用锁 | `POST /lock?pet=` → `lockId`；`POST /lock/release` | 持锁期间它完全静止；`lock-lost` 带 `cause` |
| 语音 | `POST /voice/speak {text,voice?,rate?}`、`POST /voice/hear`、`GET /voice/voices` | **TTS/STT 优先复用 DSH**：手机只播放/录音，音色目录别硬编码 |
| 配置 | `GET/PUT/POST /config`、`GET /config/meta` | `POST /config` 就是上游的"恢复默认" |

三条纪律：

1. **不改对方配置**：手机端只读 `/config`（用于对齐动画名），要改只在本地 overrides 里镜像，绝不 `PUT /config` 覆盖云电脑；
2. **要动它就上锁**：`/broadcast`、`/anim`、`/position`、`/throw`、`/bubble/clear` 都需 `?lock=`，用完立即 `release`，避免锁过期把宠物冻住；
3. **安全**：上游原文「只监听 127.0.0.1，且没有鉴权，请勿转发到公网」。你已决定隧道**不加访问密码**（R7 记为中），因此补偿：① 面板把 **Tailscale 设为首选**、隧道标「无鉴权」；② 允许填 `X-DSHPet-Token`，填了就带；③ 首启提示一次，可勾「不再提示」，不做二次拦截。

- 鉴权：`X-DSHPet-Token`（面板填，隧道/反代侧校验）+ 可选 Basic；Token 存 Keychain，日志脱敏。
- **安全红线**：SakuraFrp 免费隧道是明文转发，必须开 HTTPS 隧道 + Token，别把 DSH 裸在公网——DSH API 本身无鉴权。
- 轮询：工作状态 1–10s（默认 2s）、待办 30s、余额 60s、天气 15min；退避 1→2→4→8→30s，3 次失败进离线模式（本地台词包 + 缓存态，只记 WARN）。WSS 模式改为事件驱动。
- 状态灯：绿=已连（标注 HTTP/WSS），黄=降级/离线，红=鉴权失败；宠物头顶小云朵同步。

### 10.1.3 与 Whaleness（dsh-mobile）的关系与取舍

读了 `Clarklevis1995/dsh-mobile`（783★，Kotlin Multiplatform + SwiftUI，最新 v1.8.2 / 2026-11-14）：

| 它的做法 | 事实 | 对我们的意义 |
|---|---|---|
| 走 `dsh-plugin-mobile-gateway` 的 WebSocket | 网关是**云电脑上另装的一个插件**，不是 DSH 自带 | 所以它能连、我们不能——两条腿完全不同 |
| 帧只有 `sent` / `event`，带增量 patch（insert/append-text/remove…） | 为聊天流优化，协议在快速演进，无公开文档 | **不适合**拿来驱动"宠物状态"这种低频需求 |
| 网关"当前局域网协议不带鉴权；公网部署必须 TLS 和鉴权" | 官方自己承认 | 印证我们的 R7：隧道必须加密码/TLS |
| iOS 端内建 Tailscale 隧道控制器（`TailscaleTunnelController` / `TsnetTunnel`） | 它不是靠系统 Tailscale App，而是自己跑 tsnet | 我们做插件不适合塞 tsnet；**用系统 Tailscale App + 100.x 地址**更省 |
| 多网关存档（`MultiGatewayStore`）、配对串解析（`PairingPayloadParser`） | 家庭/公司/云电脑多档快速切换 | **已落地**：§6.2 组10「连接存档三档 + 粘贴配对串 + 优先级回落」 |
| 日志导出页（`LogExportView`） | 按类型 + 时间筛选后再分享 | **已落地**：§6.2 组12「按类型+时间筛选后导出」+ §8.5 三种导出 |
| 按住说话（只采 16kHz 单声道 PCM16，识别交主机） | 手机不算力、省电 | **已落地**：§6.6 STT 分区「按住说话」+ §6.11 语音目录驱动 |

> 这四样不是「挂在文档里备查」，而是**逐条进了面板设计**（组 10、组 12、组 6）。
| 语音按住说话：客户端只采 16kHz 单声道 PCM16，识别交给主机 `speech-input-v1` | **ASR 跑在云电脑**，手机不装模型 | 我们的 STT 同理：只负责录音 + 上传 `/voice/hear`，把算力留在家 |
| `LogExportView` 日志导出页 | 与我们的诊断页同构 | 交互可参考：按类型/时间筛选 + 分享 |

结论：**不要复刻 gateway 协议**。把 dsh-pet 插件装到云电脑上，用它的 HTTP 契约（§10.1.2）就够了；gateway 只在"哪天决定连 DSH 聊天流"时才有价值。

### 10.1.4 3065 必须留给 Agent2API —— 三条共存方案

前提已确认：`3065` 是 Agent2API 的固定端口，**不能动**；DSH 在 `52009`。两者要同时对外可达，就不能再改端口了，只能**加一条腿**。

| # | 方案 | 做法（全图形界面，不用终端） | 代价 | 取舍 |
|---|---|---|---|---|
| **①** | **新建第二条 SakuraFrp 隧道**（推荐） | 后台 → 隧道 → 新建：本地 IP `127.0.0.1`、本地端口 `52009`、类型 `TCP`、节点选同一台（重庆三线PLUS4）、远程端口填 `42430`（或让系统分配）→ 保存。后台会给出新的 `域名:端口`，形如 `https://dsh2.vbox.ltd:42430`。**原隧道 #29655552 一个字不改** | 需要账号还能再建一条隧道（免费版通常 2 条，以你后台「新建」是否可点为准）；两条隧道各自算流量 | ★★★ 主用 |
| ② | 现有隧道开「多端口穿透」 | 编辑 #29655552 → 多端口穿透模式 → 本地端口填 `3065,52009` | **会改掉 Agent2API 的对外地址**，你正在用的服务立刻受影响，且端口段映射变得不确定 | ✗ 不动 |
| ③ | **换腿：Tailscale（完全不碰 SakuraFrp）** | 云电脑与手机各装 Tailscale、登同一账号 → 云电脑查 `100.x.x.x` → 面板填 `http://100.x.x.x:52009` | 两端都要装 App；国内打洞成功率一般，走 DERP 中转时延迟 80–200ms | ★★ 备用腿 |
| ④ | 应急：Cloudflare Tunnel | 云电脑跑 `cloudflared tunnel --url http://127.0.0.1:52009` → 拿一个临时域名 | 国内访问 CF 不稳，只适合救急 | ★ 救急 |

**结论：走 ①。** 两条隧道互不干扰——3065 那条继续服务 Agent2API，52009 这条专供 DSH + 小肥娘。面板「连接存档」正好存两条：

| 存档名 | 地址 | 用途 |
|---|---|---|
| `Agent2API` | `https://dsh.vbox.ltd:42429` | 你现有的 API 网关，与本项目无关，**面板里只做备注不连接** |
| `DSH · 隧道` | `https://<新域名>:<新端口>` | 小肥娘的桥接主用 |
| `DSH · Tailscale` | `http://100.x.x.x:52009` | 备选腿（可留空） |

验收（手机 Safari，零终端）：

| 打开 | 期望 | 说明 |
|---|---|---|
| `https://<新域名>:<新端口>/` | `401 dsh web authentication required` | **401 是对的**：打到 DSH 了，根路径要令牌 |
| `https://<新域名>:<新端口>/dsh-pet-7340/state` | `{"counter":…,"sections":…}` | 桥接可用 |
| `https://dsh.vbox.ltd:42429/` | Agent2API 页面（照旧） | 证明原隧道没被影响 |

> 建完把新的 `域名:端口` 发我，我这边直接探一遍，两边对上才算数。

### 10.2 自定义模型

```jsonc
"ai": { "enabled": true, "baseURL": "https://api.deepseek.com/v1",
        "apiKeyRef": "keychain:ai.default", "model": "deepseek-chat",
        "temperature": 0.8, "maxTokens": 120, "timeoutMs": 15000,
        "stream": false, "systemPrompt": "你是一只住在手机里的鲸鱼娘…",
        "fallbackToLocal": true }
```

「测试连接」发 8 token 请求，显示首字延迟/总延迟；错误码 `E_AI_AUTH/RATE/TIMEOUT/BADREQ/PARSE` 入 errors.log。

---

### 10.4 实测配置快照（live `/config`，2026-11-15）

从 `http://127.0.0.1:52009/dsh-pet-7340/config` 实拉（7631 B，已存 `dsh-pet-config-live.json` / `dsh-pet-config-pretty.json`）。**手机的动画映射表就按这份锁死**，共 **103 条**动画条目：

| 组 | 条数 | 名称 |
|---|---|---|
| `idle` | 1 | 待机呼吸休闲 |
| `turn` | 1 | 东张西望 |
| `drag` | 1 | 被鼠标拖拽悬空反馈 |
| `clicks` | 5 | 开心跃动 / 害羞惊讶 / 傲娇生气 / 挠痒咯咯笑 / 元气挥手 |
| `moves.actions` | 3 | 螃蟹走路 / 原地漂浮踏步 / 原地左转奔跑（`minDist` 60–240、`margin` 20、`leadSec` 2、`tailSec` 2） |
| `categories[小动作]` | 18 | 悠闲哼歌 / 超大伸懒腰 / 原地敲击桌面互动 / 原地重力下蹲压缩 / 哈欠连天 / 原地小憩沉眠 / 女仆屈膝礼仪 / 被吓一跳 / 小幅度原地360度旋转展示 / 偷吃零食被抓住 / 用鲸鱼尾巴拍打地面 / 打瞌睡被惊醒 / 照镜子 / 整体换装试色 / 轻快记录 / 写代码 / 摇扇纳凉 / 晨间刷牙（权重 20） |
| `categories[玩耍]` | 27 | 玩魔方 / 玩玩具汽车 / 鲸鱼吐泡泡 / 跳抓头顶物品 / 玩游戏气急败坏 / 玩水枪 / 小提琴 / 蓝鲸现世 / 女仆舞 / 摇摆舞 / 宅舞 / 吹气球 / 动物环绕 / 放风筝 / 拆礼物 / 变鸽子 / 扑克魔术 / 抽陀螺 / 吹笛子 / 蝴蝶蜜蜂环绕 / 撸猫 / 凭空生花 / 骑木马 / 三球抛接 / 踢毽子 / 下五子棋 / 荡秋千（权重 20） |
| `categories[吃什么]` | 12 | 吃白饭 / 吃零食 / 吃Token / 早/午/晚餐 / 冰淇淋融化 / 大闸蟹 / 糖葫芦 / 长寿面 / 西瓜 / 涮火锅（权重 16） |
| `categories[时节]` | 21 | 被落叶淹没 / 中秋月饼 / 堆雪人 / 放烟花 / 粽子 / 年糕 / 青团 / 腊八粥 / 重阳糕 / 收红包 / 写福字 / 穿针乞巧 / 舞狮 / 讨糖南瓜灯 / 插茱萸赏菊 / 放河灯 / 萌化小幽灵 / 圣诞树 / 孔明灯 / 汤圆 / 饺子（权重 14） |
| `categories[文字]` | 2 | 是啊，吃什么 / 深度思考碎碎念（`noMirror: true`，不可镜像） |
| `events.balance` | 6 | 钱袋满溢 / 金袋叮当 / 钱袋如常 / 数金皱眉 / 袋空如洗 / 分文不剩 |
| `events.whisper` | 3 | 擦桌 / 发呆 / 对屏碎碎念 |
| `events.workStatus` | 6 | 思考冒泡 / 忙碌点按 / 清点归档 / 原地踱步张望 / 雀跃庆祝 / 垂头叹气冒汗 |
| `sleep` | 3 | 睡觉-开始 / 睡觉-循环 / 睡觉-起来 |
| `baifan`（吃白饭） | 5 | 开心小跑 / 侧身急躁跑 / 期待开饭 / 吃饭·碗饭 / 吃饭团 |

其余实测参数（面板默认值照抄，不自己发明）：

| 键 | 实测值 |
|---|---|
| `pets[0]` | `{name:"蓝毛小女仆", id:"main", size:462, display:"both", position:{corner:"top-right",marginX:24,marginY:100}, balanceEnabled:true, whisperEnabled:true, workStatusEnabled:true}` |
| `physics` | `gravity:1400, restitution:0.78, groundFriction:2.5, ceilingBounce:true, throwPower:1, petCollision:true, **hapticEnabled:true, tiltGravity:true, shakeThrow:true**` |
| `animationWeights` | `idle:10, turn:5, move:5` |
| `eventsRefreshSec` | `balance:1800, whisper:300, sleepTalk:60` |
| `font` | `family:"candy", size:21, followPet:true`（对应上游 `上首软糖体.ttf`） |
| `voice` | 默认**关**；`voiceName:"zh-CN-XiaoyiNeural"`、`volume:1`；`voiceWhisper/Todo/Notify` 全 false |
| `chatAnimationEnabled` | **true**（对话时按语境挑动作表演）+ `chatMemoryRounds:10` |
| `memes` | **27 张**（吃白饭的大肥鱼 / 大的要来啦 / 死掉了 / 大烧货 / Ciallo …） |
| `workStatusTexts` | 6 组 × 3 句（思考 / 处理中 / 步完成 / 等确认 / 完成 / 出错） |

> 注意 `physics.hapticEnabled: true` 是上游默认值——**iOS 现在能真的震起来**（§6.2 注记），不用再置灰。
> 实测 `/voice/voices` 返回 200 与真实音色表（晓晓 / 晓伊 …）→ §6.11 的"目录驱动"已在线上验证；`/pose` 缺 `pet` 参数时返回 `{"ok":false,"reason":"pet-required"}`，说明多实例 API 已就位。

#### 0.4.8 → 0.4.9 实例升级对账（2026-11-15 实测）

| 项 | 0.4.8（升级前 live） | 0.4.9（升级后包内） | 影响 |
|---|---|---|---|
| 动画条目 | 114 | 114 | **0 增 0 删**，§10.4 表原样可用 |
| 分类权重 | 小动作18@20 / 玩耍27@20 / 吃什么12@16 / 时节21@14 / 文字2@10 | 完全相同 | 映射与权重不动 |
| events | balance 6 / whisper 3 / workStatus 6 | 完全相同 | 六档余额动画不变 |
| 配置键 | — | 新增 `speechProvider`(`dsh`)、`notifyWhenFocused`、`environmentCity` | 面板三项必须出现 |
| `voiceName` | `zh-CN-XiaoyiNeural` | `edge/zh-CN-XiaoyiNeural` | 解析成 `provider/id`，不认旧格式要兼容 |
| `pets[]` | 无 `fixedEnabled` | `fixedEnabled:false` | 多一个"固定不坠落"开关 |
| 依赖 | — | `@andresaya/edge-tts@^1.9.1` | 0.4.9 语音注册制的实现来源 |
| DSH 兼容声明 | — | 0.2.1-rc.3 / 0.2.2-alpha.2 / 0.2.2-rc.1 = compatible | 与本机 DSH 版本一致即可 |
| 包体积 | — | 116.8 MB（114 webm / 27 memes） | 素材下载包体积基线按此算 |

升级命令与回退：

```bash
# 升级（已在 2026-11-15 执行，profile 内 pnpm 11.28.5）
cd ~/.dsh/profiles/desktop && pnpm add dsh-pet@0.4.9
# 回退
cd ~/.dsh/profiles/desktop && pnpm add dsh-pet@0.4.8
# 清单备份
package.json.bak-v048 / pnpm-lock.yaml.bak-v048
```

副作用一条：pnpm 11 会把 `dsh-pet@0.4.9` 追加进 `pnpm-workspace.yaml` 的 `minimumReleaseAgeExclude`
（因为包太新、过了冷却阈值才允许装），这是它自己的供货链策略记录，不是脏数据，别手删。

> 升级后必须**完全退出 DSH 再打开**（含托盘退出）才会加载新 `lib/`；宠物 Electron 壳进程会随之重启。
> 验收：`GET http://127.0.0.1:52009/dsh-pet-7340/state` 的 `config` 段里出现 `speechProvider`，即 0.4.9 在跑。

## 11 里程碑

| M | 内容 | 交付物 | 人日 |
|---|---|---|---|
| M0 | 环境探针 + 仓库初始化 + LICENSE/署名 | `docs/ENV.md` | 2 |
| M1 | 骨架：空注入 + 透明窗口 + 双包 CI（roothide/rootless，arm64+arm64e） | 两个 deb 均可装、`lipo -info` 含 arm64e | 4 |
| M2 | 渲染：HEVC-alpha + 循环/切段 + 3 段占位 | 会动、无黑底、温度达标 | 6 |
| M3 | 物理与交互：拖拽/甩出/回弹/点击/多开 | 手感对齐上游 | 5 |
| M4 | 设置面板 13 组 + 三层配置 + 热重载 + **尺寸实时滑块/版本区/重置** | 改开关即刻生效 | 9 |
| M5 | 日志诊断：四类日志 + 三腿崩溃 + 三种导出 + 保留天数 | §8.7 六条通过 | 6 |
| M6 | 素材包：manifest + 多节点 + 续传 + **进度 UI** + **清理/存储页** | 弱网能下完 100MB、可续、可清干净 | 6 |
| M7 | 桥接与模型：内网 + 双外网 + URL 推导 + `/state` 长轮询 + 锁语义 + 检查更新 | 断网降级正确、粘贴即通 | 7 |
| M8 | 内容对齐：气泡 8 语言 + 待办 + 余额 + 天气 + 睡觉 + **语音（复用 DSH `/voice/*`）** + **pet pack 种类** + 动画名映射 | 功能对照表全绿 | 9 |
| M9 | 稳定验收：8h 长跑 + 内存 + 崩溃率 + 发布 0.1.0 | Release + 验收报告 | 4 |
| — | **iOS 合计** | | **58** |
| M10 | Android（WebView 悬浮窗 + 同 core） | APK + 行为对齐清单 | 16 |

---

## 12 风险

| # | 风险 | 概率 | 影响 | 对策 |
|---|---|---|---|---|
| R1 | SpringBoard 内日志/动画拖慢桌面触发 watchdog | 中 | 高 | 非阻塞日志、环形缓冲、播放器上限、M9 长跑门禁 |
| R2 | 崩溃钩子自身引入不稳定 | 中 | 高 | 只裸写 + re-raise + 体积上限 + 可关（关后靠腿2/腿3） |
| R3 | ~~目标机无 `preferenceloader`~~ **已关闭**：真机多源版本均带 ✓，设置内已有「越狱插件」分组 | — | — | 主入口成立；长按菜单降为备用 |
| R4 | roothide/rootless 双包工具链差异（路径、patcher、arm64e） | 中 | 高 | M1 先验"能装能加载"，CI 断言 `lipo -info` 含 arm64e |
| R5 | 素材 CC BY-NC-SA 禁商用 | 高 | 高 | LICENSE-ASSETS + README 置顶 + Release 说明 |
| R6 | 加速节点不稳（ghfast 在我机器就不通） | 高 | 中 | 双节点 + 自定义 + 回落原始 URL + 断点续传 |
| R7 | 外网桥接暴露面（隧道/域名） | 中 | 高 | **你已决定隧道不加访问密码**（2026-11-15）→ 面板把 Tailscale 设为首选、隧道标「无鉴权」、首启提示一次；可选填 Token；不做二次拦截 |
| R8 | HEVC-alpha 个别机型解码异常/发热 | 低 | 中 | webm 逐帧兜底；面板可切后端 |
| R9 | 无 App 后麦克风 TCC 拿不到 | 高 | 中 | TTS 不依赖麦克风，先做；STT 标实验并提供"权限修复"（越狱侧写 TCC，需 root helper） |
| R10 | 上游改版漂移 | 中 | 中 | 只跟 shared/client + 上游测试当回归 |
| R11 | 装错变体（roothide/rootless 混装）导致重复注入 | 中 | 高 | `Conflicts` 互斥 + 面板显示变体 + 安装文档图示 |
| R12 | 100MB 下载在锁屏/切网时中断 | 中 | 中 | `.part` 续传 + 完整性校验 + 失败仅重下该项 + 蜂窝网确认 |
| R13 | 清理误删正在使用的素材或配置 | 低 | 中 | 二次确认 + 一键清理只清缓存类 + 配置与自定义素材不进一键清理 |
| R14 | WSS 模式与官方客户端抢同一连接（被踢/影响会话） | 中 | 高 | 默认关；只读不发命令；只做状态订阅；开启时红字警告并写日志 |
| R15 | SakuraFrp 等免费隧道限速/断流/域名变更 | 高 | 中 | 探测 4 步分层报因 + 断线退避 + 离线模式；域名变了只需改一个字段 |
| R16 | ~~iOS 无振动~~ **已更正**：iOS 原生能震（`kSystemSoundID_Vibrate` / `UIImpactFeedbackGenerator` / `CoreHaptics`），上游那句只针对 Web `navigator.vibrate` | 高 | 低 | 三档实现（轻碰撞 light / 重落地 heavy / 甩出短震）；失效仅限「系统触感反馈关闭 / 低电量 / iPad 无马达」→ 自动降级为视觉反馈 |
| R17 | ~~未装插件~~ **已更正**：隧道指错服务（3065=Agent2API）→ 全 404 | **已发生** | 低 | 实测插件 0.4.8 已装、DSH 在 52009；面板加「端口自检」：连续 3 次 `not-found` 时提示"对方端口可能不是 DSH"并给 52009 提示 |
| R18 | SpringBoard 内录麦克风缺 `NSMicrophoneUsageDescription` → 直接崩 | 高 | 中 | STT 默认关；实验路径=改 SpringBoard Info.plist + TCC 授权（需 root，M9 后再评估） |
| R19 | 上游 `config.jsonc` 字段漂移，动画池名字对不上 | 中 | 中 | 启动读 `GET /config` 对齐；名字命中率写进 runtime 日志，低于 80% 面板黄条提示 |

---

## 13 验收清单（M9）

- [ ] 桌面/App 内/设置内/锁屏唤醒，宠物均在且透明无方框
- [ ] 拖动惯性、甩出飞行、落地回弹手感与上游录屏一致
- [ ] 8 只同屏 FPS ≥ 55，内存增幅 < 300MB
- [ ] 13 组设置可改、可存、重启保持
- [ ] 日志实时可见；崩溃有条目；三种导出均可用；保留天数 1/2/3 生效
- [ ] 3 段占位可跑；完整包 1080p 可下（有进度/速度/ETA）、可暂停续传、可换节点、校验通过
- [ ] 素材与存储页六类清理各自生效、占用实时刷新、删完整包后回落占位仍可用
- [ ] 局域网与 Tailscale 均能取状态；断网降级不刷屏
- [ ] 自定义模型可测通；错误码明确
- [ ] `dpkg -l` 版本、面板版本、session.json、env.json 四处一致
- [ ] roothide / rootless 两个 deb 各在对应越狱环境装一次均正常；`lipo -info` 含 arm64e
- [ ] 卸载后 `/var/mobile/Library/DSHPet` 保留，重装可续

---

## 14 讨论纪要

### 14.1 已定

| # | 你的答复 | 落地 |
|---|---|---|
| 1 | 不用 TrollStore | 砍 App/IPA/TIPA（§1.2） |
| 2 | 设置 UI 按真实功能重做 | §6.2 十三组 |
| 3 | 必须有调用/错误/崩溃日志 | §8 全章 |
| 4 | 设置只在设置 App，无独立图标 | §6.1 主入口 + 长按兜底 |
| 5 | 3 段占位 + 下载完整包 + 自定义节点 + 双内置节点 | §9 |
| 6 | 家里/公司 DSH + 局域网 + 外网 + 自定义模型 | §10 |
| 7 | 仓库公开、保留 LICENSE + 署名 | §4.1、R5 |
| 8 | **roothide 与 rootless 都要打，且要 arm64e** | §4.4 双包 + `ARCHS = arm64 arm64e` |
| 9 | 下载要有进度条 | §9.4 总进度 + 单文件 + 速度 + ETA + 暂停续传 |
| 10 | 日志可导出，缓存 1–3 天，默认 1 天 | §8.2 保留策略、§8.5 三种导出 |
| 11 | 机型 iPhone 14 Pro | §2.1 目标机确认（A16/arm64e/17.0） |
| 12 | DSH 地址端口设置内自定义，外网走 Tailscale | §10.1 |
| 13 | 完整包 1080p ≈100MB | §9.1 默认档 |
| 14 | 语音先做哪个 | **TTS 先行**：不碰麦克风 TCC、失败可降级、感知强；STT 需权限且成本高，列 M8 之后实验项（R9）；UI 见 §6.6 |
| 15 | 完整包要有清理功能 | §9.6 素材与存储页（六类清理 + 一键缓存 + 测试用模拟项） |
| 16 | Relaxin 版本以官网最新为准 | 基线 0.5.7（§2.1） |
| 17 | 现在用云电脑，所以必须能外网连 | §10.1 三模式向导，B Tailscale 为云电脑首选，预填向导 |
| 18 | 电话助手长按桌面弹出面板 | 证明该机可装第三方 deb 且 SpringBoard hook 生效；但**不等于** `preferenceloader` 存在，判定法见 §2.1 |
| 19 | `preferenceloader` 已装（多源版本带 ✓），设置里已有「越狱插件」分组 | R3 关闭，主入口 = 设置 → 越狱插件 → 小肥娘（§2.1、C3） |
| 20 | 云电脑外网走 SakuraFrp：`wss://dsh.vbox.ltd:42429/ws/mobile` | §10.1 C 类隧道模式；粘贴自动推导基址 `https://dsh.vbox.ltd:42429` |
| 21 | 外网连接要分 2 种 | §10.1：外网① Tailscale P2P、外网② 隧道/域名（SakuraFrp/CF Tunnel/反代）；传输优先级 HTTP > WSS |
| 22 | SakuraFrp 隧道截图：本地 127.0.0.1:**3065** → TCP **42429**，自动HTTPS=自动，访问密码空，节点重庆三线PLUS4 | §10.1.1 实例表；面板默认端口 3065；R7 提到高（先设访问密码） |
| 23 | 不会用终端 | §2.3 P8 改成 Safari 三条 URL 自检法，全程零终端 |
| 24 | `/dsh-pet-7340/state` 也回 `not-found`；同机 Whaleness 能连 | 定因：云电脑**没装 dsh-pet 插件**（Whaleness 走的是 mobile-gateway，另一条腿）→ §2.4，推荐路线 A |
| 25 | 让我看 Whaleness（dsh-mobile）项目 | §10.1.3：它走 `dsh-plugin-mobile-gateway` WS + 增量 patch 协议；不复刻，改借它的多网关存档/配对串/日志导出/按住说话交互 |
| 26 | 重新审上游，找遗漏功能 | §6.2 对账表：补齐 `sizePercent` 屏宽收口、四角+双轴边距、pet pack 种类、10 项物理、动画权重、三类刷新周期、三类台词、`notifyWhenFocused`、`chatAnimationEnabled`、`environmentCity`；新增 R16–R19 |
| 27 | 版本号/检查更新/一键重置/尺寸滑块/日志全中文 | §6.7–6.9、§4.5；重置拆三档（§6.10） |
| 28 | 语音 UI 我设计 | §6.6 语音页 + §6.11 目录驱动（音色/识别实现都从宿主拉，不硬编码） |
| 24 | 宠物大小要能滑动调节、及时生效 | §6.8 实时滑块（拖动即变、松手落盘） |
| 25 | 设置底部要版本号，跟随仓库自动递增 | §6.7 + §4.5 CI 注入 `GeneratedVersion.swift` |
| 26 | 要检查更新，走节点下最新 deb | §4.5 六步：取 Release → 比 BUILD → 下载校验 → 安装 |
| 27 | 要一键重置还原 | §6.7 二次确认 + `RESET`，只清用户数据不卸载插件 |
| 28 | 日志页要全中文 | §6.9 模块/级别/错误码映射表，CI 强制校验 |
| 29 | 实测 `/dsh-pet-7340/health` 回 `{"error":"not-found"}` | **正常**：上游该前缀下无 `/health`（只在独立模式根上）；判据改用 `/state`（§10.1、P8） |
| 30 | 让我把云电脑的 dsh-pet 装上 | §2.4.1 三步流程 + 双向验收表；我无云电脑登录方式，需你操作 |
| 31 | 「我装的插件都能震动」= iOS 有震动 | R16 更正：原生能震，三档实现 + 三种失效条件（§6.2 注记） |
| 32 | 隧道不加访问密码 | §10.1.1 记为你的决定；R7 降为中；Tailscale 设首选 |
| 33 | 隧道与 Tailscale 是两条独立连接、面板自主选 | §10.1 新增「三条彼此独立 + 单选 + 优先级回落」 |
| 34 | 「这就是我的云电脑，插件你可以装」 | 现场核查：**dsh-pet 0.4.8 已装并在跑**；DSH 在 52009；3065 是 Agent2API —— §2.4 全章重写 |
| 35 | 真实 404 原因 | 隧道本地端口 3065 → 改 **52009**（§2.4.1） |
| 36 | 动画清单要锁死 | §10.4 实测 103 条动画 + 全部默认参数，映射表照抄 |
| 37 | 上游基线锁 **0.4.9**（2026-11-15 已升级） | 面板键按 0.4.9 写，含 `speechProvider`/`notifyWhenFocused`/`environmentCity`；`voiceName` 按 `provider/id` 解析 |
| 38 | 动画映射表沿用 §10.4 的 114 条 | 0.4.8→0.4.9 实测 0 增 0 删，不重做映射 |
| 39 | 升级/回退都走 profile 内 pnpm | `pnpm add dsh-pet@<ver>`；保留 `*.bak-v048` 清单备份 |
| 40 | 累计动画驱动 = 分类权重 + events + moves 距离参数 | 与上游 `animationWeights{idle,turn,move}` 相乘后再归一化，保持手感一致 |
| 41 | 3065 是 Agent2API 专用，不能在隧道里改成 DSH | §10.1.4：另建第二条隧道把 52009 引出去，原隧道零改动 |
| 42 | 手势保护区 | §15.1：顶部 40pt（通知/控制中心）、底部 34pt（Home 条）、左右 20pt（返回）一律透传 |
| 43 | 通知与音频策略 | §15.3/§15.4：音效走 `.ambient` 尊重静音；TTS 用 `.playback`；通知优先 UNUserNotificationCenter，兜底气泡+震动 |
| 44 | 开发流程固化为 S0–S12 | §16：每步 journal + 记忆点 + 证据三件齐，合计 60 人日 |

### 14.2 仍需你提供

| # | 问题 | 用途 |
|---|---|---|
| Q1 | Safari 打开 `https://dsh.vbox.ltd:42429/dsh-pet-7340/state` 的结果（JSON / 同样 not-found / 打不开） | JSON→HTTP 桥接；not-found→云电脑没装 dsh-pet（`/` 能开就是隧道好） |
| Q2 | ~~是否愿意给隧道加访问密码~~ **已答：不加**（记入 §10.1.1 / R7 中） | — |

### 14.3 下一步

1. 我推 M0 骨架：空 tweak + 两个 scheme 的 CI + 探针脚本 + LICENSE/LICENSE-ASSETS；
2. 你装上跑 §2.3 七条，贴回输出；
3. 填 `docs/ENV.md` 后进 M1/M2。

> 未经你确认不写业务代码。

---

## 15 遗漏补齐（v2.11 自查结果）

前 14 章是"要做什么"，这一章补"哪里会翻车"。逐条都是能在真机上把人坑住的点。

### 15.1 触摸与系统手势冲突矩阵（最容易废掉整台手机的地方）

宠物窗口铺在所有界面之上，**必须给系统手势让路**，否则用户下拉不了控制中心、上滑回不了桌面。

| 区域 | 系统行为 | 我们的规则 |
|---|---|---|
| 顶部左侧 0–40pt × safeTop 高度 | 下拉「通知中心」 | `hitTest` 直接返回 nil，永不接管 |
| 顶部右侧同区 | 下拉「控制中心」 | 同上 |
| 底部 Home 条上 34pt | 上滑回桌面 / 切换 App | 同上；宠物漫游地面线自动上移 34pt |
| 左右边缘 0–20pt | 返回手势 | 同上（宠物贴边时向内缩 20pt） |
| 长按空白处 1s | 进入图标抖动/编辑模式 | 检测到 SpringBoard 编辑态 → 宠物 `isHidden = YES`，退出编辑态再显示 |
| App 切换器（上滑停住） | 多任务卡片 | 宠物隐藏（避免遮挡缩略图） |
| 来电 / 闹钟 / 全屏视频 | 系统接管 | 监听 `SBUIController` / `AVPlayerViewController` 前台 → 隐藏，结束恢复 |
| 键盘弹出 | 输入框上移 | 宠物**不跟随**键盘（键盘属于 App，不属于桌面） |
| 录屏 / 截图 | 合成结果包含宠物 | 默认包含（是加分项）；面板给「录屏时隐藏」开关 |

实现要点：`hitTest` 里先算"保护区"（上面 5 行），命中即 `return nil`；再算宠物/气泡/菜单矩形；其余一律透传。保护区尺寸随 `safeAreaInsets` 与横竖屏动态变。

### 15.2 救援与安全模式（你不会用终端，所以必须全图形）

| 场景 | 出路 |
|---|---|
| 宠物导致 SpringBoard 反复崩溃 | 崩溃熔断：5 分钟内 3 次启动失败 → 自动禁用本体 + 写 `crash.marker`，桌面照常可用 |
| 想立刻停掉宠物 | 长按宠物 3 秒 → 「紧急停止（1 小时）」；或设置面板总开关 |
| 已进安全模式 | 安全模式下 tweak 不加载，直接进 Sileo 卸载或改设置 |
| 彻底删掉 | Sileo → 已安装 → 小肥娘 → 卸载（deb 会带走 dylib 与面板） |
| 想手动删残留 | Filza 打开 `/var/mobile/Library/DSHPet/` 删目录；dylib 在越狱根 `Library/MobileSubstrate/DynamicLibraries/DSHPet.dylib` |

面板「高级」页要把上表直接写成中文说明，别让用户去搜索。

### 15.3 音频会话（点击音效 / TTS 不打架）

| 用途 | 做法 | 注意 |
|---|---|---|
| 点击音效 | `AudioServicesPlaySystemSound` + 短 wav | 走 `.ambient`，尊重静音开关，不打断用户正在听的歌 |
| TTS 播报 | `AVSpeechSynthesizer`（本地）或 edge-tts 音频 → `AVAudioPlayer` | 需要出声时用 `.playback`；面板给「跟随静音开关」选项 |
| 与音乐共存 | 不抢 audio focus，不 `setActive(false)` | 播报结束后 `setActive(false, .notifyOthersOnDeactivation)` |

### 15.4 通知落地（SpringBoard 里能不能弹）

- 首选：`UNUserNotificationCenter` 在本进程投递——**需 M0 实测**，SpringBoard 有系统通知权限，大概率可用。
- 兜底 A：直接弹自家气泡 + 震动（前台可见时最自然）。
- 兜底 B：`SBUserNotificationCenter` 私有 API（iOS 17 仍在，风险中）。
- 明确不做：远程推送、后台常驻唤醒。

### 15.5 性能与内存预算（写进验收，不靠感觉）

| 指标 | 目标 | 超标动作 |
|---|---|---|
| SpringBoard 主线程占用 | < 8%（3 只宠物） | 60Hz → 30Hz → 15Hz 逐级降 |
| 常驻内存增量 | < 150MB（3 只） | 缩预载池 3 → 2 → 1 |
| 掉帧 | < 1% | 降分辨率（1080p → 720p） |
| 冷启动到首帧 | < 1.5s | 首帧静态图垫底 |
| 待机耗电 | < 3%/h | 无交互 60s 后停解码，只留静态帧 |
| 热状态 | `thermalState >= .serious` 时降级 | 自动 30Hz + 停随机动作 |

采样：每 5s 写 `metrics.jsonl`（cpu / rss / fps / thermal），面板「日志与诊断」可看曲线。

### 15.6 测试策略（把上游 232 项测试变成我们的回归门）

| 层 | 手段 | 频率 |
|---|---|---|
| core 纯逻辑 | 直接跑上游 `src/**/*.test.ts`（232 项） | 每次 PR |
| 动画映射 | `animation-map.snapshot.json`（114 条 + 权重）快照对比，上游升级即报警 | 每次同步上游 |
| 配置 schema | 面板写入 → 读回 → 与上游 `config.jsonc` 校验器比对 | 每次 PR |
| 真机冒烟 | 12 条清单（见 §13） | 每次出包 |
| 稳定性 | 24h 挂机 + 随机拖拽脚本 + 切 App 500 次 | 每个里程碑 |
| 崩溃回归 | 读取 `.ips`，按符号聚合去重 | 每周 |

### 15.7 隐私与合规

- 不上传任何数据；日志只在本机 `~/Library/DSHPet/logs`。
- 诊断包导出前脱敏：token、URL query、IP、用户名替换为 `<redacted>`。
- 面板「关于」页必须写明：代码 MIT；形象素材 CC BY-NC-SA 4.0（**禁商用**）；原作者 `PC2005-cloud/dsh-pet`；本移植仓库 `vbox-Ai/Little-fat-lady`。
- 许可文件：仓库根 `LICENSE`（MIT）+ `LICENSE-ASSETS`（CC BY-NC-SA 全文 + 署名清单）。

### 15.8 发布、回滚与上游同步

| 项 | 规则 |
|---|---|
| 出包 | 每次 push main：bump → 双 deb + SHA256SUMS + CHANGELOG → Release |
| Sileo 源 | GitHub Pages 上 `Packages` / `Release` 索引，用户加源即可升级 |
| 回滚 | Release 永远保留上一版附件；面板「检查更新」允许选「装回上一版」 |
| 分支 | `main` 保护，功能走 `feat/*`，合并前跑 §15.6 全部回归 |
| 上游同步 | 每月一次 `upstream-sync`：只同步 `src/shared` 与 `src/client/pet/{animation,motion}`，跑 232 项回归 + 映射快照 diff，结果写 `docs/upstream-sync.md` |

---

## 16 分步执行流程（S0–S12，可开工版）

> 每步一个可验证增量。**关闭条件三件齐**：`docs/journal/S<xx>.md` 写完 + `MEMORY.md` 索引追加 + 验收证据（截图/日志/命令输出）落盘。缺一件不进下一步。

| 步 | 内容 | 产出物 | 验收（可复现） | 人日 |
|---|---|---|---|---|
| **S0** | 环境与基线 | `docs/ENV.md`（§2.3 八条探针实测）、上游 0.4.9 快照（`config.jsonc` + 114 条映射）、仓库骨架 + 双 LICENSE | 探针全部有结果；快照可 diff | 2 |
| **S1** | 空壳注入 | Theos 工程、双包 CI（roothide/rootless，arm64+arm64e）、日志目录 | 真机装上后 SpringBoard 日志出现 `[DSHPet] boot`；`lipo -info` 含 arm64e | 3 |
| **S2** | 透明窗口与锚定 | `DSHPetWindow` / `Stage`、scene 附着、锁屏与切 App 处理、保护区透传 | 打开微信/浏览器宠物都在；空白处点击正常；下拉控制中心正常 | 3 |
| **S3** | 单宠物渲染 | `AVPlayerLayer` 池（预载 3）、首帧预热、静态帧垫底 | 待机动画透明无黑底；冷启 <1.5s；主线程 <5% | 4 |
| **S4** | 动画链与状态机 | core 移植（state/weights/animation）、无缝衔接、转向与漫游 | 连续播放 30 分钟无接缝抖动；漫游边界正确 | 5 |
| **S5** | 物理与交互 | 拖拽/甩抛/互撞/挤压/点击、§15.1 手势矩阵、震动三档 | 与桌面版录屏逐条对照一致；系统手势全不冲突 | 5 |
| **S6** | 多开与 UI 层 | 多实例（≤8）、气泡、长按菜单、待办面板、表情包 | 3 只互撞 + 气泡跟随 + 菜单可点 | 6 |
| **S7** | 设置面板 | 15 组 + 三层配置 + 热重载 + 版本区 + 检查更新 + 重置三档 + 全中文 | 设置里每个开关即时生效；改完重启 SpringBoard 不丢配置 | 7 |
| **S8** | 日志与诊断 | 四类日志、三腿崩溃捕获、诊断包、导出、保留 1/2/3 天、清理页 | 人为触发崩溃能被捕获；诊断包可在面板分享 | 4 |
| **S9** | 素材下载器 | 分层（3 段占位 / 1080p 完整 / 自定义）、镜像测速、断点续传、sha256、清理 | 弱网断点续传成功；校验失败可重下；占用统计准 | 4 |
| **S10** | 内容能力 | 对话与碎碎念（BYO OpenAI 兼容）、TTS/STT、天气、余额、待办提醒、工作状态三模式桥接 | 断网外全可用；桥接连通后六档动画跟着变 | 8 |
| **S11** | 稳定性与打磨 | 熔断、看门狗、热节流、72h 压测、低电量策略、横屏 | 72h 不崩；§15.5 指标全达标 | 6 |
| **S12** | 发布 | Sileo 源、README/文档、§13 验收清单、双包发布、回滚预案 | 全新设备从加源到装上可用 <10 分钟 | 3 |

**合计 60 人日**（比 §11 的 58 多 2 天：S0 基线 + S12 发布细化）。Android 仍按 §11 的 M10 预留 16 人日。

依赖关系（不可跳步）：

```
S0 ─→ S1 ─→ S2 ─→ S3 ─→ S4 ─→ S5 ─→ S6 ─┬─→ S7 ─┐
                                   │        ├─→ S8 ─┼─→ S11 ─→ S12
                                   └────────┴─→ S9 ─┘
                                              S10 可与 S7/S8/S9 并行（依赖 S4 的状态机与 S6 的 UI 层）
```

**每步的记忆点写法**（照抄改）：

```markdown
# S05 · 物理与交互
- 目标：拖拽/甩抛/互撞/挤压 与桌面版手感一致，系统手势零冲突
- 改动：packages/ios/DSHPetGesture.mm、packages/core/physics/*
- 验收：docs/evidence/s05-drag.mp4（与桌面版并排）、s05-hit-test.txt（保护区判定日志）
- 决策：保护区固定 40/34/20pt，随 safeArea 动态调整
- 风险：横屏下 Home 条位置变化 → 已在 S11 补横屏用例
- 下一步：S06 多开与 UI 层
```

**本轮唯一卡点**：S0 里的 P8（外网可达）需要你先建好第二条隧道（§10.1.4 ①），否则 S10 的桥接只能在内网验。

---

## 17 v2.12 实测修订：42429 的真实归属与正确接法

### 17.1 现场拓扑（本机实测，2026-11-15）

| 端口 | 进程 | 作用 |
|---|---|---|
| `3065` | `C:\Program Files\Agent2API\agent2api.exe` (pid 4232) | Agent2API，**必须保留** |
| `52009` | `DeepSeek Harness.exe` (pid 11928) | DSH Web 主服务：`/` 返回 `401 dsh web authentication required`；**宠物插件 API 挂在它下面** |
| `3081` | 同一个 DSH 进程 | `dsh-plugin-mobile-gateway` 的 WS 端点 `/ws/mobile`，**Whaleness 走这条腿** |
| `7789` | `caddy.exe` (pid 16088) | TLS 终点 + 反向代理，证书 `certs/dsh.vbox.ltd.crt|.key` |
| `42429` | SakuraFrp 隧道 `#29715647 (name=DeepSeek)` → `127.0.0.1:7789` | 外网入口（当前） |
| `64329` | SakuraFrp 隧道 `#29655552 (name=bxf)` → `127.0.0.1:3065` | Agent2API 的外网入口 |

隧道清单（`GET https://api.natfrp.com/v4/tunnels?token=<token>`）：

| id | name | type | 本地 | 远程 | 备注 |
|---|---|---|---|---|---|
| 29655552 | bxf | tcp | `127.0.0.1:3065` | 64329 | `auto_https = auto` |
| 29715647 | DeepSeek | tcp | `127.0.0.1:7789` | 42429 | 指向 caddy，不是 DSH |

### 17.2 关键纠正（推翻 §10.1.4 之前的两种说法）

1. **`42429` 指向的是 caddy，不是 DSH**。所以早先所有 `{"error":"not-found"}` 是 caddy 背后的 **3081 网关**对非 `/ws/mobile` 路径的应答 —— 既不是 Agent2API，也不是"插件没装"。
2. **不能把这条隧道的本地端口改成 `52009`**：同一个 `42429` 还承载着 Whaleness 的 `/ws/mobile`，改了就把手机端会话切断。
3. 正确接法是**一层路径分流**：隧道保持 → `7789`，caddy 里加一条 `handle /dsh-pet-7340/*` 转 `52009`，其余仍转 `3081`。

### 17.3 已落地的 Caddyfile 改动

备份：`C:\Users\Admin\Documents\deepseek-harness\default-workspace\tools\caddy\Caddyfile.bak-20261115130334`

```caddyfile
{
	admin off
	auto_https off
}

dsh.vbox.ltd:7789 {
	tls "C:\\Users\\Admin\\Documents\\deepseek-harness\\default-workspace\\tools/caddy/certs/dsh.vbox.ltd.crt" "C:\\Users\\Admin\\Documents\\deepseek-harness\\default-workspace\\tools/caddy/certs/dsh.vbox.ltd.key"

	# dsh-pet plugin API -> DSH web server (52009)
	handle /dsh-pet-7340/* {
		reverse_proxy 127.0.0.1:52009
	}

	# everything else, incl. /ws/mobile mobile gateway -> 3081
	handle {
		reverse_proxy 127.0.0.1:3081
	}
}
```

- `caddy validate` → `Valid configuration`（exit=0）。
- caddy 配置里有 `admin off`，**没有热重载接口**，改完必须重启进程：
  `Stop-Process -Id 10108 -Force` → `caddy.exe run --config <Caddyfile>`（新进程 pid 16088，已监听 7789）。

### 17.4 验收结果（公网实测）

| URL | 结果 | 判读 |
|---|---|---|
| `https://dsh.vbox.ltd:42429/dsh-pet-7340/state` | `200`，`counter` 递增（1794719117226 → 1794719120642） | 宠物 API 已可从外网访问，且数据是活的 |
| `https://dsh.vbox.ltd:42429/dsh-pet-7340/config` | `200` | 配置可读 |
| `https://dsh.vbox.ltd:42429/` | `404 {"error":"not-found"}` | 网关原样，未受影响 |
| `https://dsh.vbox.ltd:42429/ws/mobile`（带 WS 握手头） | `401 missing or invalid device credential` | 网关自身的设备凭证校验仍在工作 → Whaleness 这条腿完好 |

### 17.5 面板里该怎么填

| 场景 | 填法 | 说明 |
|---|---|---|
| 同局域网 | `http://192.168.x.x:52009` | 面板只拼 `/dsh-pet-7340/`，端口必须是 52009 |
| 外网（当前唯一入口） | `https://dsh.vbox.ltd:42429` | 走 caddy 分流；宠物路由**不需要 Token** |
| 备用 | Tailscale 直连 `http://100.x.x.x:52009` | 两端装 App，DERP 中转 80–200ms |

要点：`/ws/mobile` 的 `device credential` 是 **Whaleness 自己的配对凭证**，与宠物面板的 `X-DSHPet-Token` 是两套东西，面板里不要混填。

### 17.6 0.4.9 是否已生效（实测）

`/dsh-pet-7340/config` 现在能读到 `speechProvider="dsh"`、`voiceName="edge/zh-CN-XiaoyiNeural"`、`notifyWhenFocused=false`、`pets[0].fixedEnabled=false` —— 这些是 **0.4.9 才有的键**，说明插件代码已换成 0.4.9。
但桌面宠物壳进程 `pid 16492` 的启动时间仍是 **04:24:25**（升级前）：壳与主程序是两段生命周期，**完全退出 DSH（含托盘）再启动**才会连壳一起换新。

### 17.7 回滚

```powershell
Copy-Item "Caddyfile.bak-20261115130334" Caddyfile -Force
Stop-Process -Id <caddy pid> -Force
Start-Process -FilePath "caddy.exe" -ArgumentList @("run","--config","<Caddyfile>") -WorkingDirectory <caddy 目录> -WindowStyle Hidden
```
回滚后 `/dsh-pet-7340/*` 会重新变成 404，`/ws/mobile` 不受影响。

---

## 18 v2.13 遗漏补齐（第二轮）

第一轮补的是"能用"（手势、救援、音频、通知、性能、测试、隐私、发布），这轮补的是"会不会被系统挡住"。

### 18.1 网络权限与 ATS：桥接的第一道门（最高优先）

我们在别人的进程里跑（SpringBoard），**没有自己的 Info.plist 说话**，于是两条系统规则会静默生效：

| 规则 | 后果 | 触发条件 |
|---|---|---|
| **Local Network 权限**（iOS 14+） | 首次访问局域网地址会被系统拦下并弹授权，没有描述字符串时表现为"请求直接失败"，日志里只有 `NSURLErrorNotConnectedToInternet` 之类 | 目标 IP 落在局域网段（`192.168/10/172.16`）或 Tailscale `100.64/10` |
| **ATS**（App Transport Security） | 明文 `http://` 被拒，`NSURLErrorAppTransportSecurityRequiresSecureConnection` | 任何 `http://` 非 localhost 目标 |

对策，按优先级：

| # | 方案 | 做法 | 代价 |
|---|---|---|---|
| 1 | **全部走 HTTPS**（首选） | 外网本来就有 caddy + `dsh.vbox.ltd` 证书；内网也让它走同一个域名（手机在局域网时 DNS 指回内网 IP），彻底不碰 ATS | 需要一条内网 DNS 记录或 hosts 手段 |
| 2 | 内网用 HTTPS + 信任自签 | caddy 内网监听也用 `tls internal`，面板引导安装自签根证书（设置 → 通用 → 关于本机 → 证书信任设置） | 用户要点两下 |
| 3 | **裸 socket 自己发 HTTP** | 用 `CFStream`/`NWConnection` 手写 `GET`，不经过 NSURLSession，ATS 管不到 | 多写 ~200 行，需自己处理 chunked、重定向 |
| 4 | 只允许 loopback | 手机上跑中继（如 Tailscale Serve）把 http 收成 https | 多一个组件 |

> 结论：**M0/S0 必须先真机验这三件事**——① 面板能否对 `http://192.168.x.x:52009` 发起请求；② 是否弹本地网络授权；③ 换 `https://dsh.vbox.ltd:42429` 是否通。三者结果决定走方案 1 还是回落到方案 3。
> 面板要配一张「网络诊断」页：显示 ATS 判定、本地网络授权状态、DNS 解析结果、到目标的 TCP 是否可建连、HTTP 状态码——缺这一页，以后所有"连不上"都会变成猜谜。

### 18.2 arm64e 与 PAC：hook 能不能落地

| 事项 | 现实 | 动作 |
|---|---|---|
| 指针签名 | arm64e 的函数指针带 PAC，老式 `MSHookFunction` 直接写会崩 | 用 ellekit（Relaxin 自带）的 `MSHookMessageEx` / `%hook`，别用 substrate 老 API |
| 方法交换 | SpringBoard 里 swizzle `SBApplication`/`SBHomeScreenViewController` 需 `ptrauth_sign_unauthenticated` 处理 | S1 就验证，不留到后期 |
| 签名身份 | dyld 加载需有效签名，越狱环境用 `ldid -S` 签 ad-hoc | CI 里固定一步 `ldid -SDSHPet.entitlements` |
| 变体验证 | 用 `lipo -info` + `codesign -d --entitlements :-` 双查 | CI 断言失败即不出包 |

### 18.3 生命周期矩阵（补 §15.1）

| 事件 | 期望行为 | 坑 |
|---|---|---|
| 锁屏 / 解锁 | 宠物窗口随 SpringBoard 根窗口 z-order 切换；锁屏下隐藏或只留"睡觉"动画 | 锁屏是另一层 window，不处理就"锁屏后宠物消失再也不回来" |
| 来电 / Siri / 语音控制 | 立即隐藏，结束后恢复 | 音频会话被打断要能自恢复（见 §15.3） |
| 控制中心下拉 / 通知中心下划 | 宠物降到底层，不挡面板 | 手势区判定见 §15.1 |
| 旋转（横屏 App、游戏） | 跟随方向重排，气泡不越界 | 只在竖屏锁定时也要处理安全区变化 |
| 动态岛 / 刘海 | 顶部禁区，宠物与气泡不得压住 | 用 `safeAreaInsets` 而不是硬编码 |
| App 切换器 / 图标抖动编辑态 | 隐藏宠物 | 否则被缩放的卡片裁切、露馅 |
| 全屏视频 / 播放器 | 自动隐藏（可配置） | 录屏同理（§15.7） |
| 低电量弹窗 / 系统弹窗 | 不抢焦点，宠物退到后面 | — |

### 18.4 热控与低电量降级

- `ProcessInfo.thermalState`：`.serious` → 帧率 60→30；`.critical` → 暂停非可见动画（只保留睡觉循环），并在面板红字提示。
- `isLowPowerModeEnabled`：默认帧率 ×0.5、预载池减半。
- 锁屏或 App 切后台：停止渲染循环（`CADisplayLink` 置空），解锁重建——这是省电与防掉帧最有效的一刀。
- 所有降级动作都写 `metrics.jsonl`，便于回看"是不是这台机器一直热"。

### 18.5 与其它越狱插件共存

| 冲突源 | 表现 | 处理 |
|---|---|---|
| SnowBoard / 主题插件 | 壁纸层重绘 → 我们的 window 被盖住或闪烁 | 提高 windowLevel，并用 `UIWindowScene` 的层级测试 |
| Activator / 手势插件 | 抢同一批触摸区 | 我们的视图 `hitTest` 只在自己皮肤轮廓内返回 self，其余 nil（§15.1） |
| 其它悬浮窗插件（悬浮球、FloatingDock） | z-order 打架、互相把对方挤下去 | 提供"层级优先级"配置（低/中/高），默认中 |
| RootHide 的 hiding 列表 | 目标 App 里不注入（正常），但 SpringBoard 也被隐藏就全没了 | 面板「诊断」显示当前注入状态 |
| 上游 dsh-pet 桌面版 | 同一 DSH 双端同时在线，抢 `/broadcast` 锁 | 见 §18.9 |

### 18.6 打包与源索引规范

`control` 必填：`Package` / `Name` / `Version`（`MAJOR.MINOR.PATCH-BUILD`）/ `Architecture: iphoneos-arm64` / `Maintainer` / `Section: Tweaks` / `Depends: preferenceloader, firmware (>= 17.0)` / `Conflicts`（两个变体互斥）/ `Installed-Size` / `Description`（多行，含署名与素材许可）/ `Icon`。

文件布局：

```
/Library/MobileSubstrate/DynamicLibraries/DSHPet.dylib  + DSHPet.plist
/Library/PreferenceBundles/LittleFatLadyPrefs.bundle/
/Library/Application Support/DSHPet/（包内只读配置与 3 段占位素材）
/var/mobile/Library/DSHPet/（用户数据，卸载不删）
```

`postinst`：`sbreload`（不要 `killall -9 SpringBoard`）；`prerm`：只停注入、保留用户数据。仓库 Pages 输出 Sileo 需要的 `Packages` + `Packages.gz` + `Release`，每个 deb 附 `SHA256SUMS` 与 `changelog.Debian.gz`。

### 18.7 无障碍与减少动态效果

- VoiceOver：宠物本体可聚焦，读出「小肥娘，状态：工作中」；气泡文本走 `accessibilityLabel`。
- 点击热区 ≥ 44×44pt（宠物缩到 0.3 时也要保证）。
- `UIAccessibility.isReduceMotionEnabled` → 关闭甩出/抖动/惯性，只保留淡入淡出。

### 18.8 语言与时间

- 对白 8 语言：跟随系统语言，缺语言回落到英文，再回落中文。
- 24/12 小时制、时区、系统语言变更后热重载（`NSLocale.currentLocaleDidChangeNotification`）。

### 18.9 与上游插件版共存（锁语义）

桌面版 dsh-pet 与手机版会同时对同一个 DSH 说话：`/broadcast` 与 `/work-status` 都要带 `?lock=&ttl=`，谁先拿到锁谁说话，避免两端同时播报打架。手机侧默认**只读优先**：读 `/state`，写操作（说话、动效）默认只在"手机端前台可见"时才发。

### 18.10 配置迁移与双向导入

- `schemaVersion` 升级脚本：每加字段都要写迁移，不允许"读不懂就丢"。
- 支持**导入上游 `config.jsonc`**（桌面版导出的那份），字段名一一对应；反之也能把手机侧配置导出成上游能吃的 JSONC——这样用户在两端切换不用重设。
- 导出格式：`.dshpetconfig`（JSONC + 注释头说明版本与来源设备）。

### 18.11 里程碑影响

| 步骤 | 增量 | 原因 |
|---|---|---|
| S1 空壳注入 | +1 | 先证 arm64e/PAC hook 与签名能落地，再谈功能 |
| S10 内容能力 | +1 | 网络诊断页 + ATS/本地网络三条对策的实测与回落 |
| S12 发布 | +1 | deb 字段/源索引/双向配置导入的收尾 |
| **合计** | **63 人日**（原 60） | Android 仍另算 16 |

### 18.12 余额服务商失配（真机实测发现）

> **更正（v2.14）**：本节结论有一半错——配置里根本没有 `balance` 段，provider 是插件从 DSH 的 **LLM 服务商列表**里挑的。以 §19.3 为准。


手机截图里的 `/state`：`"balance":{"ok":false,"provider":"bxfvip","reason":"unsupported"}`。

查 0.4.9 的 `lib/app.js`：

```js
const BUILTIN_PROVIDERS = [opencodeGo, commandCode, deepseekOfficial, deepseekAccount];
```

内置 id 实际是 `opencode-go` / `commandcode` / `deepseek-account`（+ deepseek 官方），**`bxfvip` 在 0.4.9 里一次都没出现**——它是旧版或某个第三方登记插件留下的**过期 id**（0.4.9 改成了「注册制」，第三方要用 `registerBalanceProvider` 自己登记，插件被卸掉就会变成 unsupported）。

面板处理：

| 情形 | 显示 |
|---|---|
| `ok:true` | 正常显示余额与新金币动画 |
| `reason:"unsupported"` | 红字「当前服务商 `bxfvip` 已不被 0.4.9 支持」+ 下拉改选 `opencode-go`／`commandcode`／`deepseek-account`／`deepseek` |
| `ok:false` 且网络类错误 | 显示最后成功时间 + 「重试」 |
| 连续 3 次失败 | 余额相关动画降级为「钱袋如常」，不再播满溢/分文不剩 |

> 这条也说明：**手机端不能假设桌面的配置项永远有效**，所有 provider/模型/音色类字段都要做「值不在列表里就标红并给改选」，而不是静默失败。

---

## 19 v2.14 最终核对：上游 55 个方法逐条对账

### 19.1 全端点表（41 条路径 / 55 个方法，来自上游 `openapi.yaml` 与实测）

标记：**✅** 手机端直接用 ｜ **◐** 用但需适配 ｜ **✕** 手机端不调

| 端点 | 方法 | 手机端 | 用途 |
| --- | --- | --- | --- |
| `/state` | GET | ✅ | 主数据源；支持 `?since=&timeout=` 长轮询（≤10s），counter 变才算更新 |
| `/work-status` | POST / DELETE | ✅ | 手动设/清「工作中／思考中」，面板「工作状态」组 |
| `/balance` | POST | ✅ | 写入余额数值（自定义 provider 的出口） |
| `/environment` | POST | ✅ | 城市/天气覆盖 |
| `/focus-session` | POST | ✅ | 焦点会话（工作状态联动的细粒度入口） |
| `/whisper` | POST | ✅ | 让宠物说一句 |
| `/broadcast` | POST | ✅ | 全端广播气泡（要带 `lock`，防互相抢） |
| `/bubble/clear` | POST | ✅ | 清空气泡 |
| `/anim` | POST | ✅ | 指定播某个动画 |
| `/position` | POST | ◐ | 设位置；手机端做「叫它过来」 |
| `/throw` | POST | ◐ | 抛一下；手机端做「甩出去」 |
| `/lock` `/lock/release` | POST | ✅ | 独占（与桌面版抢控制权时的锁） |
| `/sleep` `/wake` | POST | ✅ | 强制睡觉/叫醒 |
| `/pose` | GET | ◐ | 读桌面实况（手机端自己算自己的） |
| `/pose/report` | POST | ✅ | 手机上报自己的位置/朝向，桌面面板可显示 |
| `/playback/{id}` | GET | ✅ | 某只宠物当前动画与进度 |
| `/playback/{id}/report` | POST | ✅ | 播放进度上报 |
| `/attachment` | GET | ✅ | 取附件（图片/文件） |
| `/chat` | GET / POST / DELETE | ✅ | 对话、取历史、清空 |
| `/chat/memory` | GET / DELETE | ✅ | 长期记忆读写 |
| `/config` | GET / PUT / POST | ✅ | **顶层是 `{ "main": {…} }` 命名空间**；PUT 局部合并，POST = 恢复默认 |
| `/config/meta` | GET | ◐ | 返回**宿主**存储路径（Windows 路径），手机端只能示意不能照搬 |
| `/pet-display` | POST | ✅ | `web`/`desktop`/`both`/`none` |
| `/pet-config` | POST | ✅ | 增删改宠物条目（多开管理） |
| `/models` | GET | ✅ | **动态服务商+模型列表，面板禁止硬编码** |
| `/reload` | POST | ✅ | 重载配置（比 PUT 更彻底） |
| `/quit` | GET / POST | ✕ | 会杀掉桌面宠物进程，手机端永不调用 |
| `/voice/speak` | POST | ✅ | TTS 播报 |
| `/voice/voices` | GET | ✅ | 音色目录（0.4.9 起是 `provider/id` 形式，如 `edge/zh-CN-XiaoyiNeural`） |
| `/voice/hear` | POST | ✅ | **上传音频→宿主 ASR**，手机端 STT 的正解 |
| `/voice/hear-providers` | GET | ◐ | 实测 400（需参数），S10 再探 |
| `/character` | GET | ✅ | 角色卡图 |
| `/logo` | GET | ✅ | logo 图 |
| `/pet-avatar` | GET / POST | ✅ | 宠物头像读取/上传 |
| `/menu/item` | POST / DELETE | ◐ | 注册第三方菜单项 |
| `/menu/events` | GET | ◐ | 取菜单点击（**读取即消费**，与桌面版抢会丢事件） |
| `/menu/click` | POST | ◐ | 触发菜单点击 |
| `/todos` `/todos/{id}` | GET / POST / PATCH / DELETE | ✅ | 待办 CRUD |

### 19.2 三条改变设计的发现

1. **`/models` 是动态的**：实测返回 `deepseek-official`（空）、`deepseek-account`（v4.1-flash / v4-pro）、`bxfvip`（Agent2API，十余个 `ca-*` 模型）。
   面板「对话」组必须**两级下拉动态填充**（服务商 → 模型），且失败时显示「宿主不可达」而不是空白下拉。硬编码模型名是错的。
2. **`/voice/hear` 解决了云电脑没麦克风的死结**：录音发生在手机上（需要麦克风权限，见 §15.3），识别跑在宿主。
   所以手机端 **不需要**打包本地 ASR（Whisper/Apple Speech），S10 里原计划的本地识别整块可删——少 1 人日、少 40MB 依赖。
3. **`/config` 顶层是 `{ "main": {...} }`**：实测 `main` 下 28 个键（`chatModel`、`whisperModel`、`voiceName`、`pets`、`physics`、`animations`、`eventsRefreshSec`、`animationWeights`、`workStatusTexts`、`font`、`memes`…）。
   面板写配置必须按这个命名空间包一层；**同步上游默认**（POST /config）会把用户改动全部抹掉，必须二次确认。

### 19.3 更正 §18.12：余额不是"填错了 provider"

- 实测 live 配置的 `main` 下 **没有 `balance` 段**（28 个键里没有），所以"配置里填了 bxfvip"不成立。
- `bxfvip` 出现在 `/models` 里，是**大模型服务商**（Agent2API 外网本机），不是余额服务商。
- 内置余额服务商只有 `opencode-go` / `commandcode` / `deepseek-account` / `deepseek`；插件按 DSH 的服务商顺序挑一个去查余额，挑到 `bxfvip` → `unsupported`（**Inferred**：顺序来自 DSH 配置，非 pets 配置）。
- 正确修法（S10 做）：
  1. 在 DSH 里让 `deepseek-account` 排到服务商第一位；
  2. 或注册自定义余额 provider：`balance.register({ id, fetch, shape })`，`shape` 支持 `windows` / `money` / `points` / `custom`；
  3. 手机面板只读 `/state` 的 `balance` 段，`unsupported` 时显示红字 + 引导，不自己猜。

### 19.4 网络最终定稿（用户已定：全程走 42429）

| 项 | 定稿 |
| --- | --- |
| 主通道 | `https://dsh.vbox.ltd:42429`（SakuraFrp `#29715647` → caddy `7789` → 分流） |
| 分流规则 | `/dsh-pet-7340/*` → `127.0.0.1:52009`；其余 → `127.0.0.1:3081`（Whaleness 的网关） |
| 备用腿 | Tailscale（手机上可装，面板「连接存档」第二档） |
| 明文 HTTP | **不做**。§18.1 的三条 ATS 兜底全部降级为 Save 分支，S1 只验 https 一条 |
| `/ws/mobile` | 手机端**不碰**（3081 的凭证校验属 Whaleness，抢了会互踢） |
| 3065 | 永久归 Agent2API，本项目不碰 |

### 19.5 开工前 6 条（缺一条就不要开 S0）

1. **完全退出 DSH（含托盘）再启动**——当前宠物壳还是 04:24:25 起的 0.4.8 进程，不重启就验不到 0.4.9 的 `speechProvider`。
2. Sileo 里 PreferenceLoader 已装（2.2.8），确认仍在。
3. 仓库 `vbox-Ai/Little-fat-lady` 建骨架 + `LICENSE` + `LICENSE-ASSETS`（CC BY-NC-SA 4.0 原文）。
4. 手机装 Tailscale（可后补，不阻塞 S0）。
5. 决定 `pets[0].display` 的默认值（手机端不读，桌面端读；建议保持 `both`）。
6. 余额 provider 顺序调整（不阻塞 S0，S10 处理）。

> 人日复核：S10 删本地 ASR −1、新增 `/models` 动态与端点回归 +1，**净持平 63 人日**。

---

## 20 阶段关闭闸门（硬性，写死，不可跳）

> 本节由操作员于 2026-11-15 指定为**硬性条件**。任何阶段（S0–S12）在四件事全绿之前，**不得**开始下一阶段。

### 20.1 四件齐（顺序固定，不许并行跳过）

| # | 动作 | 判定标准 | 落在哪 |
| --- | --- | --- | --- |
| 1 | **自检遗漏** | 跑 `node scripts/check-repo.mjs` 全绿；逐条核本阶段验收清单；再自问三条："新增的能力/坑/常量有没有写进文档？""有没有静默失败的分支？""有没有只在我机器上成立的假设？"——发现就**就地修完**，禁止"下阶段补" | 修完的代码 + §14.1 决议 / 对应章节 |
| 2 | **写记忆点** | `docs/journal/S<xx>.md` 六段齐全（做了什么 / 证据 / 决定 / 遗留 / 风险 / 下一步），并在 `MEMORY.md` 索引里加一行 | `docs/journal/`、`MEMORY.md` |
| 3 | **全量推送** | `git add -A && git commit && git push origin main`；本地 `git rev-parse HEAD` == 远端 `main` 的 sha | GitHub `vbox-Ai/Little-fat-lady` |
| 4 | **回报** | 把 commit sha、验收输出、下一阶段入口写给操作员 | 对话 |

### 20.2 闸门明细（每阶段同一张表）

```text
阶段：S__              commit：（推送后回填）
① 自检   check-repo.mjs exit=0 / 验收项 n/n / 遗漏修复 k 处
② 记忆   docs/journal/S__.md 六段齐 / MEMORY.md 已加索引行
③ 推送   local sha == remote sha （两边打印同一串）
④ 回报   已写
结论：CLOSED / BLOCKED（BLOCKED 必须写明卡在哪一条，且不得开下一步）
```

### 20.3 违规处理

- 跳过任一动作 → 该阶段**视为未完成**，下一步一律不开。
- 出现"先写下一阶段代码、回头补记忆" → 立即回退到该阶段，补完四件再往前走。
- 推送失败（网络/权限）→ 阶段状态 `BLOCKED`，修好再推；**不许**在未推送的情况下继续开发。
- 记忆点不许写"同上""略""见代码"：必须能只读 journal 复现当时的判断与命令。

### 20.4 与其它章节的关系

- §16 给了每阶段的人日与产出物；本节给的是**关闭条件**。两者冲突时以本节为准（本节更严）。
- §15.6 的测试策略是"代码级"门，本节是"阶段级"门，两道都要过。
- 阶段成功关闭后，才允许在 §14.1 里追加该阶段的决议（决议号连续，不跳号）。

### 20.5 S0 关闭记录（已关闭）

```text
阶段：S0 环境基线
① 自检  ：node scripts/check-repo.mjs -> PASS（19 项 ok，扫描 18 个文本文件无凭据，S00 六段齐）
② 记忆  ：docs/journal/S00.md 六段齐 + MEMORY.md 阶段索引已加 S0 行
③ 推送  ：45b4956  （18 文件，GitHub API 提交；远端 main == 本地快照）
④ 回报  ：commit 45b4956 / 验收输出 / 下一步 S1 已写入对话
结论：CLOSED
```

> 注：本机**没有 git**，推送走 GitHub REST API（`/git/blobs` → `/git/trees` → `/git/commits` → `PATCH /git/refs/heads/main`），
> 空仓库需先用 Contents API 落一个文件初始化。每次推送后校验「远端 ref sha == 本次 commit sha」。

### 20.6 S1 关闭记录（已关闭）

``text
阶段：S1 空壳注入
① 自检  ：node scripts/check-repo.mjs -> PASS；六坑全部在 CI 里修毕（macos-14 不可用 / sdks 目录冲突 /
          extern "C" / BOM / filter plist 位置 + 维护脚本 755 / deb 输出路径）
② 记忆  ：docs/journal/S01.md 六段齐 + MEMORY.md 索引已加 S1 行与闸门记录
③ 推送  ：见本轮 commit（GitHub REST 推送，远端 main == 本地快照）
④ 回报  ：CI run 43687765463 双 job 绿；deb 6130B / sha256 14d15874…133f；lipo = arm64 arm64e；
          Release v0.1.0-11 已挂 deb + SHA256SUMS
结论：CLOSED（真机「装得上 + 有日志」为 S1 的验收残留，操作员装机后回填；不影响开 S2 的准备工作）
``

> 本条新增的硬规则：**S1 之后每个阶段的关闭记录都必须有 CI run id 与产物 sha256**，不许只写"已跑通"。

### 20.7 S2 关闭记录（代码侧 CLOSED，真机待验）

```text
阶段：S2 透明浮层（SpringBoard 独立 UIWindow + 可拖动方块）
① 自检  ：node scripts/check-repo.mjs -> PASS（journal S00/S01/S02 六段齐）；
          两坑修毕：nullability-completeness（CI 为 error）、16.5 SDK 无
          UIWindowSceneDidUpdateCoordinateSpaceNotification（改 layoutSubviews）
② 记忆  ：docs/journal/S02.md 六段齐 + S01 §2.0 回填真机验收 + MEMORY.md 索引/闸门已更新
③ 推送  ：commit 147eb37（REST 推送，远端 main == 本地快照）
④ 回报  ：CI run 43690041210 双 job 绿；deb 16054B / sha256 61e1a356...cb3；
          lipo = arm64 arm64e；Release v0.1.0-15 已挂 deb + SHA256SUMS
结论：CLOSED（代码与产物已闭环）。真机五条现象为 S2 的验收残留，操作员确认后回填；
      其中「浮在桌面/App 之上」与「空白处点击穿透」两条为开 S3 的硬前提。
```

#### 20.7.1 S1 真机验收（补记，已闭环）

```text
证据：/var/mobile/Library/DSHPet/logs/runtime.jsonl 两行
      {"pid":14789,"os":"17.0","evt":"boot","exe":"com.apple.springboard",...}
      {"evt":"springboard-ready","stage":"s1","pid":14789}
判定：注入 SpringBoard 成功 + hook 生效 + 可写数据目录。
      由此关闭「是否需要 roothide 变体」的未决项——rootless 包在 Relaxin 上可直接用。
```

---

## 21 会话信息气泡（"小肥娘贴着你说话"）

> 起因：操作员看到上游小肥娘会在宠物旁边浮出一条会话信息，问我们有没有、怎么做、属于哪一阶段。
> 结论：**当前版本没有**（只有宠物本体 + 动作，没有气泡层）。本节把这件事定死成契约，避免后面各写各的。

### 21.1 这功能到底是什么

不是"聊天窗"，是**一行转写**：DSH 每一轮结束（`turn/end`）会把助手最后那段话丢给宠物插件，宠物把它显示在自己头上 4–12 秒，然后收起来。

上游证据（本机 `GET http://127.0.0.1:60513/dsh-pet-7340/state` 实测，2026-11-17）：

```json
{"sections":{"notify":{"counter":1794852068640,"data":{
  "type":"session/event",
  "event":{"type":"turn/end","data":{
    "reason":{"kind":"completed"},
    "text":"破小鸭：84 那个\"偶尔模糊\"是结构问题……"}},
  "sessionId":"session-019f60c3-404b-45e6-925d-8755bebb6dd7"}}}}
```

也就是说：**数据不用我们造**，DSH 已经把文本推过来了。我们要做的只有三件：取、洗、画。

### 21.2 数据契约（照抄，不改上游）

| 字段 | 位置 | 说明 |
|---|---|---|
| `sections.notify.counter` | 顶层 | 单调递增；**只有 counter 变了才算新消息**，别按内容去重 |
| `sections.notify.data.type` | 固定 `session/event` | 目前只有这一类 |
| `event.type` | `turn/end` / 其他 | 目前只处理 `turn/end`；未知类型忽略并记 `bubble/skip` |
| `event.data.text` | 字符串 | 上游已截断（实测约 300 字），可能含 Markdown 标记 |
| `event.data.reason.kind` | `completed`/`error`/… | `error` 用另一套配色（见 21.4） |
| `sessionId` | 字符串 | 多开时按会话过滤（S6b 用） |
| `sections.pets.main.say` | `{text,image}` | 手动 `POST /whisper` 触发，优先级高于 notify |

轮询方式：`GET /state?since=<counter>&timeout=10` 长轮询（上游支持 ≤10s）。**不要**每秒硬轮询，省电也省 DSH。

### 21.3 文本清洗规则（不洗就会露出 Markdown）

1. 去掉开头 `破小鸭：` / `小肥娘：` 这类角色前缀（正则 `^[^：:\n]{1,8}[：:]\s*`，只在首行命中时删）。
2. 去掉行内标记：`**`、`__`、`` ` ``、`#`、`> `、列表符 `- `/`1. `。
3. 代码块（```）整段替换成 `［代码］`。
4. 链接 `[文字](url)` 只留文字；裸 URL 截成前 24 字符 + `…`。
5. 换行合并成空格，连续空白压成一个；**最多展示 3 行**（约 60 字），超出加 `…`，点一下气泡展开全文（S6b）。
6. 全空或只有标点 → 不显示（记 `bubble/empty`）。

### 21.4 渲染规格

| 项 | 规格 |
|---|---|
| 位置 | 宠物头顶上方 `8pt`；放不下就自动翻到下方，仍放不下则贴屏幕边 |
| 尺寸 | 最大宽度 `min(0.62×屏宽, 280pt)`；最小 `80×32`；内边距 `10×12` |
| 圆角/尾巴 | 圆角 `14pt`，尾巴 `12×8` 指向宠物；`shadowOpacity 0.18`、半径 `8` |
| 配色 | 常规：底色 `#FFFFFF @0.94`、文字 `#1C1C1E`；错误：底色 `#FFEDEA @0.96`、文字 `#8A1F11` |
| 字号 | `15pt`（跟随系统动态字体，最大 `20pt`） |
| 动画 | 淡入 `0.15s` + 轻微上浮 `4pt`；淡出 `0.18s`；**不做**弹跳/放大 |
| 停留 | `clamp(字数×0.15s, 4s, 12s)`；新消息直接替换（不排队，避免堆积） |
| 触摸 | 气泡本身**不拦触摸**（`userInteractionEnabled=NO`），点屏幕空白照样穿透；展开态才拦 |
| 生命周期 | 锁屏/进入后台立即隐藏；旋转时按 `window.bounds` 重算（和宠物同一套坐标逻辑） |

### 21.5 状态机

```
IDLE ──(notify.counter 变化)──> CLEAN ──(文本为空)──> IDLE
                                     └──(有文本)──> SHOW ──(停留到期)──> FADE ──> IDLE
SHOW ──(新消息)──> SHOW（替换，重置停留计时）
SHOW ──(锁屏/后台)──> HIDDEN ──(回前台且未过期)──> SHOW
```

### 21.6 属于哪一阶段

| 阶段 | 做什么 | 人日 |
|---|---|---|
| **S6a** | 气泡层本身：容器 + 跟随宠物 + 淡入淡出 + 三行截断（喂假数据即可验收） | 2 |
| **S6b** | 接 `/state` 长轮询：counter 去重、文本清洗、`turn/end` 路由、点开全文 | 2 |
| **S10** | 内容扩展：`/whisper` 手动台词、待办提醒气泡、余额变化气泡、错误态配色 | 3 |

即：**S6 就能看到气泡，S10 才把各种来源接满**。S6a 不依赖网络，所以真机验收不用等隧道。

### 21.7 验收清单

1. 桌面发一条消息 → 宠物头顶 1 秒内浮出这段文字，3 行内截断。
2. 文字里的 `**`、`` ` ``、`##` 不出现。
3. 12 秒内自己消失；期间再来一条直接替换，不叠两条。
4. 气泡挡不住宠物本体，也不吃触摸（点气泡下面的图标能正常打开 App）。
5. 锁屏立刻消失；解锁回到前台，未过期的继续显示。
6. 横屏时气泡跟着宠物走，不溢出屏幕。
7. `reason.kind=error` 时配色变红。
8. 关掉「气泡对话」总开关后，一条都不出现。

### 21.8 风险

| 编号 | 风险 | 处置 |
|---|---|---|
| R20 | 长文本把气泡撑成一堵墙 | 3 行硬截断 + 展开态限高 `0.4×屏高` |
| R21 | DSH 没装 pets 插件时一条都没有 | 面板显式提示"未连接"，不静默 |
| R22 | 长轮询在后台被系统挂起 | 进后台停轮询，回前台用 `since` 补齐（不丢消息） |
| R23 | 多开多宠物抢同一条消息 | S6b 按 `sessionId` 过滤，主宠物优先 |

---

## 22 重力感应开关（`physics.tiltGravity`）—— S7 面板必备项

> 来源：操作员 m06548「物理：重力这个单独功能我建议后期阶段开发设置 ui 的时候把这个功能单独做个功能开关方便随时关闭和打开」。

### 22.1 这是什么

桌宠的"重力"有两个来源：

| 来源 | 表现 | 配置键 |
|---|---|---|
| 常量重力 | 永远朝屏幕下方掉（`gravity`，默认 1400 pt/s²） | `physics.gravity` |
| **重力感应** | 按手机倾斜方向掉；手机平放时几乎不落 | `physics.tiltGravity` |

我们两套都实现：`tiltGravity` 打开且有加速度计时用传感器向量，否则退回常量重力。

### 22.2 为什么必须做成开关

1. **躺床上侧着拿手机**：宠物会一直贴着"低的一侧"爬，有人喜欢，有人嫌烦。
2. **开车/走路导航**：机身晃动被当成重力变化，宠物自己乱跑，容易被误当成 bug。
3. **省电**：CoreMotion 常开是常驻线程，夜里挂机应可关。
4. **排障**：物理表现异常时，第一件事是"关掉感应看还乱不乱"。

### 22.3 面板设计（S7 · 组「交互物理」）

```
交互物理
┌─────────────────────────────────────────┐
│ 重力感应            [开关] 开            │  副标题：跟随手机倾斜方向
│ 重力强度            ──────●────  1400    │  600 ~ 2400
│ 弹性                ────●──────  0.62    │  0.30 ~ 0.90
│ 抓起来能甩出去      [开关] 开            │  shakeThrow
│ 震动反馈            [开关] 开            │  hapticEnabled
│ 宠物互相碰撞        [开关] 开            │  petCollision
└─────────────────────────────────────────┘
```

- 关闭重力感应：`physics.tiltGravity = false`，同时 `[_motion stopAccelerometerUpdates]`（真停，不只是忽略数据）。
- 打开：`startAccelerometerUpdates`，`accelerometerUpdateInterval = 1/30`。
- 变更立即生效，不需要重启 SpringBoard（写 `overrides.jsonc` → 发 `com.vboxai.littlefatlady.reload` → 覆盖层重读 `physics` 段）。

### 22.4 省电纪律

- 锁屏 / App 进入后台：`stopAccelerometerUpdates`；回前台再开。
- 宠物静止且无触摸 30s：降到 `1/10` 采样（重力方向变化慢，够用）。
- 关闭开关时一定 `stop`，不要只把 flag 置 false。

### 22.5 验收

1. 面板关掉"重力感应"，把手机横过来 → 宠物仍朝屏幕下方掉，不贴边。
2. 打开开关，倾斜手机 → 宠物朝倾斜方向滑，落地停住。
3. 关掉开关后查 `runtime.jsonl`，应有 `motion/stop` 一条，进程 CPU 回落。


---

## 23 发虚问题追踪（未解决 · 挂起，后期修复）

> 状态：**仍未解决**（0.1.0-114 真机复测：站立疲惫左右晃 / 向左跑仍发虚）。
> 本节是「已知未解决」清单，不再空转重试；下一步修复另起一轮，按下面 23.3 的优先序做。

### 23.1 已做过的修复（都验证过，但没根治）

| 轮次 | 版本 | 改动 | 结论 |
|---|---|---|---|
| 1 | -100/-102 | 铺满后重 fit、`ResizeAspect`、`sizeManual` 持久化 | 修了「注销拉长」，没修发虚 |
| 2 | -104 | 分桶优先、忽略平铺 mp4/mov | 修了「抽到蓝水母」，没修发虚 |
| 3 | -106 | 有 webp 就剔除 mp4/mov | 反而更虚（当时 PACK_URL 指向无 alpha 包） |
| 4 | -107/-111 | 390v2 全量素材 + 1:1 像素直出（`contentsScale=屏幕scale`） | 1:1 已对，素材无余量仍糊 |
| 5 | -113/-114 | **512 素材包**（640 源单次缩放）+ 铺满不放大 + 预解码 120→256 + 震动 | **发虚仍在** ← 本轮 |

### 23.2 最新判断（关键转折）

1:1 像素直出是对的，512 素材也是对的，但发虚**只在特定动作**（左右晃 / 向左跑），不是全局糊。
这推翻「渲染管线统一重采样」的假设——如果是管线问题，所有动作都该糊。

真正剩下的两个高嫌疑，按证据强弱排：

1. **设备上仍有旧 mp4/mov 残留，抽签时还在播旧 320×180 演示片**（最像）。
   - 证据：108 版 `render.jsonl` 还出现过 `mode:composite` + `001-idle.mp4` / `composite-ok w:320 h:180`。
   - 原因：删了 postinst 后，老安装留下的平铺文件没人清；dpkg 不会删「包外文件」。
   - 修法：启动时主动清 `DSHPet` 目录下的平铺 mp4/mov（或代码里彻底禁掉 composite/mp4 路径，只走 webp）。

2. **换片瞬间懒解码回落到低清代理帧**。
   - 预解码 cap 已 120→256，但仍只预解「当前这一段」；121 帧长片段的首几帧若没解完就开始播，会短暂糊一下。
   - 修法：预解完再上屏（首帧 ready 才 `isReady`），或对「左右晃/向左跑」这类长片段提前整段解。

### 23.3 下一步修复优先序（后期另起一轮）

1. 加「旧素材自清」：`DSHPetAssets` 在索引前清掉 DSHPet 目录下所有平铺 `*.mp4/*.mov`，只留分桶 webp。
2. 加「webp-only」硬开关：动画链路只认 webp，`composite` 分支彻底删除。
3. 首帧 ready 再上屏 + `webp-ok` 里核对 `decoded == frames`（真机抓一次日志确认没再走 composite）。
4. 若仍糊，再查「左右晃」这几段的源画布尺寸是否本来偏小（源 640 统一 vs 个别段小画布）。

### 23.4 本轮实际交付（0.1.0-113 / -114）

- 素材包升级 **512×288**（Release `pack-upstream-0.4.9-512`，137.5MB，114 段，alpha 0–255 验证）。
- `layoutContentsForImage:` 改「铺满宠物框但不超过 1:1」（框大夹住，永不放大）。
- 预解码上限 120→256 + `webp-truncated` 警告日志。
- **S5 震动落地**：`DSHPetHaptics`（点击轻/拖拽轻/抛出轻/撞边重/落地中），配置 `physics.hapticEnabled`/`hapticLevel`。
- CI 三轮修复后绿：`maxH` 未用变量 → `DSHPetLog.h` 不存在改 `DSHPetBoot.h` → 成功（run 44129510243，commit fc53666e）。

---
