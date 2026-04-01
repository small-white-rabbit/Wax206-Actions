#!/bin/bash

Dev=$1
BUILD_DIR=${2:-$1}    # ← 第2个参数是 BUILD_DIR，默认为 $1

echo "=========================================="
echo "DIY Part2 - 设备: $Dev"
echo "BUILD_DIR: $BUILD_DIR"
echo "=========================================="

echo "目标目录: $BUILD_DIR"

if [ ! -d "./$BUILD_DIR" ]; then
    echo "错误: 目录 ./$BUILD_DIR 不存在"
    ls -la
    exit 1
fi

cd "./$BUILD_DIR" || exit 1
echo "进入目录: $(pwd)"
# ... 后续配置

# 配置IP
if [ -f "package/base-files/files/bin/config_generate" ]; then
    sed -i 's/192.168.1.1/192.168.31.1/g' package/base-files/files/bin/config_generate
    echo "✓ IP改为192.168.31.1"
fi

# 配置主机名
if [ -f "package/base-files/files/bin/config_generate" ]; then
    sed -i 's/OpenWrt/Wax206/g' package/base-files/files/bin/config_generate
    echo "✓ 主机名改为Wax206"
fi

# 配置时区
if [ -f "package/base-files/files/bin/config_generate" ]; then
    sed -i "s/timezone='.*'/timezone='CST-8'/g" package/base-files/files/bin/config_generate
    sed -i "/timezone='CST-8'/a\\\t\tset system.@system[-1].zonename='Asia/Shanghai'" package/base-files/files/bin/config_generate
    echo "✓ 时区改为Asia/Shanghai"
fi

# 配置WiFi
mkdir -p files/etc/config/
cat > files/etc/config/wireless <<'EOF'
config wifi-device 'radio0'
    option type 'mac80211'
    option path 'platform/18000000.wmac'
    option channel 'auto'
    option band '2g'
    option htmode 'HT40'
    option txpower '28'
    option country 'US'
    option cell_density '0'

config wifi-iface 'default_radio0'
    option device 'radio0'
    option network 'lan'
    option mode 'ap'
    option ssid 'Wax206_2.4G'
    option encryption 'none'
    option disabled '0'

config wifi-device 'radio1'
    option type 'mac80211'
    option path '1a143000.pcie/pci0000:00/0000:00:00.0/0000:01:00.0'
    option channel '36'
    option band '5g'
    option htmode 'HE80'
    option country 'US'
    option cell_density '0'

config wifi-iface 'default_radio1'
    option device 'radio1'
    option network 'lan'
    option mode 'ap'
    option ssid 'Wax206_5G'
    option encryption 'none'
    option disabled '0'
EOF
echo "✓ WiFi配置完成"

# 添加 uci-defaults 修复脚本 - 确保重置后 HE80 不被清空
mkdir -p files/etc/uci-defaults/
cat > files/etc/uci-defaults/99-wax206-he80-fix <<'EOF'
#!/bin/sh

# 等待无线驱动完全初始化
sleep 5

# 强制恢复 5G HE80 配置（解决重置后 htmode 被清空的问题）
[ "$(uci get wireless.radio1.band 2>/dev/null)" = "5g" ] && {
    current_htmode=$(uci get wireless.radio1.htmode 2>/dev/null)
    
    if [ -z "$current_htmode" ] || [ "$current_htmode" != "HE80" ]; then
        uci set wireless.radio1.htmode='HE80'
        uci commit wireless
        wifi reload
        logger -t "wax206-fix" "Restored 5G htmode to HE80 (1200Mbps), was: '$current_htmode'"
    else
        logger -t "wax206-fix" "5G htmode already HE80, OK"
    fi
}

exit 0
EOF
chmod +x files/etc/uci-defaults/99-wax206-he80-fix
echo "✓ HE80 修复脚本添加完成"

echo "=========================================="
echo "DIY 配置完成！"
echo "=========================================="
