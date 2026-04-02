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


MAC80211_UC="package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"

if [ -f "$MAC80211_UC" ]; then
    echo "找到 mac80211.uc，修改 WiFi 默认配置..."
    
    # 1. 强制启用 WiFi
    sed -i "s/set \${si}\.disabled='\${defaults ? 0 : 1}'/set \${si}.disabled='0'/g" "$MAC80211_UC"
    
    # 2. 修改默认 SSID
    sed -i 's/"OpenWrt"/"Wax206"/g' "$MAC80211_UC"
    
    # 3. 设置国家代码为 US
    sed -i "s/set \${s}\.country='\${country || }'/set \${s}.country='US'/g" "$MAC80211_UC"
    
    # 4. 添加功率设置 28dBm（在 num_global_macaddr 行后新增）
    sed -i "/set \${s}\.num_global_macaddr='\\${num_global_macaddr || }'/a\\set \${s}.txpower='28'" "$MAC80211_UC"
    
    echo "✓ WiFi 默认启用（disabled=0）"
    echo "✓ SSID 改为 Wax206"  
    echo "✓ 国家代码设置为 US"
    echo "✓ 功率设置为 28dBm"
    
    # 验证修改
    echo "--- 验证修改结果 ---"
    grep -n "disabled=" "$MAC80211_UC" | head -3
    grep -n '"Wax206"' "$MAC80211_UC" | head -3
    grep -n "country=" "$MAC80211_UC" | head -3
    grep -n "txpower=" "$MAC80211_UC" | head -3
else
    echo "警告: 未找到 $MAC80211_UC"
    find . -name "mac80211.uc" -type f 2>/dev/null
fi
echo "=========================================="
echo "DIY 配置完成！"
echo "=========================================="
