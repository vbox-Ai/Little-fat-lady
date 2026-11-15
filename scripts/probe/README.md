# 真机探针（S0）

我没有手机访问权，这一步必须你来做。**只读，不改任何东西。**

## 怎么跑（选一个）

**A. NewTerm（建议，图形界面点一下）**
1. 打开 NewTerm，输入：
   ```sh
   sh /var/mobile/Library/DSHPet-probe.sh
   ```
   （先用 Filza 或 AirDrop 把 `collect-device-env.sh` 放到 `/var/mobile/Library/DSHPet-probe.sh`；或者直接在 NewTerm 里 `curl -sL <raw 链接> -o /var/mobile/Library/DSHPet-probe.sh`）

**B. SSH**（如果你手机开了 OpenSSH）
```sh
ssh mobile@<手机IP> 'sh -s' < collect-device-env.sh
```

## 我要看什么（七段）

| 段 | 判定什么 |
| --- | --- |
| P1 | 确认 iOS 17.0 / arm64e，内核版本对得上 Relaxin 支持表 |
| P2 | **roothide 还是 rootless** → 决定装哪个 deb 变体、`JBROOT()` 落在哪 |
| P3 | `preferenceloader` 在不在、注入器是 ElleKit 还是 Substrate |
| P4 | 动态库目录在 `/Library/MobileSubstrate/DynamicLibraries` 还是 `/var/jb/...` |
| P5 | `/var/mobile/Library` 能不能写（日志与配置落这里） |
| P6 | 手机能不能直接打 `https://dsh.vbox.ltd:42429/dsh-pet-7340/state`（决定要不要走 Tailscale） |
| P7 | 机型信息兜底 |

## 只要三段也行

时间紧就只给 **P2 + P3 + P6** —— 这三段决定 S1 能不能一次装对。
