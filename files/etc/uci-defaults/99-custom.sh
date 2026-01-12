#!/bin/sh
# 99-custom.sh - immortalwrt 首次启动初始化脚本

LOGFILE="/etc/config/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >>$LOGFILE

# =========================
# 防火墙：放行 WAN 入站（首次访问 WebUI）
# =========================
uci -q set firewall.wan.input='ACCEPT'
uci commit firewall

# =========================
# Android TV 时间解析修复
# =========================
uci add dhcp domain
uci set "dhcp.@domain[-1].name=time.android.com"
uci set "dhcp.@domain[-1].ip=203.107.6.88"
uci commit dhcp

# =========================
# 【新增】设置固件主机名
# =========================
HOSTNAME_FILE="/etc/config/custom_hostname.txt"
if [ -f "$HOSTNAME_FILE" ]; then
    HOSTNAME=$(cat "$HOSTNAME_FILE")
else
    HOSTNAME="DulWiFi-TK"
fi

uci set system.@system[0].hostname="$HOSTNAME"
uci commit system
echo "Hostname set to $HOSTNAME" >>$LOGFILE

# =========================
# 读取 PPPoE 配置
# =========================
SETTINGS_FILE="/etc/config/pppoe-settings"
if [ -f "$SETTINGS_FILE" ]; then
    . "$SETTINGS_FILE"
else
    echo "PPPoE settings file not found." >>$LOGFILE
fi

# =========================
# 网口识别
# =========================
ifnames=""
for iface in /sys/class/net/*; do
    iface_name=$(basename "$iface")
    if [ -e "$iface/device" ] && echo "$iface_name" | grep -Eq '^eth|^en'; then
        ifnames="$ifnames $iface_name"
    fi
done
ifnames=$(echo "$ifnames" | awk '{$1=$1};1')
count=$(echo "$ifnames" | wc -w)

board_name=$(cat /tmp/sysinfo/board_name 2>/dev/null || echo "unknown")
echo "Board: $board_name IFs: $ifnames" >>$LOGFILE

case "$board_name" in
    "radxa,e20c"|"friendlyarm,nanopi-r5c")
        wan_ifname="eth1"
        lan_ifnames="eth0"
        ;;
    *)
        wan_ifname=$(echo "$ifnames" | awk '{print $1}')
        lan_ifnames=$(echo "$ifnames" | cut -d ' ' -f2-)
        ;;
esac

# =========================
# 网络配置
# =========================
if [ "$count" -eq 1 ]; then
    uci set network.lan.proto='dhcp'
    uci delete network.lan.ipaddr
    uci delete network.lan.netmask
    uci delete network.lan.gateway
    uci delete network.lan.dns
    uci commit network
else
    uci set network.wan=interface
    uci set network.wan.device="$wan_ifname"
    uci set network.wan.proto='dhcp'

    uci set network.wan6=interface
    uci set network.wan6.device="$wan_ifname"
    uci set network.wan6.proto='dhcpv6'

    section=$(uci show network | grep "name='br-lan'" | cut -d. -f2 | head -n1)
    if [ -n "$section" ]; then
        uci -q delete "network.$section.ports"
        for port in $lan_ifnames; do
            uci add_list "network.$section.ports=$port"
        done
    fi

    uci set network.lan.proto='static'
    uci set network.lan.netmask='255.255.255.0'

    IP_FILE="/etc/config/custom_router_ip.txt"
    if [ -f "$IP_FILE" ]; then
        uci set network.lan.ipaddr="$(cat $IP_FILE)"
    else
        uci set network.lan.ipaddr='192.168.9.1'
    fi

    if [ "$enable_pppoe" = "yes" ] && [ -n "$pppoe_account" ]; then
        uci set network.wan.proto='pppoe'
        uci set network.wan.username="$pppoe_account"
        uci set network.wan.password="$pppoe_password"
        uci set network.wan6.proto='none'
    fi

    uci commit network
fi

# =========================
# 【新增】WiFi 名称 & 密码 & 自动启用
# =========================
WIFI_FILE="/etc/config/custom_wifi.txt"
DEFAULT_SSID="Dul-TK"
DEFAULT_KEY="password"

if [ -f "$WIFI_FILE" ]; then
    . "$WIFI_FILE"
else
    WIFI_SSID="$DEFAULT_SSID"
    WIFI_KEY="$DEFAULT_KEY"
fi

for iface in $(uci show wireless | grep "=wifi-iface" | cut -d. -f2); do
    uci set wireless.$iface.ssid="$WIFI_SSID"
    uci set wireless.$iface.encryption='psk2'
    uci set wireless.$iface.key="$WIFI_KEY"
    uci set wireless.$iface.disabled='0'
done

uci commit wireless
echo "WiFi SSID=$WIFI_SSID enabled" >>$LOGFILE

# =========================
# ttyd / SSH 全接口
# =========================
uci delete ttyd.@ttyd[0].interface
uci set dropbear.@dropbear[0].Interface=''
uci commit

# =========================
# 编译作者信息
# =========================
sed -i "s/DISTRIB_DESCRIPTION='[^']*'/DISTRIB_DESCRIPTION='Packaged by jontao'/" /etc/openwrt_release

# =========================
# advancedplus zsh 兼容
# =========================
if opkg list-installed | grep -q '^luci-app-advancedplus '; then
    sed -i '/zsh/d' /etc/profile
    sed -i '/zsh/d' /etc/init.d/advancedplus
fi

exit 0
