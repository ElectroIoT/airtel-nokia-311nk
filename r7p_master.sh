#!/bin/sh
# ==============================================================================
# Nokia FastMile 5G Receiver (AOD311NK / 5G32-A) Reliance Jio 5G Master Unblock
# Completely & Permanently Eradicates Airtel Restrictions, ACS, & EoGRE Hijack
# Runs as an AIC Detector Daemon on every boot via /configs/aic_conf.json
# ==============================================================================

LOG="/tmp/r7p.log"
exec 1>>$LOG 2>&1

echo "=========================================="
echo "[r7p] Master Unblock Daemon Started: $(date)"
echo "[r7p] Uptime: $(cat /proc/uptime 2>/dev/null)"
echo "=========================================="

send_smd11() {
  local cmd="$1"
  exec 3<>/dev/smd11 2>/dev/null
  echo -e "${cmd}\r" >&3 2>/dev/null
  cat <&3 >/dev/null 2>&1 &
  local pid=$!
  sleep 0.5
  kill -9 $pid 2>/dev/null
  exec 3>&- 2>/dev/null
}

# ------------------------------------------------------------------------------
# 0. Neutralize Watchdogs, PCD Deadman Switches & Reboot Daemons
# ------------------------------------------------------------------------------
echo "[r7p] Neutralizing hardware watchdogs, PCD traps, and reboot daemons..."
cat << 'DUMMY_EOF' > /systemrw/dummy_ok.sh
#!/bin/sh
exit 0
DUMMY_EOF
chmod 755 /systemrw/dummy_ok.sh

touch /tmp/stop_watchdog
touch /tmp/pcd_stop
rm -f /tmp/pcd_started

# Bind mount neutral script over all reboot-triggering scripts
mount --bind /systemrw/dummy_ok.sh /bin/wd_pcdtest.sh 2>/dev/null
mount --bind /systemrw/dummy_ok.sh /etc/watchdog.d/wdtest.sh 2>/dev/null
mount --bind /systemrw/dummy_ok.sh /bin/postaction.sh 2>/dev/null

# Keep PCD rapid-reboot detector disarmed in persistent storage
printf '0:700\n0:700\n0:700\n0:700\n0:700\n' > /configs/uptime 2>/dev/null

# ------------------------------------------------------------------------------
# 1. SSH & Telnet Permanent Unconditional Access
# ------------------------------------------------------------------------------
echo "[r7p] Securing SSH and Telnet access..."
mkdir -p /home/root/.ssh /var/run/sshd /configs/cert
if [ -f /configs/cert/authorized_key.root ]; then
  cat /configs/cert/authorized_key.root > /home/root/.ssh/authorized_keys
  chmod 700 /home/root /home/root/.ssh 2>/dev/null
  chmod 600 /home/root/.ssh/authorized_keys 2>/dev/null
fi

# Prepare persistent unlocked sshd_config_ext
if [ ! -f /systemrw/sshd_config_ext ]; then
  cp -f /etc/ssh/sshd_config_ext /systemrw/sshd_config_ext
fi
sed -i 's/PermitRootLogin.*/PermitRootLogin yes/g' /systemrw/sshd_config_ext 2>/dev/null
sed -i 's/AllowUsers.*/AllowUsers AOD311NK root/g' /systemrw/sshd_config_ext 2>/dev/null
grep -q '^PasswordAuthentication yes' /systemrw/sshd_config_ext 2>/dev/null || echo 'PasswordAuthentication yes' >> /systemrw/sshd_config_ext
grep -q '^PermitRootLogin yes' /systemrw/sshd_config_ext 2>/dev/null || echo 'PermitRootLogin yes' >> /systemrw/sshd_config_ext
mount --bind /systemrw/sshd_config_ext /etc/ssh/sshd_config_ext 2>/dev/null

iptables -I INPUT 1 -p tcp --dport 22 -j ACCEPT 2>/dev/null
ip6tables -I INPUT 1 -p tcp --dport 22 -j ACCEPT 2>/dev/null
iptables -I INPUT 1 -p tcp --dport 23 -j ACCEPT 2>/dev/null
ip6tables -I INPUT 1 -p tcp --dport 23 -j ACCEPT 2>/dev/null

pidof telnetd >/dev/null 2>&1 || setsid /bin/busybox telnetd -l /bin/sh >/dev/null 2>&1 &
killall sshd 2>/dev/null
/usr/sbin/sshd -p 22 -f /etc/ssh/sshd_config_ext 2>/dev/null

