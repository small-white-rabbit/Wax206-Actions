#!/bin/sh
# DeviceMaster Event Handler (v2 - Full 7-Level Identification)
# Called by dnsmasq via --dhcp-script on lease changes
# Environment variables set by dnsmasq:
#   $1 = action (add|del|old)

# Ensure full PATH - dnsmasq jail may have limited PATH
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
#   $2 = MAC address
#   $3 = IP address (empty on del)
#   $4 = hostname (may be *)
#
# 7-Level Identification Chain:
#   1. Local OUI database
#   2. Remote OUI API (via oui_lookup.sh)
#   3. mDNS probe
#   4. DHCP hostname inference
#   5. DHCP fingerprint (Option 55) analysis
#   6. nlbwmon protocol analysis
#   7. Traffic pattern analysis (conntrack ports)

OUI_DB="/usr/share/devicemaster/oui.txt"
OUI_APPEND="/usr/share/devicemaster/oui_append.txt"
OUI_LOOKUP="/usr/libexec/devicemaster/oui_lookup.sh"
COLLECTOR="/usr/libexec/devicemaster/device_collector.sh"
ARP_TABLE="/proc/net/arp"
DHCP_LEASES="/tmp/dhcp.leases"
NLBWMON_CACHE="/tmp/devicemaster_nlbwmon_cache"
MDNS_CACHE="/tmp/devicemaster_mdns_cache"

log_msg() {
    logger -t devicemaster-event "$1"
}

# ============================================================
# Level 1: Local OUI database lookup
# ============================================================
lookup_oui_local() {
    local mac="$1"
    local oui=$(echo "$mac" | tr -d ':' | cut -c1-6 | tr 'a-f' 'A-F')

    if [ -f "$OUI_DB" ]; then
        local vendor=$(grep "^${oui}" "$OUI_DB" | cut -d'|' -f2 | head -1)
        if [ -n "$vendor" ]; then
            echo "$vendor" | sed 's/ Co\..*$//'
            return
        fi
    fi

    if [ -f "$OUI_APPEND" ]; then
        local vendor=$(grep -i "${mac:0:8}" "$OUI_APPEND" | head -1 | awk -F'\t' '{print $2}')
        if [ -n "$vendor" ]; then
            echo "$vendor"
            return
        fi
    fi

    echo ""
}

# ============================================================
# Level 2: Remote OUI API (via oui_lookup.sh module)
# ============================================================
lookup_oui_remote() {
    local mac="$1"
    if [ -x "$OUI_LOOKUP" ]; then
        local vendor=$($OUI_LOOKUP lookup "$mac" 2>/dev/null)
        if [ -n "$vendor" ] && [ "$vendor" != "Unknown" ]; then
            echo "$vendor" | sed 's/ Co\..*$//'
            return
        fi
    fi
    echo ""
}

# ============================================================
# Level 3: mDNS probe
# ============================================================
mdns_probe_ip() {
    local ip="$1"
    local result=""

    if command -v avahi-browse >/dev/null 2>&1; then
        result=$(avahi-browse -a -t -r -p 2>/dev/null | grep -i "$ip" | head -1)
        if [ -n "$result" ]; then
            echo "$result" | awk -F';' '{print $4}' | sed 's/\.local$//'
            return
        fi
    fi

    if command -v avahi-resolve >/dev/null 2>&1; then
        result=$(avahi-resolve-host-name -a "$ip" 2>/dev/null | awk '{print $2}')
        if [ -n "$result" ]; then
            echo "$result" | sed 's/\.local$//'
            return
        fi
    fi

    if command -v nslookup >/dev/null 2>&1; then
        result=$(nslookup "$ip" 2>/dev/null | grep "name = " | head -1)
        if [ -n "$result" ]; then
            echo "$result" | sed 's/.*name = //' | sed 's/\..*//'
            return
        fi
    fi

    echo ""
}

infer_vendor_from_mdns() {
    local name="$1"
    local n=$(echo "$name" | tr 'A-Z' 'a-z')
    case "$n" in
        *iphone*|*ipad*|*macbook*|*imac*|*mac-pro*|*mac-mini*|*airplay*|*homepod*) echo "Apple" ;;
        *redmi*|*xiaomi*|*mi-*|*mico*|*yeelight*) echo "Xiaomi" ;;
        *samsung*|*galaxy*) echo "Samsung" ;;
        *huawei*|*honor*) echo "Huawei" ;;
        *chromecast*|*google-home*|*nest*) echo "Google" ;;
        *echo*|*kindle*|*fire-*) echo "Amazon" ;;
        *sonos*) echo "Sonos" ;;
        *hp-*|*hp_*|*deskjet*|*laserjet*|*officejet*) echo "HP" ;;
        *brother*) echo "Brother" ;;
        *epson*) echo "Epson" ;;
        *canon*) echo "Canon" ;;
        *) echo "" ;;
    esac
}

