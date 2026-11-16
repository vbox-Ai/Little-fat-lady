# MEMORY.md · 跨会话记忆索引

> 只记**下次会话不知道就会踩坑**的事实。流程日志进 `docs/journal/`，这里只放结论与索引。

## 项目环境

- 目标机：iPhone 14 Pro（A16 / arm64e / MQ0D3CH/A）、iOS 17.0（21A329）、Relaxin（RootHide 型）越狱；PreferenceLoader 2.2.8 已装，设置根页有「越狱插件」分组。
- 宿主 DSH 在本机（就是这台 Windows 云电脑）：Web 服务 `127.0.0.1:52009`，宠物 API 前缀 `/dsh-pet-7340`；`dsh-plugin-mobile-gateway` 的 WS 在 `127.0.0.1:3081`（`/ws/mobile`，Whaleness 用）；`3065` = Agent2API，**不可动**。
- 外网入口 `https://dsh.vbox.ltd:42429` → SakuraFrp `#29715647` → caddy `7789` → 路径分流：`/dsh-pet-7340/*` → 52009，其余 → 3081。
- 上游插件版本 **0.4.9**（profile `~/.dsh/profiles/desktop`，pnpm 管理）；宠物壳需**完全退出 DSH（含托盘）**才换新 lib。
- 本机没有 git、没有 python 在 PATH：git 用 GitHub API 推送，python 用 `C:\Users\Admin\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe`。

## 项目约定
- 多候选根扫描必须真的逐根扫：`buildIndexFromDir:` 里拼子路径要用参数 `scanDir`，用 `self.dir` 会让所有根都退化成第一个根（0.1.0-65 的真因）。
- 「玫红方块」= 首帧 2 秒未 ready 的告警色，等价于"素材索引空/路径错"，不是渲染管线问题，先查 `anim.jsonl` 的 `index` 行。


- 阶段闸门四件（自检 → 记忆点 → 全量推送 → 回报）写进方案 §20 与本仓 `AGENTS.md`，操作员指定为硬性条件。
- 我不会用终端 → 所有真机步骤必须给图形界面或浏览器 URL。
- 面板所有"服务商/模型/音色"字段必须从宿主动态拉（`/models`、`/voice/voices`），值不在列表里标红，不静默失败。
- 文档只增不改历史：每次修订在头部加 changelog，正文用 vN 标记。

## 关键决策
- 出包只走 ci.yml 一条线；S0 留下的 release.yml 已删（它缺 S1 的六处修复，永远红，会误判成构建失败）。
- **唯一坐标真相是 `window.bounds`**：`topLevel` 额外 `UIWindow` 的 bounds 会随方向换（393×852 ↔ 852×393），而 `scene.coordinateSpace.bounds` **恒为竖屏尺寸、从不随方向变**；拿它去设 frame 会把窗口塞回竖屏形状，横屏就是"方块还在竖屏那个位置 + 屏幕外围露黑"。
- **不要给浮层设 frame/transform**：窗口几何交给 UIKit，自己只管布局；旋转期也不要 alpha/hidden 藏层（那只会制造残影与闪烁），重排一次即可。

- 旋转类通知会因**微小倾斜**连发：处理前先比 `scene.coordinateSpace.bounds.size`，**尺寸没变就绝不动 alpha**（否则就是闪一下）；连续旋转用 token 只让最后一次收尾生效。
- `@implementation` 内不能写前向声明（clang 报 `expected method body` / `duplicate declaration`）；声明放 `@interface X ()` 扩展里。

- 技术路线：SpringBoard 注入 + `UIWindow`（`windowLevel` 高于普通 App）+ AVPlayerLayer 播 HEVC-alpha，透明 WKWebView 只画气泡/菜单/设置。
- 双包：`com.vboxai.littlefatlady`（roothide）与 `.rootless`，`ARCHS = arm64 arm64e`，两包 Conflicts 互斥。
- 网络：全程走 42429 隧道，Tailscale 备用；明文 HTTP 兜底降级为 Save 分支（ATS 只验 https）。
- 语音：TTS 先行；STT 走 `POST /voice/hear`（手机录音 → 宿主 ASR），**不打包本地 ASR**。
- 配置：顶层 `{main:{…}}` 命名空间；写配置只走 `PUT /config`（局部合并），**永不** `POST /config`。
- 手机端永不调用 `/quit`；不碰 `/ws/mobile`；不抢 `/menu/events`。

