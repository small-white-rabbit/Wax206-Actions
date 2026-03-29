DTS_DIR := $(DTS_DIR)/mediatek

DEVICE_VARS += BUFFALO_TRX_MAGIC

define Image/Prepare
	# For UBI we want only one extra block
	rm -f $(KDIR)/ubi_mark
	echo -ne '\xde\xad\xc0\xde' > $(KDIR)/ubi_mark
endef

define Build/bl2
	cat $(STAGING_DIR_IMAGE)/mt7622-$1-bl2.img >> $@
endef

define Build/bl31-uboot
	cat $(STAGING_DIR_IMAGE)/mt7622_$1-u-boot.fip >> $@
endef

define Build/uboot-bin
	cat $(STAGING_DIR_IMAGE)/mt7622_$1-u-boot.bin >> $@
endef

define Build/uboot-fit
	$(TOPDIR)/scripts/mkits.sh \
		-D $(DEVICE_NAME) -o $@.its -k $@ \
		-C $(word 1,$(1)) \
		-a 0x41e00000 -e 0x41e00000 \
		-c "config-1" \
		-A $(LINUX_KARCH) -v u-boot
	PATH=$(LINUX_DIR)/scripts/dtc:$(PATH) mkimage -f $@.its $@.new
	@mv $@.new $@
endef

define Build/mt7622-gpt
	cp $@ $@.tmp 2>/dev/null || true
	ptgen -g -o $@.tmp -a 1 -l 1024 \
		$(if $(findstring sdmmc,$1), \
			-H \
			-t 0x83	-N bl2		-r	-p 512k@512k \
		) \
			-t 0xef	-N fip		-r	-p 2M@2M \
			-t 0x83	-N ubootenv	-r	-p 1M@4M \
				-N recovery	-r	-p 32M@6M \
		$(if $(findstring sdmmc,$1), \
				-N install	-r	-p 7M@38M \
			-t 0x2e -N production		-p $(CONFIG_TARGET_ROOTFS_PARTSIZE)M@45M \
		) \
		$(if $(findstring emmc,$1), \
			-t 0x2e -N production		-p $(CONFIG_TARGET_ROOTFS_PARTSIZE)M@40M \
		)
	cat $@.tmp >> $@
	rm $@.tmp
endef

define Device/netgear_wax206
  $(Device/dsa-migration)
  DEVICE_VENDOR := NETGEAR
  DEVICE_MODEL := WAX206
  DEVICE_DTS := mt7622-netgear-wax206
  DEVICE_DTS_DIR := ../dts
  NETGEAR_ENC_MODEL := WAX206
  NETGEAR_ENC_REGION := US
  DEVICE_PACKAGES := kmod-mt7915-firmware
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  KERNEL_SIZE := 14436k
  IMAGE_SIZE := 262144k
  KERNEL := kernel-bin | lzma | fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb | \
	append-squashfs4-fakeroot
# recovery can also be used with stock firmware web-ui, hence the padding...
  KERNEL_INITRAMFS := kernel-bin | lzma | \
	fit lzma $$(KDIR)/image-$$(firstword $$(DEVICE_DTS)).dtb with-initrd | pad-to 128k
  KERNEL_INITRAMFS_SUFFIX := -recovery.itb
  IMAGES += factory.img
  IMAGE/factory.img := append-kernel | pad-to $$(KERNEL_SIZE) | \
	append-ubi | check-size | netgear-encrypted-factory
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += netgear_wax206
