#!/bin/bash

Dev=$1
echo "设备参数: $Dev"

# 根据 Dev 确定构建目录（与 pre_clone_action.sh 保持一致）
case "$Dev" in
    "fmwax206")
        BUILD_DIR="fmwax206"
        ;;
    "gwax206")
        BUILD_DIR="gwax206"
        ;;
    "wax206"|*)
        BUILD_DIR="wax206"
        ;;
esac

echo "构建目录: $BUILD_DIR"

# 检查目录是否存在
if [ ! -d "../$BUILD_DIR" ]; then
    echo "错误: 目录 ../$BUILD_DIR 不存在"
    echo "当前目录: $(pwd)"
    echo "上级目录内容:"
    ls -la ../
    exit 1
fi

# 进入构建目录
cd "../$BUILD_DIR" || {
    echo "错误: 无法进入目录 ../$BUILD_DIR"
    exit 1
}

echo "当前工作目录: $(pwd)"
echo "开始配置 $Dev ..."

# 1. 设置默认IP为 192.168.31.1
if [ -f "package/base-files/files/bin/config_generate" ]; then
    sed -i 's/192.168.1.1/192.168.31.1/g' package/base-files/files/bin/config_generate
    echo "✓ 已修改默认IP为 192.168.31.1"
else
    echo "✗ 警告: config_generate 不存在，跳过IP修改"
fi

# 2. 设置主机名
if [ -f "package/base-files/files/bin/config_generate" ]; then
    sed -i 's/OpenWrt/Wax206/g' package/base-files/files/bin/config_generate
    echo "✓ 已修改主机名为 Wax206"
fi

# 3. 设置时区为上海
if [ -f "package/base-files/files/bin/config_generate" ]; then
    sed -i "s/timezone='.*'/timezone='CST-8'/g" package/base-files/files/bin/config_generate
    sed -i "/timezone='CST-8'/a\\\t\tset system.@system[-1].zonename='Asia/Shanghai'" package/base-files/files/bin/config_generate
    echo "✓ 已设置时区为 Asia/Shanghai"
fi

# 4. 配置WiFi
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
    option channel 'auto'
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

echo "✓ 已配置WiFi默认设置"
echo "DIY 配置完成！"
