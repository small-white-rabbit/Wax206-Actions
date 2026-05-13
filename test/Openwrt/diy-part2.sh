#!/bin/bash
#
# WAX206 DIY Part 2 - 修改默认配置
#

# 修改默认 IP 地址
sed -i 's/192.168.1.1/192.168.31.1/g' package/base-files/files/bin/config_generate

# 修改默认主机名
sed -i 's/OpenWrt/WAX206/g' package/base-files/files/bin/config_generate

# 修改默认时区
sed -i "s/timezone='.*'/timezone='CST-8'/g" package/base-files/files/bin/config_generate
sed -i "/timezone='CST-8'/a\\\t\tset system.@system[-1].zonename='Asia/Shanghai'" package/base-files/files/bin/config_generate

# 添加自定义软件包 (如果有)
# mkdir -p package/custom
# git clone https://github.com/example/custom-package package/custom/custom-package

echo "DIY Part 2 完成"
