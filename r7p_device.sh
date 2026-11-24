#!/bin/sh
# Nokia FastMile 5G Receiver Boot Unblock & Jio True5G SA Master Daemon
(
  mkdir -p /systemrw /configs /home/root/.ssh /configs/cert
  echo -e '#!/bin/sh\nexit 0' > /systemrw/dummy_ok.sh
  chmod 755 /systemrw/dummy_ok.sh

  for target in /bin/action_reboot.sh /bin/postaction.sh /bin/wd_pcdtest.sh /etc/watchdog.d/wdtest.sh; do
    [ -e "$target" ] && mount | grep -q " on $target " || mount --bind /systemrw/dummy_ok.sh "$target" 2>/dev/null
  done

  # Remount configs and tmp as executable for patched daemons
  mount -o remount,exec /configs 2>/dev/null
  mount -o remount,exec /tmp 2>/dev/null

  # Bind-mount patched cfgmgr to ensure /tmp/cfgmgr_socket stays alive for Web UI
  if [ -f /configs/cfgmgr_bin ]; then
    mount | grep -q " on /usr/bin/cfgmgr " || mount --bind /configs/cfgmgr_bin /usr/bin/cfgmgr 2>/dev/null
  fi
  if [ ! -S /tmp/cfgmgr_socket ]; then
    killall -9 cfgmgr 2>/dev/null
    setsid /bin/start_cfgmgr.sh >/tmp/cfgmgr_start.log 2>&1 &
  fi

  touch /tmp/stop_watchdog /tmp/pcd_stop
  printf '0:700\n0:700\n0:700\n0:700\n0:700\n' > /configs/uptime 2>/dev/null

  [ -f /configs/cert/authorized_key.root ] && cp -f /configs/cert/authorized_key.root /home/root/.ssh/authorized_keys
  chmod 700 /home/root/.ssh 2>/dev/null
  chmod 600 /home/root/.ssh/authorized_keys 2>/dev/null

  sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config_ext 2>/dev/null
  sed -i 's/^AllowUsers.*/AllowUsers AOD311NK root/' /etc/ssh/sshd_config_ext 2>/dev/null
  grep -q '^PasswordAuthentication yes' /etc/ssh/sshd_config_ext 2>/dev/null || echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config_ext

  if [ -s /configs/cert/root_hash ]; then
    H=$(cat /configs/cert/root_hash)
    grep -q "^root:$H:" /etc/shadow 2>/dev/null || sed -i "s|^root:[^:]*:|root:$H:|" /etc/shadow 2>/dev/null
  fi

  iptables -I INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null
  iptables -I INPUT -p tcp --dport 23 -j ACCEPT 2>/dev/null
  pidof telnetd >/dev/null 2>&1 || setsid /bin/busybox telnetd -l /bin/sh >/dev/null 2>&1 &
  kill -HUP $(pidof sshd) 2>/dev/null || /usr/sbin/sshd -p 22 -f /etc/ssh/sshd_config_ext 2>/dev/null

  killall -9 nuspd 2>/dev/null
  echo "none" > /configs/uspprimController 2>/dev/null
  for d in verne-shard4.corteca.airtelbroadband.in corteca.airtelbroadband.in acs.airtelbroadband.in testacs.airtelbroadband.in gre.fwabng.airtelbroadband.in; do
    grep -q "$d" /etc/hosts 2>/dev/null || echo "127.0.0.1 $d" >> /etc/hosts
  done
  for p in 8103 5683 8883; do
    iptables -C OUTPUT -p tcp --dport "$p" -j REJECT 2>/dev/null || iptables -I OUTPUT 1 -p tcp --dport "$p" -j REJECT 2>/dev/null
  done

  ip addr del 169.254.51.1/24 dev eth0 2>/dev/null
  brctl delif br_gre eth0 2>/dev/null
  brctl addif bridge0 eth0 2>/dev/null
  echo 0 > /proc/sys/net/bridge/bridge-nf-call-iptables 2>/dev/null
  echo 0 > /proc/sys/net/bridge/bridge-nf-call-ip6tables 2>/dev/null

  for cfg in /systemrw/data/mobileap_cfg_b2c_494_1.xml /systemrw/data/mobileap_cfg.xml /systemrw/data/mobileap_cfg_460_1.xml; do
    [ -w "$cfg" ] || continue
    sed -i "s|<FirstPreferredBackhaul>.*</FirstPreferredBackhaul>|<FirstPreferredBackhaul>wwan</FirstPreferredBackhaul>|g" "$cfg"
    sed -i "s|<EoGREProfile1>1</EoGREProfile1>|<EoGREProfile1>0</EoGREProfile1>|g" "$cfg"
    sed -i "s|<EoGREProfile1TunnelCount>1</EoGREProfile1TunnelCount>|<EoGREProfile1TunnelCount>0</EoGREProfile1TunnelCount>|g" "$cfg"
    sed -i "s|<EoGREConfiguredForPDN>1</EoGREConfiguredForPDN>|<EoGREConfiguredForPDN>0</EoGREConfiguredForPDN>|g" "$cfg"
    sed -i "s|<EoGRETunneledTraffic>3</EoGRETunneledTraffic>|<EoGRETunneledTraffic>0</EoGRETunneledTraffic>|g" "$cfg"
    sed -i "s|<EoGRENonTunneledTraffic>0</EoGRENonTunneledTraffic>|<EoGRENonTunneledTraffic>1</EoGRENonTunneledTraffic>|g" "$cfg"
    sed -i "s|<APN_Name>.*</APN_Name>|<APN_Name>jionet</APN_Name>|g" "$cfg"
    sed -i "s|<APN_Name />|<APN_Name>jionet</APN_Name>|g" "$cfg"
    sed -i "s|<AutoConnect>0</AutoConnect>|<AutoConnect>1</AutoConnect>|g" "$cfg"
  done

  # TR-181 Cellular & OperatorLock unblocks
  cfgcli -s InternetGatewayDevice.WANDevice.2.X_ALU-COM_Cellular.Interface.1.X_ALU-COM_OperatorLock false 2>/dev/null
  cfgcli -s InternetGatewayDevice.WANDevice.2.X_ALU-COM_Cellular.Interface.1.X_ALU-COM_CellListBehavior AllowUEMode 2>/dev/null
  ubus call Nokia.GenericService SetCellularAccessConfig '{"originator":"admin","paralist":[{"AccessModeNo":3,"NetworkSlicingEnable":false}]}' 2>/dev/null
  sysevent set CellularMgr_Block false 2>/dev/null
  sysevent set InitMgr_Block false 2>/dev/null
  sysevent set X_ALU_COM_AllowedForwarding_Block false 2>/dev/null

  # Switch Qualcomm SDX65 to physical SIM Slot 1 (Jio USIM tray)
  sleep 2
  exec 3<>/dev/smd11 2>/dev/null && {
    echo -e "AT+QUIMSLOT=1\r" >&3
    sleep 1
    echo -e "AT+CFUN=1\r" >&3
    sleep 0.5
    exec 3>&-
  }

  while true; do
    echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null
    echo 1 > /proc/sys/net/ipv6/conf/all/forwarding 2>/dev/null
    echo 1 > /proc/sys/net/ipv4/conf/bridge0/forwarding 2>/dev/null
    printf '0:700\n0:700\n0:700\n0:700\n0:700\n' > /configs/uptime 2>/dev/null

    # Watchdog & self-heal cfgmgr socket for Web UI
    if [ ! -S /tmp/cfgmgr_socket ]; then
      mount -o remount,exec /configs 2>/dev/null
      mount | grep -q " on /usr/bin/cfgmgr " || mount --bind /configs/cfgmgr_bin /usr/bin/cfgmgr 2>/dev/null
      killall -9 cfgmgr 2>/dev/null
      setsid /bin/start_cfgmgr.sh >/tmp/cfgmgr_start.log 2>&1 &
    fi

    WAN=""
    if ip a show rmnet_data1 2>/dev/null | grep -q 'inet '; then
      WAN="rmnet_data1"
    elif ip a show rmnet_data0 2>/dev/null | grep -q 'inet '; then
      WAN="rmnet_data0"
    fi

    if [ -n "$WAN" ]; then
      tc qdisc del dev "$WAN" root 2>/dev/null
      ip route show | grep -q "default .* $WAN" || ip route replace default dev "$WAN" 2>/dev/null
      iptables -t nat -C POSTROUTING -o "$WAN" -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -o "$WAN" -j MASQUERADE 2>/dev/null
      iptables -C FORWARD -i bridge0 -o "$WAN" -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 -i bridge0 -o "$WAN" -j ACCEPT 2>/dev/null
      iptables -C FORWARD -i "$WAN" -o bridge0 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 -i "$WAN" -o bridge0 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null
      /bin/send_led_event.sh -e 302 2>/dev/null
      /bin/send_led_event.sh -e 5817 -a '{"ActiveWAN":"Cellular"}' 2>/dev/null
    else
      exec 3<>/dev/smd11 2>/dev/null && {
        echo -e "AT+QUIMSLOT=1\r" >&3
        sleep 1
        echo -e "AT+CFUN=1\r" >&3
        sleep 0.5
        exec 3>&-
      }
    fi
    sleep 15
  done
) >/tmp/r7p.log 2>&1 &
exit 0
