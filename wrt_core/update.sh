#!/usr/bin/env bash

# 开启严格模式，但我们会通过逻辑控制防止误杀
set -e
set -o errexit
set -o errtrace

error_handler() {
    echo "Error occurred in script at line: ${BASH_LINENO[0]}, command: '${BASH_COMMAND}'"
}

trap 'error_handler' ERR

REPO_URL=$1
REPO_BRANCH=$2
BUILD_DIR=$3
COMMIT_HASH=$4

# 转换为绝对路径
if [[ "$BUILD_DIR" != /* ]]; then
    BUILD_DIR="$(pwd)/$BUILD_DIR"
fi

# 核心变量设置
FEEDS_CONF="feeds.conf.default"
GOLANG_REPO="https://github.com/sbwml/packages_lang_golang"
GOLANG_BRANCH="26.x"
THEME_SET="argon"
LAN_ADDR="192.168.31.1"

SCRIPT_DIR=$(cd $(dirname $0) && pwd)
BASE_PATH=${BASE_PATH:-$SCRIPT_DIR}

# 引入模块
source "$SCRIPT_DIR/modules/general.sh"
source "$SCRIPT_DIR/modules/feeds.sh"
source "$SCRIPT_DIR/modules/packages.sh"
source "$SCRIPT_DIR/modules/system.sh"
# source "$SCRIPT_DIR/modules/cups.sh" # 打印机依赖复杂，建议精简

main() {
    # 1. 源码与插件池准备
    clone_repo
    clean_up
    reset_feeds_conf
    update_feeds

    # 2. 基础环境修复 (通常是必须的)
    update_golang           # 升级 Go 环境以支持新版插件
    remove_unwanted_packages
    fix_default_set
    #fix_miniupnpd
    fix_mk_def_depends
    fix_compile_coremark
    fix_rust_compile_error

    # 3. 固件个性化设置
    update_default_lan_addr # 修改 IP 地址
    change_dnsmasq2full     # 替换为完整的 dnsmasq
    change_cpuusage         # 优化 CPU 使用率显示
    #set_build_signature     # 注入编译信息
    update_menu_location    # 优化菜单布局
    set_nginx_default_config

    # 4. 热门插件版本同步 (按需保留)
    update_argon || true      # Argon 主题
    update_adguardhome || true
    update_smartdns || true
    #update_dockerman || true
    update_geoip || true      # 更新地理位置数据库

    # 5. 系统底层修复 (可选)
    fix_openssl_ktls || true  # 修复加速
    fix_opkg_check || true

    # 6. 安装 Feeds 并收尾
    install_feeds
    update_script_priority
    
    echo "✅ 所有预处理任务已完成！"
}

# 启动脚本
main "$@"