# ============================================================
# Level 4: DHCP hostname inference (with structured parsing)
# Strategy:
#   1. Structured parsing: extract vendor prefix, region, model
#      e.g. "H-de-S20" -> prefix=H(Honor), region=de, model=S20
#           "cph-nx1"  -> prefix=cph(OPPO), model=nx1
#   2. Full keyword fallback: match known brand words
# ============================================================
infer_vendor_from_hostname() {
    local hostname="$1"
    local h=$(echo "$hostname" | tr 'A-Z' 'a-z')
    local vendor=""

    # --- Stage 1: Structured prefix parsing ---
    # Honor/Huawei: H-<region>-<model> or Honor-<model>
    case "$h" in
        h-*)
            # Honor naming: H-de-S20, H-cn-Mate60, H-in-Ace
            local model=$(echo "$h" | sed 's/^h-[a-z]*-//')
            local region=$(echo "$h" | sed 's/^h-//;s/-.*//')
            # Verify model part exists (not just "h-de")
            if [ -n "$model" ] && [ "$model" != "$h" ]; then
                echo "Honor"
                return
            fi
            ;;
    esac

    # OPPO: cph-<model> or rmx-<model>
    case "$h" in
        cph-*|rmx-*) echo "OPPO"; return ;;
    esac

    # vivo: v<numbers><letters> or V<numbers>
    case "$h" in
        v[0-9][0-9][0-9][0-9]*|v[0-9][0-9][0-9]*) echo "vivo"; return ;;
    esac

    # Realme: rmx-<model> (already covered above) or RMX-<model>
    case "$h" in
        rmx-*) echo "Realme"; return ;;
    esac

    # Xiaomi codenames: mido, nitrogen, cepheus, raphael, davinci, vayu, begonia, etc.
    case "$h" in
        mido|nitrogen|cepheus|raphael|davinci|vayu|begonia|nabu|alioth|surya|merlin|lancelot|monet|rosemary|joyeuse|biloba|citrus|olive|oliva|pipa|fog|dandelion|evergo|cannon|lisa|munch|stone|marble)
            echo "Xiaomi"; return ;;
    esac

    # --- Stage 2: Full keyword matching ---
    case "$h" in
        *redmi*|*mi-*|*mi_*|*xiaomi*) vendor="Xiaomi" ;;
        *iphone*|*ipad*|*macbook*|*imac*|*mac-mini*) vendor="Apple" ;;
        *samsung*|*galaxy*|*note-*|*a[0-9][0-9]-*) vendor="Samsung" ;;
        *huawei*|*honor*|*nova*|*mate*|*p40*|*p50*|*p60*|*p70*) vendor="Huawei" ;;
        *oppo*|*find*|*reno*|*a[0-9][0-9][0-9]*) vendor="OPPO" ;;
        *vivo*|*x[0-9][0-9]*|*v[0-9][0-9]*) vendor="vivo" ;;
        *oneplus*) vendor="OnePlus" ;;
        *realme*) vendor="Realme" ;;
        *pixel*|*nexus*) vendor="Google" ;;
        *surface*|*lumia*|*windows*) vendor="Microsoft" ;;
        *dell*|*latitude*|*inspiron*|*xps*|*precision*|*optiplex*) vendor="Dell" ;;
        *lenovo*|*thinkpad*|*thinkcentre*|*ideapad*|*legion*) vendor="Lenovo" ;;
        *hp*|*pavilion*|*omen*|*elitebook*|*probook*|*zbook*) vendor="HP" ;;
        *asus*|*rog*|*tuf*|*zenbook*|*vivobook*) vendor="ASUS" ;;
        *acer*|*aspire*|*predator*|*nitro*) vendor="Acer" ;;
        *espressif*|*esp32*|*esp8266*) vendor="Espressif" ;;
        *tuya*|*smart-life*) vendor="Tuya" ;;
        *yeelight*) vendor="Yeelight" ;;
        *midea*) vendor="Midea" ;;
        *haier*|*u-home*) vendor="Haier" ;;
        *) vendor="" ;;
    esac

    echo "$vendor"
}

