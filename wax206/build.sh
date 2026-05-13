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

# ==================== 全局变量 ====================
Dev=$1
Build_Mod=$2

# 确定 wax206 目录路径
if [ -d "wax206" ]; then
    WAX206_PATH="wax206"
elif [ -d "../wax206" ]; then
    WAX206_PATH="../wax206"
else
    echo "Error: wax206 directory not found!"
    exit 1
fi
BASE_PATH=$(cd "$WAX206_PATH" && pwd)

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

if [[ -d "action_build" ]]; then
    BUILD_DIR="action_build"
fi

# update.sh 使用的变量
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
remove_unwanted_packages() {
    cd "$BUILD_DIR"
    local luci_packages=(
        "luci-app-passwall" "luci-app-ddns-go" "luci-app-rclone" "luci-app-ssr-plus"
        "luci-app-vssr" "luci-app-daed" "luci-app-dae" "luci-app-alist" "luci-app-homeproxy"
        "luci-app-haproxy-tcp" "luci-app-openclash" "luci-app-mihomo" "luci-app-appfilter"
        "luci-app-msd_lite" "luci-app-unblockneteasemusic"
    )
    local packages_net=(
        "haproxy" "xray-core" "xray-plugin" "dns2socks" "alist" "hysteria"
        "mosdns" "adguardhome" "ddns-go" "naiveproxy" "shadowsocks-rust"
        "sing-box" "v2ray-core" "v2ray-geodata" "v2ray-plugin" "tuic-client"
        "chinadns-ng" "ipt2socks" "tcping" "trojan-plus" "simple-obfs" "shadowsocksr-libev"
        "dae" "daed" "mihomo" "geoview" "tailscale" "open-app-filter" "msd_lite"
    )
    local packages_utils=("cups")
    local packages_broken=("fatresize" "onionshare-cli" "python-platformio" "python-uvicorn")
    local fichenx_package=(
        "ppp" "firewall" "dae" "daed" "daed-next" "libnftnl" "nftables" "dnsmasq" "luci-app-alist"
        "alist" "opkg" "smartdns" "luci-app-smartdns" "easytier"
    )

    for pkg in "${luci_packages[@]}"; do
        if [[ -d "./feeds/luci/applications/$pkg" ]]; then \rm -rf "./feeds/luci/applications/$pkg"; fi
        if [[ -d "./feeds/luci/themes/$pkg" ]]; then \rm -rf "./feeds/luci/themes/$pkg"; fi
    done
    for pkg in "${packages_net[@]}"; do
        if [[ -d "./feeds/packages/net/$pkg" ]]; then \rm -rf "./feeds/packages/net/$pkg"; fi
    done
    for pkg in "${packages_utils[@]}"; do
        if [[ -d "./feeds/packages/utils/$pkg" ]]; then \rm -rf "./feeds/packages/utils/$pkg"; fi
    done
    for pkg in "${packages_broken[@]}"; do
        find ./feeds -type d -name "$pkg" -exec \rm -rf {} + 2>/dev/null || true
    done
    for pkg in "${fichenx_package[@]}"; do
        if [[ -d "./feeds/fichenx/$pkg" ]]; then \rm -rf "./feeds/fichenx/$pkg"; fi
    done
    if [[ -d "./package/istore" ]]; then \rm -rf "./package/istore"; fi
    if [ -d "$BUILD_DIR/target/linux/qualcommax/base-files/etc/uci-defaults" ]; then
        find "$BUILD_DIR/target/linux/qualcommax/base-files/etc/uci-defaults/" -type f -name "99*.sh" -exec rm -f {} +
    fi
    cd - > /dev/null
}

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

install_passwall() {
    cd "$BUILD_DIR"
    ./scripts/feeds install -p passwall -f luci-app-passwall
    cd - > /dev/null
}



check_default_settings() {
    local settings_dir="$BUILD_DIR/package/emortal/default-settings"
    if [ -z "$(find "$BUILD_DIR/package" -type d -name "default-settings" -print -quit 2>/dev/null)" ]; then
        echo "在 $BUILD_DIR/package 中未找到 default-settings 目录，正在从 immortalwrt 仓库克隆..."
        local tmp_dir
        tmp_dir=$(mktemp -d)
        if git clone --depth 1 --filter=blob:none --sparse https://github.com/immortalwrt/immortalwrt.git "$tmp_dir"; then
            pushd "$tmp_dir" >/dev/null
            git sparse-checkout set package/emortal/default-settings
            mkdir -p "$(dirname "$settings_dir")"
            mv package/emortal/default-settings "$settings_dir"
            popd >/dev/null
            rm -rf "$tmp_dir"
            echo "default-settings 克隆并移动成功"
        else
            echo "错误：克隆 immortalwrt 仓库失败" >&2
            rm -rf "$tmp_dir"
            exit 1
        fi
    fi
}


update_homeproxy() {
    local target_dir="$BUILD_DIR/feeds/fichenx/luci-app-homeproxy"
    if [ -d "$target_dir" ]; then
        echo "正在更新 homeproxy..."
        rm -rf "$target_dir"
        if ! git clone --depth 1 "https://github.com/immortalwrt/homeproxy.git" "$target_dir"; then
            echo "错误：克隆 homeproxy 仓库失败" >&2
            exit 1
        fi
    fi
}

