# 致谢与借鉴边界

## 上游（本体）

- **dsh-pet** —— <https://github.com/PC2005-cloud/dsh-pet>
  DeepSeek Harness 的桌面宠物插件。本项目是它的 **iOS 越狱移植**，不是分支，也不是重写：
  行为契约（HTTP API、配置键名、动画语义）全部以上游为准。
- 形象与素材授权 → 见 `LICENSE-ASSETS`。

## 形象

- 原型「溟月」：B 站 **@上善无形**
- 女仆鲸鱼娘设计：**@ZipZipPipe**
- 归属：社区二创 DeepSeek「大肥鱼」鲸鱼娘（非官方）

## 借鉴（只有设计，不含代码）

- **dsh-mobile / Whaleness** —— <https://github.com/Clarklevis1995/dsh-mobile>
  借鉴四样**交互设计**：多网关存档、配对串导入、日志导出页、按住说话。
  它的 `dsh-plugin-mobile-gateway` 协议（`/ws/mobile` + 增量 patch 帧）本项目**不复刻、不占用**
  —— 3081 那条腿留给 Whaleness 自己，本项目只走 `/dsh-pet-7340/*`（52009）。

## 工具与运行时

- Theos / ldid / dpkg-deb / fakeroot
- Caddy（本机反代分流，非本项目依赖）
- SakuraFrp（用户自有隧道）

## 声明

本仓库不含上游的任何二进制或素材包，只含本项目自己的源码、脚本与文档。
