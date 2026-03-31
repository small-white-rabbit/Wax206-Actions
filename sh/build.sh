#!/usr/bin/env bash

set -e

# Determine wrt_core path
if [ -d "wrt_core" ]; then
    WRT_CORE_PATH="wrt_core"
elif [ -d "../wrt_core" ]; then
    WRT_CORE_PATH="../wrt_core"
else
    echo "Error: wrt_core directory not found!"
    exit 1
fi

BASE_PATH=$(cd "$WRT_CORE_PATH" && pwd)

Dev=$1
Build_Mod=$2

CONFIG_FILE="$BASE_PATH/deconfig/$Dev.config"
INI_FILE="$BASE_PATH/compilecfg/$Dev.ini"

if [[ ! -f $CONFIG_FILE ]]; then
    echo "Config not found: $CONFIG_FILE"
    exit 1
fi

if [[ ! -f $INI_FILE ]]; then
    echo "INI file not found: $INI_FILE"
    exit 1
fi

read_ini_by_key() {
    local key=$1
    awk -F"=" -v key="$key" '$1 == key {print $2}' "$INI_FILE"
}

remove_uhttpd_dependency() {
    local config_path="$BASE_PATH/../$BUILD_DIR/.config"
    local luci_makefile_path="$BASE_PATH/../$BUILD_DIR/feeds/luci/collections/luci/Makefile"

    if grep -q "CONFIG_PACKAGE_luci-app-quickfile=y" "$config_path"; then
        if [ -f "$luci_makefile_path" ]; then
            sed -i '/luci-light/d' "$luci_makefile_path"
            echo "Removed uhttpd (luci-light) dependency as luci-app-quickfile (nginx) is enabled."
        fi
    fi
}

apply_config() {
    \cp -f "$CONFIG_FILE" "$BASE_PATH/../$BUILD_DIR/.config"
    
    if grep -qE "(ipq60xx|ipq807x)" "$BASE_PATH/../$BUILD_DIR/.config" &&
        ! grep -q "CONFIG_GIT_MIRROR" "$BASE_PATH/../$BUILD_DIR/.config"; then
        cat "$BASE_PATH/deconfig/nss.config" >> "$BASE_PATH/../$BUILD_DIR/.config"
    fi

    #cat "$BASE_PATH/config/compile_base.config" >> "$BASE_PATH/../$BUILD_DIR/.config"

    #cat "$BASE_PATH/config/docker_deps.config" >> "$BASE_PATH/../$BUILD_DIR/.config"

    #cat "$BASE_PATH/deconfig/proxy.config" >> "$BASE_PATH/../$BUILD_DIR/.config"
}

REPO_URL=$(read_ini_by_key "REPO_URL")
REPO_BRANCH=$(read_ini_by_key "REPO_BRANCH")
REPO_BRANCH=${REPO_BRANCH:-main}
BUILD_DIR=$(read_ini_by_key "BUILD_DIR")
COMMIT_HASH=$(read_ini_by_key "COMMIT_HASH")
COMMIT_HASH=${COMMIT_HASH:-none}

if [[ -d action_build ]]; then
    BUILD_DIR="action_build"
fi