# ------------------------------------------------------------------------------
# 2. Eradicate Airtel Remote Control, ACS (TR-069) & Corteca USP (TR-369)
# ------------------------------------------------------------------------------
echo "[r7p] Neutralizing Airtel TR-069 ACS & Corteca USP remote management..."

# Kill running USP agent
killall -9 nuspd 2>/dev/null

# Disable CWMP & TR-369 USP agent in Nokia cfgmgr
cfgcli -s InternetGatewayDevice.ManagementServer.EnableCWMP false 2>/dev/null
cfgcli -s InternetGatewayDevice.ManagementServer.X_ALU-COM_TR369Agent_Enable false 2>/dev/null
cfgcli -s InternetGatewayDevice.ManagementServer.URL "http://127.0.0.1:8080" 2>/dev/null
cfgcli --save-flash-now 2>/dev/null

# Clear USP primary controller
echo "none" > /configs/uspprimController 2>/dev/null

# Sinkhole all Airtel ACS and Corteca management domains locally
for host in \
  "verne-shard4.corteca.airtelbroadband.in" \
  "corteca.airtelbroadband.in" \
  "acs.airtelbroadband.in" \
  "testacs.airtelbroadband.in" \
  "gre.fwabng.airtelbroadband.in" \
  "airtelbroadband.in" \
  "airtel.in" \
  "airtel.com"; do
  grep -q "$host" /etc/hosts 2>/dev/null || echo "127.0.0.1 $host" >> /etc/hosts
  grep -q "$host" /etc/hosts 2>/dev/null || echo "::1 $host" >> /etc/hosts
done

# Block outgoing management traffic to Airtel ports
iptables -I OUTPUT 1 -p tcp --dport 8103 -j REJECT 2>/dev/null
iptables -I OUTPUT 1 -p tcp --dport 5683 -j REJECT 2>/dev/null
iptables -I OUTPUT 1 -p tcp --dport 8883 -j REJECT 2>/dev/null

# ------------------------------------------------------------------------------
# 3. LAN Untagged Bridging (Allow any PC / Wi-Fi Router without VLAN 1999)
# ------------------------------------------------------------------------------
echo "[r7p] Ensuring LAN bridge supports eth0 & eth0.1999..."
ip addr del 169.254.51.1/24 dev eth0 2>/dev/null
echo 0 > /proc/sys/net/bridge/bridge-nf-call-iptables 2>/dev/null
echo 0 > /proc/sys/net/bridge/bridge-nf-call-ip6tables 2>/dev/null
echo 0 > /proc/sys/net/bridge/bridge-nf-call-arptables 2>/dev/null

brctl delif br_gre eth0 2>/dev/null
brctl addif bridge0 eth0 2>/dev/null

iptables -C INPUT -p udp --dport 67:68 -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -p udp --dport 67:68 -j ACCEPT 2>/dev/null
iptables -C INPUT -i bridge0 -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -i bridge0 -j ACCEPT 2>/dev/null
iptables -C INPUT -i eth0 -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -i eth0 -j ACCEPT 2>/dev/null
iptables -C FORWARD -i bridge0 -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 -i bridge0 -j ACCEPT 2>/dev/null
iptables -C FORWARD -o bridge0 -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 -o bridge0 -j ACCEPT 2>/dev/null
iptables -C FORWARD -i eth0 -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 -i eth0 -j ACCEPT 2>/dev/null
iptables -C FORWARD -o eth0 -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 -o eth0 -j ACCEPT 2>/dev/null

# ------------------------------------------------------------------------------
# 4. Remove Airtel Web UI Branding & Prepare Web SSL
# ------------------------------------------------------------------------------
echo "[r7p] Removing Airtel web branding & preparing Web server..."
mkdir -p /configs/airtel_branding_bak
for brand_file in /configs/colors.css /configs/logo_login.svg /configs/logo_side.svg; do
  [ -f "$brand_file" ] && mv -f "$brand_file" /configs/airtel_branding_bak/ 2>/dev/null
done

# Decrypt SSL private key for lighttpd HTTPS (port 443)
if [ ! -f /tmp/key.pem ] && [ -f /configs/download/key.pem ]; then
  /usr/bin/LighttpdMgr /configs/download/key.pem /tmp/key.pem 2>/dev/null
  chown webServer:root /tmp/key.pem 2>/dev/null
fi

