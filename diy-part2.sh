#!/bin/bash
#
# Copyright (c) 2019-2020 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#

# Modify default IP
#sed -i 's/192.168.1.1/192.168.50.5/g' package/base-files/files/bin/config_generate
#!/bin/bash
#=================================================
# Description: DIY script for Wax206-Actions
# 功能：设置默认IP、WiFi开启及功率调整
#=================================================

# 1. 设置默认IP为 192.168.31.1
sed -i 's/192.168.1.1/192.168.31.1/g' package/base-files/files/bin/config_generate

# 2. 设置主机名（可选）
sed -i 's/OpenWrt/Wax206/g' package/base-files/files/bin/config_generate

# 3. 设置时区为上海
sed -i "s/timezone='.*'/timezone='CST-8'/g" package/base-files/files/bin/config_generate
sed -i "/timezone='CST-8'/a\\\t\tset system.@system[-1].zonename='Asia/Shanghai'" package/base-files/files/bin/config_generate

# 4. 配置WiFi默认开启、无密码、2.4G功率28dBm、国家代码US
mkdir -p files/etc/config/

cat > files/etc/config/wireless <<'EOF'
config wifi-device 'radio0'
    option type 'mac80211'
    option path 'platform/18000000.wmac'
    option channel 'auto'
    option band '2g'
    option htmode 'HT40'
    option txpower '28'
    option country 'US'
    option cell_density '0'

config wifi-iface 'default_radio0'
    option device 'radio0'
    option network 'lan'
    option mode 'ap'
    option ssid 'Wax206_2.4G'
    option encryption 'none'
    option disabled '0'

config wifi-device 'radio1'
    option type 'mac80211'
    option path '1a143000.pcie/pci0000:00/0000:00:00.0/0000:01:00.0'
    option channel 'auto'
    option band '5g'
    option htmode 'HE80'
    option country 'US'
    option cell_density '0'

config wifi-iface 'default_radio1'
    option device 'radio1'
    option network 'lan'
    option mode 'ap'
    option ssid 'Wax206_5G'
    option encryption 'none'
    option disabled '0'
EOF

echo "DIY 配置完成！"
