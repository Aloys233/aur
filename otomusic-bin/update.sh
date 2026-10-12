#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
    echo "用法: ./update.sh <新版本号> [--no-push]"
    echo "示例: ./update.sh 1.0.4"
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

if [[ ! "$NEW_VER" =~ ^[0-9A-Za-z._+-]+$ ]]; then
    echo "错误：版本号包含不支持的字符：$NEW_VER"
    exit 1
fi

for cmd in curl sha256sum awk sed makepkg git; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "错误：缺少命令：$cmd"
        exit 1
    fi
done

replace_checksum() {
    local array_name=$1
    local checksum=$2

    sed -i "s/^${array_name}=.*/${array_name}=('${checksum}')/" PKGBUILD
}

fetch_checksum() {
    local upstream_arch=$1
    local output_file=$2
    local url="https://github.com/Aloys233/OtoMusic/releases/download/v${NEW_VER}/OtoMusic-${NEW_VER}-linux-${upstream_arch}.tar.gz"

    echo "正在下载并计算 ${upstream_arch} tarball 的 SHA256 ..." >&2
    curl -fL --retry 3 --output "$output_file" "$url"
    sha256sum "$output_file" | awk '{print $1}'
}

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

echo "开始更新 otomusic-bin 到版本 $NEW_VER ..."

x86_64_sum=$(fetch_checksum "x64" "$tmpdir/otomusic-linux-x64.tar.gz")
aarch64_sum=$(fetch_checksum "arm64" "$tmpdir/otomusic-linux-arm64.tar.gz")

echo "正在修改 PKGBUILD ..."
sed -i "s/^pkgver=.*/pkgver=$NEW_VER/" PKGBUILD
sed -i "s/^pkgrel=.*/pkgrel=1/" PKGBUILD
replace_checksum "sha256sums_x86_64" "$x86_64_sum"
replace_checksum "sha256sums_aarch64" "$aarch64_sum"

echo "正在生成 .SRCINFO 文件 ..."
makepkg --printsrcinfo > .SRCINFO

if [ "$PUSH" -eq 1 ]; then
    if git diff --quiet -- PKGBUILD .SRCINFO; then
        echo "没有需要提交的变更。"
        exit 0
    fi

    echo "正在提交到 AUR 仓库 ..."
    git add PKGBUILD .SRCINFO
    git commit -m "Update to v$NEW_VER"

    echo "正在推送到 AUR 服务器 ..."
    git push
else
    echo "已跳过本地 Git 提交与推送 (--no-push)。"
fi

echo "更新完成。"
