# 小肥娘 · Little Fat Lady

把 [dsh-pet](https://github.com/PC2005-cloud/dsh-pet)（DeepSeek Harness 的桌面宠物）搬到 **iPhone** 上的越狱插件：
桌面、锁屏之后、以及**任意 App 内**都能看见那只鲸鱼娘，保留上游全部动画与能力（余额、碎碎念、工作状态、待办、睡觉、语音、对话、多开）。

- 目标机：**iPhone 14 Pro（A16 · arm64e）· iOS 17.0 · Relaxin（RootHide 型）越狱**
- 宿主：DeepSeek Harness 的 `dsh-pet` 插件（HTTP API 在 `127.0.0.1:52009/dsh-pet-7340`）
- 外网：`https://dsh.vbox.ltd:42429`（SakuraFrp → caddy 按路径分流）
- 备用腿：Tailscale

## 当前状态

**S0 · 环境基线（进行中）** —— 仓库骨架、CI、探针脚本、双许可证。
功能代码从 **S1** 开始（空壳注入）。方案全文见 [`docs/PLAN.md`](docs/PLAN.md)（v2.15，1616 行）。

## 目录

```
docs/PLAN.md            完整开发方案（v2.15）
docs/journal/           每阶段记忆点（S00、S01…）
scripts/                check-repo / bump-version / 真机探针
packages/ios/           Theos 工程（S1 起）
.github/workflows/      CI 与发版
MEMORY.md               跨会话记忆索引
AGENTS.md               协作规则（含阶段闸门）
```

## 许可与署名 · 必读

| 对象 | 许可 |
| --- | --- |
| 本项目代码 | **MIT**（见 `LICENSE`） |
| 宠物形象与动画素材 | **CC BY-NC-SA 4.0**，**禁止任何形式商用**（见 `LICENSE-ASSETS`） |

形象原点：社区二创的 DeepSeek「大肥鱼」鲸鱼娘（非官方）。原型「溟月」出自 B 站 **@上善无形**，
女仆鲸鱼娘设计出自 **@ZipZipPipe**，素材仓库 **@PC2005-cloud/dsh-pet**。
二次创作在公开渠道分发时**必须署名**上述来源。

## 阶段闸门（硬性）

每个阶段必须依次完成：**自检遗漏 → 写记忆点 → 全量推送仓库 → 回报 commit**，四件齐才算关闭，缺一不许开下一步。
规则原文见方案 **§20**，索引见 `AGENTS.md`。