# ============================================================
# Level 5: DHCP fingerprint (Option 55) analysis
# ============================================================
dhcp_fingerprint_lookup() {
    local mac="$1"

    # Check dnsmasq log for Option 55
    local logfile=""
    [ -f "/tmp/dnsmasq.log" ] && logfile="/tmp/dnsmasq.log"
    [ -f "/var/log/dnsmasq.log" ] && logfile="/var/log/dnsmasq.log"

    if [ -n "$logfile" ]; then
        local opt55=$(grep -i "$mac" "$logfile" 2>/dev/null | grep 'req-opt:' | tail -1 | sed 's/.*req-opt: *//' | tr -d ' ')
        if [ -n "$opt55" ]; then
            case "$opt55" in
                *1,3,6,15,26,28,51*|*1,3,6,15,26,28,51,58,59,119,121*) echo "Apple"; return ;;
                *1,3,6,12,15,21,23,28,36,42*|*1,3,6,12,15,21,23,28,36,42,119,121*) echo "Android"; return ;;
                *1,3,6,15,31,33,43,44*|*1,3,6,15,31,33,43,44,46,47,119,121,249,252*) echo "Windows"; return ;;
                *1,3,6,12,15,17,28,42*|*1,3,6,12,15,17,28,42,119,121*) echo "Linux"; return ;;
            esac
        fi
    fi

    # Check DHCP lease vendor class (field 5)
    if [ -f "$DHCP_LEASES" ]; then
        local vendor_class=$(grep -i "$mac" "$DHCP_LEASES" 2>/dev/null | awk '{print $5}')
        case "$vendor_class" in
            MSFT|windows) echo "Windows"; return ;;
            Apple|MacOS) echo "Apple"; return ;;
            android) echo "Android"; return ;;
        esac
    fi

    echo ""
}

# ============================================================
# Level 6: nlbwmon protocol analysis
# ============================================================
detect_by_nlbwmon() {
    local mac="$1"
    local mac_lower=$(echo "$mac" | tr 'A-F' 'a-f')
    [ ! -f "$NLBWMON_CACHE" ] && { echo ""; return; }

    # Cache is JSON: {"columns":[...],"data":[["TCP",443,"mac",...,"layer7"],...]}
    # Split data rows, filter by MAC, extract layer7 (last field)
    local tmpfile="/tmp/nlbw_proto_$$"
    grep "$mac" "$NLBWMON_CACHE" | sed 's/\],\[/\n/g' | grep "$mac" | while IFS=',' read -r row; do
        layer7=$(echo "$row" | sed 's/^.*"\([^"]*\)"$/\1/' | awk -F'"' '{print $(NF-1)}')
        # Skip null/empty, non-identifying, and non-protocol values
        [ -z "$layer7" ] && continue
        [ "$layer7" = "null" ] && continue
        # Skip values that look like MAC addresses
        echo "$layer7" | grep -q ":" && continue
        echo "$layer7"
    done | sort -u > "$tmpfile"

    local protocols=$(cat "$tmpfile" 2>/dev/null | tr '\n' ' ')
    rm -f "$tmpfile"
    [ -z "$protocols" ] && { echo ""; return; }

    # Match protocol combinations to vendors
    echo "$protocols" | grep -q "Apple Push Service" && { echo "Apple"; return; }

    local has_gcm=0 has_xmpp=0 has_rdp=0 has_imaps=0
    echo "$protocols" | grep -q "Google Cloud Messaging" && has_gcm=1
    echo "$protocols" | grep -q "XMPP" && has_xmpp=1
    echo "$protocols" | grep -q "Microsoft RDP" && has_rdp=1
    echo "$protocols" | grep -q "IMAPS" && has_imaps=1

    if [ "$has_gcm" -eq 1 ] && [ "$has_xmpp" -eq 1 ]; then
        echo "Samsung"; return
    fi
    if [ "$has_rdp" -eq 1 ]; then
        echo "Microsoft"; return
    fi
    if [ "$has_imaps" -eq 1 ] && [ "$has_gcm" -eq 1 ]; then
        echo "Android"; return
    fi
    # Single GCM alone is NOT strong evidence (Chrome/Google apps on PC also use it)
    # Apple Push Service is strong (only Apple devices)
    # Do NOT return on single GCM - let other levels decide
    echo ""
}

