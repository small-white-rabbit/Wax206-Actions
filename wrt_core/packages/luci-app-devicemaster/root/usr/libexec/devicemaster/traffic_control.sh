#!/bin/sh
# Traffic Control - Block or limit device bandwidth
# Uses nftables for modern OpenWrt versions

# Check if tc is available
TC_AVAILABLE=0
if command -v tc >/dev/null 2>&1; then
    TC_AVAILABLE=1
fi

# Find device section by MAC (using uci directly for reliability)
find_device_section() {
    local mac="$1"
    local idx=0
    local empty_count=0
    while [ $empty_count -lt 5 ]; do
        local m=$(uci -q get "devicemaster.@device[$idx].mac" 2>/dev/null)
        if [ -n "$m" ] && [ "$m" = "$mac" ]; then
            echo "@device[$idx]"
            return
        fi
        if [ -z "$m" ]; then
            empty_count=$((empty_count + 1))
        else
            empty_count=0
        fi
        idx=$((idx + 1))
    done
}

# Get IP from MAC
get_ip_from_mac() {
    local mac="$1"
    grep -i "$mac" /proc/net/arp 2>/dev/null | awk '{print $1}' | head -1
}

# Block device by MAC address
block_device() {
    local mac="$1"
    local action="$2"  # add or remove
    
    if [ "$action" = "add" ]; then
        # Add MAC to blocked set
        nft add element inet devicemaster blocked_macs { "$mac" } 2>/dev/null
        
        # Ensure blocking chains exist with rules for both forward and input
        if ! nft list chain inet devicemaster dm_block 2>/dev/null | grep -q "blocked_macs"; then
            nft add chain inet devicemaster dm_block '{ type filter hook forward priority filter; policy accept; }' 2>/dev/null
            nft add rule inet devicemaster dm_block ether saddr @blocked_macs drop 2>/dev/null
            nft add rule inet devicemaster dm_block ether daddr @blocked_macs drop 2>/dev/null
        fi
        if ! nft list chain inet devicemaster dm_block_input 2>/dev/null | grep -q "blocked_macs"; then
            nft add chain inet devicemaster dm_block_input '{ type filter hook input priority filter; policy accept; }' 2>/dev/null
            nft add rule inet devicemaster dm_block_input ether saddr @blocked_macs drop 2>/dev/null
            nft add rule inet devicemaster dm_block_input ether daddr @blocked_macs drop 2>/dev/null
        fi
        
        # Update UCI config - find existing section or create new
        local section=$(find_device_section "$mac")
        if [ -z "$section" ]; then
            section=$(uci add devicemaster device)
            uci set "devicemaster.$section.mac=$mac"
        fi
        uci set "devicemaster.$section.blocked=1"
        uci commit devicemaster
        
        # Invalidate caches so frontend shows updated blocked status
        rm -f /tmp/devicemaster_device_cache /tmp/devicemaster_custom_cache
        
        logger -t devicemaster "Blocked device: $mac"
        echo "success"
    elif [ "$action" = "remove" ]; then
        # Remove MAC from blocked set
        nft delete element inet devicemaster blocked_macs { "$mac" } 2>/dev/null
        
        # Update UCI config
        local section=$(find_device_section "$mac")
        if [ -n "$section" ]; then
            uci set "devicemaster.$section.blocked=0"
            uci commit devicemaster
        fi
        
        # Invalidate caches so frontend shows updated blocked status
        rm -f /tmp/devicemaster_device_cache /tmp/devicemaster_custom_cache
        
        logger -t devicemaster "Unblocked device: $mac"
        echo "success"
    fi
}

# Limit device using nftables (fallback when tc is not available)
limit_device_nft() {
    local mac="$1"
    local rate="$2"  # e.g., "1mbit", "512kbit"
    
    # Convert rate to pps (packets per second) for nftables limit
    # This is a rough approximation: 1mbit ~ 125pps (assuming 1000 byte packets)
    local pps=125
    case "$rate" in
        *kbit) pps=$(echo "$rate" | sed 's/kbit//' | awk '{print int($1/8)}') ;;
        *mbit) pps=$(echo "$rate" | sed 's/mbit//' | awk '{print int($1*125)}') ;;
        *gbit) pps=$(echo "$rate" | sed 's/gbit//' | awk '{print int($1*125000)}') ;;
        *) pps=125 ;;
    esac
    
    # Ensure limited_macs set exists
    nft add set inet devicemaster limited_macs '{ type ether_addr; flags timeout; timeout 1h; }' 2>/dev/null
    
    # Add MAC to limited set
    nft add element inet devicemaster limited_macs { "$mac" } 2>/dev/null
    
    # Create limit chain if not exists
    if ! nft list chain inet devicemaster dm_limit 2>/dev/null | grep -q "limited_macs"; then
        nft add chain inet devicemaster dm_limit '{ type filter hook forward priority filter; policy accept; }' 2>/dev/null
        nft add rule inet devicemaster dm_limit ether saddr @limited_macs limit rate over "$pps/second" drop 2>/dev/null
        nft add rule inet devicemaster dm_limit ether daddr @limited_macs limit rate over "$pps/second" drop 2>/dev/null
    fi
    
    # Update UCI config
    local section=$(find_device_section "$mac")
    if [ -z "$section" ]; then
        section=$(uci add devicemaster device)
        uci set "devicemaster.$section.mac=$mac"
    fi
    uci set "devicemaster.$section.rate_limit=$rate"
    uci commit devicemaster
    
    # Invalidate cache
    rm -f /tmp/devicemaster_custom_cache
    
    logger -t devicemaster "Rate limited device $mac to $rate (nftables fallback)"
    echo "success"
}