add_timecontrol() {
    local timecontrol_dir="$BUILD_DIR/package/luci-app-timecontrol"
    rm -rf "$timecontrol_dir" 2>/dev/null || true
    echo "正在添加 luci-app-timecontrol..."
    if ! git clone --depth 1 "https://github.com/sirpdboy/luci-app-timecontrol.git" "$timecontrol_dir"; then
        echo "错误：克隆 luci-app-timecontrol 仓库失败" >&2
        exit 1
    fi
}

update_adguardhome() {
    local adguardhome_dir="$BUILD_DIR/package/feeds/fichenx/luci-app-adguardhome"
    rm -rf "$adguardhome_dir" 2>/dev/null || true
    echo "正在更新 luci-app-adguardhome..."
    if ! git clone --depth 1 "https://github.com/ZqinKing/luci-app-adguardhome.git" "$adguardhome_dir"; then
        echo "错误：克隆 luci-app-adguardhome 仓库失败" >&2
        exit 1
    fi
}

update_smartdns() {
    local SMARTDNS_DIR="$BUILD_DIR/feeds/packages/net/smartdns"
    local LUCI_APP_SMARTDNS_DIR="$BUILD_DIR/feeds/luci/applications/luci-app-smartdns"
    echo "正在更新 smartdns..."
    rm -rf "$SMARTDNS_DIR"
    if ! git clone --depth=1 "https://github.com/ZqinKing/openwrt-smartdns.git" "$SMARTDNS_DIR"; then
        echo "错误：克隆 smartdns 仓库失败" >&2
        exit 1
    fi
    sed -i '/define Build\/Compile\/smartdns-ui/,/endef/s/CC=\$(TARGET_CC)/CC="\$(TARGET_CC_NOCACHE)"/' "$SMARTDNS_DIR/Makefile"
    echo "正在更新 luci-app-smartdns..."
    rm -rf "$LUCI_APP_SMARTDNS_DIR"
    if ! git clone --depth=1 "https://github.com/pymumu/luci-app-smartdns.git" "$LUCI_APP_SMARTDNS_DIR"; then
        echo "错误：克隆 luci-app-smartdns 仓库失败" >&2
        exit 1
    fi
}

update_diskman() {
    local path="$BUILD_DIR/feeds/luci/applications/luci-app-diskman"
    if [ -d "$path" ]; then
        echo "正在更新 diskman..."
        cd "$BUILD_DIR/feeds/luci/applications" || return
        \rm -rf "luci-app-diskman"
        if ! git clone --filter=blob:none --no-checkout "https://github.com/lisaac/luci-app-diskman.git" diskman; then
            echo "错误：克隆 diskman 仓库失败" >&2
            exit 1
        fi
        cd diskman || return
        git sparse-checkout init --cone
        git sparse-checkout set applications/luci-app-diskman || return
        git checkout --quiet
        mv applications/luci-app-diskman ../luci-app-diskman || return
        cd .. || return
        \rm -rf diskman
        cd "$BUILD_DIR"
        sed -i 's/fs-ntfs /fs-ntfs3 /g' "$path/Makefile"
        sed -i '/ntfs-3g-utils /d' "$path/Makefile"
    fi
}

add_quickfile() {
    local target_dir="$BUILD_DIR/package/emortal/quickfile"
    if [ -d "$target_dir" ]; then rm -rf "$target_dir"; fi
    echo "正在添加 luci-app-quickfile..."
    if ! git clone --depth 1 "https://github.com/sbwml/luci-app-quickfile.git" "$target_dir"; then
        echo "错误：克隆 luci-app-quickfile 仓库失败" >&2
        exit 1
    fi
    local makefile_path="$target_dir/quickfile/Makefile"
    if [ -f "$makefile_path" ]; then
        sed -i '/\t\$(INSTALL_BIN) \$(PKG_BUILD_DIR)\/quickfile-\$(ARCH_PACKAGES)/c\
\tif [ "\$(ARCH_PACKAGES)" = "x86_64" ]; then \\\t\t\$(INSTALL_BIN) \$(PKG_BUILD_DIR)\/quickfile-x86_64 \$(1)\/usr\/bin\/quickfile; \\\telse \\\t\t\$(INSTALL_BIN) \$(PKG_BUILD_DIR)\/quickfile-aarch64_generic \$(1)\/usr\/bin\/quickfile; \\\tfi' "$makefile_path"
    fi
}

update_argon() {
    local dst_theme_path="$BUILD_DIR/feeds/luci/themes/luci-theme-argon"
    local tmp_dir
    tmp_dir=$(mktemp -d)
    echo "正在更新 argon 主题..."
    if ! git clone --depth 1 "https://github.com/ZqinKing/luci-theme-argon.git" "$tmp_dir"; then
        echo "错误：克隆 argon 主题仓库失败" >&2
        rm -rf "$tmp_dir"
        exit 1
    fi
    rm -rf "$dst_theme_path"
    rm -rf "$tmp_dir/.git"
    mv "$tmp_dir" "$dst_theme_path"
    echo "luci-theme-argon 更新完成"
}

remove_attendedsysupgrade() {
    find "$BUILD_DIR/feeds/luci/collections" -name "Makefile" | while read -r makefile; do
        if grep -q "luci-app-attendedsysupgrade" "$makefile"; then
            sed -i "/luci-app-attendedsysupgrade/d" "$makefile"
            echo "Removed luci-app-attendedsysupgrade from $makefile"
        fi
    done
}