# ============================================================
# Level 7: Traffic pattern analysis (conntrack ports)
# ============================================================
detect_type_by_traffic() {
    local mac="$1"
    local ip=$(grep -i "$mac" "$ARP_TABLE" 2>/dev/null | awk '{print $1}' | head -1)
    [ -z "$ip" ] && { echo ""; return; }

    local conntrack="/proc/net/nf_conntrack"
    [ ! -f "$conntrack" ] && { echo ""; return; }

    local ports=$(grep "src=$ip " "$conntrack" 2>/dev/null | grep 'dport=' | sed 's/.*dport=//' | awk '{print $1}' | sort -u)

    local has_phone_ports=0
    local has_pc_ports=0
    local has_iot_ports=0

    for port in $ports; do
        case "$port" in
            5228) has_phone_ports=1 ;;
            554|8554|5060|5061|5555) has_phone_ports=1 ;;
            1883|8883|5683|5684|49152|49153|6668|9999|8080|8443) has_iot_ports=1 ;;
            3389|22|445|139|135|5900|5901) has_pc_ports=1 ;;
        esac
    done

    if [ "$has_pc_ports" -eq 1 ] && [ "$has_phone_ports" -eq 0 ]; then
        echo "pc"
    elif [ "$has_iot_ports" -eq 1 ] && [ "$has_phone_ports" -eq 0 ] && [ "$has_pc_ports" -eq 0 ]; then
        echo "iot"
    elif [ "$has_phone_ports" -eq 1 ]; then
        echo "phone"
    else
        echo ""
    fi
}

# ============================================================
# Auto-generate device name from vendor and type
# Similar to Lua's auto_name function
# ============================================================
auto_name() {
    local vendor="$1"
    local devtype="$2"

    # Skip if vendor is empty, unknown, or LAA
    [ -z "$vendor" ] && return
    [ "$vendor" = "Unknown" ] && return
    [ "$vendor" = "LAA" ] && return

    # Shorten vendor name
    local short=$(echo "$vendor" | sed \
        -e 's/ Mobile Communication//g' \
        -e 's/ Corporation//g' \
        -e 's/ Inc\.//g' \
        -e 's/ Co\..*$//g' \
        -e 's/ Technology//g' \
        -e 's/ TECHNOLOGY CO\.,LTD\.//g' \
        -e 's/ CO\.,LTD\.//g' \
        -e 's/ CO\.//g')

    [ -z "$short" ] && return

    # If no type, just return vendor short name
    if [ -z "$devtype" ] || [ "$devtype" = "unknown" ]; then
        echo "$short"
        return
    fi

    # Return vendor-type format
    echo "${short}-${devtype}"
}

# ============================================================
# Comprehensive device type detection
# ============================================================
detect_device_type() {
    local mac="$1"
    local hostname="$2"
    local vendor="$3"

    # Stage 1: Match by vendor
    local v=$(echo "$vendor" | tr 'A-Z' 'a-z')
    case "$v" in
        *apple*|*samsung*|*xiaomi*|*huawei*|*oppo*|*vivo*|*oneplus*|*realme*|*google*|*android*|*nokia*|*motorola*|*sony*|*lg*|*htc*|*blackberry*|*zte*|*lenovo*|*asus*|*microsoft*|*honor*|*meizu*)
            echo "phone"; return ;;
        *dell*|*hp*|*acer*|*msi*|*razer*|*intel*|*realtek*|*windows*|*giga*|*gigabyte*)
            echo "pc"; return ;;
        *espressif*|*tuya*|*broadlink*|*yeelight*|*midea*|*haier*|*brother*|*epson*|*canon*)
            echo "iot"; return ;;
        *cisco*|*tp-link*|*netgear*|*ubiquiti*|*mikrotik*|*hiwifi*|*mercury*|*xiaomi*|*comheart*|*telecom*)
            echo "network"; return ;;
    esac

    # Stage 2: Match by hostname (structured prefix + keyword)
    local h=$(echo "$hostname" | tr 'A-Z' 'a-z')
    # Honor prefix: H-<region>-<model>
    case "$h" in
        h-*)
            local model=$(echo "$h" | sed 's/^h-[a-z]*-//')
            [ -n "$model" ] && [ "$model" != "$h" ] && { echo "phone"; return; }
            ;;
    esac
    # OPPO prefix
    case "$h" in cph-*|rmx-*) echo "phone"; return ;; esac
    # vivo prefix
    case "$h" in v[0-9]*|V[0-9]*) echo "phone"; return ;; esac
    # Xiaomi codenames
    case "$h" in
        mido|nitrogen|cepheus|raphael|davinci|vayu|begonia|nabu|alioth|surya|merlin|lancelot|monet|rosemary|joyeuse|biloba|citrus|olive|oliva|pipa|fog|dandelion|evergo|cannon|lisa|munch|stone|marble)
            echo "phone"; return ;;
    esac
    # Full keyword matching
    case "$h" in
        *iphone*|*ipad*|*redmi*|*samsung*|*galaxy*|*huawei*|*honor*|*oppo*|*vivo*|*pixel*|*oneplus*|*realme*|*mate*|*nova*|*reno*|*find*|*nokia*|*lumia*|*windows-phone*|*motorola*|*xperia*|*Honor*)
            echo "phone"; return ;;
        *desktop*|*laptop*|*pc*|*thinkpad*|*latitude*|*pavilion*|*xps*|*ideapad*|*macbook*|*imac*|*surface*|*legion*|*omen*|*rog*|*zenbook*|*vivobook*|*inspiron*|*aspire*|*predator*|*nitro*|*optiplex*|*elitebook*|*probook*|*zbook*|*precision*)
            echo "pc"; return ;;
        *esp*|*tuya*|*yeelight*|*midea*|*haier*|*smart*|*plug*|*bulb*|*sensor*|*switch*|*camera*|*door*|*lock*|*thermostat*|*aircon*|*purifier*)
            echo "iot"; return ;;
        *router*|*ap-*|*gateway*|*bridge*|*repeater*|*satellite*|*wax-*|*wax*)
            echo "network"; return ;;
    esac

    echo "unknown"
}

