# OpenWrt DeviceMaster

增强型 OpenWrt 设备管理插件 - 支持最新版 OpenWrt 24.1 / 25.12

## 功能特性

### 🔍 多维设备识别
- **MAC OUI 查询**: 自动识别设备厂商（Apple、Samsung、Xiaomi、Huawei 等）
- **设备类型分类**: 自动分类为手机、电脑、IoT设备、网络设备
- **智能图标**: 根据设备类型自动分配图标

### 📝 设备管理
- **自定义命名**: 为设备设置自定义名称
- **双向同步**: 名称自动同步到 dnsmasq，在原生设备列表中显示
- **设备分组**: 将设备组织到自定义分组中
- **备注功能**: 为设备添加备注信息

### 📊 流量监控
- **实时带宽**: 显示每个设备的实时上下行带宽
- **连接统计**: 显示设备的活跃连接数
- **历史记录**: 保留设备在线/离线历史

### 🛡️ 流量控制
- **一键断网**: 通过 nftables 快速屏蔽设备
- **带宽限制**: 使用 tc (Traffic Control) 限制设备网速
- **定时规则**: 设置定时断网/限速规则

## 编译方法

### 方法一：集成到 OpenWrt 源码编译

```bash
# 1. 进入 OpenWrt 源码目录
cd openwrt

# 2. 复制插件到 package 目录
cp -r luci-app-devicemaster feeds/luci/applications/

# 3. 更新 feeds
./scripts/feeds update luci
./scripts/feeds install luci-app-devicemaster

# 4. 配置编译选项
make menuconfig
# 选择 LuCI -> Applications -> luci-app-devicemaster

# 5. 编译
make package/luci-app-devicemaster/compile V=s
```

### 方法二：使用 OpenWrt SDK

```bash
# 1. 下载对应版本的 SDK
# 从 https://downloads.openwrt.org/ 选择对应版本

# 2. 解压并进入 SDK 目录
tar xf openwrt-sdk-*.tar.xz
cd openwrt-sdk-*

# 3. 复制插件源码
cp -r luci-app-devicemaster package/

# 4. 编译
make package/luci-app-devicemaster/compile V=s
```

## 安装方法

### 从 IPK 安装

```bash
# 上传 ipk 文件到路由器
scp luci-app-devicemaster_*.ipk root@192.168.1.1:/tmp/

# 安装
opkg install /tmp/luci-app-devicemaster_*.ipk

# 重启 rpcd 和 uhttpd
/etc/init.d/rpcd restart
/etc/init.d/uhttpd restart
```

### 手动安装

```bash
# 复制文件到路由器
scp -r root/* root@192.168.1.1:/
scp -r luasrc/* root@192.168.1.1:/usr/lib/lua/luci/

# 设置权限
chmod +x /etc/init.d/devicemaster
chmod +x /usr/libexec/devicemaster/*

# 运行初始化脚本
sh /etc/uci-defaults/90_devicemaster

# 启动服务
/etc/init.d/devicemaster enable
/etc/init.d/devicemaster start
```

## 使用说明

### 访问界面

安装后，在 LuCI 界面中访问：
- **网络 → Device Master → 设备列表**: 查看和管理所有设备
- **网络 → Device Master → 分组**: 管理设备分组
- **网络 → Device Master → 设置**: 配置插件选项

### 设备操作

1. **编辑设备**: 点击设备卡片的"编辑"按钮，设置自定义名称、分组和备注
2. **屏蔽设备**: 点击"屏蔽"按钮，立即断开该设备的网络连接
3. **限速设备**: 点击"限速"按钮，输入限速值（如 1mbit, 512kbit）

### 分组管理

1. 创建分组并设置图标和颜色
2. 在设备编辑界面将设备分配到分组
3. 可以为分组设置默认限速规则

## 依赖项

```
luci-lib-base
luci-lib-jsonc
libubus-lua
ipset
nftables
kmod-sched-core
tc-full
```

## 目录结构

```
luci-app-devicemaster/
├── Makefile                          # OpenWrt 编译配置
├── luasrc/
│   ├── controller/
│   │   └── devicemaster.lua          # 控制器（API 端点）
│   ├── model/cbi/
│   │   └── devicemaster/
│   │       └── settings.lua          # 设置页面模型
│   └── view/
│       └── devicemaster/
│           ├── devices.htm           # 设备列表视图
│           └── groups.htm            # 分组管理视图
├── root/
│   ├── etc/
│   │   ├── config/
│   │   │   └── devicemaster          # UCI 配置文件
│   │   ├── init.d/
│   │   │   └── devicemaster          # 服务初始化脚本
│   │   └── uci-defaults/
│   │       └── 90_devicemaster       # 安装后初始化脚本
│   └── usr/
│       ├── libexec/devicemaster/
│       │   ├── devicemasterd         # 主守护进程
│       │   ├── device_collector.sh   # 设备数据采集
│       │   ├── traffic_monitor.sh    # 流量监控
│       │   └── traffic_control.sh    # 流量控制
│       └── share/
│           ├── devicemaster/
│           │   └── oui.txt           # OUI 厂商数据库
│           └── rpcd/acl.d/
│               └── luci-app-devicemaster.json  # ACL 配置
└── po/
    └── zh_Hans/
        └── devicemaster.po           # 中文翻译
```

## 技术架构

```
┌─────────────────────────────────────────────────────────────┐
│                    LuCI Frontend (JS/HTML)                   │
│                  devices.htm / groups.htm                    │
└─────────────────────────┬───────────────────────────────────┘
                          │ HTTP/JSON-RPC
┌─────────────────────────▼───────────────────────────────────┐
│                 LuCI Controller (Lua)                        │
│              devicemaster.lua (API Handler)                  │
└─────────────────────────┬───────────────────────────────────┘
                          │ Shell Exec
┌─────────────────────────▼───────────────────────────────────┐
│                  Backend Scripts (Shell)                     │
│  ┌────────────────┐ ┌────────────────┐ ┌────────────────┐   │
│  │device_collector│ │traffic_monitor │ │traffic_control │   │
│  │     .sh        │ │     .sh        │ │     .sh        │   │
│  └───────┬────────┘ └───────┬────────┘ └───────┬────────┘   │
└──────────┼──────────────────┼──────────────────┼────────────┘
           │                  │                  │
┌──────────▼──────────────────▼──────────────────▼────────────┐
│                    System Resources                          │
│  /tmp/dhcp.leases  /proc/net/arp  nftables  tc  UCI         │
└─────────────────────────────────────────────────────────────┘
```

## 常见问题

### Q: 设备列表为空？
A: 确保 dnsmasq 正在运行，且有设备已连接到路由器。

### Q: 无法屏蔽设备？
A: 检查 nftables 是否正常工作：`nft list tables`

### Q: 限速不生效？
A: 确保 tc 和相关内核模块已安装：`opkg install tc-full kmod-sched-core`

### Q: 名称同步不生效？
A: 检查 dnsmasq 配置是否正确写入：`uci show dhcp | grep host`

## 许可证

GPL-2.0-only

## 贡献

欢迎提交 Issue 和 Pull Request！

## 致谢

- OpenWrt 项目
- LuCI 项目
- IEEE OUI 数据库
