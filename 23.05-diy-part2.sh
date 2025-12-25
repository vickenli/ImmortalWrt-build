#!/bin/bash
# diy-part2.sh - 适配 ImmortalWrt 23.05 系统基础配置预设
# 请修改下方 WIFI_2G/5G_NAME、WIFI_PSK、PPPOE_USER、PPPOE_PWD 为你的实际值

# 配置参数（请手动修改以下4项）
LAN_IP="192.168.10.1"
WIFI_2G_NAME="MyWiFi_2.4G"
WIFI_5G_NAME="MyWiFi_5G"
WIFI_PSK=""  # 建议至少8位，含大小写+数字
PPPOE_USER=""
PPPOE_PWD=""

# 1. 修改 LAN 口 IP 为 192.168.10.1
uci set network.lan.ipaddr="$LAN_IP"
uci set network.lan.netmask="255.255.255.0"
uci commit network
echo "✅ LAN IP 已设为 $LAN_IP"

# 2. 设置 WAN 口为 PPPoE 并填入账号密码
uci set network.wan.proto="pppoe"
uci set network.wan.username="$PPPOE_USER"
uci set network.wan.password="$PPPOE_PWD"
uci set network.wan.peerdns="1"  # 启用运营商 DNS
uci set network.wan.ipv6="auto"  # 自动获取 IPv6（按需启用）
uci commit network
echo "✅ WAN 口已设为 PPPoE，账号/密码已配置"

# 3. 配置 2.4G WiFi（radio0 通常为2.4G，部分机型可能为 radio1，请根据机型调整）
uci set wireless.radio0.disabled="0"
uci set wireless.default_radio0.ssid="$WIFI_2G_NAME"
uci set wireless.default_radio0.encryption="psk2"
uci set wireless.default_radio0.key="$WIFI_PSK"
uci set wireless.default_radio0.network="lan"
uci commit wireless
echo "✅ 2.4G WiFi SSID: $WIFI_2G_NAME, 密码: $WIFI_PSK"

# 4. 配置 5G WiFi（radio1 通常为5G，部分机型可能为 radio0，请根据机型调整）
uci set wireless.radio1.disabled="0"
uci set wireless.default_radio1.ssid="$WIFI_5G_NAME"
uci set wireless.default_radio1.encryption="psk2"
uci set wireless.default_radio1.key="$WIFI_PSK"
uci set wireless.default_radio1.network="lan"
uci commit wireless
echo "✅ 5G WiFi SSID: $WIFI_5G_NAME, 密码: $WIFI_PSK"

# 5. 应用配置并清理
echo "✅ 所有基础配置已预设完成，编译后固件将直接生效"
