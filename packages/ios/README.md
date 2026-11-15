# packages/ios —— Theos 工程（S1 起）

**S0 故意留空。** 理由写在 `docs/journal/S00.md` §3 决定 2：
先建一个编不出 deb 的工程会让 CI 出现"绿但没产物"的假绿，所以 S1 一次性把下面四件建齐：

```
packages/ios/
├── Makefile                 # THEOS 工程定义，ARCHS = arm64 arm64e，TARGET=iphone:clang:latest:17.0
├── control                  # Depends: preferenceloader, firmware (>= 17.0)；两变体 Package 名不同
├── Tweak.xm                 # S1 只 hook SpringBoard，只写一条 boot 日志，不出 UI
├── layout/
│   ├── DEBIAN/postinst      # 建 /var/mobile/Library/DSHPet/{logs,cache,assets}，chown mobile
│   ├── DEBIAN/postrm
│   ├── Library/PreferenceLoader/Preferences/DSHPet.plist   # 设置入口（S7 才有面板内容）
│   └── Library/MobileSubstrate/DynamicLibraries/DSHPet.plist
└── src/                     # 随阶段增长
```

## S1 的关闭条件（抄自方案 §16）

- 装完：`/var/mobile/Library/DSHPet/logs/runtime.jsonl` 里有 `{"evt":"boot",...}`
- 卸载后：`ps -ax | grep -i dshpet` 空、`DynamicLibraries` 里无残留
- 双包都能装、都能卸；`lipo -info` 含 `arm64e`
- CI 出两个 deb + `SHA256SUMS`

## 不要做的事

- 不要在 S1 就接 `/state`（数据层是 S3/S4）。
- 不要复制上游的 `assets/`（素材不入库，见 `LICENSE-ASSETS` §3）。
