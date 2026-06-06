#!/usr/bin/env bash
# ============================================================================
# 模块：Conntrack 配置
# 功能：配置连接跟踪优化参数
# ============================================================================

configure_conntrack() {
    local BUILD_DIR="$1"
    local CONFIG_FILE="${OPT_PATH}/config/config.conf"
    
    # 加载配置
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    fi
    
    echo "=== 配置 Conntrack 优化 ==="
    
    cd "$BUILD_DIR" || return 1
    
    # 创建目录
    mkdir -p package/base-files/files/etc/sysctl.d
    mkdir -p package/base-files/files/etc/modules.d
    mkdir -p package/base-files/files/etc/hotplug.d/iface
    
    # 写入 sysctl 配置
    cat > package/base-files/files/etc/sysctl.d/99-conntrack.conf << EOF
net.netfilter.nf_conntrack_max=${CONNTRACK_MAX}
net.netfilter.nf_conntrack_tcp_timeout_established=${CONNTRACK_TCP_TIMEOUT_ESTABLISHED}
net.netfilter.nf_conntrack_tcp_timeout_time_wait=${CONNTRACK_TCP_TIMEOUT_TIME_WAIT}
net.netfilter.nf_conntrack_tcp_timeout_close_wait=${CONNTRACK_TCP_TIMEOUT_CLOSE_WAIT}
net.netfilter.nf_conntrack_tcp_timeout_fin_wait=${CONNTRACK_TCP_TIMEOUT_FIN_WAIT}
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
    
    # 写入网络配置
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
    
    # 写入模块配置
    echo "nf_conntrack hashsize=65536" > package/base-files/files/etc/modules.d/99-nf-conntrack-custom
    echo "✓ /etc/modules.d/99-nf-conntrack-custom 已写入"
    
    # 写入 hotplug 脚本
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
    
    cd - > /dev/null
}