## 阶段索引

| 阶段 | 状态 | journal |
| --- | --- | --- |
| S0 环境基线 | **已关闭**（`45b4956`） | [docs/journal/S00.md](docs/journal/S00.md) |
| S1 空壳注入 | **已关闭** | [docs/journal/S01.md](docs/journal/S01.md) |
| S2 透明浮层 | **代码侧关闭**（真机待验） | [docs/journal/S02.md](docs/journal/S02.md) |
| S3 单宠物渲染 | 未开始（等 S2 真机第 1/2 条） | — |

## 闸门记录

- S0：自检 PASS → journal 六段齐 → 推送 `45b4956` → 回报已写。**唯一遗留**：手机七条探针 `NOT RUN`（等操作员跑 `scripts/probe/collect-device-env.sh`）。
- S2 修复：横屏丢方块=relayout 二次设 frame（转两次）；旋转残影=浮层参与 SB 快照 → 旋转期间 alpha=0 + 窗口层彻底透明。修复版 v0.1.0-19（sha256 83e8489d…36eb）。
- S2 二轮修复：横屏只有一边=额外窗口尺寸没跟上（硬同步 frame 到 scene bounds）；轻微晃动闪烁=假旋转事件触发 alpha 归零（按场景尺寸过滤）。v0.1.0-24（sha256 5487de0f…9299，CI 43694259113）。
- S2：CI run 43690041210 双 job 绿 → deb 16054B（arm64+arm64e）/ sha256 61e1a356...cb3 → Release v0.1.0-15 → journal 六段齐 → 推送 147eb37。**遗留**：五条真机现象 NOT RUN。
- S1 真机验收通过：rootless 包在 Relaxin 上注入成功（boot + springboard-ready，pid 14789 / iOS 17.0）→ 不需要 roothide 变体。
- 本机**没有 git**：所有推送走 _push.mjs（GitHub REST），凭据读环境变量 GH_TOKEN，不落盘、不进仓库。
- 空仓库首次推送必须先用 Contents API 落一个文件（否则 git-data 接口全 409 Git Repository is empty）。

- 旋转时会黑边：SpringBoard 旋转快照会连高 `windowLevel` 的窗口一起拍，缓冲按旧尺寸分配 → 必须在**真旋转**发生前用 `hidden` 撤层，0.45/0.80s 后重排复显；判断用 `UIDevice.orientation` 的方向类别（比 `scene.interfaceOrientation` 早），轻微晃动不触发。
- 透明视频素材：HEVC-alpha 只能在 macOS 编码；本机用 `ffmpeg -c:v prores_ks -profile:v 4444 -pix_fmt yuva444p10le` 出 ProRes 4444 with alpha 做验证，A16 能硬解。
- 素材查找优先级固定为 `main.*` > 非 demo > `demo.mov`，免得演示素材盖住真素材。

- rootless 包会把 `layout/` 下所有路径加 `/var/jb` 前缀：静态素材不要放 `layout/var/mobile/...`（会变成 `/var/jb/var/mobile/...`），要么放 `/var/jb/Library/...` 再让 postinst 拷到 `/var/mobile`，要么全部运行时生成。
- CI 禁止"编译失败也打包"的兜底：会让真机现象变成"改了没生效"，比直接红更浪费；`scripts/build-deb.sh` 已删该分支。
- 用 GitHub `base_tree` 推送不会删除本地已删的文件，必须显式给 `sha: null` 条目；否则废弃路径会一直被打进 deb。

- 装包脚本（postinst/postrm）里绝对禁止 `sbreload`/`killall SpringBoard`：dpkg 事务会被打断，用户会卡在 `half-configured`、一开 Sileo 就注销。生效由用户点 Sileo 的"重启 SpringBoard"。
- `postrm` 必须按 `$1` 分支：`remove|purge` 才删数据，`upgrade` 保留，否则每次升级都清空日志与素材。
- 用户卡在 dpkg interrupted 时，图形化自救见仓库 `docs/RECOVERY.md`（Sileo 修复 → 卸载重装 → Filza 删 lock/updates）。

