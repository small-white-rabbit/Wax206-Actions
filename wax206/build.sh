#!/usr/bin/env bash
# ============================================================================
# WAX206 一体化编译脚本
# 整合 pre_clone_action.sh + update.sh + modules/*.sh + build.sh
# ============================================================================

set -o errexit
set -o errtrace
set -o pipefail

error_handler() {
    local line=$1
    local cmd=$2
    echo "Error occurred in script at line: ${line}, command: '${cmd}'"
    exit 1
}
trap 'error_handler "${BASH_LINENO[0]}" "${BASH_COMMAND}"' ERR

# ==================== 自动定位仓库根目录 ====================
# 获取脚本自身所在目录（支持符号链接）
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_SOURCE" ]; do
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
    SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
    [[ "$SCRIPT_SOURCE" != /* ]] && SCRIPT_SOURCE="$SCRIPT_DIR/$SCRIPT_SOURCE"
done
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"

# 关键修复：判断脚本所在的目录名，回到正确的仓库根目录
SCRIPT_BASENAME="$(basename "$SCRIPT_DIR")"
if [ "$SCRIPT_BASENAME" = "wax206" ] || [ "$SCRIPT_BASENAME" = "wrt_core" ] || [ "$SCRIPT_BASENAME" = "scripts" ] || [ "$SCRIPT_BASENAME" = "bin" ]; then
    REPO_ROOT="$(dirname "$SCRIPT_DIR")"
else
    REPO_ROOT="$SCRIPT_DIR"
fi

# 切换到仓库根目录
cd "$REPO_ROOT" || { echo "Error: Cannot cd to $REPO_ROOT"; exit 1; }
echo ">>> 工作目录: $(pwd)"
echo ">>> REPO_ROOT: $REPO_ROOT"
# ==========================================================

# ==================== 全局变量 ====================
Dev=$1
Build_Mod=$2

# 确定 wax206 目录路径（现在在正确的根目录下判断）
if [ -d "wax206" ]; then
    WAX206_PATH="wax206"
elif [ -d "../wax206" ]; then
    WAX206_PATH="../wax206"
else
    echo "Error: wax206 directory not found! (PWD: $(pwd))"
    # 最后尝试从脚本位置搜索
    FOUND_WAX206=$(find "$REPO_ROOT" -maxdepth 2 -type d -name "wax206" | head -1)
    if [ -n "$FOUND_WAX206" ]; then
        WAX206_PATH="$FOUND_WAX206"
        echo "Found wax206 via search: $WAX206_PATH"
    else
        exit 1
    fi
fi

BASE_PATH=$(cd "$WAX206_PATH" && pwd)
echo ">>> BASE_PATH: $BASE_PATH"

CONFIG_FILE="$BASE_PATH/deconfig/$Dev.config"
INI_FILE="$BASE_PATH/compilecfg/$Dev.ini"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Config not found: $CONFIG_FILE"
    exit 1
fi

if [[ ! -f "$INI_FILE" ]]; then
    echo "INI file not found: $INI_FILE"
    exit 1
fi

# ==================== 工具函数 ====================
read_ini_by_key() {
    local key=$1
    awk -F"=" -v key="$key" '$1 == key {print $2}' "$INI_FILE"
}

REPO_URL=$(read_ini_by_key "REPO_URL")
REPO_BRANCH=$(read_ini_by_key "REPO_BRANCH")
REPO_BRANCH=${REPO_BRANCH:-main}
BUILD_DIR=$(read_ini_by_key "BUILD_DIR")
COMMIT_HASH=$(read_ini_by_key "COMMIT_HASH")
COMMIT_HASH=${COMMIT_HASH:-none}

# 如果 action_build 目录存在，强制使用它
if [[ -d "action_build" ]]; then
    BUILD_DIR="action_build"
fi

# 确保 BUILD_DIR 是绝对路径
if [[ "$BUILD_DIR" != /* ]]; then
    BUILD_DIR="$(pwd)/$BUILD_DIR"
fi

FEEDS_CONF="feeds.conf.default"
GOLANG_REPO="https://github.com/sbwml/packages_lang_golang"
GOLANG_BRANCH="26.x"
THEME_SET="argon"
LAN_ADDR="192.168.31.1"

# ==================== [pre_clone_action.sh] 克隆源码 ====================
clone_source() {
    echo "=== 克隆固件代码 ==="
    echo "$REPO_URL $REPO_BRANCH"
    echo "$REPO_URL/$REPO_BRANCH" >"$BASE_PATH/../repo_flag"

    if [[ -d "$BASE_PATH/../action_build" ]]; then
        echo "action_build already exists, skipping clone"
        return 0
    fi

    if ! git clone --depth 1 -b "$REPO_BRANCH" "$REPO_URL" "$BASE_PATH/../action_build"; then
        echo "错误：克隆仓库 $REPO_URL 失败" >&2
        exit 1
    fi

    # 移除国内下载源
    local mirrors_file="$BASE_PATH/../action_build/scripts/projectsmirrors.json"
    if [ -f "$mirrors_file" ]; then
        sed -i '/.cn\//d; /tencent/d; /aliyun/d' "$mirrors_file"
    fi
}

# ==================== [modules/general.sh] 通用准备 ====================
clone_repo() {
    if [[ ! -d "$BUILD_DIR" ]]; then
        echo "克隆仓库: $REPO_URL 分支: $REPO_BRANCH"
        if ! git clone --depth 1 -b "$REPO_BRANCH" "$REPO_URL" "$BUILD_DIR"; then
            echo "错误：克隆仓库 $REPO_URL 失败" >&2
            exit 1
        fi
    fi
}

clean_up() {
    if [[ ! -d "$BUILD_DIR" ]]; then
        echo "Build directory $BUILD_DIR does not exist"
        return
    fi
    cd "$BUILD_DIR"
    if [[ -f ".config" ]]; then
        \rm -f ".config"
    fi
    if [[ -d "tmp" ]]; then
        \rm -rf "tmp"
    fi
    if [[ -d "logs" ]]; then
        find logs -type f -delete 2>/dev/null || true
    fi
    if [[ -d "feeds" ]]; then
        ./scripts/feeds clean
    fi
    mkdir -p "tmp"
    echo "1" >"tmp/.build"
    cd - > /dev/null
}

reset_feeds_conf() {
    cd "$BUILD_DIR"
    git reset --hard "origin/$REPO_BRANCH"
    git clean -f -d
    git pull
    if [[ "$COMMIT_HASH" != "none" ]]; then
        git checkout "$COMMIT_HASH"
    fi
    cd - > /dev/null
}

# ==================== [modules/feeds.sh] Feeds 管理 ====================
update_feeds() {
    cd "$BUILD_DIR"
    local FEEDS_PATH="$BUILD_DIR/$FEEDS_CONF"
    if [[ -f "$BUILD_DIR/feeds.conf" ]]; then
        FEEDS_PATH="$BUILD_DIR/feeds.conf"
    fi
    sed -i '/^#/d' "$FEEDS_PATH"
    sed -i '/packages_ext/d' "$FEEDS_PATH"
    
    if ! grep -q "small" "$FEEDS_PATH"; then
        [ -z "$(tail -c 1 "$FEEDS_PATH")" ] || echo "" >>"$FEEDS_PATH"
        echo "src-git small https://github.com/kenzok8/small.git;master" >>"$FEEDS_PATH"
    fi
   
    if ! grep -q "kenzok" "$FEEDS_PATH"; then
        [ -z "$(tail -c 1 "$FEEDS_PATH")" ] || echo "" >>"$FEEDS_PATH"
        echo "src-git kenzok https://github.com/kenzok8/openwrt-packages.git;master" >>"$FEEDS_PATH"
    fi

    if ! grep -q "openwrt-passwall" "$FEEDS_PATH"; then
        [ -z "$(tail -c 1 "$FEEDS_PATH")" ] || echo "" >>"$FEEDS_PATH"
        echo "src-git passwall https://github.com/Openwrt-Passwall/openwrt-passwall;main" >>"$FEEDS_PATH"
    fi

    if ! grep -q "openclash" "$FEEDS_PATH"; then
        [ -z "$(tail -c 1 "$FEEDS_PATH")" ] || echo "" >>"$FEEDS_PATH"
        echo "src-git openclash https://github.com/vernesong/OpenClash.git;master" >>"$FEEDS_PATH"
    fi

    if ! grep -q "openwrt_bandix" "$BUILD_DIR/$FEEDS_CONF"; then
        [ -z "$(tail -c 1 "$BUILD_DIR/$FEEDS_CONF")" ] || echo "" >>"$BUILD_DIR/$FEEDS_CONF"
        echo 'src-git openwrt_bandix https://github.com/timsaya/openwrt-bandix.git;main' >>"$BUILD_DIR/$FEEDS_CONF"
    fi

    if ! grep -q "luci_app_bandix" "$BUILD_DIR/$FEEDS_CONF"; then
        [ -z "$(tail -c 1 "$BUILD_DIR/$FEEDS_CONF")" ] || echo "" >>"$BUILD_DIR/$FEEDS_CONF"
        echo 'src-git luci_app_bandix https://github.com/timsaya/luci-app-bandix.git;main' >>"$BUILD_DIR/$FEEDS_CONF"
    fi

    if [ ! -f "$BUILD_DIR/include/bpf.mk" ]; then
        touch "$BUILD_DIR/include/bpf.mk"
    fi

    ./scripts/feeds update -a
    cd - > /dev/null
}

install_feeds() {
    cd "$BUILD_DIR"
    ./scripts/feeds update -i
    for dir in "$BUILD_DIR"/feeds/*; do
        if [ -d "$dir" ] && [[ ! "$dir" == *.tmp ]] && [[ ! "$dir" == *.index ]] && [[ ! "$dir" == *.targetindex ]]; then
            local feed_name
            feed_name=$(basename "$dir")
            if [[ "$feed_name" == "openclash" ]]; then
                install_openclash
            elif [[ "$feed_name" == "passwall" ]]; then
                install_passwall
            else
                ./scripts/feeds install -f -ap "$feed_name"
            fi
        fi
    done
    cd - > /dev/null
}

# ==================== [modules/packages.sh] 包管理 ====================
update_golang() {
    cd "$BUILD_DIR"
    if [[ -d ./feeds/packages/lang/golang ]]; then
        echo "正在更新 golang 软件包..."
        \rm -rf ./feeds/packages/lang/golang
        if ! git clone --depth 1 -b "$GOLANG_BRANCH" "$GOLANG_REPO" ./feeds/packages/lang/golang; then
            echo "错误：克隆 golang 仓库 $GOLANG_REPO 失败" >&2
            exit 1
        fi
    fi
    cd - > /dev/null
}

install_fichenx() {
    cd "$BUILD_DIR"
    ./scripts/feeds install -p  -f luci-app-argon-config luci-theme-design luci-app-design-config luci-app-watchcat-plus luci-app-wol luci-app-timecontrol \
        xray-core xray-plugin dns2tcp dns2socks haproxy hysteria \
        naiveproxy shadowsocks-rust sing-box v2ray-core v2ray-geodata geoview v2ray-plugin \
        tuic-client chinadns-ng ipt2socks tcping trojan-plus simple-obfs shadowsocksr-libev \
        v2dat mosdns luci-app-mosdns adguardhome luci-app-adguardhome ddns-go \
        luci-app-ddns-go taskd luci-lib-xterm luci-lib-taskd luci-app-store quickstart \
        luci-app-quickstart luci-app-istorex luci-app-cloudflarespeedtest netdata luci-app-netdata \
        lucky luci-app-lucky luci-app-openclash luci-app-homeproxy luci-app-amlogic nikki luci-app-nikki \
        tailscale luci-app-tailscale oaf open-app-filter luci-app-oaf easytier luci-app-easytier \
        msd_lite luci-app-msd_lite cups luci-app-cupsd
    cd - > /dev/null
}

install_openclash() {
    cd "$BUILD_DIR"
    ./scripts/feeds install -p openclash -f luci-app-openclash
    cd - > /dev/null
}

install_passwall() {
    cd "$BUILD_DIR"
    ./scripts/feeds install -p passwall -f luci-app-passwall
    cd - > /dev/null
}

remove_attendedsysupgrade() {
    find "$BUILD_DIR/feeds/luci/collections" -name "Makefile" | while read -r makefile; do
        if grep -q "luci-app-attendedsysupgrade" "$makefile"; then
            sed -i "/luci-app-attendedsysupgrade/d" "$makefile"
            echo "Removed luci-app-attendedsysupgrade from $makefile"
        fi
    done
}

fix_rust_compile_error() {
    if [ -f "$BUILD_DIR/feeds/packages/lang/rust/Makefile" ]; then
        sed -i 's/download-ci-llvm=true/download-ci-llvm=false/g' "$BUILD_DIR/feeds/packages/lang/rust/Makefile"
    fi
}

update_nginx_ubus_module() {
    local makefile_path="$BUILD_DIR/feeds/packages/net/nginx/Makefile"
    if [ -f "$makefile_path" ]; then
        sed -i "s/SOURCE_DATE:=2020-09-06/SOURCE_DATE:=2024-03-02/g; s/SOURCE_VERSION:=b2d7260dcb428b2fb65540edb28d7538602b4a26/SOURCE_VERSION:=564fa3e9c2b04ea298ea659b793480415da26415/g; s/MIRROR_HASH:=515bb9d355ad80916f594046a45c190a68fb6554d6795a54ca15cab8bdd12fda/MIRROR_HASH:=92c9ab94d88a2fe8d7d1e8a15d15cfc4d529fdc357ed96d22b65d5da3dd24d7f/g" "$makefile_path"
        echo "已更新 nginx-mod-ubus 模块"
    fi
}

install_opkg_distfeeds() {
    local emortal_def_dir="$BUILD_DIR/package/emortal/default-settings"
    local distfeeds_conf="$emortal_def_dir/files/99-distfeeds.conf"
    if [ -d "$emortal_def_dir" ] && [ ! -f "$distfeeds_conf" ]; then
        cat <<'EOF' >"$distfeeds_conf"
src/gz openwrt_base https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/base/
src/gz openwrt_luci https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/luci/
src/gz openwrt_packages https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/packages/
src/gz openwrt_routing https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/routing/
src/gz openwrt_telephony https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/telephony/
EOF
        sed -i "/define Package\/default-settings\/install/a\\
\t\$(INSTALL_DIR) \$(1)/etc\n\
\t\$(INSTALL_DATA) ./files/99-distfeeds.conf \$(1)/etc/99-distfeeds.conf\n" "$emortal_def_dir/Makefile"
        sed -i "/exit 0/i\\
[ -f \'/etc/99-distfeeds.conf\' ] && mv \'/etc/99-distfeeds.conf\' \'/etc/opkg/distfeeds.conf\'\n\
sed -ri \'/check_signature/s@^[^#]@#&@\' /etc/opkg.conf\n" "$emortal_def_dir/files/99-default-settings"
    fi
}

# ==================== [build.sh] 构建辅助函数 ====================
remove_uhttpd_dependency() {
    local config_path="$BUILD_DIR/.config"
    local luci_makefile_path="$BUILD_DIR/feeds/luci/collections/luci/Makefile"
    if grep -q "CONFIG_PACKAGE_luci-app-quickfile=y" "$config_path"; then
        if [ -f "$luci_makefile_path" ]; then
            sed -i '/luci-light/d' "$luci_makefile_path"
            echo "Removed uhttpd (luci-light) dependency as luci-app-quickfile (nginx) is enabled."
        fi
    fi
}

apply_config() {
    \cp -f "$CONFIG_FILE" "$BUILD_DIR/.config"
    if grep -qE "(ipq60xx|ipq807x)" "$BUILD_DIR/.config" &&
        ! grep -q "CONFIG_GIT_MIRROR" "$BUILD_DIR/.config"; then
        cat "$BASE_PATH/deconfig/nss.config" >> "$BUILD_DIR/.config"
    fi
}

replace_custom_files() {
    local dts_src dts_dst mk_src mk_dst
    dts_dst="$BUILD_DIR/target/linux/mediatek/dts/mt7622-netgear-wax206.dts"
    mk_dst="$BUILD_DIR/target/linux/mediatek/image/mt7622.mk"
    case "$Dev" in
        "fmwax206")
            echo "=== 应用 FMWAX206 自定义配置（70M 大分区）==="
            dts_src="$BASE_PATH/dts/wax206-70m.dts"; mk_src="$BASE_PATH/mediatek/image/mt7622-70m.mk" ;;
        "gwax206")
            echo "=== 应用 GWAX206 自定义配置（256M 大分区）==="
            dts_src="$BASE_PATH/dts/wax206-256m.dts"; mk_src="$BASE_PATH/mediatek/image/mt7622-256m.mk" ;;
        "gwax206_imm")
            echo "=== 应用 GWAX206 自定义配置（256M 大分区）==="
            dts_src="$BASE_PATH/dts/wax206-256m.dts"; mk_src="$BASE_PATH/mediatek/image/mt7622-256m.mk" ;;
        "wax206")
            echo "=== 使用 WAX206 默认配置（不进行替换）==="; return 0 ;;
        *)
            echo "=== 设备 $Dev 无需自定义 DTS/MK 替换 ==="; return 0 ;;
    esac
    if [[ -f "$dts_src" ]]; then \cp -f "$dts_src" "$dts_dst"; echo "已替换 DTS: $dts_src -> $dts_dst"; else echo "警告: DTS 源文件不存在: $dts_src"; fi
    if [[ -f "$mk_src" ]]; then \cp -f "$mk_src" "$mk_dst"; echo "已替换 MK: $mk_src -> $mk_dst"; else echo "警告: MK 源文件不存在: $mk_src"; fi
}

# ==================== [update.sh main] 源码更新主流程 ====================
run_update() {
    clone_repo
    clean_up
    reset_feeds_conf
    update_feeds
    update_golang
    fix_rust_compile_error
    update_nginx_ubus_module
    install_opkg_distfeeds
    remove_attendedsysupgrade
    install_feeds
}

# ==================== 主流程 ====================
echo "=========================================="
echo "WAX206 一体化编译脚本"
echo "设备: $Dev"
echo "=========================================="

# Step 1: 克隆源码
clone_source

# Step 2: 执行源码更新（原 update.sh 的 main）
run_update

# Step 3: 执行 DIY Part2 配置（已合并到 build.sh）
echo "=== 执行 DIY Part2 配置 ==="

run_diy_part2() {
    local Dev="$1"
    local BUILD_DIR="$2"

    echo "=========================================="
    echo "DIY Part2 - 设备: $Dev"
    echo "BUILD_DIR: $BUILD_DIR"
    echo "=========================================="

    echo "目标目录: $BUILD_DIR"

    if [ ! -d "$BUILD_DIR" ]; then
        echo "错误: 目录 $BUILD_DIR 不存在"
        ls -la
        exit 1
    fi

    # ========== 添加自定义插件 ==========
    echo ">>> 添加自定义插件 luci-app-devicemaster..."

    if [ -d "$REPO_ROOT/wax206/packages/luci-app-devicemaster" ]; then  # REPO_ROOT已确保是仓库根
        cp -r "$REPO_ROOT/wax206/packages/luci-app-devicemaster" "$BUILD_DIR/package/"
        echo "✓ 插件已复制到 $BUILD_DIR/package/luci-app-devicemaster"
    else
        echo "⚠ 警告: $REPO_ROOT/wax206/packages/luci-app-devicemaster 不存在，跳过插件安装"
    fi

    cd "$BUILD_DIR" || exit 1
    echo "进入目录: $(pwd)"

    # ========== 安装插件到 feeds ==========
    if [ -d "package/luci-app-devicemaster" ]; then
        ./scripts/feeds update luci >/dev/null 2>&1
        ./scripts/feeds install -a -p luci >/dev/null 2>&1
        echo "✓ luci-app-devicemaster feeds 安装完成"
    fi

    # ========== 配置IP ==========
    if [ -f "package/base-files/files/bin/config_generate" ]; then
        sed -i 's/192.168.1.1/192.168.31.1/g' package/base-files/files/bin/config_generate
        echo "✓ IP改为192.168.31.1"
    fi

    # ========== 配置主机名 ==========
    if [ -f "package/base-files/files/bin/config_generate" ]; then
        sed -i 's/OpenWrt/Wax206/g' package/base-files/files/bin/config_generate
        echo "✓ 主机名改为Wax206"
    fi

    # ========== 配置时区 ==========
    if [ -f "package/base-files/files/bin/config_generate" ]; then
        sed -i "s/timezone='.*'/timezone='CST-8'/g" package/base-files/files/bin/config_generate
        sed -i "/timezone='CST-8'/a\\t\tset system.@system[-1].zonename='Asia/Shanghai'" package/base-files/files/bin/config_generate
        echo "✓ 时区改为Asia/Shanghai"
    fi

    # ========== 强制覆盖 distfeeds.list ==========
    echo ">>> 强制重置 distfeeds.list 为官方源..."

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

    echo ">>> distfeeds.list 已重置："
    cat package/base-files/files/etc/apk/repositories.d/distfeeds.list

    # ========== Conntrack 优化配置 ==========
    echo "配置 conntrack 优化..."

    mkdir -p package/base-files/files/etc/sysctl.d
    mkdir -p package/base-files/files/etc/modules.d
    mkdir -p package/base-files/files/etc/hotplug.d/iface

    cat > package/base-files/files/etc/sysctl.d/99-conntrack.conf << 'EOF'
net.netfilter.nf_conntrack_max=262144
net.netfilter.nf_conntrack_tcp_timeout_established=600
net.netfilter.nf_conntrack_tcp_timeout_time_wait=30
net.netfilter.nf_conntrack_tcp_timeout_close_wait=10
net.netfilter.nf_conntrack_tcp_timeout_fin_wait=10
net.netfilter.nf_conntrack_tcp_timeout_syn_recv=30
net.netfilter.nf_conntrack_tcp_timeout_syn_sent=30
net.netfilter.nf_conntrack_tcp_timeout_last_ack=10
net.netfilter.nf_conntrack_udp_timeout=10
net.netfilter.nf_conntrack_udp_timeout_stream=30
net.netfilter.nf_conntrack_icmp_timeout=5
net.netfilter.nf_conntrack_log_invalid=0
net.netfilter.nf_conntrack_tcp_be_liberal=1
EOF
    echo "✓ /etc/sysctl.d/99-conntrack.conf 已写入"

    cat > package/base-files/files/etc/sysctl.d/99-network.conf << 'EOF'
net.core.netdev_max_backlog=65536
net.core.netdev_budget=50000
net.ipv4.tcp_mem=262144 524288 786432
net.ipv4.tcp_rmem=4096 87380 6291456
net.ipv4.tcp_wmem=4096 65536 6291456
net.ipv4.tcp_congestion_control=cubic
net.ipv4.ip_local_port_range=1024 65535
net.ipv4.tcp_slow_start_after_idle=0
EOF
    echo "✓ /etc/sysctl.d/99-network.conf 已写入"

    echo "nf_conntrack hashsize=65536" > package/base-files/files/etc/modules.d/99-nf-conntrack-custom
    echo "✓ /etc/modules.d/99-nf-conntrack-custom 已写入"

    cat > package/base-files/files/etc/hotplug.d/iface/99-conntrack << 'HOTPLUG'
#!/bin/sh
[ "$ACTION" = "ifup" ] && [ "$INTERFACE" = "wan" ] && {
    sleep 2
    echo 262144 > /proc/sys/net/netfilter/nf_conntrack_max
    echo 600 > /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established
    echo 30 > /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_time_wait
    echo 10 > /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_close_wait
    echo 10 > /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_fin_wait
    echo 30 > /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_syn_recv
    echo 30 > /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_syn_sent
    echo 10 > /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_last_ack
    echo 10 > /proc/sys/net/netfilter/nf_conntrack_udp_timeout
    echo 30 > /proc/sys/net/netfilter/nf_conntrack_udp_timeout_stream
    echo 5 > /proc/sys/net/netfilter/nf_conntrack_icmp_timeout
    echo 0 > /proc/sys/net/netfilter/nf_conntrack_log_invalid
    echo 1 > /proc/sys/net/netfilter/nf_conntrack_tcp_be_liberal
}
HOTPLUG
    chmod +x package/base-files/files/etc/hotplug.d/iface/99-conntrack
    echo "✓ /etc/hotplug.d/iface/99-conntrack 已写入"

    # ========== WiFi 配置 ==========
    MAC80211_UC="package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"

    if [ -f "$MAC80211_UC" ]; then
        echo "找到 mac80211.uc，修改 WiFi 默认配置..."

        sed -i "s/set \${si}\.disabled='\${defaults ? 0 : 1}'/set \${si}.disabled='0'/g" "$MAC80211_UC"
        sed -i 's/"OpenWrt"/"Wax206"/g' "$MAC80211_UC"
        sed -i "s|set \${s}.country=.*|set \${s}.country='US'|g" "$MAC80211_UC"
        sed -i "/set \${s}.country=/a set \${s}.txpower='28'" "$MAC80211_UC"

        echo "✓ WiFi 默认启用"
        echo "✓ SSID 改为 Wax206"
        echo "✓ 国家代码 US，功率 28"
    else
        echo "警告: 未找到 $MAC80211_UC"
        find . -name "mac80211.uc" -type f 2>/dev/null
    fi

    echo "=========================================="
    echo "DIY 配置完成！"
    echo "=========================================="
}

# 执行 DIY Part2
run_diy_part2 "$Dev" "$BUILD_DIR"

# DIY 执行完后回到仓库根目录（后续步骤需要）
cd "$REPO_ROOT" || exit 1


# Step 4: 替换自定义 DTS/MK 文件
replace_custom_files

# Step 5: 应用编译配置
apply_config
remove_uhttpd_dependency

# Step 6: 编译
cd "$BUILD_DIR"
make defconfig

if grep -qE "^CONFIG_TARGET_x86_64=y" "$CONFIG_FILE"; then
    local DISTFEEDS_PATH="$BUILD_DIR/package/emortal/default-settings/files/99-distfeeds.conf"
    if [ -d "${DISTFEEDS_PATH%/*}" ] && [ -f "$DISTFEEDS_PATH" ]; then
        sed -i 's/aarch64_cortex-a53/x86_64/g' "$DISTFEEDS_PATH"
    fi
fi

if [[ "$Build_Mod" == "debug" ]]; then exit 0; fi

TARGET_DIR="$BUILD_DIR/bin/targets"
if [[ -d "$TARGET_DIR" ]]; then
    find "$TARGET_DIR" -type f \( -name "*.bin" -o -name "*.manifest" -o -name "*efi.img.gz" -o -name "*.itb" -o -name "*.img" -o -name "*.ubi" -o -name "*.tar.gz" \) -exec rm -f {} +
fi

make download
make V=s -j$(($(nproc) + 1))

# Step 7: 收集固件
cd "$BUILD_DIR/bin/packages"
tar -zcvf Packages.tar.gz ./*
cp Packages.tar.gz "$BUILD_DIR/bin/targets/"
cd "$BUILD_DIR"

FIRMWARE_DIR="$BASE_PATH/../firmware"
\rm -rf "$FIRMWARE_DIR"
mkdir -p "$FIRMWARE_DIR"
find "$TARGET_DIR" -type f \( -name "*.bin" -o -name "*.itb" -o -name "*.manifest" \) -exec cp -f {} "$FIRMWARE_DIR/" \;

if [[ -d "action_build" ]]; then make clean; fi

echo "=========================================="
echo "编译完成！固件已保存到 $FIRMWARE_DIR"
echo "=========================================="
