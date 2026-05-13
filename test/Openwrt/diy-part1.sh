#!/bin/bash
#
# WAX206 DIY Part 1 - 添加自定义软件源
#

# 添加额外的软件源到 feeds.conf.default
# 格式: src-git <name> <url>[;<branch>]

# 添加第三方软件源示例 (取消注释使用)
# echo 'src-git small https://github.com/kenzok8/small-package' >> feeds.conf.default
# echo 'src-git kenzok8 https://github.com/kenzok8/openwrt-packages' >> feeds.conf.default

# 更新 feeds
./scripts/feeds update -a

# 安装所有 feeds
./scripts/feeds install -a

echo "DIY Part 1 完成"