# ============================================================
# Master identification: 7-level chain, ALL run, then vote
# Confidence weights:
#   L1/L2 OUI:        HIGH   (direct MAC registration)
#   L3 mDNS:          MEDIUM (service advertisement)
#   L4 hostname:      LOW    (user-settable, unreliable)
#   L5 DHCP fingerprint: HIGH (OS-level protocol signature)
#   L6 nlbwmon:       HIGH   (observed protocol behavior)
#   L7 traffic ports: MEDIUM (connection patterns)
#
# Resolution: HIGH evidence overrides LOW evidence
#   If L5/L6/L7 disagree with L4, trust L5/L6/L7
# ============================================================
identify_vendor() {
    local mac="$1"
    local ip="$2"
    local hostname="$3"

    # Run ALL levels, collect results
    local l1=$(lookup_oui_local "$mac")
    local l2=$(lookup_oui_remote "$mac")
    local l3=""
    if [ -n "$ip" ]; then
        local mdns_name=$(mdns_probe_ip "$ip")
        [ -n "$mdns_name" ] && l3=$(infer_vendor_from_mdns "$mdns_name")
    fi
    local l4=$(infer_vendor_from_hostname "$hostname")
    local l5=$(dhcp_fingerprint_lookup "$mac")
    local l6=$(detect_by_nlbwmon "$mac")

    # Check if MAC is LAA (random MAC)
    local first_byte=$(echo "$mac" | tr -d ':' | cut -c1-2)
    local byte_val=$(printf '%d' "0x$first_byte" 2>/dev/null)
    local is_laa=0
    [ $((byte_val & 2)) -ne 0 ] && is_laa=1

    # Collect HIGH evidence (OUI, protocol-based)
    local high_vendor=""
    for v in "$l1" "$l2" "$l5" "$l6"; do
        if [ -n "$v" ] && [ "$v" != "Unknown" ] && [ "$v" != "LAA" ]; then
            if [ -z "$high_vendor" ]; then
                high_vendor="$v"
            elif [ "$high_vendor" != "$v" ]; then
                # HIGH evidence conflicts - trust protocol-based (L5, L6) over OUI
                case "$v" in
                    "$l5") high_vendor="$l5" ;;
                    "$l6") high_vendor="$l6" ;;
                esac
            fi
        fi
    done

    # If HIGH evidence found, return it (overrides L4)
    if [ -n "$high_vendor" ]; then
        echo "$high_vendor"
        return
    fi

    # For LAA devices with no OUI match, prioritize mDNS and hostname
    # MEDIUM evidence (L3 mDNS)
    if [ -n "$l3" ]; then
        echo "$l3"
        return
    fi

    # LOW evidence (L4 hostname) - elevated for LAA devices
    if [ -n "$l4" ]; then
        echo "$l4"
        return
    fi

    # No vendor identified
    if [ "$is_laa" = "1" ]; then
        echo "LAA"
    fi
    echo ""
}

# ============================================================
# Master identification: device type (uses vendor + traffic)
# ============================================================
identify_type() {
    local mac="$1"
    local ip="$2"
    local hostname="$3"
    local vendor="$4"

    # First try: vendor + hostname based detection
    local dtype=$(detect_device_type "$mac" "$hostname" "$vendor")
    if [ -n "$dtype" ] && [ "$dtype" != "unknown" ]; then
        echo "$dtype"
        return
    fi

    # Second try: traffic pattern analysis
    if [ -n "$ip" ]; then
        local dtype=$(detect_type_by_traffic "$mac")
        if [ -n "$dtype" ]; then
            echo "$dtype"
            return
        fi
    fi

    echo "unknown"
}

