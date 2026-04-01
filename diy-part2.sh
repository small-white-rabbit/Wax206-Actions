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

mkdir -p files/etc/uci-defaults/

cat > files/etc/uci-defaults/99_init_wifi <<'EOF'
#!/bin/sh

# 检查是否已正确配置为 HE80（保留配置且正确时跳过）
current_htmode=$(uci get wireless.radio1.htmode 2>/dev/null)
if [ "$current_htmode" = "HE80" ]; then
    logger -t init_wifi "HE80 already configured, skipping"
    exit 0
fi

# 等待无线驱动加载
sleep 3

# 配置 2.4G
uci set wireless.radio0=wifi-device
uci set wireless.radio0.type='mac80211'
uci set wireless.radio0.phy='wl0'
uci set wireless.radio0.band='2g'
uci set wireless.radio0.htmode='HT40'
uci set wireless.radio0.channel='auto'
uci set wireless.radio0.country='US'
uci set wireless.radio0.cell_density='0'

uci set wireless.default_radio0=wifi-iface
uci set wireless.default_radio0.device='radio0'
uci set wireless.default_radio0.network='lan'
uci set wireless.default_radio0.mode='ap'
uci set wireless.default_radio0.ssid='Wax206_2.4G'
uci set wireless.default_radio0.encryption='none'

# 配置 5G - HE80
uci set wireless.radio1=wifi-device
uci set wireless.radio1.type='mac80211'
uci set wireless.radio1.phy='wl1'
uci set wireless.radio1.band='5g'
uci set wireless.radio1.htmode='HE80'
uci set wireless.radio1.channel='149'
uci set wireless.radio1.country='US'
uci set wireless.radio1.cell_density='0'

uci set wireless.default_radio1=wifi-iface
uci set wireless.default_radio1.device='radio1'
uci set wireless.default_radio1.network='lan'
uci set wireless.default_radio1.mode='ap'
uci set wireless.default_radio1.ssid='Wax206_5G'
uci set wireless.default_radio1.encryption='none'

uci commit wireless
wifi reload

logger -t init_wifi "WiFi initialized with HE80"
EOF

chmod +x files/etc/uci-defaults/99_init_wifi



echo "=========================================="
echo "DIY 配置完成！"
echo "=========================================="
