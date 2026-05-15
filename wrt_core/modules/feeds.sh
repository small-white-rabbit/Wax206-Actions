#!/usr/bin/env bash

get_feeds_path() {
    local feeds_path="$BUILD_DIR/$FEEDS_CONF"
    if [[ -f "$BUILD_DIR/feeds.conf" ]]; then
        feeds_path="$BUILD_DIR/feeds.conf"
    fi
    printf '%s\n' "$feeds_path"
}

append_feed_if_missing() {
    local feeds_path="$1"
    local match_pattern="$2"
    local feed_entry="$3"

    if ! grep -q "$match_pattern" "$feeds_path"; then
        [ -z "$(tail -c 1 "$feeds_path")" ] || echo "" >>"$feeds_path"
        echo "$feed_entry" >>"$feeds_path"
    fi
}

update_feeds() {
    local FEEDS_PATH
    FEEDS_PATH=$(get_feeds_path)
    sed -i '/^#/d' "$FEEDS_PATH"
    sed -i '/packages_ext/d' "$FEEDS_PATH"
    sed -i '/[[:space:]]fichenx[[:space:]]/d' "$FEEDS_PATH"
    sed -i '/[[:space:]]custom_feed[[:space:]]/d' "$FEEDS_PATH"

    append_feed_if_missing "$FEEDS_PATH" "openwrt_bandix" "src-git openwrt_bandix https://github.com/timsaya/openwrt-bandix.git;main"
    append_feed_if_missing "$FEEDS_PATH" "luci_app_bandix" "src-git luci_app_bandix https://github.com/timsaya/luci-app-bandix.git;main"
    append_feed_if_missing "$FEEDS_PATH" "kenzok" "src-git kenzok https://github.com/kenzok8/openwrt-packages.git;master"
    append_feed_if_missing "$FEEDS_PATH" "small" "src-git small https://github.com/kenzok8/small.git;master"

    if [ ! -f "$BUILD_DIR/include/bpf.mk" ]; then
        touch "$BUILD_DIR/include/bpf.mk"
    fi

    ./scripts/feeds update -a
}

install_feeds() {
    ./scripts/feeds update -i
    # 跳过 kenzok8 源的全量安装，避免与官方源包冲突
    # kenzok8/small 和 kenzok/openwrt-packages 仅作为依赖源
    for feed in "$BUILD_DIR"/feeds/*; do
        [ -d "$feed" ] || continue
        local feed_name
        feed_name=$(basename "$feed")
        case "$feed_name" in
            *.tmp|*.index|*.targetindex) continue ;;
            small|kenzok)
                echo "跳过 $feed_name 源的全量安装（仅作为依赖源）"
                continue
                ;;
        esac
        ./scripts/feeds install -f -p "$feed_name"
    done
}