# ============================================================
# UCI helpers
# ============================================================
mac_exists_in_uci() {
    local mac="$1"
    local idx=0
    while uci -q get "devicemaster.@device[$idx].mac" >/dev/null 2>&1; do
        local stored_mac=$(uci -q get "devicemaster.@device[$idx].mac")
        if [ "$stored_mac" = "$mac" ]; then
            if [ -n "$3" ]; then
                uci -q set "devicemaster.@device[$idx].last_ip=$3"
                uci -q commit devicemaster
            fi
            return 0
        fi
        idx=$((idx + 1))
    done
    return 1
}

# ============================================================
# Check if MAC is LAA (Locally Administered Address)
# ============================================================
is_laa_mac() {
    local mac="$1"
    local first_byte=$(echo "$mac" | tr -d ':' | cut -c1-2)
    local byte_val=$(printf '%d' "0x$first_byte" 2>/dev/null)
    [ $((byte_val & 2)) -ne 0 ] && return 0
    return 1
}

# ============================================================
# Find and merge device with same hostname/vendor/type
# Returns: merged=1 if merged, merged=0 if not
# If merged, sets: merged_idx, merged_mac, merged_ip
# ============================================================
try_merge_device() {
    local new_mac="$1"
    local new_ip="$2"
    local new_hostname="$3"
    local new_vendor="$4"
    local new_type="$5"

    merged=0
    merged_idx=""
    merged_mac=""
    merged_ip=""

    # Skip if hostname is empty or meaningless
    [ -z "$new_hostname" ] && return
    case "$new_hostname" in
        "*"|"-"|unknown|wlan0|android-*)
            return ;;
    esac

    # Only merge LAA devices
    is_laa_mac "$new_mac" || return

    local idx=0
    while uci -q get "devicemaster.@device[$idx].mac" >/dev/null 2>&1; do
        local old_mac=$(uci -q get "devicemaster.@device[$idx].mac")
        local old_hostname=$(uci -q get "devicemaster.@device[$idx].hostname")
        local old_vendor=$(uci -q get "devicemaster.@device[$idx].vendor")
        local old_type=$(uci -q get "devicemaster.@device[$idx].type")
        local old_ip=$(uci -q get "devicemaster.@device[$idx].last_ip")

        # Check if same hostname, vendor, type
        if [ "$old_hostname" = "$new_hostname" ] && \
           [ "$old_vendor" = "$new_vendor" ] && \
           [ "$old_type" = "$new_type" ] && \
           [ "$old_mac" != "$new_mac" ]; then

            # Check if old device is offline (not in ARP table)
            local old_online=$(grep -i "$old_mac" /proc/net/arp 2>/dev/null | grep -v "00:00:00:00:00:00" | wc -l)

            if [ "$old_online" = "0" ]; then
                # Old device is offline, can merge
                log_msg "Merging device $new_mac into existing device $old_mac (same $new_hostname)"

                # Update the existing device with new MAC and IP
                uci -q set "devicemaster.@device[$idx].mac=$new_mac"
                uci -q set "devicemaster.@device[$idx].last_ip=$new_ip"
                uci -q set "devicemaster.@device[$idx].discovered_at=$(date +%s)"

                # Add old MAC to history list for tracking
                local mac_history=$(uci -q get "devicemaster.@device[$idx].mac_history")
                if [ -z "$mac_history" ]; then
                    mac_history="$old_mac"
                else
                    # Check if old_mac already in history
                    if ! echo "$mac_history" | grep -q "$old_mac"; then
                        mac_history="$mac_history,$old_mac"
                    fi
                fi
                uci -q set "devicemaster.@device[$idx].mac_history=$mac_history"

                uci -q commit devicemaster

                merged=1
                merged_idx="$idx"
                merged_mac="$new_mac"
                merged_ip="$new_ip"
                return
            fi
        fi
        idx=$((idx + 1))
    done
}

