#!/usr/bin/env bash
# ============================================================================
# 模块：自定义包安装
# 功能：安装自定义插件
# ============================================================================

install_custom_packages() {
    local BUILD_DIR="$1"
    local REPO_ROOT="$2"
    
    echo "=== 安装自定义插件 ==="
    
    cd "$BUILD_DIR" || return 1
    
    # 安装 luci-app-devicemaster
    if [[ -d "$REPO_ROOT/wax206_optimized/packages/luci-app-devicemaster" ]]; then
        cp -r "$REPO_ROOT/wax206_optimized/packages/luci-app-devicemaster" "$BUILD_DIR/package/"
        echo "✓ luci-app-devicemaster 已复制"
    elif [[ -d "$REPO_ROOT/wax206/packages/luci-app-devicemaster" ]]; then
        cp -r "$REPO_ROOT/wax206/packages/luci-app-devicemaster" "$BUILD_DIR/package/"
        echo "✓ luci-app-devicemaster 已复制（从 wax206）"
    else
        echo "⚠ 警告: luci-app-devicemaster 不存在，跳过"
    fi
    
    # 安装 feeds
    if [[ -d "package/luci-app-devicemaster" ]]; then
        ./scripts/feeds update luci >/dev/null 2>&1
        ./scripts/feeds install -a -p luci >/dev/null 2>&1
        echo "✓ luci-app-devicemaster feeds 安装完成"
    fi
    
    cd - > /dev/null
}