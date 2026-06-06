#!/usr/bin/env bash
# ============================================================================
# 模块：网络配置
# 功能：配置 LAN IP、主机名、时区
# ============================================================================

configure_network() {
    local BUILD_DIR="$1"
    local CONFIG_FILE="${OPT_PATH}/config/config.conf"
    
    # 加载配置
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    fi
    
    echo "=== 配置网络 ==="
    
    cd "$BUILD_DIR" || return 1
    
    # 配置 IP
    if [[ -f "package/base-files/files/bin/config_generate" ]]; then
        sed -i "s/192.168.1.1/${LAN_IP}/g" package/base-files/files/bin/config_generate
        echo "✓ IP 改为 ${LAN_IP}"
    fi
    
    # 配置主机名
    if [[ -f "package/base-files/files/bin/config_generate" ]]; then
        sed -i "s/OpenWrt/${HOSTNAME}/g" package/base-files/files/bin/config_generate
        echo "✓ 主机名改为 ${HOSTNAME}"
    fi
    
    # 配置时区
    if [[ -f "package/base-files/files/bin/config_generate" ]]; then
        sed -i "s/timezone='.*'/timezone='CST-8'/g" package/base-files/files/bin/config_generate
        sed -i "/timezone='CST-8'/a\\t\tset system.@system[-1].zonename='${TIMEZONE}'" package/base-files/files/bin/config_generate
        echo "✓ 时区改为 ${TIMEZONE}"
    fi
    
    cd - > /dev/null
}