- 0.1.0-40 那次"dpkg 被中断 / 一开 Sileo 就注销桌面"是 `postinst` 里杀 SpringBoard 造成的：dpkg 事务没结束就丢桌面 → 包停在 half-configured，之后每次收尾都重跑 dpkg 保存的**旧 postinst 副本**，形成死循环。规矩：维护脚本里绝不重启桌面，卸载/升级逻辑放 `postrm` 按 `$1` 分支。
- rootless 包给 `layout/` 下所有路径加 `/var/jb` 前缀，所以数据文件不要放 `layout/var/mobile/...`；放 `layout/Library/Application Support/<Name>/`，由 `postinst` 拷到运行目录。
- 发布脚本别在 PowerShell here-string 里放中文：会被控制台编码打坏；正确做法是 python 写 UTF-8 JSON 文件，node 读文件发请求，二进制再用 `Invoke-RestMethod -InFile` 上传。

- 配置里判断"用户有没有配过"不能用绝对阈值（`size < 120 → 300`），用户捏到 118pt 是合法值 —— 这就是"缩小后注销又变大"的根因。宽度一律 `sizeRatio`（屏宽比例）优先、`size` 兜底、都没有才给默认 30%。
- 额外 UIWindow 的 `windowLevel = 1100` 会被短剧/视频类 App 的全屏窗口压住（宠物"消失"）；实测抬到 **1500**（状态栏 1000 之上、系统弹窗 2000 之下）才稳，老配置要写迁移，只改默认值救不了已装用户。
- `AVPlayer` 被 audio session 中断后不会自己恢复；必须 `.ambient + mixWithOthers` + 中断结束/回前台恢复 + 3 秒看门狗，否则一播视频宠物就定格。
- 往实现段插方法时 `str.replace("@end", ...)` 会命中**类扩展的** `@end`，方法体落进 `@interface` → `expected ';' after method prototype`；必须 `rindex("@end")` 或用方法名做锚点。
- 素材"两套同类别"会互相抢抽签：平铺 `idle.mov`（占位 demo）和 `idle/001-idle.mov`（真素材）都归 `idle`，一半概率抽到占位。规矩：包装里只留分桶，平铺演示片一律不进 deb。
- `postinst` 不再重启桌面之后，"装了但看起来没变"绝大多数是**没手动重启 SpringBoard**，旧 dylib 还在跑；发布说明必须把这一步写成第一条。
- 素材不要靠 `postinst` 拷：roothide 类越狱里维护脚本跑在假根、SpringBoard 看到的是 `/var/jb`，`cp` 会静默失败还被 `|| true` 吞掉。规矩：运行期在多候选根里找素材（`DSHPetAssetRoots()`），命中记日志。
- 项目里 warning 即 error（`-Werror`）：挪代码后遗留的未用变量（`NSFileManager *fm`）会直接卡住 CI，改完审视一遍新增/删除的局部变量。

## 阶段结论（S4 · 黑底）
- 单参数 `playClipAtURL:` 必须与双参数版本等价（无蒙版走亮度键），否则旧素材会绕过合成把黑底画上屏。
- 选素材根时给 `color/` 根加权，别只比 clip 数量；启动时清掉 `assets/` 下旧的单路素材（保留 `color/`、`matte/`、`main.*`）。
- 判据：`render.jsonl` 里 `composite` 出现 0 次 = 合成没跑，此时看到的黑底必然来自 AVPlayerLayer 单路播放。

## 阶段结论（S4 · 图层尺寸）
- 移除 `AVPlayerLayer` 后必须复核 `syncLayerFrame` 之类"以 _layer 存在为前提"的早退，否则 `_contentLayer` 永远零尺寸，画面全空。
- 亮度键用单次 `CIColorMatrix`（RGB=1、A=luma）+ `CIBlendWithMask`；`CIMaximumCompositing` 叠三通道会把 alpha 叠成 0。
