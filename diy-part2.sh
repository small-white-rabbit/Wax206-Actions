#!/bin/bash

Dev=$1
BUILD_DIR=${2:-$1}

echo "=========================================="
echo "DIY Part2 - 设备: $Dev"
echo "BUILD_DIR: $BUILD_DIR"
echo "=========================================="

echo "目标目录: $BUILD_DIR"

if [ ! -d "./$BUILD_DIR" ]; then
    echo "错误: 目录 ./$BUILD_DIR 不存在"
    ls -la
    exit 1
fi

# ========== 添加自定义插件（必须在 cd 之前执行）==========
echo ">>> 添加自定义插件 luci-app-devicemaster..."

if [ -d "wax206/packages/luci-app-devicemaster" ]; then
    cp -r wax206/packages/luci-app-devicemaster "$BUILD_DIR/package/"
    echo "✓ 插件已复制到 $BUILD_DIR/package/luci-app-devicemaster"
else
    echo "⚠ 警告: wax206/packages/luci-app-devicemaster 不存在，跳过插件安装"
fi

# ========== 转发加速固化（flow offload + IRQ/RPS 多核分发） ==========
# 与 wrt_core/modules/system.sh 的注入等价且幂等；此链由 sh/build.sh 调用
if [ -f "wrt_core/patches/993_forward_offload" ] && [ -f "wrt_core/patches/forward-affinity" ]; then
    DEST_FILES="$BUILD_DIR/package/base-files/files"
    mkdir -p "$DEST_FILES/etc/uci-defaults" "$DEST_FILES/etc/init.d"
    install -Dm544 "wrt_core/patches/993_forward_offload" "$DEST_FILES/etc/uci-defaults/993_forward_offload"
    install -Dm755 "wrt_core/patches/forward-affinity" "$DEST_FILES/etc/init.d/forward-affinity"
    echo "✓ 转发加速配置已固化到固件"
else
    echo "⚠ 警告: 未找到转发加速补丁文件，跳过固化"
fi

cd "./$BUILD_DIR" || exit 1
echo "进入目录: $(pwd)"

# ========== 安装插件到 feeds ==========
if [ -d "package/luci-app-devicemaster" ]; then
    ./scripts/feeds update luci >/dev/null 2>&1
    ./scripts/feeds install -a -p luci >/dev/null 2>&1
    echo "✓ luci-app-devicemaster feeds 安装完成"
fi

# LuCI 已用内存采用 MemAvailable 口径，避免把可回收缓存算作占用
MEMORY_VIEW="feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/20_memory.js"
if [ -f "$MEMORY_VIEW" ]; then
    if grep -qF '(mem.total&&mem.available!=null)?(mem.total-mem.available):null' "$MEMORY_VIEW"; then
        # 已是 MemAvailable 口径（之前已修正）
        echo "✓ LuCI 已用内存已是 MemAvailable 口径（无需修改）"
    elif grep -qF '(mem.total&&mem.free)?(mem.total-mem.free):null' "$MEMORY_VIEW"; then
        # 旧写法：total - free → 改成 total - available
        sed -i 's/(mem.total&&mem.free)?(mem.total-mem.free):null/(mem.total\&\&mem.available!=null)?(mem.total-mem.available):null/' "$MEMORY_VIEW"
        grep -qF '(mem.total&&mem.available!=null)?(mem.total-mem.available):null' "$MEMORY_VIEW" || exit 1
        echo "✓ LuCI 已用内存已改为 MemAvailable 口径"
    elif grep -qE 'mem\.available' "$MEMORY_VIEW"; then
        # 上游新版 20_memory.js 已直接使用 mem.available（"Used"=total-free，"Total Available"=available），
        # 无需再做替换；为保持口径一致，把 Used 也改为 total - available。
        sed -i -E 's/\(mem\.total && mem\.free\) \? \(mem\.total - mem\.free\) : null/(mem.total \&\& mem.available!=null) ? (mem.total - mem.available) : null/' "$MEMORY_VIEW"
        echo "✓ LuCI 已用内存已对齐 MemAvailable 口径（上游新版结构）"
    else
        echo "错误：LuCI 内存页面结构已变化，无法安全修正内存口径" >&2
        exit 1
    fi