# Remove nftables limit
unlimit_device_nft() {
    local mac="$1"
    
    # Remove from limited set
    nft delete element inet devicemaster limited_macs { "$mac" } 2>/dev/null
    
    # Update UCI config
    local section=$(find_device_section "$mac")
    if [ -n "$section" ]; then
        uci delete "devicemaster.$section.rate_limit" 2>/dev/null
        uci commit devicemaster
    fi
    
    # Invalidate cache
    rm -f /tmp/devicemaster_custom_cache
    
    logger -t devicemaster "Removed rate limit for device $mac (nftables)"
    echo "success"
}

# Limit device bandwidth using tc (traffic control)
limit_device() {
    local mac="$1"
    local rate="$2"  # e.g., "1mbit", "512kbit"
    local ip=$(get_ip_from_mac "$mac")
    
    if [ -z "$ip" ]; then
        echo "error: device not found in ARP table"
        return 1
    fi
    
    if [ -n "$rate" ]; then
        # Check if tc is available
        if [ $TC_AVAILABLE -eq 0 ]; then
            logger -t devicemaster "tc not available, using nftables fallback for $mac"
            limit_device_nft "$mac" "$rate"
            return
        fi
        
        # Get the LAN interface
        local lan_dev="br-lan"
        
        # Create qdisc and class for bandwidth limiting
        tc qdisc add dev "$lan_dev" root handle 1: htb default 10 2>/dev/null || \
        tc qdisc replace dev "$lan_dev" root handle 1: htb default 10
        
        # Create class for this device
        local class_id=$(echo "$ip" | awk -F'.' '{print $4}')
        tc class add dev "$lan_dev" parent 1: classid "1:$class_id" htb rate "$rate" ceil "$rate" 2>/dev/null || \
        tc class replace dev "$lan_dev" parent 1: classid "1:$class_id" htb rate "$rate" ceil "$rate"
        
        # Add filter for this IP
        tc filter add dev "$lan_dev" protocol ip parent 1:0 prio 1 u32 match ip dst "$ip" flowid "1:$class_id" 2>/dev/null
        tc filter add dev "$lan_dev" protocol ip parent 1:0 prio 1 u32 match ip src "$ip" flowid "1:$class_id" 2>/dev/null
        
        # Update UCI config
        local section=$(find_device_section "$mac")
        if [ -z "$section" ]; then
            section=$(uci add devicemaster device)
            uci set "devicemaster.$section.mac=$mac"
        fi
        uci set "devicemaster.$section.rate_limit=$rate"
        uci commit devicemaster
        
        # Invalidate cache
        rm -f /tmp/devicemaster_custom_cache
        
        logger -t devicemaster "Rate limited device $mac ($ip) to $rate (tc)"
        echo "success"
    else
        # Remove rate limit
        if [ $TC_AVAILABLE -eq 0 ]; then
            unlimit_device_nft "$mac"
            return
        fi
        
        local class_id=$(echo "$ip" | awk -F'.' '{print $4}')
        tc class del dev "$lan_dev" classid "1:$class_id" 2>/dev/null
        tc filter del dev "$lan_dev" protocol ip parent 1:0 prio 1 u32 match ip dst "$ip" 2>/dev/null
        tc filter del dev "$lan_dev" protocol ip parent 1:0 prio 1 u32 match ip src "$ip" 2>/dev/null
        
        # Update UCI config
        local section=$(find_device_section "$mac")
        if [ -n "$section" ]; then
            uci delete "devicemaster.$section.rate_limit" 2>/dev/null
            uci commit devicemaster
        fi
        
        # Invalidate cache
        rm -f /tmp/devicemaster_custom_cache
        
        logger -t devicemaster "Removed rate limit for device $mac (tc)"
        echo "success"
    fi
}

# Get current rate limit status
get_rate_limit() {
    local mac="$1"
    local ip=$(get_ip_from_mac "$mac")
    
    # Check tc first
    if [ $TC_AVAILABLE -eq 1 ] && [ -n "$ip" ]; then
        local class_id=$(echo "$ip" | awk -F'.' '{print $4}')
        tc class show dev br-lan classid "1:$class_id" 2>/dev/null | grep -o 'rate [^ ]*'
        return
    fi
    
    # Check nftables fallback
    if nft list set inet devicemaster limited_macs 2>/dev/null | grep -qi "$mac"; then
        echo "nftables-limited"
    fi
}

# List all blocked devices
list_blocked() {
    nft list set inet devicemaster blocked_macs 2>/dev/null | grep -o '([[:xdigit:]:]*)' | tr -d '()'
}

# Entry point - only execute if run directly (not sourced)
main() {
    case "$1" in
        block)
            block_device "$2" "add"
            ;;
        unblock)
            block_device "$2" "remove"
            ;;
        limit)
            limit_device "$2" "$3"
            ;;
        unlimit)
            limit_device "$2" ""
            ;;
        status)
            get_rate_limit "$2"
            ;;
        list)
            list_blocked
            ;;
        *)
            echo "Usage: $0 {block|unblock|limit|unlimit|status|list} <mac> [rate]"
            exit 1
            ;;
    esac
}

# Only run main if script is executed directly (not sourced)
[ "${0##*/}" = "traffic_control.sh" ] && main "$@"
