#!/bin/sh
# scripts/build-deb.sh <BUILD>  —— 在 CI（macOS runner）里编 S1 的 deb
# 需要：THEOS 环境变量、dpkg-deb、ldid、lipo
set -eu

BUILD="${1:-local}"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
VER=$(cat "$ROOT/VERSION")
DEBVER="${VER}-${BUILD}"
[ -n "${THEOS:-}" ] || { echo "THEOS 未设置"; exit 2; }

cd "$ROOT/packages/ios"
echo "== 版本：$DEBVER =="

# 版本常量注入（方案 §4.5）：编译期把 VERSION-BUILD 写进 dylib，面板「关于」读同一份
cat > DSHPetVersion.h <<EOF
// 自动生成，勿手改（scripts/build-deb.sh）
#define DSHPET_VERSION_STRING @"${DEBVER}"
EOF
echo "== 生成 DSHPetVersion.h：${DEBVER} =="

make clean >/dev/null 2>&1 || true

if make package FINALPACKAGE=1 \
        PACKAGE_VERSION="$DEBVER" \
        THEOS_PACKAGE_SCHEME=rootless \
        ARCHS="arm64 arm64e" \
        TARGET=iphone:clang:latest:17.0; then
  echo "== make package 成功 =="
else
  echo "== make package 失败，走 dpkg-deb 兜底 =="
  make FINALPACKAGE=1 PACKAGE_VERSION="$DEBVER" ARCHS="arm64 arm64e" TARGET=iphone:clang:latest:17.0 || exit 1
  STAGE="$ROOT/packages/ios/.theos/_"
  [ -d "$STAGE" ] || { echo "没有 staging 目录：$STAGE"; exit 1; }
  mkdir -p "$STAGE/DEBIAN"
  cp "$ROOT/packages/ios/layout/DEBIAN/"* "$STAGE/DEBIAN/" 2>/dev/null || true
  # 把 control 的 Version 改成真实版本
  sed -i.bak "s/^Version:.*/Version: $DEBVER/" "$STAGE/DEBIAN/control" 2>/dev/null || true
  rm -f "$STAGE/DEBIAN/control.bak"
  dpkg-deb --build --root-owner-group "$STAGE" "$ROOT/packages/ios/dshpet-${DEBVER}.deb" || exit 1
fi

echo "== 产物 =="
ls -l "$ROOT"/packages/ios/packages/*.deb 2>/dev/null || ls -l "$ROOT"/packages/ios/*.deb