# ============================================================
# Register a device to UCI
# ============================================================
register_device() {
    local mac="$1"
    local ip="$2"
    local hostname="$3"

    # Run 7-level identification
    local vendor=$(identify_vendor "$mac" "$ip" "$hostname")
    local devtype=$(identify_type "$mac" "$ip" "$hostname" "$vendor")

    [ "$hostname" = "*" ] && hostname=""

    # Try to merge with existing device (same hostname/vendor/type, old device offline)
    try_merge_device "$mac" "$ip" "$hostname" "$vendor" "$devtype"
    if [ "$merged" = "1" ]; then
        log_msg "Device $mac merged into existing record (hostname: $hostname)"
        return
    fi

    # Auto-generate name only if hostname is meaningless
    local name=""
    local is_meaningless=0
    case "$hostname" in
        ""|"*"|"-"|unknown|wlan0|android-*)
            is_meaningless=1 ;;
    esac
    if [ "$is_meaningless" = "0" ] && echo "$hostname" | grep -qiE '^[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}'; then
        is_meaningless=1
    fi
    if [ "$is_meaningless" = "1" ] && [ -n "$vendor" ] && [ "$vendor" != "LAA" ] && [ "$vendor" != "Unknown" ] && [ -n "$devtype" ] && [ "$devtype" != "unknown" ]; then
        name=$(auto_name "$vendor" "$devtype")
    fi

    # Create UCI section
    local section=$(uci -q add devicemaster device)
    uci -q set "devicemaster.$section.mac=$mac"
    uci -q set "devicemaster.$section.hostname=$hostname"
    uci -q set "devicemaster.$section.name=$name"
    uci -q set "devicemaster.$section.last_ip=$ip"
    uci -q set "devicemaster.$section.vendor=$vendor"
    uci -q set "devicemaster.$section.type=$devtype"
    uci -q set "devicemaster.$section.discovered=1"
    uci -q set "devicemaster.$section.discovered_at=$(date +%s)"
    uci -q set "devicemaster.$section.blocked=0"
    uci -q commit devicemaster

    log_msg "Registered $mac as $vendor ($devtype) at $ip"

    # Sync to dnsmasq static lease (via dedicated script to avoid index bugs)
    # Run synchronously - DHCP event handler must complete before returning to dnsmasq
    if [ -n "$hostname" ] && [ -n "$ip" ]; then
        /usr/libexec/devicemaster/sync_hostname.sh "$mac" "$hostname" "$ip" >/dev/null 2>&1
    fi
}

# ============================================================
# DHCP event handler (called by dnsmasq)
# ============================================================
main() {
    local action="$1"
    local mac="$2"
    local ip="$3"
    local hostname="$4"

    # Lowercase MAC - must work without external commands (dnsmasq jail has no tr/awk)
    # Use printf + sed as fallback; if sed also unavailable, skip (non-critical for DHCP events)
    mac=$(printf '%s' "$mac" 2>/dev/null | sed 's/A/a/g;s/B/b/g;s/C/c/g;s/D/d/g;s/E/e/g;s/F/f/g' 2>/dev/null)
    [ -z "$mac" ] && mac="$2"
    [ "$action" != "add" ] && exit 0
    [ -z "$mac" ] && exit 0
    [ "$mac" = "00:00:00:00:00:00" ] && exit 0

    # Filter out APIPA (169.254.x.x) self-assigned addresses
    # These are NOT real DHCP addresses - iOS devices generate them before disconnecting
    case "$ip" in
        169.254.*) log_msg "Ignored APIPA address for $mac ($ip)"; exit 0 ;;
    esac

    if mac_exists_in_uci "$mac"; then
        log_msg "Updated last_ip for $mac -> $ip"
        exit 0
    fi

    log_msg "New device: $mac ($hostname) at $ip"
    register_device "$mac" "$ip" "$hostname"
}

# ============================================================
# Discover mode: batch register all ARP devices
# ============================================================
discover_all() {
    local arp_tmp="/tmp/dm_discover_arp"
    awk 'NR>1 && $4!="00:00:00:00:00:00" && $3!="0x0" {print $1, $4}' /proc/net/arp 2>/dev/null > "$arp_tmp"

    while read -r ip mac; do
        [ -z "$mac" ] && continue
        mac=$(echo "$mac" | tr '[:upper:]' '[:lower:]')

        local idx=0
        local found=0
        while uci -q get "devicemaster.@device[$idx].mac" >/dev/null 2>&1; do
            local stored=$(uci -q get "devicemaster.@device[$idx].mac")
            if [ "$stored" = "$mac" ]; then
                found=1
                uci -q set "devicemaster.@device[$idx].last_ip=$ip"
                break
            fi
            idx=$((idx + 1))
        done

        if [ "$found" = "0" ]; then
            local hostname=$(grep -i "$mac" /tmp/dhcp.leases 2>/dev/null | awk '{print $4}')
            register_device "$mac" "$ip" "$hostname"
        fi
    done < "$arp_tmp"
    rm -f "$arp_tmp"

    uci -q commit devicemaster 2>/dev/null
}

