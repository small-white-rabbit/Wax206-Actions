**中文** | [上游源代码](https://github.com/P3TERX/Actions-OpenWrt)

该项目仅针对wax206，默认添加argon主题、openclash、ttyd

wax206=openwrt原版固件

fmwax206=采用237大佬的扩容方案，删除、合并backup分区，实际空间近70M【剩余空间=70-固件大小】

gwax206=采用x.lethe大佬的256m全扩容方案

---------------------------

diy-part2.sh 修改默认配置信息ip、wifi信息

wrt_core/compilecfg 内修改对应引用源码地址
  ps：默认源码为openwrt官方源码

wrt_core/deconfig 内修改对应config


---------------------------

windows下采用nmrpflash方式刷机


nmrpflash命令：

查看有线连接端口

nmrpflash.exe -L

插电后回车下列命令 

nmrpflash.exe -i 端口名 -f 固件名.itb -a 192.168.1.11 -A 192.168.1.1 


例：nmrpflash.exe -i eth14 -f v1053.img -a 192.168.1.11 -A 192.168.1.1 

PS:尽量使用itb、bin两种格式，img格式非官方固件可能会遇到循环重启。
---------------------------