# ==================== 新增：替换自定义 DTS/MK 文件 ====================
replace_custom_files() {
    local dts_src dts_dst mk_src mk_dst
    
    # 定义目标路径（OpenWrt 源码中的默认位置）
    dts_dst="$BASE_PATH/../$BUILD_DIR/target/linux/mediatek/dts/mt7622-netgear-wax206.dts"
    mk_dst="$BASE_PATH/../$BUILD_DIR/target/linux/mediatek/image/mt7622.mk"
    
    case "$Dev" in
        "fmwax206")
            echo "=== 应用 FMWAX206 自定义配置（70M 大分区）==="
            dts_src="$BASE_PATH/dts/wax206-70m.dts"
            mk_src="$BASE_PATH/mediatek/image/mt7622-70m.mk"
            ;;
        "gwax206")
            echo "=== 应用 GWAX206 自定义配置（256M 大分区）==="
            dts_src="$BASE_PATH/dts/wax206-256m.dts"
            mk_src="$BASE_PATH/mediatek/image/mt7622-256m.mk"
            ;;
        "wax206")
            echo "=== 使用 WAX206 默认配置（不进行替换）==="
            return 0
            ;;
        *)
            echo "=== 设备 $Dev 无需自定义 DTS/MK 替换 ==="
            return 0
            ;;
    esac
    
    # 执行替换
    if [[ -f "$dts_src" ]]; then
        \cp -f "$dts_src" "$dts_dst"
        echo "已替换 DTS: $dts_src -> $dts_dst"
    else
        echo "警告: DTS 源文件不存在: $dts_src"
    fi
    
    if [[ -f "$mk_src" ]]; then
        \cp -f "$mk_src" "$mk_dst"
        echo "已替换 MK: $mk_src -> $mk_dst"
    else
        echo "警告: MK 源文件不存在: $mk_src"
    fi
}
# ==================================================


"$BASE_PATH/update.sh" "$REPO_URL" "$REPO_BRANCH" "$BUILD_DIR" "$COMMIT_HASH"
# 第 90-102 行
echo "=== 执行 diy-part2.sh（WAX206 专用）==="
echo "当前工作目录: $(pwd)"
echo "BUILD_DIR: $BUILD_DIR"          # ← 加调试

if [ -f "./diy-part2.sh" ]; then
    chmod +x "./diy-part2.sh"
    # 传入 Dev 和实际的 BUILD_DIR
    if bash "./diy-part2.sh" "$Dev" "$BUILD_DIR"; then
        echo "diy-part2.sh 执行成功"
    else
        echo "错误：diy-part2.sh 执行失败，退出码: $?"
        exit 1
    fi
else
    echo "警告：diy-part2.sh 不存在，跳过自定义配置"
fi
replace_custom_files
apply_config
remove_uhttpd_dependency

cd "$BASE_PATH/../$BUILD_DIR"
make defconfig

if grep -qE "^CONFIG_TARGET_x86_64=y" "$CONFIG_FILE"; then
    DISTFEEDS_PATH="$BASE_PATH/../$BUILD_DIR/package/emortal/default-settings/files/99-distfeeds.conf"
    if [ -d "${DISTFEEDS_PATH%/*}" ] && [ -f "$DISTFEEDS_PATH" ]; then
        sed -i 's/aarch64_cortex-a53/x86_64/g' "$DISTFEEDS_PATH"
    fi
fi

if [[ $Build_Mod == "debug" ]]; then
    exit 0
fi

TARGET_DIR="$BASE_PATH/../$BUILD_DIR/bin/targets"
if [[ -d $TARGET_DIR ]]; then
    find "$TARGET_DIR" -type f \( -name "*.bin" -o -name "*.manifest" -o -name "*efi.img.gz" -o -name "*.itb" -o -name "*.img" -o -name "*.ubi" -o -name "*.tar.gz" \) -exec rm -f {} +
fi

make download -j$(($(nproc) * 2))
make -j$(($(nproc) + 1)) || make -j1 V=s

cd $BASE_PATH/../$BUILD_DIR/bin/packages
tar -zcvf Packages.tar.gz ./*
cp Packages.tar.gz $BASE_PATH/../$BUILD_DIR/bin/targets/
cd "$BASE_PATH/../$BUILD_DIR"

FIRMWARE_DIR="$BASE_PATH/../firmware"
\rm -rf "$FIRMWARE_DIR"
mkdir -p "$FIRMWARE_DIR"

# 复制固件和 manifest 文件
find "$TARGET_DIR" -type f \( -name "*.bin"  -o -name "*.itb" -o -name "*.manifest" \) -exec cp -f {} "$FIRMWARE_DIR/" \;

# 删除这行或注释掉
# \rm -f "$BASE_PATH/../firmware/Packages.manifest" 2>/dev/null

if [[ -d action_build ]]; then
    make clean
fi
