#!/usr/bin/env bash
# ============================================================================
# 模块：软件源配置
# 功能：配置 distfeeds.list
# ============================================================================

configure_distfeeds() {
    local BUILD_DIR="$1"
    
    echo "=== 配置软件源 ==="
    
    cd "$BUILD_DIR" || return 1
    
    mkdir -p package/base-files/files/etc/apk/repositories.d/
    
    cat > package/base-files/files/etc/apk/repositories.d/distfeeds.list << 'EOF'
# This file is auto-generated and build-specific, any changes will be intentionally lost in sysupgrade.
# Add your custom feeds to /etc/apk/repositories.d/customfeeds.list
https://downloads.openwrt.org/snapshots/targets/mediatek/mt7622/packages/packages.adb
https://downloads.openwrt.org/snapshots/packages/aarch64_cortex-a53/base/packages.adb
https://downloads.openwrt.org/snapshots/packages/aarch64_cortex-a53/luci/packages.adb
https://downloads.openwrt.org/snapshots/packages/aarch64_cortex-a53/packages/packages.adb
https://downloads.openwrt.org/snapshots/packages/aarch64_cortex-a53/routing/packages.adb
https://downloads.openwrt.org/snapshots/packages/aarch64_cortex-a53/telephony/packages.adb
https://downloads.openwrt.org/snapshots/packages/aarch64_cortex-a53/video/packages.adb
EOF
    
    echo "✓ distfeeds.list 已配置"
    
    cd - > /dev/null
}