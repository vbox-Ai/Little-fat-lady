# AGENTS.md · 协作规则（硬性）

> 本文件是给**任何在本仓库干活的 agent / 人**的约束。与 `docs/PLAN.md` §20 同源，冲突时以 §20 为准。

## 1. 阶段闸门（不可跳）

每个阶段（S0–S12）关闭前必须依次做完四件，缺一不许开下一步：

1. **自检遗漏** —— `node scripts/check-repo.mjs` 全绿 + 本阶段验收清单逐条过 + 三问（新坑/常量写进文档没？有静默失败分支没？有只在我机器上成立的假设没？）。
2. **写记忆点** —— `docs/journal/S<xx>.md` 六段齐（做了什么 / 证据 / 决定 / 遗留 / 风险 / 下一步），并在 `MEMORY.md` 加一行索引。
3. **全量推送** —— `git add -A && git commit -m "S<xx>: <一句话>" && git push origin main`，本地 `HEAD` 必须等于远端 `main`。
4. **回报** —— 把 commit sha、验收输出、下一步入口写进对话。

违规：跳过任一动作 → 该阶段视为未完成；"先写下一步、回头补记忆" → 回退重做。

## 2. 红线

- **不提交凭据**：token / 密码 / 隧道密钥一律走环境变量或本地文件，`.gitignore` 已挡 `dsh-pet-config-live.json` 等实测产物；`check-repo.mjs` 会扫 `ghp_` / `github_pat_` 前缀。
- **不改上游**：`node_modules/dsh-pet/**` 只读。要动行为，走它的 HTTP API（`/config` 用 **PUT 局部合并**，**永不** `POST /config`——那是恢复默认）。
- **不杀桌面宠物**：手机端**永不**调用 `GET|POST /quit`。
- **不抢事件**：`/menu/events` 读取即消费；`/ws/mobile`（3081）是 Whaleness 的腿，本项目不碰。
- **素材不入库**：完整包 100MB+ 且 CC BY-NC-SA，仓库只放 3 段占位。

## 3. 提交信息

```
S<xx>: <动词> <对象>           例：S01: add springboard injection skeleton
docs: <改了什么>               例：docs: v2.16 补 §21 通知落地实测
fix:  <修了什么>               例：fix: 取消长按计时器导致的触摸泄漏
```

正文里必须有一行 `Gate: ①②③④`（四个动作都做了才写全）。

## 4. 版本号

- `VERSION` 文件 = `MAJOR.MINOR.PATCH`；deb 版本 = `MAJOR.MINOR.PATCH-BUILD`，`BUILD` = `git rev-list --count HEAD`。
- 递增用 `node scripts/bump-version.mjs --patch|--minor|--major`，不要手改。
- 面板"关于"页显示的版本必须与 `VERSION` 一致（CI 会校验）。

## 5. 真机

- 我没有手机访问权：所有真机步骤必须写成**图形界面或浏览器 URL**的形式交给操作员（他不会用终端）。
- 需要终端命令时，写成可复制的一段，并说明"在手机上用 NewTerm / SSH 跑"。
