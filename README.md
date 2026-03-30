**中文** | [上游源代码](https://github.com/P3TERX/Actions-OpenWrt)

该项目仅针对wax206

wax206=openwrt原版固件

fmwax206=采用237大佬的扩容方案，删除、合并backup分区，实际空间近70M【剩余空间=70-固件大小】

gwax206=采用x.lethe大佬的256m全扩容方案，该方案由于机体差异可能会出现问题，如果无法使用可尝试原版或者70M方案

---------------------------

windows下采用nmrpflash方式刷机
nmrpflash命令：

查看有线连接端口/n
nmrpflash.exe -L /n
插电后回车下列命令 /n
nmrpflash.exe -i 端口名 -f 固件名.img -a 192.168.1.11 -A 192.168.1.1 /n

例：nmrpflash.exe -i eth14 -f v1053.img -a 192.168.1.11 -A 192.168.1.1 /n

---------------------------