update_package() {
    local dir
    dir=$(find "$BUILD_DIR/package" \( -type d -o -type l \) -name "$1")
    if [ -z "$dir" ]; then return 0; fi
    local branch="$2"
    if [ -z "$branch" ]; then branch="releases"; fi
    local mk_path="$dir/Makefile"
    if [ -f "$mk_path" ]; then
        local PKG_REPO
        PKG_REPO=$(grep -oE "^PKG_GIT_URL.*github.com(/[-_a-zA-Z0-9]{1,}){2}" "$mk_path" | awk -F"/" '{print $(NF - 1) "/" $NF}')
        if [ -z "$PKG_REPO" ]; then
            PKG_REPO=$(grep -oE "^PKG_SOURCE_URL.*github.com(/[-_a-zA-Z0-9]{1,}){2}" "$mk_path" | awk -F"/" '{print $(NF - 1) "/" $NF}')
            if [ -z "$PKG_REPO" ]; then
                echo "错误：无法提取 PKG_REPO" >&2
                return 1
            fi
        fi
        local PKG_VER
        if ! PKG_VER=$(curl -fsSL "https://api.github.com/repos/$PKG_REPO/$branch" | jq -r '.[0] | .tag_name // .name'); then
            echo "错误：获取版本信息失败" >&2
            return 1
        fi
        if [ -n "$3" ]; then PKG_VER="$3"; fi
        local PKG_VER_CLEAN
        PKG_VER_CLEAN=$(echo "$PKG_VER" | sed 's/^v//')
        if grep -q "^PKG_GIT_SHORT_COMMIT:=" "$mk_path"; then
            local PKG_GIT_URL_RAW
            PKG_GIT_URL_RAW=$(awk -F"=" '/^PKG_GIT_URL:=/ {print $NF}' "$mk_path")
            local PKG_GIT_REF_RAW
            PKG_GIT_REF_RAW=$(awk -F"=" '/^PKG_GIT_REF:=/ {print $NF}' "$mk_path")
            if [ -z "$PKG_GIT_URL_RAW" ] || [ -z "$PKG_GIT_REF_RAW" ]; then
                echo "错误：缺少 PKG_GIT_URL 或 PKG_GIT_REF" >&2
                return 1
            fi
            local PKG_GIT_REF_RESOLVED
            PKG_GIT_REF_RESOLVED=$(echo "$PKG_GIT_REF_RAW" | sed "s/\$(PKG_VERSION)/$PKG_VER_CLEAN/g; s/\${PKG_VERSION}/$PKG_VER_CLEAN/g")
            local PKG_GIT_REF_TAG="${PKG_GIT_REF_RESOLVED#refs/tags/}"
            local COMMIT_SHA LS_REMOTE_OUTPUT
            LS_REMOTE_OUTPUT=$(git ls-remote "https://$PKG_GIT_URL_RAW" "refs/tags/${PKG_GIT_REF_TAG}" "refs/tags/${PKG_GIT_REF_TAG}^{}" 2>/dev/null)
            COMMIT_SHA=$(echo "$LS_REMOTE_OUTPUT" | awk '/\^{}$/ {print $1; exit}')
            if [ -z "$COMMIT_SHA" ]; then COMMIT_SHA=$(echo "$LS_REMOTE_OUTPUT" | awk 'NR==1{print $1}'); fi
            if [ -z "$COMMIT_SHA" ]; then COMMIT_SHA=$(git ls-remote "https://$PKG_GIT_URL_RAW" "${PKG_GIT_REF_RESOLVED}^{}" 2>/dev/null | awk 'NR==1{print $1}'); fi
            if [ -z "$COMMIT_SHA" ]; then COMMIT_SHA=$(git ls-remote "https://$PKG_GIT_URL_RAW" "$PKG_GIT_REF_RESOLVED" 2>/dev/null | awk 'NR==1{print $1}'); fi
            if [ -z "$COMMIT_SHA" ]; then
                echo "错误：无法获取提交哈希" >&2
                return 1
            fi
            local SHORT_COMMIT
            SHORT_COMMIT=$(echo "$COMMIT_SHA" | cut -c1-7)
            sed -i "s/^PKG_GIT_SHORT_COMMIT:=.*/PKG_GIT_SHORT_COMMIT:=$SHORT_COMMIT/g" "$mk_path"
        fi
        PKG_VER=$(echo "$PKG_VER" | grep -oE "[\.0-9]{1,}")
        local PKG_NAME
        PKG_NAME=$(awk -F"=" '/PKG_NAME:=/ {print $NF}' "$mk_path" | grep -oE "[-_:/\$\(\)\?\.a-zA-Z0-9]{1,}")
        local PKG_SOURCE
        PKG_SOURCE=$(awk -F"=" '/PKG_SOURCE:=/ {print $NF}' "$mk_path" | grep -oE "[-_:/\$\(\)\?\.a-zA-Z0-9]{1,}")
        local PKG_SOURCE_URL
        PKG_SOURCE_URL=$(awk -F"=" '/PKG_SOURCE_URL:=/ {print $NF}' "$mk_path" | grep -oE "[-_:/\$\(\)\{\}\?\.a-zA-Z0-9]{1,}")
        local PKG_GIT_URL
        PKG_GIT_URL=$(awk -F"=" '/PKG_GIT_URL:=/ {print $NF}' "$mk_path")
        local PKG_GIT_REF
        PKG_GIT_REF=$(awk -F"=" '/PKG_GIT_REF:=/ {print $NF}' "$mk_path")
        PKG_SOURCE_URL=${PKG_SOURCE_URL//\$\(PKG_GIT_URL\)/$PKG_GIT_URL}
        PKG_SOURCE_URL=${PKG_SOURCE_URL//\$\(PKG_GIT_REF\)/$PKG_GIT_REF}
        PKG_SOURCE_URL=${PKG_SOURCE_URL//\$\(PKG_NAME\)/$PKG_NAME}
        PKG_SOURCE_URL=$(echo "$PKG_SOURCE_URL" | sed "s/\${PKG_VERSION}/$PKG_VER/g; s/\$(PKG_VERSION)/$PKG_VER/g")
        PKG_SOURCE=${PKG_SOURCE//\$\(PKG_NAME\)/$PKG_NAME}
        PKG_SOURCE=${PKG_SOURCE//\$\(PKG_VERSION\)/$PKG_VER}
        local PKG_HASH
        if ! PKG_HASH=$(curl -fsSL "$PKG_SOURCE_URL""$PKG_SOURCE" | sha256sum | cut -b -64); then
            echo "错误：获取软件包哈希失败" >&2
            return 1
        fi
        sed -i 's/^PKG_VERSION:=.*/PKG_VERSION:='$PKG_VER'/g' "$mk_path"
        sed -i 's/^PKG_HASH:=.*/PKG_HASH:='$PKG_HASH'/g' "$mk_path"
        echo "更新软件包 $1 到 $PKG_VER $PKG_HASH"
    fi
}

# ==================== [modules/system.sh] 系统修复 ====================
fix_default_set() {
    if [ -d "$BUILD_DIR/feeds/luci/collections/" ]; then
        find "$BUILD_DIR/feeds/luci/collections/" -type f -name "Makefile" -exec sed -i "s/luci-theme-bootstrap/luci-theme-$THEME_SET/g" {} \;
    fi
}

change_dnsmasq2full() {
    cd "$BUILD_DIR"
    if ! grep -q "dnsmasq-full" include/target.mk; then
        sed -i 's/dnsmasq/dnsmasq-full/g' ./include/target.mk
    fi
    cd - > /dev/null
}


fix_kconfig_recursive_dependency() {
    local file="$BUILD_DIR/scripts/package-metadata.pl"
    if [ -f "$file" ]; then
        sed -i 's/<PACKAGE_\$pkgname/!=y/g' "$file"
        echo "已修复 package-metadata.pl 的 Kconfig 递归依赖生成逻辑"
    fi
}

update_default_lan_addr() {
    local CFG_PATH="$BUILD_DIR/package/base-files/files/bin/config_generate"
    if [ -f "$CFG_PATH" ]; then
        sed -i 's/192\.168\.[0-9]*\.[0-9]*/'$LAN_ADDR'/g' "$CFG_PATH"
    fi
}

remove_something_nss_kmod() {
    local ipq_mk_path="$BUILD_DIR/target/linux/qualcommax/Makefile"
    local target_mks=("$BUILD_DIR/target/linux/qualcommax/ipq60xx/target.mk" "$BUILD_DIR/target/linux/qualcommax/ipq807x/target.mk")
    for target_mk in "${target_mks[@]}"; do
        if [ -f "$target_mk" ]; then sed -i 's/kmod-qca-nss-crypto//g' "$target_mk"; fi
    done
    if [ -f "$ipq_mk_path" ]; then
        sed -i '/kmod-qca-nss-drv-eogremgr/d; /kmod-qca-nss-drv-gre/d; /kmod-qca-nss-drv-map-t/d; /kmod-qca-nss-drv-match/d; /kmod-qca-nss-drv-mirror/d; /kmod-qca-nss-drv-tun6rd/d; /kmod-qca-nss-drv-tunipip6/d; /kmod-qca-nss-drv-vxlanmgr/d; /kmod-qca-nss-drv-wifi-meshmgr/d; /kmod-qca-nss-macsec/d' "$ipq_mk_path"
        sed -i 's/automount //g; s/cpufreq //g' "$ipq_mk_path"
    fi
}

update_affinity_script() {
    local affinity_script_dir="$BUILD_DIR/target/linux/qualcommax"
    if [ -d "$affinity_script_dir" ]; then
        find "$affinity_script_dir" -name "set-irq-affinity" -exec rm -f {} \;
        find "$affinity_script_dir" -name "smp_affinity" -exec rm -f {} \;
    fi
}

fix_hash_value() {
    local makefile_path="$1"
    local old_hash="$2"
    local new_hash="$3"
    local package_name="$4"
    if [ -f "$makefile_path" ]; then
        local escaped_old escaped_new
        escaped_old=$(echo "$old_hash" | sed 's/[\/&]/\\&/g')
        escaped_new=$(echo "$new_hash" | sed 's/[\/&]/\\&/g')
        sed -i "s/$escaped_old/$escaped_new/g" "$makefile_path"
        echo "已修复 $package_name 的哈希值"
    fi
}

apply_hash_fixes() {
    fix_hash_value "$BUILD_DIR/package/feeds/packages/smartdns/Makefile" "860a816bf1e69d5a8a2049483197dbebe8a3da2c9b05b2da68c85ef7dee7bdde" "582021891808442b01f551bc41d7d95c38fb00c1ec78a58ac3aaaf898fbd2b5b" "smartdns"
    fix_hash_value "$BUILD_DIR/package/feeds/packages/smartdns/Makefile" "320c99a65ca67a98d11a45292aa99b8904b5ebae5b0e17b302932076bf62b1ec" "43e58467690476a77ce644f9dc246e8a481353160644203a1bd01eb09c881275" "smartdns"
}



update_tcping() {
    local tcping_path="$BUILD_DIR/feeds/fichenx/tcping/Makefile"
    local url="https://raw.githubusercontent.com/Openwrt-Passwall/openwrt-passwall-packages/refs/heads/main/tcping/Makefile"
    if [ -d "$(dirname "$tcping_path")" ]; then
        echo "正在更新 tcping Makefile..."
        if ! curl -fsSL -o "$tcping_path" "$url"; then
            echo "错误：下载 tcping Makefile 失败" >&2
            exit 1
        fi
    fi
}

set_custom_task() {
    local sh_dir="$BUILD_DIR/package/base-files/files/etc/init.d"
    cat <<'EOF' >"$sh_dir/custom_task"
#!/bin/sh /etc/rc.common
START=99
boot() {
    sed -i '/drop_caches/d' /etc/crontabs/root
    echo "15 3 * * * sync && echo 3 > /proc/sys/vm/drop_caches" >>/etc/crontabs/root
    sed -i '/wireguard_watchdog/d' /etc/crontabs/root
    local wg_ifname
    wg_ifname=$(wg show | awk '/interface/ {print $2}')
    if [ -n "$wg_ifname" ]; then
        echo "*/15 * * * * /usr/bin/wireguard_watchdog" >>/etc/crontabs/root
        uci set system.@system[0].cronloglevel='9'
        uci commit system
        /etc/init.d/cron restart
    fi
    crontab /etc/crontabs/root
}
EOF
    chmod +x "$sh_dir/custom_task"
}

apply_passwall_tweaks() {
    local chnlist_path="$BUILD_DIR/feeds/passwall/luci-app-passwall/root/usr/share/passwall/rules/chnlist"
    if [ -f "$chnlist_path" ]; then >"$chnlist_path"; fi
    local xray_util_path="$BUILD_DIR/feeds/passwall/luci-app-passwall/luasrc/passwall/util_xray.lua"
    if [ -f "$xray_util_path" ]; then
        sed -i 's/maxRTT = "1s"/maxRTT = "2s"/g' "$xray_util_path"
        sed -i 's/sampling = 3/sampling = 5/g' "$xray_util_path"
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

update_nss_pbuf_performance() {
    local pbuf_path="$BUILD_DIR/package/kernel/mac80211/files/pbuf.uci"
    if [ -d "$(dirname "$pbuf_path")" ] && [ -f "$pbuf_path" ]; then
        sed -i "s/auto_scale '1'/auto_scale 'off'/g; s/scaling_governor 'performance'/scaling_governor 'schedutil'/g" "$pbuf_path"
    fi
}

set_build_signature() {
    local file="$BUILD_DIR/feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js"
    if [ -d "$(dirname "$file")" ] && [ -f "$file" ]; then
        sed -i "s#(\(luciversion || ''\))#(\1) + (' / build by Rabbit(\$(TZ=Asia/Shanghai date +%Y.%m.%d))')#g" "$file"

    fi
}


update_menu_location() {
    local samba4_path="$BUILD_DIR/feeds/luci/applications/luci-app-samba4/root/usr/share/luci/menu.d/luci-app-samba4.json"
    if [ -d "$(dirname "$samba4_path")" ] && [ -f "$samba4_path" ]; then sed -i 's/nas/services/g' "$samba4_path"; fi
    local tailscale_path="$BUILD_DIR/feeds/fichenx/luci-app-tailscale/root/usr/share/luci/menu.d/luci-app-tailscale.json"
    if [ -d "$(dirname "$tailscale_path")" ] && [ -f "$tailscale_path" ]; then sed -i 's/services/vpn/g' "$tailscale_path"; fi
}

fix_compile_coremark() {
    local file="$BUILD_DIR/feeds/packages/utils/coremark/Makefile"
    if [ -d "$(dirname "$file")" ] && [ -f "$file" ]; then sed -i 's/mkdir \$/mkdir -p \$/g' "$file"; fi
}

update_dnsmasq_conf() {
    local file="$BUILD_DIR/package/network/services/dnsmasq/files/dhcp.conf"
    if [ -d "$(dirname "$file")" ] && [ -f "$file" ]; then sed -i '/dns_redirect/d' "$file"; fi
}

add_backup_info_to_sysupgrade() {
    local conf_path="$BUILD_DIR/package/base-files/files/etc/sysupgrade.conf"
    if [ -f "$conf_path" ]; then
        cat >"$conf_path" <<'EOF'
/etc/AdGuardHome.yaml
/etc/easytier
/etc/lucky/
EOF
    fi
}

update_script_priority() {
    local qca_drv_path="$BUILD_DIR/package/feeds/nss_packages/qca-nss-drv/files/qca-nss-drv.init"
    if [ -d "${qca_drv_path%/*}" ] && [ -f "$qca_drv_path" ]; then sed -i 's/START=.*/START=88/g' "$qca_drv_path"; fi
    local pbuf_path="$BUILD_DIR/package/kernel/mac80211/files/qca-nss-pbuf.init"
    if [ -d "${pbuf_path%/*}" ] && [ -f "$pbuf_path" ]; then sed -i 's/START=.*/START=89/g' "$pbuf_path"; fi
    local mosdns_path="$BUILD_DIR/package/feeds/fichenx/luci-app-mosdns/root/etc/init.d/mosdns"
    if [ -d "${mosdns_path%/*}" ] && [ -f "$mosdns_path" ]; then sed -i 's/START=.*/START=94/g' "$mosdns_path"; fi
}

update_mosdns_deconfig() {
    local mosdns_conf="$BUILD_DIR/feeds/fichenx/luci-app-mosdns/root/etc/config/mosdns"
    if [ -d "${mosdns_conf%/*}" ] && [ -f "$mosdns_conf" ]; then
        sed -i 's/8000/300/g; s/5335/5336/g' "$mosdns_conf"
    fi
}

fix_quickstart() {
    local file_path="$BUILD_DIR/feeds/fichenx/luci-app-quickstart/luasrc/controller/istore_backend.lua"
    local url="https://gist.githubusercontent.com/puteulanus/1c180fae6bccd25e57eb6d30b7aa28aa/raw/istore_backend.lua"
    if [ -f "$file_path" ]; then
        echo "正在修复 quickstart..."
        if ! curl -fsSL -o "$file_path" "$url"; then
            echo "错误：下载 istore_backend.lua 失败" >&2
            exit 1
        fi
    fi
}

update_oaf_deconfig() {
    local conf_path="$BUILD_DIR/feeds/fichenx/open-app-filter/files/appfilter.config"
    local uci_def="$BUILD_DIR/feeds/fichenx/luci-app-oaf/root/etc/uci-defaults/94_feature_3.0"
    local disable_path="$BUILD_DIR/feeds/fichenx/luci-app-oaf/root/etc/uci-defaults/99_disable_oaf"
    if [ -d "${conf_path%/*}" ] && [ -f "$conf_path" ]; then
        sed -i -e "s/record_enable '1'/record_enable '0'/g" -e "s/disable_hnat '1'/disable_hnat '0'/g" -e "s/auto_load_engine '1'/auto_load_engine '0'/g" "$conf_path"
    fi
    if [ -d "${uci_def%/*}" ] && [ -f "$uci_def" ]; then
        sed -i '/\(disable_hnat\|auto_load_engine\)/d' "$uci_def"
        cat >"$disable_path" <<-EOF
#!/bin/sh
[ "\$(uci get appfilter.global.enable 2>/dev/null)" = "0" ] && {
    /etc/init.d/appfilter disable
    /etc/init.d/appfilter stop
}
EOF
        chmod +x "$disable_path"
    fi
}

update_geoip() {
    local geodata_path="$BUILD_DIR/package/feeds/fichenx/v2ray-geodata/Makefile"
    if [ -d "${geodata_path%/*}" ] && [ -f "$geodata_path" ]; then
        local GEOIP_VER
        GEOIP_VER=$(awk -F"=" '/GEOIP_VER:=/ {print $NF}' "$geodata_path" | grep -oE "[0-9]{1,}")
        if [ -n "$GEOIP_VER" ]; then
            local base_url="https://github.com/v2fly/geoip/releases/download/${GEOIP_VER}"
            local old_SHA256 new_SHA256
            if ! old_SHA256=$(curl -fsSL "$base_url/geoip.dat.sha256sum" | awk '{print $1}'); then
                echo "错误：获取旧校验和失败" >&2
                return 1
            fi
            if ! new_SHA256=$(curl -fsSL "$base_url/geoip-only-cn-private.dat.sha256sum" | awk '{print $1}'); then
                echo "错误：获取新校验和失败" >&2
                return 1
            fi
            if [ -n "$old_SHA256" ] && [ -n "$new_SHA256" ]; then
                if grep -q "$old_SHA256" "$geodata_path"; then
                    sed -i "s|=geoip.dat|=geoip-only-cn-private.dat|g; s/$old_SHA256/$new_SHA256/g" "$geodata_path"
                fi
            fi
        fi
    fi
}

fix_rust_compile_error() {
    if [ -f "$BUILD_DIR/feeds/packages/lang/rust/Makefile" ]; then
        sed -i 's/download-ci-llvm=true/download-ci-llvm=false/g' "$BUILD_DIR/feeds/packages/lang/rust/Makefile"
    fi
}

fix_easytier_lua() {
    local file_path="$BUILD_DIR/package/feeds/fichenx/luci-app-easytier/luasrc/model/cbi/easytier.lua"
    if [ -f "$file_path" ]; then sed -i 's/util.pcdata/xml.pcdata/g' "$file_path"; fi
}

fix_easytier_mk() {
    local mk_path="$BUILD_DIR/feeds/fichenx/luci-app-easytier/easytier/Makefile"
    if [ -f "$mk_path" ]; then sed -i 's/!@(mips||mipsel)/!TARGET_mips \&\& !TARGET_mipsel/g' "$mk_path"; fi
}

update_nginx_ubus_module() {
    local makefile_path="$BUILD_DIR/feeds/packages/net/nginx/Makefile"
    if [ -f "$makefile_path" ]; then
        sed -i "s/SOURCE_DATE:=2020-09-06/SOURCE_DATE:=2024-03-02/g; s/SOURCE_VERSION:=b2d7260dcb428b2fb65540edb28d7538602b4a26/SOURCE_VERSION:=564fa3e9c2b04ea298ea659b793480415da26415/g; s/MIRROR_HASH:=515bb9d355ad80916f594046a45c190a68fb6554d6795a54ca15cab8bdd12fda/MIRROR_HASH:=92c9ab94d88a2fe8d7d1e8a15d15cfc4d529fdc357ed96d22b65d5da3dd24d7f/g" "$makefile_path"
        echo "已更新 nginx-mod-ubus 模块"
    fi
}


install_pbr_cmcc() {
    local pbr_pkg_dir="$BUILD_DIR/package/feeds/packages/pbr"
    local pbr_dir="$pbr_pkg_dir/files/usr/share/pbr"
    local pbr_conf="$pbr_pkg_dir/files/etc/config/pbr"
    local pbr_makefile="$pbr_pkg_dir/Makefile"
    if [ -d "$pbr_pkg_dir" ]; then
        echo "正在安装 PBR CMCC 配置文件..."
        if [ -f "$pbr_makefile" ]; then
            if ! grep -q "pbr.user.cmcc" "$pbr_makefile"; then
                sed -i '/pbr.user.netflix.*\$(1)/a\
\t$(INSTALL_DATA) ./files/usr/share/pbr/pbr.user.cmcc $(1)/usr/share/pbr/pbr.user.cmcc\
\t$(INSTALL_DATA) ./files/usr/share/pbr/pbr.user.cmcc6 $(1)/usr/share/pbr/pbr.user.cmcc6' "$pbr_makefile"
            fi
        fi
    fi
    if [ -f "$pbr_conf" ]; then
        if ! grep -q "pbr.user.cmcc" "$pbr_conf"; then
            sed -i "/option path '\/usr\/share\/pbr\/pbr.user.netflix'/,/option enabled '0'/{
                /option enabled '0'/a\\\n\
config include\\\n\toption path '/usr/share/pbr/pbr.user.cmcc'\\\n\toption enabled '0'\\\n\
config include\\\n\toption path '/usr/share/pbr/pbr.user.cmcc6'\\\n\toption enabled '0'
            }" "$pbr_conf"
        fi
    fi
}

fix_pbr_ip_forward() {
    local pbr_pkg_dir="$BUILD_DIR/package/feeds/packages/pbr"
    local pbr_init_script="$pbr_pkg_dir/files/etc/init.d/pbr"
    if [ ! -d "$pbr_pkg_dir" ]; then echo "PBR package directory not found"; return 0; fi
    if [ ! -f "$pbr_init_script" ]; then echo "PBR init script not found"; return 0; fi
    if grep -q '\[ -n "\$enabled" \] && \[ -n "\$strict_enforcement" \]' "$pbr_init_script"; then
        echo "PBR IP Forward fix already applied"; return 0
    fi
    if ! grep -q '\[ -n "\$strict_enforcement" \] && \[ "\$(cat /proc/sys/net/ipv4/ip_forward)"' "$pbr_init_script"; then
        echo "PBR IP Forward: 未找到需要修复的代码"; return 0
    fi
    echo "正在应用 PBR IP Forward 修复..."
    sed -i 's/\[ -n "\$strict_enforcement" \] && \[ "\$(cat \/proc\/sys\/net\/ipv4\/ip_forward)"/\[ -n "\$enabled" \] \&\& \[ -n "\$strict_enforcement" \] \&\& \[ "\$(cat \/proc\/sys\/net\/ipv4\/ip_forward)"/' "$pbr_init_script"
    if grep -q '\[ -n "\$enabled" \] && \[ -n "\$strict_enforcement" \]' "$pbr_init_script"; then
        echo "PBR IP Forward 修复应用成功"; return 0
    else
        echo "修复应用失败"; return 0
    fi
}

fix_quectel_cm() {
    local makefile_path="$BUILD_DIR/package/feeds/packages/quectel-cm/Makefile"
    local cmake_patch_path="$BUILD_DIR/package/feeds/packages/quectel-cm/patches/020-cmake.patch"
    if [ -f "$makefile_path" ]; then
        echo "正在修复 quectel-cm Makefile..."
        sed -i '/^PKG_SOURCE:=/d; /^PKG_SOURCE_URL:=@IMMORTALWRT/d; /^PKG_HASH:=/d' "$makefile_path"
        sed -i '/^PKG_RELEASE:=/a\
\
PKG_SOURCE_PROTO:=git\
PKG_SOURCE_URL:=https://github.com/Carton32/quectel-CM.git\
PKG_SOURCE_VERSION:=$(PKG_VERSION)\
PKG_MIRROR_HASH:=skip' "$makefile_path"
        sed -i 's/^PKG_RELEASE:=2$/PKG_RELEASE:=3/' "$makefile_path"
        echo "quectel-cm Makefile 修复完成"
    fi
    if [ -f "$cmake_patch_path" ]; then
        sed -i 's/-cmake_minimum_required(VERSION 2\.4)$/-cmake_minimum_required(VERSION 2.4) /' "$cmake_patch_path"
        sed -i 's/project(quectel-CM)$/project(quectel-CM) /' "$cmake_patch_path"
    fi
}

set_nginx_default_config() {
    local nginx_config_path="$BUILD_DIR/feeds/packages/net/nginx-util/files/nginx.config"
    if [ -f "$nginx_config_path" ]; then
        cat >"$nginx_config_path" <<EOF
config main 'global'
        option uci_enable 'true'
config server '_lan'
        list listen '443 ssl default_server'
        list listen '[::]:443 ssl default_server'
        option server_name '_lan'
        list include 'restrict_locally'
        list include 'conf.d/*.locations'
        option uci_manage_ssl 'self-signed'
        option ssl_certificate '/etc/nginx/conf.d/_lan.crt'
        option ssl_certificate_key '/etc/nginx/conf.d/_lan.key'
        option ssl_session_cache 'shared:SSL:32k'
        option ssl_session_timeout '64m'
        option access_log 'off; # logd openwrt'
config server 'http_only'
        list listen '80'
        list listen '[::]:80'
        option server_name 'http_only'
        list include 'conf.d/*.locations'
        option access_log 'off; # logd openwrt'
EOF
    fi
    local nginx_template="$BUILD_DIR/feeds/packages/net/nginx-util/files/uci.conf.template"
    if [ -f "$nginx_template" ]; then
        if ! grep -q "client_body_in_file_only clean;" "$nginx_template"; then
            sed -i "/client_max_body_size 128M;/a\\\n\tclient_body_in_file_only clean;\\\n\tclient_body_temp_path /mnt/tmp;" "$nginx_template"
        fi
    fi
    local luci_support_script="$BUILD_DIR/feeds/packages/net/nginx/files-luci-support/60_nginx-luci-support"
    if [ -f "$luci_support_script" ]; then
        if ! grep -q "client_body_in_file_only off;" "$luci_support_script"; then
            sed -i "/ubus_parallel_req 2;/a\\\n        client_body_in_file_only off;\\\n        client_max_body_size 1M;" "$luci_support_script"
        fi
    fi
}

update_uwsgi_limit_as() {
    local cgi_io_ini="$BUILD_DIR/feeds/packages/net/uwsgi/files-luci-support/luci-cgi_io.ini"
    local webui_ini="$BUILD_DIR/feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini"
    if [ -f "$cgi_io_ini" ]; then sed -i 's/^limit-as = .*/limit-as = 8192/g' "$cgi_io_ini"; fi
    if [ -f "$webui_ini" ]; then sed -i 's/^limit-as = .*/limit-as = 8192/g' "$webui_ini"; fi
}

remove_tweaked_packages() {
    local target_mk="$BUILD_DIR/include/target.mk"
    if [ -f "$target_mk" ]; then
        if grep -q "^DEFAULT_PACKAGES += \$(DEFAULT_PACKAGES.tweak)" "$target_mk"; then
            sed -i 's/DEFAULT_PACKAGES += $(DEFAULT_PACKAGES.tweak)/# DEFAULT_PACKAGES += $(DEFAULT_PACKAGES.tweak)/g' "$target_mk"
        fi
    fi
}


# ==================== [modules/cups.sh] CUPS 修复 ====================
fix_cups_libcups_avahi_depends() {
    local makefile_path="$BUILD_DIR/feeds/fichenx/cups/Makefile"
    if [ ! -f "$makefile_path" ]; then echo "cups: libcups Makefile not found, skip"; return 0; fi
    if sed -n '/^[[:space:]]*define Package\/libcups[[:space:]]*$/,/^[[:space:]]*endef[[:space:]]*$/p' "$makefile_path" | grep -q "+libavahi-client" && \
       sed -n '/^[[:space:]]*define Package\/libcups[[:space:]]*$/,/^[[:space:]]*endef[[:space:]]*$/p' "$makefile_path" | grep -q "+libavahi"; then
        echo "cups: libcups avahi deps already present, skip"; return 0
    fi
    sed -i '/^[[:space:]]*define Package\/libcups[[:space:]]*$/,/^[[:space:]]*endef[[:space:]]*$/ {
        /DEPENDS:=/ s/$/ +libavahi-client +libavahi/
    }' "$makefile_path"
    echo "cups: added missing avahi deps to Package/libcups"
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
    #remove_unwanted_packages
    #remove_tweaked_packages
    # install_custom_feed  # 未定义，已移除
    #update_homeproxy
    #fix_default_set
    # fix_miniupnpd        # 未定义，已移除
    update_golang
    #change_dnsmasq2full
    #update_default_lan_addr
    #remove_something_nss_kmod
    #update_affinity_script
    #update_tcping
    # add_ax6600_led       # 未定义，已移除
    #set_custom_task
    #apply_passwall_tweaks
    #update_nss_pbuf_performance
    #set_build_signature
    #pdate_menu_location
    #fix_compile_coremark
    #update_dnsmasq_conf
    #add_backup_info_to_sysupgrade
    #update_mosdns_deconfig
    #fix_quickstart
    #update_oaf_deconfig
    #add_timecontrol
    #add_quickfile
    fix_rust_compile_error
    #update_smartdns
    #update_diskman
    #set_nginx_default_config
    #update_uwsgi_limit_as
    #update_argon
    update_nginx_ubus_module
    #check_default_settings
    install_opkg_distfeeds
    #fix_easytier_mk
    remove_attendedsysupgrade
    #fix_kconfig_recursive_dependency
    install_feeds
    #fix_cups_libcups_avahi_depends
    #fix_easytier_lua
    #update_adguardhome
    #update_script_priority
    #update_geoip
    # fix_netfilter_kmod_clash  # 未定义，已移除
    #fix_quectel_cm
    #install_pbr_cmcc
    #fix_pbr_ip_forward
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

# Step 3: 执行 diy-part2.sh
echo "=== 执行 diy-part2.sh（WAX206 专用）==="
if [ -f "./wax206/diy-part2.sh" ]; then
    chmod +x "./wax206/diy-part2.sh"
    if bash "./wax206/diy-part2.sh" "$Dev" "$BUILD_DIR"; then
        echo "diy-part2.sh 执行成功"
    else
        echo "错误：diy-part2.sh 执行失败，退出码: $?"
        exit 1
    fi
else
    echo "警告：wax206/diy-part2.sh 不存在，跳过自定义配置"
fi

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