# Mount unlocked Adminuser permissions if present
if [ -f /systemrw/Adminuser.json ]; then
  mount --bind /systemrw/Adminuser.json /etc/configs/rbac/AdminUser/FWAG/Adminuser.json 2>/dev/null
  mount --bind /systemrw/Adminuser.json /etc/configs/rbac/NormalUser/FWAG/Normaluser.json 2>/dev/null
fi

# ------------------------------------------------------------------------------
# 5. Patch Persistent QCMAP Configuration (No EoGRE, Jio APN, WWAN First)
# ------------------------------------------------------------------------------
echo "[r7p] Ensuring QCMAP XML configurations are fully patched..."
patch_qcmap() {
  local target="$1"
  [ -f "$target" ] || return
  cp -f "$target" /tmp/qcmap_edit.xml
  sed -i "s/<FirstPreferredBackhaul>.*<\/FirstPreferredBackhaul>/<FirstPreferredBackhaul>wwan<\/FirstPreferredBackhaul>/g" /tmp/qcmap_edit.xml
  sed -i "s/<FifthPreferredBackhaul>.*<\/FifthPreferredBackhaul>/<FifthPreferredBackhaul>bt-pan<\/FifthPreferredBackhaul>/g" /tmp/qcmap_edit.xml
  sed -i "s/<EoGREProfile1>1<\/EoGREProfile1>/<EoGREProfile1>0<\/EoGREProfile1>/g" /tmp/qcmap_edit.xml
  sed -i "s/<EoGREProfile1TunnelCount>1<\/EoGREProfile1TunnelCount>/<EoGREProfile1TunnelCount>0<\/EoGREProfile1TunnelCount>/g" /tmp/qcmap_edit.xml
  sed -i "s/<EoGREConfiguredForPDN>1<\/EoGREConfiguredForPDN>/<EoGREConfiguredForPDN>0<\/EoGREConfiguredForPDN>/g" /tmp/qcmap_edit.xml
  sed -i "s/<EoGRETunneledTraffic>3<\/EoGRETunneledTraffic>/<EoGRETunneledTraffic>0<\/EoGRETunneledTraffic>/g" /tmp/qcmap_edit.xml
  sed -i "s/<EoGRENonTunneledTraffic>0<\/EoGRENonTunneledTraffic>/<EoGRENonTunneledTraffic>1<\/EoGRENonTunneledTraffic>/g" /tmp/qcmap_edit.xml
  sed -i "s/<APN_Name>.*<\/APN_Name>/<APN_Name>jionet<\/APN_Name>/g" /tmp/qcmap_edit.xml
  sed -i "s/<APN_Name \/>/<APN_Name>jionet<\/APN_Name>/g" /tmp/qcmap_edit.xml
  sed -i "s/<AutoConnect>0<\/AutoConnect>/<AutoConnect>1<\/AutoConnect>/g" /tmp/qcmap_edit.xml
  cat /tmp/qcmap_edit.xml > "$target"
  rm -f /tmp/qcmap_edit.xml
}

for cfg in \
  /systemrw/data/mobileap_cfg_b2c_494_1.xml \
  /systemrw/data/mobileap_cfg.xml \
  /systemrw/data/mobileap_cfg_460_1.xml \
  /etc/data/mobileap_cfg.xml; do
  patch_qcmap "$cfg"
done

# ------------------------------------------------------------------------------
# 6. Continuous Jio 5G Watchdog Daemon (Runs in Foreground for AIC)
# ------------------------------------------------------------------------------
echo "[r7p-watchdog] Entering continuous watchdog loop..."
echo "[r7p] Switching Qualcomm SDX65 to physical SIM Slot 1 (Jio USIM)..."
send_smd11 "AT+QUIMSLOT=1"
sleep 1
send_smd11 "AT+CFUN=1"

