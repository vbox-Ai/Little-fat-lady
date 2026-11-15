# 安装失败自救（dpkg 被中断 / 一开 Sileo 就注销）

越狱机装包时最怕的不是装不上，是 **dpkg 事务被打断**：包停在 half-configured 状态，
之后每次打开 Sileo 都会重试收尾、收不了尾就注销桌面。

## 0 触发原因（我们踩过的真实例子）

`postinst` 里执行了 `sbreload` / `killall -9 SpringBoard`。dpkg 还在 configure 阶段，
桌面被干掉 → Sileo 的安装事务中断 → 留下 interrupted 状态。

**结论：装包脚本里永远不要重启 SpringBoard。** 需要生效就让用户在 Sileo 结束时点"重启 SpringBoard"。

## 1 先做：停止反复打开 Sileo

每开一次都可能再跑一遍中断事务、再注销一次。先把它放一边。

## 2 重启一次设备

电话助手长按菜单 → **重启用户空间**（或直接关机重开）。这一步能清掉大量瞬时状态。

## 3 打开 Sileo，让它自己修

- 若弹出"dpkg 被中断 / 是否修复"，点 **修复**（等价于 `dpkg --configure -a`）。
- 修完再看"已安装"里那个包：仍是半装状态就 **卸载** 它，再重新安装。

## 4 Sileo 不给修、或一开就注销 → 用 Filza 手工解锁

路径分两种布局，先看哪个存在：

| 布局 | dpkg 数据库 |
|---|---|
| rootless（本项目发布的就是这种） | `/var/jb/var/lib/dpkg/` |
| rootful | `/var/lib/dpkg/` |

在该目录下：

1. 删除 `lock`、`lock-frontend`（锁文件，删了下次 dpkg 会重建）；
2. 清空 `updates/` 里的临时文件（`updates/0000`、`0001`…，只删文件，别删目录）；
3. 回到 Sileo → 修复 / 卸载那个包；
4. 仍不行再看 `status` 里该包的 `Status:` 行，形如 `install ok half-configured` 说明它确实卡住了，
   用 Sileo 的"重新安装"跑一遍收尾。

## 5 最后手段

- Sileo → 软件包 → 找到 `com.vboxai.littlefatlady` → 卸载；
- 或 Filza 删 `/var/jb/Library/MobileSubstrate/DynamicLibraries/DSHPet.dylib` 与
  `/var/jb/Library/MobileSubstrate/DynamicLibraries/DSHPet.plist`，再重启用户空间。

卸载/删除后重新装 `v0.1.0-42` 或更新的包（0.1.0-42 起 postinst 不再碰 SpringBoard）。

## 6 以后怎么避免

- 本项目：`postinst` 只做 mkdir / cp / chown；`postrm` 只在 `remove|purge` 时删数据；
  Makefile 不挂 `after-install` 的 sbreload。
- 装别人的包时若也遇到同样现象，多半也是它的 postinst 在杀 SpringBoard。
