#!/bin/sh
# scripts/build-deb.sh <BUILD> —— 在 CI（macOS runner）里编出可安装的 deb
# 需要：THEOS 环境变量、dpkg-deb、ldid、lipo
set -eu

BUILD="${1:-local}"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
VER=$(cat "$ROOT/VERSION")
DEBVER="${VER}-${BUILD}"
[ -n "${THEOS:-}" ] || { echo "THEOS 未设置"; exit 2; }

cd "$ROOT/packages/ios"
echo "== 版本：$DEBVER =="

# 版本常量注入（方案 §4.5）：编译期把 VERSION-BUILD 写进 dylib，面板读到的与仓库一致
cat > DSHPetVersion.h <<EOF
// 自动生成，勿手改（scripts/build-deb.sh）
#define DSHPET_VERSION_STRING @"${DEBVER}"
EOF
echo "== 生成 DSHPetVersion.h：$DEBVER =="

make clean >/dev/null 2>&1 || true

# 编译失败就失败，绝不打包半成品：
# 之前这里有一条 "make package 失败 → 直接 dpkg-deb 打 .theos/_" 的兜底，
# 它会把一个缺少新代码的旧 staging 打成 deb，装上去表现为"功能没生效"，
# 掩盖真实编译错误（0.1.0-32 就是这么发出去的）。
make package FINALPACKAGE=1 \
     PACKAGE_VERSION="$DEBVER" \
     THEOS_PACKAGE_SCHEME=rootless \
     ARCHS="arm64 arm64e" \
     TARGET=iphone:clang:latest:15.0

echo "== 产物 =="
ls -l "$ROOT"/packages/ios/packages/*.deb
