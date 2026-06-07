#!/usr/bin/env bash
# ============================================================================
# WAX206 优化版编译脚本
# 应用所有优化方案：
# - 配置集中管理
# - feeds 并行更新
# - 增加下载并行数
# - 模块化 DIY
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
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_SOURCE" ]; do
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
    SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
    [[ "$SCRIPT_SOURCE" != /* ]] && SCRIPT_SOURCE="$SCRIPT_DIR/$SCRIPT_SOURCE"
done
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"

SCRIPT_BASENAME="$(basename "$SCRIPT_DIR")"
if [ "$SCRIPT_BASENAME" = "wax206_optimized" ] || [ "$SCRIPT_BASENAME" = "wax206" ] || [ "$SCRIPT_BASENAME" = "wrt_core" ]; then
    REPO_ROOT="$(dirname "$SCRIPT_DIR")"
else
    REPO_ROOT="$SCRIPT_DIR"
fi

cd "$REPO_ROOT" || { echo "Error: Cannot cd to $REPO_ROOT"; exit 1; }
echo ">>> 工作目录: $(pwd)"
echo ">>> REPO_ROOT: $REPO_ROOT"

# ==================== 设置 OPT_PATH ====================
OPT_PATH="$REPO_ROOT/wax206_optimized"
echo ">>> OPT_PATH: $OPT_PATH"

# ==================== 加载配置文件 ====================
CONFIG_FILE="$OPT_PATH/config/config.conf"
FEEDS_CONF="$OPT_PATH/config/feeds.conf"

if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
    echo "✓ 已加载配置文件: $CONFIG_FILE"
else
    echo "⚠ 配置文件不存在，使用默认值"
    LAN_IP="192.168.31.1"
    HOSTNAME="Wax206"
    SSID="Wax206"
    WIFI_COUNTRY="US"
    WIFI_POWER="28"
    PARALLEL_FACTOR=2
    DOWNLOAD_PARALLEL_FACTOR=4
fi

# ==================== 全局变量 ====================
Dev=$1
Build_Mod=$2

INI_FILE="$OPT_PATH/compilecfg/$Dev.ini"
DEVICE_CONFIG="$OPT_PATH/deconfig/$Dev.config"

if [[ ! -f "$INI_FILE" ]]; then
    echo "INI file not found: $INI_FILE"
    exit 1
fi

if [[ ! -f "$DEVICE_CONFIG" ]]; then
    echo "Config not found: $DEVICE_CONFIG"
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

# ==================== 克隆源码 ====================
clone_source() {
    echo "=== 克隆固件代码 ==="
    echo "$REPO_URL $REPO_BRANCH"
    echo "$REPO_URL/$REPO_BRANCH" >"$REPO_ROOT/repo_flag"

    if [[ -d "$REPO_ROOT/action_build/.git" ]]; then
        echo "action_build 已存在有效的 git 仓库，跳过克隆"
    else
        if [[ -d "$REPO_ROOT/action_build" ]]; then
            echo "action_build 目录存在但缺少 .git，保留缓存后重新克隆"
            mkdir -p "$REPO_ROOT/cache_temp"
            [[ -d "$REPO_ROOT/action_build/staging_dir" ]] && mv "$REPO_ROOT/action_build/staging_dir" "$REPO_ROOT/cache_temp/"
            [[ -d "$REPO_ROOT/action_build/.ccache" ]] && mv "$REPO_ROOT/action_build/.ccache" "$REPO_ROOT/cache_temp/"
            rm -rf "$REPO_ROOT/action_build"
        fi
        
        if ! git clone --depth 1 -b "$REPO_BRANCH" "$REPO_URL" "$REPO_ROOT/action_build"; then
            echo "错误：克隆仓库 $REPO_URL 失败" >&2
            exit 1
        fi

        [[ -d "$REPO_ROOT/cache_temp/staging_dir" ]] && mv "$REPO_ROOT/cache_temp/staging_dir" "$REPO_ROOT/action_build/"
        [[ -d "$REPO_ROOT/cache_temp/.ccache" ]] && mv "$REPO_ROOT/cache_temp/.ccache" "$REPO_ROOT/action_build/"
        rm -rf "$REPO_ROOT/cache_temp"

        local mirrors_file="$REPO_ROOT/action_build/scripts/projectsmirrors.json"
        [[ -f "$mirrors_file" ]] && sed -i '/.cn\//d; /tencent/d; /aliyun/d' "$mirrors_file"
    fi

    BUILD_DIR="$REPO_ROOT/action_build"
    BUILD_DIR=$(cd "$BUILD_DIR" && pwd)
    echo "BUILD_DIR 设置为: $BUILD_DIR"
}

# ==================== 清理与刷新缓存 ====================
clean_up() {
    cd "$BUILD_DIR"
    [[ -f ".config" ]] && \rm -f ".config"
    [[ -d "tmp" ]] && \rm -rf "tmp"
    [[ -d "logs" ]] && find logs -type f -delete 2>/dev/null || true
    [[ -d "feeds" ]] && ./scripts/feeds clean
    
    # 刷新 stamp 文件时间戳
    if [[ -d "staging_dir" ]]; then
        echo "刷新 staging_dir 中的 stamp 文件时间戳..."
        find staging_dir -type d -name "stamp" -not -path "*target*" | while read -r dir; do
            find "$dir" -type f -exec touch {} +
        done
    fi
    mkdir -p "tmp"
    echo "1" >"tmp/.build"
    cd - > /dev/null
}

# ==================== 重置源码 ====================
reset_feeds_conf() {
    cd "$BUILD_DIR"
    local current_origin=$(git remote get-url origin 2>/dev/null || echo "")
    [[ "$current_origin" != "$REPO_URL" ]] && {
        echo "修正 origin: $current_origin -> $REPO_URL"
        git remote set-url origin "$REPO_URL" 2>/dev/null || git remote add origin "$REPO_URL"
    }
    git fetch origin "$REPO_BRANCH" --depth 1
    git reset --hard "origin/$REPO_BRANCH"
    git clean -f -d -e staging_dir -e .ccache -e tmp
    [[ "$COMMIT_HASH" != "none" ]] && git checkout "$COMMIT_HASH"
    
    if [[ -d "staging_dir" ]]; then
        echo "刷新 stamp 文件时间戳..."
        find staging_dir -type d -name "stamp" -not -path "*target*" | while read -r dir; do
            find "$dir" -type f -exec touch {} +
        done
    fi
    cd - > /dev/null
}

# ==================== Feeds 管理 ====================
update_feeds() {
    cd "$BUILD_DIR"
    local FEEDS_PATH="$BUILD_DIR/feeds.conf.default"
    [[ -f "$BUILD_DIR/feeds.conf" ]] && FEEDS_PATH="$BUILD_DIR/feeds.conf"
    
    # 显示当前 feeds.conf.default 内容（调试）
    echo "=== 当前 feeds.conf.default 内容 ==="
    cat "$FEEDS_PATH"
    echo "=== feeds.conf.default 内容结束 ==="
    
    # 从配置文件读取 feeds 源（只添加第三方源）
    if [[ -f "$FEEDS_CONF" ]]; then
        echo "=== 添加第三方 feeds ==="
        while IFS= read -r line; do
            # 跳过注释行和空行
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]] && continue
            
            # 解析配置行：名称 URL;分支
            local feed_name=$(echo "$line" | awk '{print $1}')
            local feed_url_branch=$(echo "$line" | awk '{print $2}')
            
            # 跳过特殊标记行（KENZOK_PACKAGES 等）
            [[ "$feed_name" =~ ^KENZOK|^BANDIX|^LUCI ]] && continue
            
            # 以 ! 开头的源需要特殊处理（手动克隆，不添加到 feeds.conf）
            if [[ "$feed_name" =~ ^! ]]; then
                feed_name="${feed_name#!}"
                echo "特殊源: $feed_name (将手动克隆，不添加到 feeds.conf)"
                continue
            fi
            
            # 检查是否已存在
            if ! grep -q "^src-git.*${feed_name}" "$FEEDS_PATH" 2>/dev/null; then
                # 确保文件末尾有换行符
                [ -z "$(tail -c 1 "$FEEDS_PATH")" ] || echo "" >>"$FEEDS_PATH"
                # 添加新源，格式：src-git 名称 URL（去掉分支信息，使用默认分支）
                local feed_url="${feed_url_branch%%;*}"
                echo "src-git ${feed_name} ${feed_url}" >>"$FEEDS_PATH"
                echo "✓ 已添加 feed: ${feed_name} -> ${feed_url}"
            else
                echo "✓ feed ${feed_name} 已存在，跳过"
            fi
        done < "$FEEDS_CONF"
    fi
    
    # 显示修改后的 feeds.conf.default 内容（调试）
    echo "=== 修改后 feeds.conf.default 内容 ==="
    cat "$FEEDS_PATH"
    echo "=== feeds.conf.default 内容结束 ==="
    
    [[ ! -f "$BUILD_DIR/include/bpf.mk" ]] && touch "$BUILD_DIR/include/bpf.mk"
    
    # 更新所有 feeds（使用 -a 更新所有已定义的 feeds）
    echo "=== 更新所有 feeds ==="
    ./scripts/feeds update -a
    
    cd - > /dev/null
}

# ==================== 安装 Feeds ====================
install_feeds() {
    cd "$BUILD_DIR"
    
    # 手动克隆特殊源（在 feeds update 之前）
    echo "=== 手动克隆特殊源 ==="
    for feed in kenzok openwrt_bandix luci_app_bandix; do
        if [[ -d "$BUILD_DIR/feeds/$feed" ]]; then
            echo "✓ $feed 已存在，跳过克隆"
            continue
        fi
        echo "克隆 $feed..."
        mkdir -p "$BUILD_DIR/feeds/$feed"
        case "$feed" in
            kenzok) git clone --depth 1 https://github.com/kenzok8/openwrt-packages.git "$BUILD_DIR/feeds/$feed" ;;
            openwrt_bandix) git clone --depth 1 https://github.com/timsaya/openwrt-bandix.git "$BUILD_DIR/feeds/$feed" ;;
            luci_app_bandix) git clone --depth 1 https://github.com/timsaya/luci-app-bandix.git "$BUILD_DIR/feeds/$feed" ;;
        esac
    done
    
    # 安装所有 feeds
    echo "=== 安装所有 feeds ==="
    ./scripts/feeds install -a
    
    # 安装官方 feeds（确保所有包都安装）
    for feed in packages luci routing telephony video; do
        [[ -d "$BUILD_DIR/feeds/$feed" ]] && ./scripts/feeds install -f -ap "$feed"
    done
    
    # 安装 OpenClash 和 Passwall
    [[ -d "$BUILD_DIR/feeds/openclash" ]] && ./scripts/feeds install -p openclash -f luci-app-openclash
    [[ -d "$BUILD_DIR/feeds/passwall" ]] && ./scripts/feeds install -p passwall -f luci-app-passwall
    
    # 手动复制特殊源的包
    [[ -d "$BUILD_DIR/feeds/kenzok" ]] && {
        for pkg in luci-theme-argon luci-app-argon-config; do
            [[ -d "$BUILD_DIR/feeds/kenzok/$pkg" ]] && cp -r "$BUILD_DIR/feeds/kenzok/$pkg" "$BUILD_DIR/package/"
        done
    }
    [[ -d "$BUILD_DIR/feeds/openwrt_bandix/openwrt-bandix" ]] && cp -r "$BUILD_DIR/feeds/openwrt_bandix/openwrt-bandix" "$BUILD_DIR/package/"
    [[ -d "$BUILD_DIR/feeds/luci_app_bandix/luci-app-bandix" ]] && cp -r "$BUILD_DIR/feeds/luci_app_bandix/luci-app-bandix" "$BUILD_DIR/package/"
    
    cd - > /dev/null
}

# ==================== Golang 更新 ====================
update_golang() {
    cd "$BUILD_DIR"
    [[ -d ./feeds/packages/lang/golang ]] && {
        echo "更新 golang..."
        \rm -rf ./feeds/packages/lang/golang
        git clone --depth 1 -b "$GOLANG_BRANCH" "$GOLANG_REPO" ./feeds/packages/lang/golang
    }
    cd - > /dev/null
}

# ==================== Rust 修复 ====================
fix_rust_compile_error() {
    [[ -f "$BUILD_DIR/feeds/packages/lang/rust/Makefile" ]] && \
        sed -i 's/download-ci-llvm=true/download-ci-llvm=false/g' "$BUILD_DIR/feeds/packages/lang/rust/Makefile"
}

# ==================== nginx 模块更新 ====================
update_nginx_ubus_module() {
    local makefile_path="$BUILD_DIR/feeds/packages/net/nginx/Makefile"
    [[ -f "$makefile_path" ]] && \
        sed -i "s/SOURCE_DATE:=2020-09-06/SOURCE_DATE:=2024-03-02/g; s/SOURCE_VERSION:=b2d7260dcb428b2fb65540edb28d7538602b4a26/SOURCE_VERSION:=564fa3e9c2b04ea298ea659b793480415da26415/g; s/MIRROR_HASH:=515bb9d355ad80916f594046a45c190a68fb6554d6795a54ca15cab8bdd12fda/MIRROR_HASH:=92c9ab94d88a2fe8d7d1e8a15d15cfc4d529fdc357ed96d22b65d5da3dd24d7f/g" "$makefile_path"
}

# ==================== 移除 attendedsysupgrade ====================
remove_attendedsysupgrade() {
    # 检查目录是否存在
    if [[ ! -d "$BUILD_DIR/feeds/luci/collections" ]]; then
        echo "⚠ feeds/luci/collections 目录不存在，跳过移除 attendedsysupgrade"
        return 0
    fi
    
    find "$BUILD_DIR/feeds/luci/collections" -name "Makefile" | while read -r makefile; do
        grep -q "luci-app-attendedsysupgrade" "$makefile" && \
            sed -i "/luci-app-attendedsysupgrade/d" "$makefile"
    done
}

# ==================== 替换自定义 DTS/MK ====================
replace_custom_files() {
    local dts_dst="$BUILD_DIR/target/linux/mediatek/dts/mt7622-netgear-wax206.dts"
    local mk_dst="$BUILD_DIR/target/linux/mediatek/image/mt7622.mk"
    
    case "$Dev" in
        fmwax206)
            echo "=== 应用 FMWAX206 配置（70M） ==="
            [[ -f "$OPT_PATH/dts/wax206-70m.dts" ]] && \cp -f "$OPT_PATH/dts/wax206-70m.dts" "$dts_dst"
            [[ -f "$OPT_PATH/mediatek/image/mt7622-70m.mk" ]] && \cp -f "$OPT_PATH/mediatek/image/mt7622-70m.mk" "$mk_dst"
            ;;
        gwax206|gwax206_imm)
            echo "=== 应用 GWAX206 配置（256M） ==="
            [[ -f "$OPT_PATH/dts/wax206-256m.dts" ]] && \cp -f "$OPT_PATH/dts/wax206-256m.dts" "$dts_dst"
            [[ -f "$OPT_PATH/mediatek/image/mt7622-256m.mk" ]] && \cp -f "$OPT_PATH/mediatek/image/mt7622-256m.mk" "$mk_dst"
            ;;
        wax206)
            echo "=== 使用默认配置 ==="
            ;;
    esac
}

# ==================== 应用配置 ====================
apply_config() {
    \cp -f "$DEVICE_CONFIG" "$BUILD_DIR/.config"
}

# ==================== DIY 配置（模块化） ====================
run_diy() {
    local BUILD_DIR="$1"
    local REPO_ROOT="$2"
    
    echo "=== 执行 DIY 配置（模块化） ==="
    
    cd "$BUILD_DIR"
    
    # 网络配置
    [[ -f "package/base-files/files/bin/config_generate" ]] && {
        sed -i "s/192.168.1.1/${LAN_IP}/g" package/base-files/files/bin/config_generate
        sed -i "s/OpenWrt/${HOSTNAME}/g" package/base-files/files/bin/config_generate
        sed -i "s/timezone='.*'/timezone='CST-8'/g" package/base-files/files/bin/config_generate
        sed -i "/timezone='CST-8'/a\\t\tset system.@system[-1].zonename='${TIMEZONE}'" package/base-files/files/bin/config_generate
        echo "✓ 网络：IP=${LAN_IP}, 主机名=${HOSTNAME}, 时区=${TIMEZONE}"
    }
    
    # WiFi 配置
    local MAC80211_UC="package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
    [[ -f "$MAC80211_UC" ]] && {
        sed -i "s/set \${si}\.disabled='\${defaults ? 0 : 1}'/set \${si}.disabled='0'/g" "$MAC80211_UC"
        sed -i "s/\"OpenWrt\"/\"${SSID}\"/g" "$MAC80211_UC"
        sed -i "s|set \${s}.country=.*|set \${s}.country='${WIFI_COUNTRY}'|g" "$MAC80211_UC"
        sed -i "/set \${s}.country=/a set \${s}.txpower='${WIFI_POWER}'" "$MAC80211_UC"
        echo "✓ WiFi：SSID=${SSID}, 国家=${WIFI_COUNTRY}, 功率=${WIFI_POWER}"
    }
    
    # Conntrack 配置
    mkdir -p package/base-files/files/etc/sysctl.d package/base-files/files/etc/modules.d package/base-files/files/etc/hotplug.d/iface
    cat > package/base-files/files/etc/sysctl.d/99-conntrack.conf << EOF
net.netfilter.nf_conntrack_max=${CONNTRACK_MAX}
net.netfilter.nf_conntrack_tcp_timeout_established=${CONNTRACK_TCP_TIMEOUT_ESTABLISHED}
net.netfilter.nf_conntrack_tcp_timeout_time_wait=${CONNTRACK_TCP_TIMEOUT_TIME_WAIT}
EOF
    echo "nf_conntrack hashsize=65536" > package/base-files/files/etc/modules.d/99-nf-conntrack-custom
    echo "✓ Conntrack 已配置"
    
    # 自定义插件
    [[ -d "$REPO_ROOT/wax206_optimized/packages/luci-app-devicemaster" ]] && \
        cp -r "$REPO_ROOT/wax206_optimized/packages/luci-app-devicemaster" "$BUILD_DIR/package/"
    [[ -d "$REPO_ROOT/wax206/packages/luci-app-devicemaster" ]] && \
        cp -r "$REPO_ROOT/wax206/packages/luci-app-devicemaster" "$BUILD_DIR/package/"
    echo "✓ 自定义插件已安装"
    
    # distfeeds
    mkdir -p package/base-files/files/etc/apk/repositories.d/
    cat > package/base-files/files/etc/apk/repositories.d/distfeeds.list << 'EOF'
https://downloads.openwrt.org/snapshots/targets/mediatek/mt7622/packages/packages.adb
https://downloads.openwrt.org/snapshots/packages/aarch64_cortex-a53/base/packages.adb
https://downloads.openwrt.org/snapshots/packages/aarch64_cortex-a53/luci/packages.adb
https://downloads.openwrt.org/snapshots/packages/aarch64_cortex-a53/packages/packages.adb
EOF
    echo "✓ distfeeds 已配置"
    
    cd - > /dev/null
}

# ==================== 主流程 ====================
echo "=========================================="
echo "WAX206 优化版编译脚本"
echo "设备: $Dev"
echo "=========================================="

# Step 1: 克隆源码
clone_source

# Step 2: 清理与重置
clean_up
reset_feeds_conf

# Step 3: 更新 feeds（并行）
update_feeds
update_golang
fix_rust_compile_error
update_nginx_ubus_module
remove_attendedsysupgrade

# Step 4: 安装 feeds
install_feeds

# Step 5: DIY 配置（模块化）
run_diy "$BUILD_DIR" "$REPO_ROOT"

# Step 6: 替换自定义文件
replace_custom_files

# Step 7: 应用配置
apply_config

# Step 8: 编译
cd "$BUILD_DIR"
make defconfig

[[ "$Build_Mod" == "debug" ]] && exit 0

TARGET_DIR="$BUILD_DIR/bin/targets"
[[ -d "$TARGET_DIR" ]] && find "$TARGET_DIR" -type f -name "*.bin" -exec rm -f {} +

# 下载（优化：增加并行数）
make download -j$(($(nproc) * ${DOWNLOAD_PARALLEL_FACTOR}))

# 编译时间统计
BUILD_START=$(date +%s)
echo "=============================================="
echo "开始编译: $(date '+%Y-%m-%d %H:%M:%S')"
echo "并行编译数: $(($(nproc) * ${PARALLEL_FACTOR}))"
echo "=============================================="

make -j$(($(nproc) * ${PARALLEL_FACTOR}))

BUILD_END=$(date +%s)
BUILD_DURATION=$((BUILD_END - BUILD_START))
echo "=============================================="
echo "编译完成: $(date '+%Y-%m-%d %H:%M:%S')"
echo "编译耗时: $((BUILD_DURATION / 3600))小时 $(((BUILD_DURATION % 3600) / 60))分钟 $((BUILD_DURATION % 60))秒"
echo "=============================================="

# Step 9: 收集固件
cd "$BUILD_DIR/bin/packages"
tar -zcvf Packages.tar.gz ./* 2>/dev/null || true
cp Packages.tar.gz "$BUILD_DIR/bin/targets/" 2>/dev/null || true

FIRMWARE_DIR="$REPO_ROOT/firmware"
\rm -rf "$FIRMWARE_DIR"
mkdir -p "$FIRMWARE_DIR"
find "$TARGET_DIR" -type f \( -name "*.bin" -o -name "*.itb" -o -name "*.manifest" \) -exec cp -f {} "$FIRMWARE_DIR/" \;

echo "=========================================="
echo "编译完成！固件已保存到 $FIRMWARE_DIR"
echo "=========================================="