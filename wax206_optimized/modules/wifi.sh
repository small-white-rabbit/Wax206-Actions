#!/usr/bin/env bash
# ============================================================================
# 模块：WiFi 配置
# 功能：配置 WiFi SSID、国家代码、功率
# ============================================================================

configure_wifi() {
    local BUILD_DIR="$1"
    local CONFIG_FILE="${OPT_PATH}/config/config.conf"
    
    # 加载配置
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    fi
    
    echo "=== 配置 WiFi ==="
    
    cd "$BUILD_DIR" || return 1
    
    local MAC80211_UC="package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
    
    if [[ -f "$MAC80211_UC" ]]; then
        echo "找到 mac80211.uc，修改 WiFi 默认配置..."
        
        # 启用 WiFi
        if [[ "$WIFI_ENABLED" == "1" ]]; then
            sed -i "s/set \${si}\.disabled='\${defaults ? 0 : 1}'/set \${si}.disabled='0'/g" "$MAC80211_UC"
            echo "✓ WiFi 默认启用"
        fi
        
        # 配置 SSID
        sed -i "s/\"OpenWrt\"/\"${SSID}\"/g" "$MAC80211_UC"
        echo "✓ SSID 改为 ${SSID}"
        
        # 配置国家代码
        sed -i "s|set \${s}.country=.*|set \${s}.country='${WIFI_COUNTRY}'|g" "$MAC80211_UC"
        echo "✓ 国家代码 ${WIFI_COUNTRY}"
        
        # 配置功率
        sed -i "/set \${s}.country=/a set \${s}.txpower='${WIFI_POWER}'" "$MAC80211_UC"
        echo "✓ 功率 ${WIFI_POWER}"
    else
        echo "⚠ 警告: 未找到 $MAC80211_UC"
        find . -name "mac80211.uc" -type f 2>/dev/null
    fi
    
    cd - > /dev/null
}