while true; do
  # 1. Maintain Watchdog neutralization & disarm flags
  brctl show br_gre 2>/dev/null | grep -q eth0 && { brctl delif br_gre eth0 2>/dev/null; brctl addif bridge0 eth0 2>/dev/null; }
  touch /tmp/stop_watchdog 2>/dev/null
  touch /tmp/pcd_stop 2>/dev/null
  mount | grep -q wdtest.sh || mount --bind /systemrw/dummy_ok.sh /etc/watchdog.d/wdtest.sh 2>/dev/null
  mount | grep -q wd_pcdtest.sh || mount --bind /systemrw/dummy_ok.sh /bin/wd_pcdtest.sh 2>/dev/null
  mount | grep -q postaction.sh || mount --bind /systemrw/dummy_ok.sh /bin/postaction.sh 2>/dev/null

  # 2. Maintain SSH & Telnet access
  mount | grep -q sshd_config_ext || mount --bind /systemrw/sshd_config_ext /etc/ssh/sshd_config_ext 2>/dev/null
  iptables -C INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -p tcp --dport 22 -j ACCEPT 2>/dev/null
  iptables -C INPUT -p tcp --dport 23 -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -p tcp --dport 23 -j ACCEPT 2>/dev/null
  pidof telnetd >/dev/null 2>&1 || setsid /bin/busybox telnetd -l /bin/sh >/dev/null 2>&1 &
  pidof sshd >/dev/null 2>&1 || (/usr/sbin/sshd -p 22 -f /etc/ssh/sshd_config_ext 2>/dev/null || kill -HUP $(pidof sshd) 2>/dev/null)

  # 3. Ensure Lighttpd web server is running on port 443
  if [ ! -f /tmp/key.pem ] && [ -f /configs/download/key.pem ]; then
    /usr/bin/LighttpdMgr /configs/download/key.pem /tmp/key.pem 2>/dev/null
    chown webServer:root /tmp/key.pem 2>/dev/null
  fi
  pidof lighttpd >/dev/null 2>&1 || (/bin/lighttpd.sh -f /etc/hb/lighttpd.conf -m /webs/config/lib -D &)

  # 4. Kill nuspd if re-spawned
  pidof nuspd >/dev/null 2>&1 && killall -9 nuspd 2>/dev/null

  # 5. Check cellular interface
  WAN_IF=""
  if ip a show rmnet_data1 2>/dev/null | grep -q 'inet '; then
    WAN_IF="rmnet_data1"
  elif ip a show rmnet_data0 2>/dev/null | grep -q 'inet '; then
    WAN_IF="rmnet_data0"
  fi

  if [ -z "$WAN_IF" ]; then
    echo "[r7p-watchdog] WAN down, verifying SIM Slot 1 & radio..."
    send_smd11 "AT+QUIMSLOT=1"
    sleep 1
    send_smd11 "AT+CFUN=1"
    systemctl restart QCMAP_ConnectionManagerd 2>/dev/null
    sleep 8
  else
    # 6. Ensure default route via carrier gateway
    ip route show | grep -q "default .* $WAN_IF" || ip route replace default via 192.0.0.1 dev "$WAN_IF" mtu 1372 2>/dev/null

    # 7. Enable IP Forwarding on kernel & all interfaces
    echo 1 > /proc/sys/net/ipv4/ip_forward
    echo 1 > /proc/sys/net/ipv6/conf/all/forwarding
    for f in /proc/sys/net/ipv4/conf/*/forwarding; do [ "$(cat "$f" 2>/dev/null)" = "1" ] || echo 1 > "$f"; done
    for f in /proc/sys/net/ipv6/conf/*/forwarding; do [ "$(cat "$f" 2>/dev/null)" = "1" ] || echo 1 > "$f"; done
    
    # 8. Firewall forwarding & NAT masquerade
    iptables -C FORWARD -i bridge0 -o "$WAN_IF" -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 -i bridge0 -o "$WAN_IF" -j ACCEPT 2>/dev/null
    iptables -C FORWARD -i "$WAN_IF" -o bridge0 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 -i "$WAN_IF" -o bridge0 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null
    iptables -t nat -C POSTROUTING -o "$WAN_IF" -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -o "$WAN_IF" -j MASQUERADE 2>/dev/null

    # 9. Clear Nokia status blocks & illuminate green LED
    ubus call Nokia.GenericService SetCellularAccessConfig '{"originator":"admin","paralist":[{"AccessModeNo":3,"NetworkSlicingEnable":false}]}' 2>/dev/null
    sysevent set CellularMgr_Block false 2>/dev/null
    sysevent set InitMgr_Block false 2>/dev/null
    sysevent set X_ALU_COM_AllowedForwarding_Block false 2>/dev/null
    /bin/send_led_event.sh -e 302 2>/dev/null
    /bin/send_led_event.sh -e 1102 2>/dev/null
    /bin/send_led_event.sh -e 1601 -a '{"Event":"2"}' 2>/dev/null
    /bin/send_led_event.sh -e 5817 -a '{"ActiveWAN":"Cellular"}' 2>/dev/null
  fi

  sleep 10
done