else
    echo "错误：未找到 LuCI 内存页面 $MEMORY_VIEW" >&2
    exit 1
fi

# ==========================================
# 配置IP
# ==========================================
if [ -f "package/base-files/files/bin/config_generate" ]; then
    sed -i 's/192.168.1.1/192.168.31.1/g' package/base-files/files/bin/config_generate
    echo "✓ IP改为192.168.31.1"
fi

# ==========================================
# 配置主机名
# ==========================================
if [ -f "package/base-files/files/bin/config_generate" ]; then
    sed -i 's/OpenWrt/Wax206/g' package/base-files/files/bin/config_generate
    echo "✓ 主机名改为Wax206"
fi

# ==========================================
# 配置时区
# ==========================================
if [ -f "package/base-files/files/bin/config_generate" ]; then
    sed -i "s/timezone='.*'/timezone='CST-8'/g" package/base-files/files/bin/config_generate
    sed -i "/timezone='CST-8'/a\\\t\tset system.@system[-1].zonename='Asia/Shanghai'" package/base-files/files/bin/config_generate
    echo "✓ 时区改为Asia/Shanghai"
fi

# ========== 最后：强制覆盖 distfeeds.list ==========

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

# ==========================================
# Conntrack 优化配置
# ==========================================
echo "配置 conntrack 优化..."

mkdir -p package/base-files/files/etc/sysctl.d
mkdir -p package/base-files/files/etc/modules.d
mkdir -p package/base-files/files/etc/hotplug.d/iface

cat > package/base-files/files/etc/sysctl.d/99-conntrack.conf << 'EOF'
net.netfilter.nf_conntrack_max=65535
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
net.core.netdev_max_backlog=4096
net.core.netdev_budget=50000
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.ip_local_port_range=1024 65535
net.ipv4.tcp_slow_start_after_idle=0
EOF
echo "✓ /etc/sysctl.d/99-network.conf 已写入（TCP 缓冲由内核按物理内存自动计算）"

# conntrack 哈希表：实测并发连接仅 ~1900 条，65536 桶属于过度预分配。
# 16384 桶（vmalloc 约 256KB）足够上万条连接，比 65536 桶省约 0.75MB 内核内存。
echo "nf_conntrack hashsize=16384" > package/base-files/files/etc/modules.d/99-nf-conntrack-custom
echo "✓ /etc/modules.d/99-nf-conntrack-custom 已写入"

cat > package/base-files/files/etc/hotplug.d/iface/99-conntrack << 'HOTPLUG'
#!/bin/sh
[ "$ACTION" = "ifup" ] && [ "$INTERFACE" = "wan" ] && {
    sleep 2
    echo 65535 > /proc/sys/net/netfilter/nf_conntrack_max
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
    # 上行抗 bufferbloat：WAN egress Cake（上行 50M，按 45M 整形留余量）
    command -v tc >/dev/null 2>&1 && tc qdisc replace dev wan root cake bandwidth 45mbit diffserv4 ack-filter-aggressive 2>/dev/null
}
HOTPLUG
chmod +x package/base-files/files/etc/hotplug.d/iface/99-conntrack
echo "✓ /etc/hotplug.d/iface/99-conntrack 已写入"

# ==========================================
# WiFi 配置
# ==========================================
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

# ==========================================
# 运行内存收口：默认关闭常驻 Web 终端（2026-11-05）
# ==========================================
# 实测 ttyd 在本机常驻 RSS 约 3.9MB（主机/子机各一份），日常用 SSH 时完全用不到。
# 这里只关闭“开机自启”，包仍保留；需要网页终端时在
# LuCI → 系统 → 管理权 → 终端 里一键重新启用即可。
mkdir -p package/base-files/files/etc/uci-defaults
cat > package/base-files/files/etc/uci-defaults/99-mem-trim << 'EOF'
#!/bin/sh
if [ -f /etc/config/ttyd ] && uci -q get ttyd.@ttyd[0] >/dev/null 2>&1; then
    uci -q set ttyd.@ttyd[0].enable=0
    uci -q commit ttyd
