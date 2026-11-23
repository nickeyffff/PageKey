#!/usr/bin/env bash
# PageKey 一键安装脚本
#
#   curl -fsSL https://github.com/nickeyffff/PageKey/releases/latest/download/install.sh | bash
#
# 做四件事：下载最新 Release → 解压 → 安装到 ~/Applications → 去掉隔离属性
# 不会改动系统设置，不会写入任何后台服务。

set -euo pipefail

REPO="nickeyffff/PageKey"
DEST="${HOME}/Applications"
APP="PageKey.app"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

say() { printf '  %s\n' "$*"; }
ok()  { printf '✓ %s\n' "$*"; }
die() { printf '✗ %s\n' "$*" >&2; exit 1; }

echo "PageKey 安装程序"
echo

command -v curl >/dev/null || die "需要 curl"
command -v unzip >/dev/null || die "需要 unzip"

say "下载最新版本…"
URL="https://github.com/${REPO}/releases/latest/download/PageKey.app.zip"
if ! curl -fsSL "${URL}" -o "${TMP}/PageKey.zip"; then
  say "直连下载失败，改用 GitHub API 查询…"
  URL="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
        | grep -o 'https://[^"]*PageKey\.app\.zip' | head -1 || true)"
  [ -n "${URL}" ] || die "找不到可下载的发布包，请检查网络或改用源码安装"
  curl -fsSL "${URL}" -o "${TMP}/PageKey.zip"
fi
ok "已下载"

say "解压…"
unzip -q "${TMP}/PageKey.zip" -d "${TMP}"
[ -d "${TMP}/${APP}" ] || die "压缩包结构异常：缺少 ${APP}"
ok "已解压"

say "安装到 ${DEST}…"
mkdir -p "${DEST}"
rm -rf "${DEST:?}/${APP}"
cp -R "${TMP}/${APP}" "${DEST}/"
ok "已安装 ${DEST}/${APP}"

# 关键：去掉从网络下载带来的隔离标记，否则首次打开会被 Gatekeeper 拦下
if xattr -p com.apple.quarantine "${DEST}/${APP}" >/dev/null 2>&1; then
  xattr -dr com.apple.quarantine "${DEST}/${APP}" 2>/dev/null && ok "已移除隔离属性（quarantine）"
else
  ok "无需移除隔离属性"
fi

# 重新做一次本地 ad-hoc 签名，确保可执行文件签名有效
codesign --force --sign - --identifier local.pagekey.windowsapp "${DEST}/${APP}" 2>/dev/null \
  && ok "已重新签名" || say "签名跳过（不影响运行）"

echo
ok "安装完成"
echo
echo "下一步："
echo "  1. 双击 ${DEST}/${APP}"
echo "  2. 菜单栏出现 ⌨ 图标即为常驻成功"
echo "  3. 切到 Windows App，右上角会提示「已启用」"
echo
echo "开机自启（可选）：系统设置 → 通用 → 登录项与扩展 → 添加 ${APP}"
echo "卸载：${DEST}/${APP}/Contents/MacOS/pagekey --reset ; rm -rf ${DEST}/${APP}"
