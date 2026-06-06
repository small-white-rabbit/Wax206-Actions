#!/usr/bin/env bash
# ============================================================================
# DIY 模块主入口
# 功能：加载并执行所有 DIY 配置模块
# ============================================================================

# 模块目录
MODULES_DIR="${OPT_PATH}/modules"

# 加载所有模块
source "${MODULES_DIR}/network.sh"
source "${MODULES_DIR}/wifi.sh"
source "${MODULES_DIR}/conntrack.sh"
source "${MODULES_DIR}/packages.sh"
source "${MODULES_DIR}/distfeed.sh"

# DIY 主函数
run_diy() {
    local BUILD_DIR="$1"
    local REPO_ROOT="$2"
    
    echo "=========================================="
    echo "DIY 配置 - 优化版"
    echo "BUILD_DIR: $BUILD_DIR"
    echo "=========================================="
    
    # 执行所有模块
    configure_network "$BUILD_DIR"
    configure_wifi "$BUILD_DIR"
    configure_conntrack "$BUILD_DIR"
    install_custom_packages "$BUILD_DIR" "$REPO_ROOT"
    configure_distfeeds "$BUILD_DIR"
    
    echo "=========================================="
    echo "DIY 配置完成！"
    echo "=========================================="
}