fi
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/99-mem-trim
echo "✓ /etc/uci-defaults/99-mem-trim 已写入（ttyd 默认不自启）"

# ==========================================
# 无线 / 漫游 / DNS 基线固化（2026-11-24）
# ==========================================
# 1) 关闭 802.11r（FT 在本 Mesh 组合下引发 key addition failed），保留 11k/11v
# 2) isolate=0，允许同 AP 无线设备互访（投屏/无线打印）
# 3) usteer 统一温和参数，避免 2.4G/5G 反复震荡
# 4) 局域网不宣告 IPv6 RA（与 OpenClash fake-ip 架构一致）
# 5) WAN 设备 MTU 1500（DHCP 场景）
# 6) 清理无效 SQM eth1 示例
# 7) OpenClash 启用自定义 fallback-filter
cat > package/base-files/files/etc/uci-defaults/98-net-tune << 'EOF'
#!/bin/sh
[ -f /etc/config/wireless ] || wifi config 2>/dev/null
for s in $(uci -q show wireless | sed -n 's/^wireless\.\([^.=]*\)=wifi-iface$/\1/p'); do
    uci -q set wireless.$s.ieee80211r='0'
    uci -q set wireless.$s.ieee80211k='1'
    uci -q set wireless.$s.bss_transition='1'
    uci -q set wireless.$s.isolate='0'
done
uci -q commit wireless

if [ -f /etc/config/usteer ] && uci -q get usteer.@usteer[0] >/dev/null 2>&1; then
    uci -q set usteer.@usteer[0].aggressiveness='2'
    uci -q set usteer.@usteer[0].band_steering_interval='60000'
    uci -q set usteer.@usteer[0].band_steering_min_snr='-70'
    uci -q set usteer.@usteer[0].signal_diff_threshold='5'
    uci -q set usteer.@usteer[0].roam_trigger_snr='-75'
    uci -q set usteer.@usteer[0].roam_trigger_interval='60000'
    uci -q commit usteer
fi

if uci -q get dhcp.lan >/dev/null 2>&1; then
    uci -q set dhcp.lan.ra='disabled'
    uci -q set dhcp.lan.dhcpv6='disabled'
    uci -q commit dhcp
fi

if uci -q get network.@device[1] >/dev/null 2>&1; then
    uci -q set network.@device[1].mtu='1500'
    uci -q commit network
fi

if [ -f /etc/config/sqm ]; then
    uci -q delete sqm.eth1 2>/dev/null
    uci -q commit sqm
fi

if [ -f /etc/config/openclash ]; then
    uci -q set openclash.config.custom_fallback_filter='1'
    uci -q commit openclash
    mkdir -p /etc/openclash/custom
    cat > /etc/openclash/custom/openclash_custom_fallback_filter.yaml << 'YAML'
fallback-filter:
  geoip: true
  geoip-code: CN
  ipcidr:
    - 240.0.0.0/4
    - 127.0.0.1/8
  domain:
    - '+.google.com'
    - '+.facebook.com'
    - '+.youtube.com'
    - '+.xn--ngstr-lra8j.com'
YAML
fi
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/98-net-tune
echo "✓ /etc/uci-defaults/98-net-tune 已写入（无线/漫游/IPv6/MTU/DNS 基线）"

# 注意：OpenClash 的自定义配置不放 base-files。luci-app-openclash 包自带同名文件，
# 放在 base-files 会导致 package/install 阶段 apk 报 "trying to overwrite" 而失败。
# 改为在 98-net-tune 的 uci-defaults 里运行期写入。

echo "=========================================="
echo "DIY 配置完成！"
echo "=========================================="
