#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CONFIG_FILE="${ROOT_DIR}/packages.json"

TARGET="${1:-${TARGET_PKG:-all}}"
PUSH_AUR="${PUSH_AUR:-true}"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ 找不到配置文件: $CONFIG_FILE"
    exit 1
fi

total_updated=0

# 读取 packages.json 中的项数
count=$(jq '. | length' "$CONFIG_FILE")

for ((i=0; i<count; i++)); do
    item=$(jq -c ".[$i]" "$CONFIG_FILE")
    name=$(echo "$item" | jq -r '.name')
    dir_name=$(echo "$item" | jq -r '.dir')
    aur_name=$(echo "$item" | jq -r '.aur_name')
    upstream=$(echo "$item" | jq -r '.upstream')

    if [ "$TARGET" != "all" ] && [ "$TARGET" != "$name" ] && [ "$TARGET" != "$dir_name" ]; then
        continue
    fi

    echo ""
    echo "============================================================"
    echo "📦 正在检查包: $name ($dir_name)"
    echo "🔗 上游仓库: https://github.com/$upstream"
    echo "============================================================"

    pkg_dir="${ROOT_DIR}/${dir_name}"
    if [ ! -d "$pkg_dir" ] || [ ! -f "${pkg_dir}/PKGBUILD" ]; then
        echo "⚠️ 目录或 PKGBUILD 不存在: $pkg_dir，跳过。"
        continue
    fi

    # 获取当前 PKGBUILD 中的 pkgver
    current_ver=$(grep -E "^pkgver=" "${pkg_dir}/PKGBUILD" | head -n1 | cut -d= -f2 | tr -d " '\";")
    echo "📌 当前本地版本: $current_ver"

    # 获取上游 GitHub 最新 Release
    api_url="https://api.github.com/repos/${upstream}/releases/latest"
    release_json=$(curl -sSL --retry 3 "${api_url}" || true)
    latest_tag=$(echo "$release_json" | jq -r '.tag_name // empty')

    if [ -z "$latest_tag" ] || [ "$latest_tag" = "null" ]; then
        echo "⚠️ 获取上游最新 Release 失败（可能未发 Release 或触发速率限制），跳过。"
        continue
    fi

    # 去掉前导 'v'
    latest_ver="${latest_tag#v}"
    echo "🚀 上游最新版本: $latest_ver (tag: $latest_tag)"

    if [ "$current_ver" = "$latest_ver" ]; then
        echo "✨ 已是最新版本 ($current_ver)，无需更新。"
        continue
    fi

    echo "⚡ 发现新版本 $current_ver -> $latest_ver！开始执行更新..."
    
    cd "$pkg_dir"
    if [ -x "./update.sh" ]; then
        ./update.sh "$latest_ver" --no-push
    else
        echo "❌ 找不到可执行的 update.sh: ${pkg_dir}/update.sh"
        cd "$ROOT_DIR"
        continue
    fi
    cd "$ROOT_DIR"

    total_updated=$((total_updated + 1))

    # 如果开启了 AUR 推送
    if [ "$PUSH_AUR" = "true" ] || [ "$PUSH_AUR" = "1" ]; then
        echo "📤 准备推送到 AUR: $aur_name ..."
        tmp_aur=$(mktemp -d)
        
        # 克隆 AUR 仓库
        aur_url="ssh://aur@aur.archlinux.org/${aur_name}.git"
        echo "正在克隆 $aur_url ..."
        if git clone "$aur_url" "$tmp_aur"; then
            # 拷贝文件，排除 update.sh 等
            rsync -av --exclude="update.sh" --exclude=".*" --exclude="*.bak" "${pkg_dir}/" "$tmp_aur/" 2>/dev/null || {
                cp "${pkg_dir}/PKGBUILD" "$tmp_aur/"
                cp "${pkg_dir}/.SRCINFO" "$tmp_aur/"
                for extra in "${pkg_dir}"/*.svg "${pkg_dir}"/*.desktop "${pkg_dir}"/*.png "${pkg_dir}"/*.install; do
                    if [ -f "$extra" ]; then
                        cp "$extra" "$tmp_aur/"
                    fi
                done
            }

            cd "$tmp_aur"
            git config user.name "Aloys23"
            git config user.email "aloys233@gmail.com"
            git add -A

            if ! git diff --cached --quiet; then
                git commit -m "Update to v${latest_ver}"
                echo "🚀 正在推送至 AUR master 分支..."
                git push origin master
                echo "🎉 成功更新并推送到 AUR: $aur_name (v$latest_ver)！"
            else
                echo "ℹ️ AUR 仓库内容没有实质变化，跳过推送。"
            fi
            cd "$ROOT_DIR"
            rm -rf "$tmp_aur"
        else
            echo "❌ 克隆 AUR 仓库失败，请检查 SSH 密钥与网络。"
            rm -rf "$tmp_aur"
        fi
    else
        echo "ℹ️ 已跳过推送到 AUR (PUSH_AUR=$PUSH_AUR)。"
    fi
done

echo ""
echo "============================================================"
echo "🎯 更新检查完成！共更新了 $total_updated 个包。"
echo "============================================================"
