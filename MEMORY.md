# MEMORY.md · 跨会话记忆索引

> 只记**下次会话不知道就会踩坑**的事实。流程日志进 `docs/journal/`，这里只放结论与索引。

## 项目环境

- 目标机：iPhone 14 Pro（A16 / arm64e / MQ0D3CH/A）、iOS 17.0（21A329）、Relaxin（RootHide 型）越狱；PreferenceLoader 2.2.8 已装，设置根页有「越狱插件」分组。
- 宿主 DSH 在本机（就是这台 Windows 云电脑）：Web 服务 `127.0.0.1:52009`，宠物 API 前缀 `/dsh-pet-7340`；`dsh-plugin-mobile-gateway` 的 WS 在 `127.0.0.1:3081`（`/ws/mobile`，Whaleness 用）；`3065` = Agent2API，**不可动**。
- 外网入口 `https://dsh.vbox.ltd:42429` → SakuraFrp `#29715647` → caddy `7789` → 路径分流：`/dsh-pet-7340/*` → 52009，其余 → 3081。
- 上游插件版本 **0.4.9**（profile `~/.dsh/profiles/desktop`，pnpm 管理）；宠物壳需**完全退出 DSH（含托盘）**才换新 lib。
- 本机没有 git、没有 python 在 PATH：git 用 GitHub API 推送，python 用 `C:\Users\Admin\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe`。

## 项目约定

- 阶段闸门四件（自检 → 记忆点 → 全量推送 → 回报）写进方案 §20 与本仓 `AGENTS.md`，操作员指定为硬性条件。
- 我不会用终端 → 所有真机步骤必须给图形界面或浏览器 URL。
- 面板所有"服务商/模型/音色"字段必须从宿主动态拉（`/models`、`/voice/voices`），值不在列表里标红，不静默失败。
- 文档只增不改历史：每次修订在头部加 changelog，正文用 vN 标记。

## 关键决策

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
- S2：CI run 43690041210 双 job 绿 → deb 16054B（arm64+arm64e）/ sha256 61e1a356...cb3 → Release v0.1.0-15 → journal 六段齐 → 推送 147eb37。**遗留**：五条真机现象 NOT RUN。
- S1 真机验收通过：rootless 包在 Relaxin 上注入成功（boot + springboard-ready，pid 14789 / iOS 17.0）→ 不需要 roothide 变体。
- 本机**没有 git**：所有推送走 _push.mjs（GitHub REST），凭据读环境变量 GH_TOKEN，不落盘、不进仓库。
- 空仓库首次推送必须先用 Contents API 落一个文件（否则 git-data 接口全 409 Git Repository is empty）。
