# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2024 OpenWrt-DeviceMaster Project
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-devicemaster
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_MAINTAINER:=OpenWrt-DeviceMaster Team
PKG_LICENSE:=GPL-2.0-only

LUCI_TITLE:=LuCI Device Master - Enhanced Device Management Plugin
LUCI_DEPENDS:=+luci-lib-base +luci-lib-jsonc +libubus-lua +ipset +nftables +kmod-sched-core
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

$(eval $(call BuildPackage,luci-app-devicemaster))
