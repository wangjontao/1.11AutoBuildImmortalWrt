#!/bin/bash
set -e

source shell/custom-packages.sh
# 该文件实际为 imagebuilder 容器内的 build.sh

echo "🔄 同步第三方 run 文件仓库..."
git clone --depth=1 https://github.com/wukongdaily/store.git /tmp/store-run-repo

# 拷贝 run / ipk 到 extra-packages
mkdir -p /home/build/immortalwrt/extra-packages
cp -r /tmp/store-run-repo/run/arm64/* /home/build/immortalwrt/extra-packages/

echo "✅ 已拷贝 run 文件："
ls -lh /home/build/immortalwrt/extra-packages || true

# 解包并准备 ipk
sh shell/prepare-packages.sh

echo "✅ 当前 packages 目录："
ls -lah /home/build/immortalwrt/packages/ || true

# 添加架构优先级
sed -i '1i\
arch aarch64_generic 10\n\
arch aarch64_cortex-a53 15' repositories.conf

# 构建目标
echo "🧱 Building for PROFILE: $PROFILE"
echo "📦 Include Docker: $INCLUDE_DOCKER"

# -----------------------------
# PPPoE 配置
# -----------------------------
mkdir -p /home/build/immortalwrt/files/etc/config

cat << EOF > /home/build/immortalwrt/files/etc/config/pppoe-settings
enable_pppoe=${ENABLE_PPPOE}
pppoe_account=${PPPOE_ACCOUNT}
pppoe_password=${PPPOE_PASSWORD}
EOF

echo "📄 pppoe-settings:"
cat /home/build/immortalwrt/files/etc/config/pppoe-settings

echo "$(date '+%F %T') - Build start"

# -----------------------------
# 基础插件
# -----------------------------
PACKAGES="
curl
luci
luci-i18n-base-zh-cn
luci-i18n-firewall-zh-cn
luci-theme-argon
luci-app-argon-config
luci-i18n-argon-config-zh-cn
luci-i18n-diskman-zh-cn
luci-i18n-package-manager-zh-cn
luci-i18n-ttyd-zh-cn
openssh-sftp-server
luci-i18n-filemanager-zh-cn
luci-i18n-dufs-zh-cn
"

# -----------------------------
# 第三方插件（PassWall / HomeProxy / NPC）
# -----------------------------
THIRD_PARTY_PACKAGES="
luci-app-passwall
luci-i18n-passwall-zh-cn
luci-app-passwall2
luci-i18n-passwall2-zh-cn
luci-app-homeproxy
luci-i18n-homeproxy-zh-cn
luci-app-npc
npc
"

# -----------------------------
# 运行依赖（非常关键）
# -----------------------------
RUNTIME_DEPS="
xray-core
sing-box
iptables
ipset
kmod-tun
kmod-inet-diag
"

# -----------------------------
# GL.iNet 特殊机型限制
# -----------------------------
if [ "$PROFILE" = "glinet_gl-axt1800" ] || [ "$PROFILE" = "glinet_gl-ax1800" ]; then
    echo "⚠️ $PROFILE 使用 snapshot / apk，限制部分第三方插件"
    PACKAGES="$PACKAGES luci-app-passwall luci-app-passwall2 luci-app-npc npc"
else
    PACKAGES="$PACKAGES $THIRD_PARTY_PACKAGES"
fi

# -----------------------------
# Docker
# -----------------------------
if [ "$INCLUDE_DOCKER" = "yes" ]; then
    PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
    echo "🐳 Docker enabled"
fi

# -----------------------------
# OpenClash core 自动处理
# -----------------------------
if echo "$PACKAGES" | grep -q "luci-app-openclash"; then
    echo "✅ OpenClash detected, downloading core..."
    mkdir -p files/etc/openclash/core

    wget -qO- \
      https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz \
      | tar xOvz > files/etc/openclash/core/clash_meta

    chmod +x files/etc/openclash/core/clash_meta

    wget -q \
      https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat \
      -O files/etc/openclash/GeoIP.dat

    wget -q \
      https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat \
      -O files/etc/openclash/GeoSite.dat
else
    echo "ℹ️ OpenClash not selected"
fi

# -----------------------------
# 合并依赖
# -----------------------------
PACKAGES="$PACKAGES $RUNTIME_DEPS $CUSTOM_PACKAGES"

# -----------------------------
# 构建前自检
# -----------------------------
echo "🔍 检查第三方 ipk："
ls /home/build/immortalwrt/packages | grep -E "passwall|homeproxy|npc|xray|sing" || true

# -----------------------------
# 开始构建
# -----------------------------
echo "$(date '+%F %T') - Building image"
echo "📦 PACKAGES:"
echo "$PACKAGES"

make image \
  PROFILE="$PROFILE" \
  PACKAGES="$PACKAGES" \
  FILES="/home/build/immortalwrt/files"

echo "$(date '+%F %T') - ✅ Build completed successfully"
