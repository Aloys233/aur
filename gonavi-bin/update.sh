#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
    echo "用法: ./update.sh <新版本号> [--no-push]"
    echo "示例: ./update.sh 0.7.4"
}

if [ $# -lt 1 ]; then
    echo "错误：缺少版本号参数。"
    usage
    exit 1
fi

NEW_VER=$1
PUSH=1

if [ "${2:-}" = "--no-push" ]; then
    PUSH=0
elif [ $# -gt 1 ]; then
    echo "错误：未知参数：$2"
    usage
    exit 1
fi

echo "🚀 开始更新 GoNavi-bin 到版本 $NEW_VER ..."

# 自动修改 PKGBUILD 中的版本号，并将 pkgrel 重置为 1
echo "📝 正在修改 PKGBUILD ..."
sed -i "s/^pkgver=.*/pkgver=$NEW_VER/" PKGBUILD
sed -i "s/^pkgrel=.*/pkgrel=1/" PKGBUILD

# 下载新源码并更新 SHA256 校验和
echo "📥 正在获取新版本并更新哈希值 (updpkgsums) ..."
updpkgsums

# 生成 AUR 必需的 .SRCINFO 文件
echo "⚙️ 正在生成 .SRCINFO 文件 ..."
makepkg --printsrcinfo > .SRCINFO

# 清理 updpkgsums 下载到本地的源码压缩包与临时文件
rm -f GoNavi-*.tar.gz *.part

if [ "$PUSH" -eq 1 ]; then
    echo "📦 正在提交到 AUR 仓库 ..."
    git add PKGBUILD .SRCINFO
    git commit -m "Update to v$NEW_VER"

    echo "☁️ 正在推送到 AUR 服务器 ..."
    git push
    echo "🎉 更新全流程搞定！AUR 上已经是最新版了。"
else
    echo "✅ 已完成文件更新与 .SRCINFO 生成 (--no-push)。"
fi
