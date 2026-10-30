# SPDX-License-Identifier: GPL-2.0-only
#
# Open-Box 闭源二进制分发打包
# 源码仓库: https://github.com/liandu2024/Open-Box
# Open-Box 自有程序为闭源专有软件,本 Makefile 仅负责将官方发布的
# arm64 二进制 tarball 下载并安装到固件中,不涉及编译。
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-openbox
PKG_VERSION:=0.1.378
PKG_RELEASE:=1

PKG_SOURCE:=open-box-v$(PKG_VERSION)-linux-arm64.tar.gz
PKG_SOURCE_URL:=https://github.com/liandu2024/Open-Box/releases/download/v$(PKG_VERSION)/
PKG_HASH:=c03ae5b2c0a556a90b460b4e8af7242a8013d7cb7bea3dea85106e7c25373664

PKG_BUILD_DIR:=$(BUILD_DIR)/open-box-$(PKG_VERSION)

PKG_MAINTAINER:=Open-Box
PKG_LICENSE:=Proprietary

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-openbox
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Web Servers/Proxies
  TITLE:=Open-Box - Transparent Proxy (sing-box + Node, binary distribution)
  URL:=https://github.com/liandu2024/Open-Box
  DEPENDS:=+kmod-tun +kmod-nft-queue +kmod-nft-nat +kmod-veth +ip-full +ca-bundle
endef

define Package/luci-app-openbox/description
  Open-Box 一体化透明代理。安装包内置 Open-Box、sing-box 内核、
  Node 运行时以及完整 GeoSite / GeoIP 数据,通过浏览器面板完成
  订阅、节点、分流、DNS 和防火墙设置。
  本包为官方 arm64 二进制分发,安装到 /opt/open-box,
  并提供 LuCI 兜底页面(服务 -> Open-Box)。
  内核依赖(kmod-tun/kmod-nft-queue/kmod-nft-nat/kmod-veth)
  必须编译进固件,SNAPSHOT 无法在线安装。
endef

# 二进制分发,无需编译,也无需 make install(tarball 内无 Makefile)
define Build/Compile
endef

define Build/Install
endef

define Package/luci-app-openbox/install
	# 主体安装到 /opt/open-box(tarball 解开后直接就是 open-box 目录内容)
	$(INSTALL_DIR) $(1)/opt/open-box
	$(CP) $(PKG_BUILD_DIR)/* $(1)/opt/open-box/

	# 运行时数据目录(面板端口、通道等)
	$(INSTALL_DIR) $(1)/opt/open-box/data

	# procd 服务脚本
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/openwrt/initd/openbox $(1)/etc/init.d/openbox
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/openwrt/initd/openbox-panel $(1)/etc/init.d/openbox-panel

	# 命令行入口
	$(INSTALL_DIR) $(1)/usr/bin
	ln -sf /opt/open-box/openwrt/bin/open-box $(1)/usr/bin/open-box

	# LuCI 视图(JS)
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/openbox
	$(CP) $(PKG_BUILD_DIR)/openwrt/luci/htdocs/luci-static/resources/view/openbox/*.js \
		$(1)/www/luci-static/resources/view/openbox/
	chmod 644 $(1)/www/luci-static/resources/view/openbox/*.js 2>/dev/null || true

	# LuCI 菜单
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/openwrt/luci/root/usr/share/luci/menu.d/luci-app-openbox.json \
		$(1)/usr/share/luci/menu.d/

	# LuCI ACL(rpcd 权限)
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/openwrt/luci/root/usr/share/rpcd/acl.d/luci-app-openbox.json \
		$(1)/usr/share/rpcd/acl.d/
endef

# 配置数据目录升级时保留
define Package/luci-app-openbox/conffiles
/opt/open-box/data
endef

$(eval $(call BuildPackage,luci-app-openbox))
