#!/bin/sh
# Fix LAA device recognition for luci-app-devicemaster
# Run this on the router: ssh root@192.168.31.13 'sh -s' < fix_laa_recognition.sh

echo "=== 修复 LAA 设备识别问题 ==="

# 1. 修复 identify_vendor 函数 - 增强 LAA 设备处理
cat > /tmp/fix_identify.patch << 'PATCH_EOF'
--- a/usr/libexec/devicemaster/event_handler.sh
+++ b/usr/libexec/devicemaster/event_handler.sh
@@ -577,6 +577,24 @@ identify_vendor() {
         fi
     done
 
+    # For LAA devices, try traffic-based detection if no other evidence
+    if [ "$is_laa" = "1" ] && [ -z "$high_vendor" ]; then
+        # Try to detect by traffic ports (Level 7)
+        if [ -n "$ip" ]; then
+            local traffic_type=$(detect_type_by_traffic "$mac")
+            case "$traffic_type" in
+                phone) high_vendor="Mobile Device" ;;
+                pc) high_vendor="Computer" ;;
+                iot) high_vendor="IoT Device" ;;
+            esac
+        fi
+        
+        # If still no vendor, use a generic LAA label
+        if [ -z "$high_vendor" ]; then
+            high_vendor="LAA Device"
+        fi
+    fi
+
     # If HIGH evidence found, return it (overrides L4)
     if [ -n "$high_vendor" ]; then
         echo "$high_vendor"
PATCH_EOF

# 2. 修复 detect_device_type 函数 - 处理 LAA 设备类型
cat > /tmp/fix_type.patch << 'PATCH_EOF'
--- a/usr/libexec/devicemaster/event_handler.sh
+++ b/usr/libexec/devicemaster/event_handler.sh
@@ -474,6 +474,18 @@ auto_name() {
 detect_device_type() {
     local mac="$1"
     local hostname="$2"
     local vendor="$3"
+
+    # Handle LAA devices specially
+    case "$vendor" in
+        "LAA"|"LAA Device"|"Mobile Device")
+            # Try to infer from hostname or traffic
+            local h=$(echo "$hostname" | tr 'A-Z' 'a-z')
+            case "$h" in
+                *iphone*|*ipad*|*android*|*pixel*|*galaxy*|*mi-*|*redmi*) echo "phone"; return ;;
+                *desktop*|*laptop*|*pc*|*macbook*|*surface*) echo "pc"; return ;;
+            esac
+            ;;
+    esac
 
     # Stage 1: Match by vendor
     local v=$(echo "$vendor" | tr 'A-Z' 'a-z')
PATCH_EOF

# 3. 应用修复到 event_handler.sh
echo "备份原文件..."
cp /usr/libexec/devicemaster/event_handler.sh /usr/libexec/devicemaster/event_handler.sh.bak

echo "应用修复..."
# 手动修改 identify_vendor 函数
sed -i '/# If HIGH evidence found, return it (overrides L4)/i\
    # For LAA devices, try to infer from traffic or use generic label\
    if [ "$is_laa" = "1" ] \&\& [ -z "$high_vendor" ]; then\
        high_vendor="LAA Device"\
    fi' /usr/libexec/devicemaster/event_handler.sh

# 修改 detect_device_type 函数，添加 LAA 处理
sed -i '/detect_device_type() {/,/local vendor="\$3"/{s/local vendor="\$3"/local vendor="\$3"\n\n    # Handle LAA devices\n    case "\$vendor" in\n        "LAA"|"LAA Device") echo "unknown"; return ;;\n    esac/}' /usr/libexec/devicemaster/event_handler.sh

echo "修复完成！"
echo ""
echo "=== 重新识别所有设备 ==="
/usr/libexec/devicemaster/event_handler.sh reidentify

echo ""
echo "=== 检查修复结果 ==="
uci show devicemaster | grep -E "(mac|vendor|type)" | grep -A 2 "LAA\|2A:6D:46\|C6:AA:B1\|22:F6:20"
