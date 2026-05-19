#!/bin/sh
# Manual fix for LAA devices - set descriptive names
# Run on router: ssh root@192.168.31.13

echo "=== 手动修复 LAA 设备名称 ==="

# Device 1: C6:AA:B1:9B:61:6B (192.168.31.102)
uci set devicemaster.@device[1].name='Unknown-LAA-1'
uci set devicemaster.@device[1].vendor='Unknown'
uci set devicemaster.@device[1].type='phone'
uci set devicemaster.@device[1].manual='1'

# Device 2: 2A:6D:46:D5:D5:01 (192.168.31.116)
uci set devicemaster.@device[4].name='Unknown-LAA-2'
uci set devicemaster.@device[4].vendor='Unknown'
uci set devicemaster.@device[4].type='phone'
uci set devicemaster.@device[4].manual='1'

# Device 3: 22:F6:20:4A:70:CC (192.168.31.124)
uci set devicemaster.@device[6].name='Unknown-LAA-3'
uci set devicemaster.@device[6].vendor='Unknown'
uci set devicemaster.@device[6].type='phone'
uci set devicemaster.@device[6].manual='1'

uci commit devicemaster

echo "修复完成！设备已设置为 Unknown-LAA-1/2/3"
echo ""
echo "=== 修复后的设备列表 ==="
uci show devicemaster | grep -A 5 "mac.*C6:AA\|mac.*2A:6D\|mac.*22:F6"
