#!/bin/sh
# scripts/probe/collect-device-env.sh —— S0 真机探针（在 iPhone 上用 NewTerm 或 SSH 跑）
# 用法：sh collect-device-env.sh > /var/mobile/Library/DSHPet-env.txt 2>&1 ; cat /var/mobile/Library/DSHPet-env.txt
# 输出粘回对话即可。只读，不改任何东西。

set -u
echo "=== DSHPet S0 probe $(date '+%Y-%m-%dT%H:%M:%S%z') ==="

echo
echo "--- P1 系统与内核 ---"
uname -a
sw_vers 2>/dev/null || true
sysctl -n hw.machine hw.product 2>/dev/null || true
sysctl -n kern.osversion 2>/dev/null || true

echo
echo "--- P2 越狱类型（roothide? rootless?） ---"
if [ -d /var/containers/Bundle/tweaksupport ]; then
  echo "tweaksupport: YES  (rootless/roothide 风格)"
  ls -ld /var/containers/Bundle/tweaksupport 2>/dev/null
  ls -1 /var/containers/Bundle/tweaksupport/Library/MobileSubstrate/DynamicLibraries 2>/dev/null | head -20
else
  echo "tweaksupport: NO"
fi
if [ -e /var/jb ]; then echo "/var/jb: EXISTS -> $(readlink -f /var/jb 2>/dev/null || echo '?')"; else echo "/var/jb: ABSENT"; fi
if [ -d /var/mobile/Library/Preferences ]; then echo "prefs dir: ok"; fi

echo
echo "--- P3 包管理器与关键依赖 ---"
which dpkg sileo sbreload 2>/dev/null || true
dpkg -l 2>/dev/null | grep -i -E 'preferenceloader|ellekit|substrate|safe ?mode|libhooker|cephei' || echo "(none matched)"
echo "--- dpkg 版本 3 行 ---"
dpkg -l 2>/dev/null | head -3

echo
echo "--- P4 注入器情况 ---"
ls -1 /usr/lib/libsubstrate* /usr/lib/libhooker* /var/jb/usr/lib/libsubstrate* 2>/dev/null || echo "(no substrate/hooker lib visible)"
ls -1 /Library/MobileSubstrate/DynamicLibraries 2>/dev/null | head -20 || true

echo
echo "--- P5 可写目录与磁盘 ---"
df -h / 2>/dev/null | head -3
ls -ld /var/mobile/Library 2>/dev/null
mkdir -p /var/mobile/Library/DSHPet 2>/dev/null && echo "DSHPet 目录: 可写" || echo "DSHPet 目录: 不可写"
du -sh /var/mobile/Library/DSHPet 2>/dev/null || true

echo
echo "--- P6 网络（能不能到宿主） ---"
echo "P6.1 局域网网关可达性（无 curl 时用 nc）:"
which curl || echo "(no curl)"
if command -v curl >/dev/null 2>&1; then
  curl -s -o /dev/null -w "public state: %{http_code} in %{time_total}s\n" \
    --max-time 8 "https://dsh.vbox.ltd:42429/dsh-pet-7340/state" || echo "public state: FAIL"
  curl -s -o /dev/null -w "public root:  %{http_code}\n" \
    --max-time 8 "https://dsh.vbox.ltd:42429/" || echo "public root: FAIL"
fi
ifconfig 2>/dev/null | grep -E 'inet |utun' | head -10 || true

echo
echo "--- P7 显示与机型 ---"
system_profiler SPHardwareDataType 2>/dev/null | head -12 || true
scutil --get ComputerName 2>/dev/null || true

echo
echo "=== END ==="
