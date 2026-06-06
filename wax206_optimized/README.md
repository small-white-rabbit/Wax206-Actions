# WAX206 优化版编译脚本

## 📁 文件结构

```
wax206_optimized/
├── config/
│   ├── config.conf      # 集中配置文件（网络、WiFi、编译参数）
│   └── feeds.conf       # feeds 源配置
├── modules/
│   ├── network.sh       # 网络配置模块
│   ├── wifi.sh          # WiFi 配置模块
│   ├── conntrack.sh     # Conntrack 配置模块
│   ├── packages.sh      # 自定义包安装模块
│   ├── distfeeds.sh     # 软件源配置模块
│   └── diy_main.sh      # DIY 主入口
├── deconfig/
│   └── gwax206.config   # 设备编译配置
├── compilecfg/
│   └── gwax206.ini      # 设备源码配置
├── dts/                 # DTS 文件
├── mediatek/image/      # Makefile 文件
├── packages/            # 自定义包
└── build.sh             # 优化版编译脚本
```

## 🎯 优化项

| 优化项 | 描述 | 效果 |
|--------|------|------|
| 配置集中管理 | 所有可配置项集中在 config.conf | 便捷修改 |
| feeds 并行更新 | 使用 xargs -P 并行更新 feeds | 减少 5-10 分钟 |
| feeds 缓存 | 缓存 feeds 目录到 GitHub Actions | 减少 3-5 分钟 |
| 下载并行数增加 | DOWNLOAD_PARALLEL_FACTOR=4 | 减少下载时间 |
| 模块化 DIY | DIY 功能拆分为独立模块 | 易于维护 |

## 📝 使用方法

### 1. 修改配置

编辑 `config/config.conf` 文件：

```bash
# 网络配置
LAN_IP=192.168.31.1
HOSTNAME=Wax206

# WiFi 配置
SSID=Wax206
WIFI_COUNTRY=US
WIFI_POWER=28

# 编译配置
PARALLEL_FACTOR=2
DOWNLOAD_PARALLEL_FACTOR=4
```

### 2. 添加/删除 feeds 源

编辑 `config/feeds.conf` 文件：

```bash
# 正常源（通过 feeds update 更新）
passwall https://github.com/Openwrt-Passwall/openwrt-passwall;main

# 特殊源（手动克隆，以 ! 开头）
!kenzok https://github.com/kenzok8/openwrt-packages.git;master
```

### 3. 运行编译

```bash
./wax206_optimized/build.sh gwax206
```

### 4. GitHub Actions 测试

触发 workflow：`编译优化测试 V2`

## 🔧 模块说明

| 模块 | 功能 | 配置项 |
|------|------|--------|
| network.sh | IP、主机名、时区 | LAN_IP, HOSTNAME, TIMEZONE |
| wifi.sh | SSID、国家、功率 | SSID, WIFI_COUNTRY, WIFI_POWER |
| conntrack.sh | 连接跟踪优化 | CONNTRACK_MAX, CONNTRACK_*_TIMEOUT |
| packages.sh | 自定义插件 | 无（自动复制 packages 目录） |
| distfeeds.sh | 软件源列表 | 无（固定配置） |

## 📊 预期效果

- 编译时间：从 ~50 分钟降至 ~40 分钟
- 配置修改：一处修改，全局生效
- 维护难度：模块化设计，易于扩展