# ============================================================
# Re-identify mode: re-run 7-level chain for existing devices
# ============================================================
reidentify_all() {
    local idx=0
    local fixed=0
    while uci -q get "devicemaster.@device[$idx].mac" >/dev/null 2>&1; do
        local mac=$(uci -q get "devicemaster.@device[$idx].mac")
        local old_vendor=$(uci -q get "devicemaster.@device[$idx].vendor")
        local old_type=$(uci -q get "devicemaster.@device[$idx].type")
        local hostname=$(uci -q get "devicemaster.@device[$idx].hostname")
        local ip=$(uci -q get "devicemaster.@device[$idx].last_ip")
        local manual=$(uci -q get "devicemaster.@device[$idx].manual")
        local discovered=$(uci -q get "devicemaster.@device[$idx].discovered")

        # Skip manually annotated devices (user has set vendor/type by hand)
        if [ "$manual" = "1" ]; then
            idx=$((idx + 1))
            continue
        fi

        # Refresh hostname from DHCP leases if empty
        if [ -z "$hostname" ]; then
            hostname=$(grep -i "$mac" /tmp/dhcp.leases 2>/dev/null | awk '{print $4}')
            [ "$hostname" = "*" ] && hostname=""
            if [ -n "$hostname" ]; then
                uci -q set "devicemaster.@device[$idx].hostname=$hostname"
            fi
        fi

        local new_vendor=$(identify_vendor "$mac" "$ip" "$hostname")
        local new_type=$(identify_type "$mac" "$ip" "$hostname" "$new_vendor")

        local changed=0
        if [ "$new_vendor" != "$old_vendor" ] && [ -n "$new_vendor" ]; then
            uci -q set "devicemaster.@device[$idx].vendor=$new_vendor"
            changed=1
        fi
        if [ "$new_type" != "$old_type" ] && [ -n "$new_type" ]; then
            uci -q set "devicemaster.@device[$idx].type=$new_type"
            changed=1
        fi

        # Auto-generate name only if hostname is meaningless AND name is not set
        # Meaningless: empty, *, -, MAC address, unknown, wlan0, etc.
        local old_name=$(uci -q get "devicemaster.@device[$idx].name")
        local old_hostname=$(uci -q get "devicemaster.@device[$idx].hostname")

        # If hostname is now meaningful but name was auto-generated (vendor-type format),
        # clear the auto-name so display falls back to hostname
        if [ -n "$old_name" ] && [ -n "$old_hostname" ] && [ "$manual" != "1" ]; then
            local is_meaningless=0
            case "$old_hostname" in
                ""|"*"|"-"|unknown|wlan0|android-*)
                    is_meaningless=1 ;;
            esac
            if [ "$is_meaningless" = "0" ] && echo "$old_hostname" | grep -qiE '^[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}'; then
                is_meaningless=1
            fi
            # Hostname is meaningful, auto-name should be cleared
            if [ "$is_meaningless" = "0" ]; then
                uci -q delete "devicemaster.@device[$idx].name"
                old_name=""
                changed=1
            fi
        fi

        if [ -z "$old_name" ]; then
            local is_meaningless=0
            case "$old_hostname" in
                ""|"*"|"-"|unknown|wlan0|android-*)
                    is_meaningless=1 ;;
            esac
            # Check if hostname looks like a MAC address
            if [ "$is_meaningless" = "0" ] && echo "$old_hostname" | grep -qiE '^[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}'; then
                is_meaningless=1
            fi
            # Only auto-name when hostname is meaningless AND we have vendor+type
            if [ "$is_meaningless" = "1" ] && [ -n "$new_vendor" ] && [ "$new_vendor" != "LAA" ] && [ "$new_vendor" != "Unknown" ] && [ -n "$new_type" ] && [ "$new_type" != "unknown" ]; then
                local new_name=$(auto_name "$new_vendor" "$new_type")
                if [ -n "$new_name" ]; then
                    uci -q set "devicemaster.@device[$idx].name=$new_name"
                    changed=1
                fi
            fi
        fi

        if [ "$changed" = "1" ]; then
            log_msg "Re-identified $mac: $old_vendor/$old_type -> $new_vendor/$new_type"
            fixed=$((fixed + 1))
        fi
        idx=$((idx + 1))
    done
    uci -q commit devicemaster 2>/dev/null
    echo "Re-identified $fixed devices"
}

# ============================================================
# Entry point
# ============================================================
case "$1" in
    discover)   discover_all; exit 0 ;;
    reidentify) reidentify_all; exit 0 ;;
    *)          main "$@" ;;
esac
