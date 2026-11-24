# Nokia FastMile 5G Outdoor Unit (AOD311NK / 5G32-A) Architecture & TR-181 Workflow Reverse Engineering

> **Device:** Nokia FastMile 5G Receiver ODU (`5G32-A` / Board: `AOD311NK`)  
> **Modem-RF SOC:** Qualcomm Snapdragon X65 (`sdxlemur`, ARM Cortex-A7 32-bit @ 1.0 GHz)  
> **Kernel:** Linux `5.4.289` PREEMPT (ARMv7l)  
> **Firmware Distro:** QTI Linux Reference nogplv3 distro (`f4582504a8`)  
> **Network PHY:** Realtek RTL8168 PCIe 2.5G/1G Ethernet (`r8168_ioss`) with Qualcomm IP Accelerator (`IPA`)  
> **Target IP:** `192.168.0.1` (VLAN 1999 OAM Management, Laptop: `192.168.0.150`)

---

## 📋 Table of Contents
1. [Overview & High-Level Architecture](#1-overview--high-level-architecture)
2. [Hardware & Partition Layout](#2-hardware--partition-layout)
3. [Boot Chain & Nokia PCD Supervisor Graph](#3-boot-chain--nokia-pcd-supervisor-graph)
4. [TR-181 & TR-369 Data Model Architecture](#4-tr-181--tr-369-data-model-architecture)
5. [Ethernet & VLAN Traffic Plane (VLAN 1999 vs VLAN 1081)](#5-ethernet--vlan-traffic-plane-vlan-1999-vs-vlan-1081)
6. [Cellular 5G Dual-APN Plane (QTI IPA)](#6-cellular-5g-dual-apn-plane-qti-ipa)
7. [Security Traps, Watchdogs & Cell Lock Mechanisms](#7-security-traps-watchdogs--cell-lock-mechanisms)
8. [Permanent Standalone Unlock Architecture (Jio True 5G / Any Carrier)](#8-permanent-standalone-unlock-architecture-jio-true-5g--any-carrier)
9. [Component Backup Archives & Diagnostics Reference](#9-component-backup-archives--diagnostics-reference)

---

## 1. Overview & High-Level Architecture

The Nokia FastMile 5G Outdoor Unit (AOD311NK) is an enterprise-grade 5G Sub-6 / mmWave Customer Premises Equipment (CPE) deployed by Airtel in India for AirFiber fixed-wireless access (FWA).

In its stock deployment, the device is configured **not** as a typical home router, but as a locked cellular-to-Ethernet bridge that tunnels all end-user traffic to the indoor unit (IDU) via **Layer-2 Ethernet-over-GRE (L2 EoGRE)** encapsulated with **802.1Q VLAN 1081**, while exposing a dedicated management plane on **VLAN 1999**.

```
+----------------------------------------------------------------------------------------------------+
|                                    NOKIA FASTMILE 5G ODU (AOD311NK)                                |
|                                                                                                    |
|  [Hardware] Qualcomm Snapdragon X65 5G Modem-RF + ARM Cortex-A7 (1GHz) + Realtek PCIe 2.5G/1G     |
+----------------------------------------------------------------------------------------------------+
                                                  |
                                                  v
+----------------------------------------------------------------------------------------------------+
|  1. BOOTLOADER & KERNEL (Linux 5.4.289 PREEMPT)                                                    |
|  - Rootfs: SquashFS Read-Only dm-verity (/dev/ubiblock0_0 -> /dev/dm-0, 75MB)                      |
|  - DSP Firmware: Modem firmware (/dev/ubiblock1_0, 81MB)                                           |
|  - Writable Flash: UBIFS /configs (8MB), /systemrw (30MB), OverlayFS on /etc & /home               |
+----------------------------------------------------------------------------------------------------+
                                                  |
                                                  v
+----------------------------------------------------------------------------------------------------+
|  2. NOKIA PCD SUPERVISOR (Process Controller Daemon - /bin/pcd via /etc/hb/*.pcd)                 |
|  Strict start condition graph:                                                                     |
|  prepare.pcd -> SysEvent (syseventd) -> MQTT (mosquitto 127.0.0.1:1883)                            |
|  -> CfgMgr (decrypts syscfg.db into RAM) -> SWMgr -> CellularMgr -> TR069Agent / obuspa            |
+----------------------------------------------------------------------------------------------------+
                                                  |
                                                  v
+----------------------------------------------------------------------------------------------------+
|  3. CELLULAR 5G MODEM PLANE (QTI IPA - rmnet_ipa0, MTU 9216)                                       |
|  - APN 1 (OAM APN - rmnet_data0): Dedicated TR-069 ACS, TR-369 USP (obuspa), NTP, OTA Firmware   |
|  - APN 2 (INTERNET APN - rmnet_data1): End-user 5G SA/NSA data traffic                             |
+----------------------------------------------------------------------------------------------------+
                                                  |
                                                  v
+----------------------------------------------------------------------------------------------------+
|  4. ETHERNET & VLAN ARCHITECTURE (eth0 <-> bridge0)                                                |
|                                                                                                    |
|  [VLAN 1999 - Management (OAM)]               [VLAN 1081 - Airtel User Traffic (EoGRE)]           |
|  - Interface: eth0.1999 (MTU 1500/2000)        - Interface: br_gre / L2 EoGRE tunnel (br0)         |
|  - IP: 192.168.0.1/24 on bridge0               - gre_tunnel_web_app.cgi + action_handletraffic.sh   |
|  - Services: Web GUI (80/443), SSH (22),       - Airtel IDU router-ilekku Layer-2 Ethernet         |
|    Telnet (23 - permanent root), DNS (53)        GRE tunnel aayi encapsulate cheythu vidunnu       |
+----------------------------------------------------------------------------------------------------+
```

---

## 2. Hardware & Partition Layout

The storage layout uses raw NAND flash managed through UBI (Unsorted Block Images) volumes:

| Partition / Mount | Device Node | File System | Size | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| `/` (rootfs) | `/dev/dm-0` (`/dev/ubiblock0_0`) | SquashFS (dm-verity) | 75.3 MB | Immutable root filesystem containing `/bin`, `/sbin`, `/usr`, `/lib`, `/webs`. |
| `/firmware` | `/dev/ubiblock1_0` | SquashFS | 81.4 MB | Qualcomm SDX65 modem DSP firmware binaries (`modem.b*`). |
| `/configs` | `ubi29:configs` | UBIFS | 8.0 MB (5.8M used) | Persistent configuration flash: `syscfg.db` (AES encrypted), `tr181.db`, `usp.db`, certificates, SSH keys. |
| `/systemrw` | `/dev/ubi2_0` | UBIFS | 30.0 MB (3.2M used) | Writable system overlay for unlock scripts, custom SSH configurations, and runtime state. |
| `/etc`, `/home` | `overlay` (tmpfs backed) | OverlayFS | ~18 MB | Writable overlay over read-only system configurations. |
| `/tmp` | `tmpfs` | tmpfs (RAM) | 108 MB | Volatile runtime storage for IPC sockets, PID files, and temporary logs. |

---

## 3. Boot Chain & Nokia PCD Supervisor Graph

Nokia utilizes a proprietary supervisor daemon known as the **Process Controller Daemon (`/bin/pcd`)**, configured through `/etc/hb/*.pcd` rule definitions.

### Process Dependency Order
1. **`prepare.pcd`**: Validates hardware identifiers, mounts filesystems, initializes entropy.
2. **`SysEvent.pcd` (`syseventd`)**: Launches the internal system event bus on loopback.
3. **`MQTT.pcd` (`mosquitto`)**: Starts MQTT broker on `127.0.0.1:1883` for inter-daemon IPC.
4. **`CfgMgr.pcd` (`/usr/bin/CfgMgr`)**: Reads and decrypts `/configs/syscfg.db` into memory using `/configs/config_encryption.cfg`.
5. **`updatedb.pcd` & `SWMgr.pcd`**: Verifies data model schema migrations.
6. **`CellularMgr.pcd` (`/usr/bin/CellularMgr`)**: Initializes QTI QCMAP, binds to QMI/MBIM modem interfaces, and brings up 5G APNs.
7. **`TR069Agent.pcd` & `obuspa.pcd` (`nuspd`)**: Establishes TR-069 CWMP and TR-369 USP sessions to Airtel ACS management servers.
8. **`lighttpd.pcd`**: Starts Lighttpd web server on `192.168.0.1:80` and `443` running the 43+ CGI backend handlers.

---

## 4. TR-181 & TR-369 Data Model Architecture

The ODU implements Broadband Forum TR-181 Issue 2 Data Model version `2.15` extended with Nokia/Alcatel-Lucent proprietary parameters (`X_ALU-COM_SurgeRootDataModelVersion = surge-fwa.0.9.2`).

### Key Parameters Dumped from Live ODU (`cfgcli_wan.txt`)

```xml
<InternetGatewayDevice.>
  <RootDataModelVersion v="2.15" />
  <X_ALU-COM_SurgeRootDataModelVersion v="surge-fwa.0.9.2" />
  
  <!-- Cellular WAN Configuration -->
  <WANDevice.2.X_ALU-COM_Cellular.>
    <AccessPoint.1. n="OAM_APN">
      <APN v="airtelgprs.com" />
      <X_ALU-COM_ConnectionState v="Connected" />
      <NetworkInterface v="rmnet_data0" />
    </AccessPoint.1.>
    <AccessPoint.2. n="INTERNET_APN">
      <APN v="airtelgprs.com" />
      <X_ALU-COM_ConnectionState v="Connected" />
      <NetworkInterface v="rmnet_data1" />
    </AccessPoint.2.>
  </WANDevice.2.X_ALU-COM_Cellular.>

  <!-- Layer-2 EoGRE Tunnel & Bridge -->
  <GRE.Tunnel.1.>
    <X_ALU-COM_GreTunnelType v="L2" />
    <X_ALU-COM_MTU v="1500" />
    <X_ALU-COM_Bridge.1.>
      <BridgeName v="br0" />
      <BridgeVLANID v="1081" />
      <Enable v="true" />
    </X_ALU-COM_Bridge.1.>
  </GRE.Tunnel.1.>

  <!-- Management Server (TR-069 & TR-369 USP) -->
  <ManagementServer.>
    <EnableCWMP v="true" />
    <URL v="http://acs.airtel.com:8080/cwmp" />
    <X_ALU-COM_TR369Agent_Enable v="true" />
  </ManagementServer.>
</InternetGatewayDevice.>
```

---

## 5. Ethernet & VLAN Traffic Plane (VLAN 1999 vs VLAN 1081)

The ODU separates control/management from user traffic using strict 802.1Q VLAN separation:

1. **VLAN 1999 (OAM Management Plane)**:
   - Interface: `eth0.1999` (enqueued into `bridge0`).
   - Static IP: `192.168.0.1/24`.
   - Accessible services:
     - **Web UI:** Port `80` (HTTP redirect) and `443` (HTTPS) served by Lighttpd.
     - **Telnet:** Port `23` (`/bin/busybox telnetd -l /bin/sh`), permanent unauthenticated root access.
     - **SSH:** Port `22` (OpenSSH server, root login enabled via `/systemrw/sshd_config_ext`).
     - **DNS Forwarder:** Port `53` (`dnsmasq`).

2. **VLAN 1081 (User Traffic Plane)**:
   - In stock Airtel operation, user data packets are **not** routed as plain IP.
   - User packets arriving at the Ethernet port are encapsulated into **L2 EoGRE (Ethernet-over-GRE)** tagged with **VLAN 1081** inside `br_gre` and sent across the cellular WAN directly to the Airtel Core/IDU.

---

## 6. Cellular 5G Dual-APN Plane (QTI IPA)

The modem hardware interfaces through the Qualcomm IP Accelerator (`IPA` / `rmnet_ipa0`, hardware MTU 9216):

- **APN 1 (`rmnet_data0`) — OAM APN**:
  - Dedicated for Airtel TR-069 ACS, TR-369 USP (`obuspa`), NTP synchronization, and Over-the-Air (OTA) firmware delivery.
- **APN 2 (`rmnet_data1`) — Internet APN**:
  - Dedicated for user broadband traffic.

---

## 7. Security Traps, Watchdogs & Cell Lock Mechanisms

### A. Watchdog & Rapid-Reboot Deadman Switch
- The script `/bin/wd_pcdtest.sh` and `/etc/watchdog.d/wdtest.sh` continuously audit whether Airtel ACS is reachable and whether all PCD daemons report healthy. If checks fail, it triggers hardware reset via `/dev/watchdog`.
- `/configs/uptime`: A rapid-reboot detector. If the device restarts more than 5 times within 700 seconds without checking in with Airtel, the bootloader triggers a firmware fallback or factory reset.

### B. Operator & Cell Lock (`action_handletraffic.sh`)
- Nokia script `/bin/action_handletraffic.sh` compares the active SIM operator ID (`get_opid.sh`) against the factory registered Operator ID (`ri_host get OperatorID`).
- If an unsupported SIM is inserted, or if cell locking fails (`CellularMgr_cell_lock_failure`), it fires event `5826` over MQTT (`/Device/Service/Config/UserTraffic`), writing `echo 0 > /proc/sys/net/ipv4/ip_forward` and setting the status LED to solid red/amber.

---

## 8. Permanent Standalone Unlock Architecture (Jio True 5G / Any Carrier)

To run the Nokia AOD311NK as an independent high-performance 5G SA gateway on Reliance Jio, BSNL, Vi, or Airtel without the proprietary IDU:

1. **Disarm Watchdogs & Reboot Loops**:
   Bind-mount `/systemrw/dummy_ok.sh` (`exit 0`) over `/bin/wd_pcdtest.sh` and `/etc/watchdog.d/wdtest.sh`. Write `0:700` into `/configs/uptime`.
2. **Neutralize Airtel Remote ACS & Telemetry**:
   Set `EnableCWMP` and `X_ALU-COM_TR369Agent_Enable` to `false` via `cfgcli`. Kill `nuspd`.
3. **Disable EoGRE & Enable Standalone Routing**:
   Disable `br_gre`. Enable kernel IPv4/IPv6 forwarding:
   ```bash
   echo 1 > /proc/sys/net/ipv4/ip_forward
   echo 1 > /proc/sys/net/ipv6/conf/all/forwarding
   ```
4. **NAT Masquerade & MSS Clamping**:
   ```bash
   iptables -t nat -A POSTROUTING -o rmnet_data0 -j MASQUERADE
   iptables -t nat -A POSTROUTING -o rmnet_data1 -j MASQUERADE
   iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
   iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1360
   ```
5. **Boot Persistence**:
   Incorporate into `/configs/aic_conf.json` so the unlock daemon starts automatically on every boot.

---

## 9. Component Backup Archives & Diagnostics Reference

All dumped components and diagnostics are stored in [`NOKIA_ODU_FULL_DUMP_20261124_LIVE/`](../NOKIA_ODU_FULL_DUMP_20261124_LIVE/):

- [`archives/bin_sbin.tar.gz`](../NOKIA_ODU_FULL_DUMP_20261124_LIVE/archives/bin_sbin.tar.gz) — 7.6 MB (All system binaries and Nokia scripts)
- [`archives/configs.tar.gz`](../NOKIA_ODU_FULL_DUMP_20261124_LIVE/archives/configs.tar.gz) — 1.4 MB (UBIFS `/configs` partition)
- [`archives/etc.tar.gz`](../NOKIA_ODU_FULL_DUMP_20261124_LIVE/archives/etc.tar.gz) — 6.3 MB (All systemd and PCD configurations)
- [`archives/webs.tar.gz`](../NOKIA_ODU_FULL_DUMP_20261124_LIVE/archives/webs.tar.gz) — 3.3 MB (Lighttpd, 43+ CGIs, Web UI)
- [`archives/lib.tar.gz`](../NOKIA_ODU_FULL_DUMP_20261124_LIVE/archives/lib.tar.gz) — 4.8 MB (Shared libraries and linkers)
- [`archives/data_usrdata.tar.gz`](../NOKIA_ODU_FULL_DUMP_20261124_LIVE/archives/data_usrdata.tar.gz) — 1.4 MB (Daemon IPC logs and state)
- [`system_diagnostics/cfgcli_wan.txt`](../NOKIA_ODU_FULL_DUMP_20261124_LIVE/system_diagnostics/cfgcli_wan.txt) — 1.0 MB (Complete decrypted TR-181 data model dump)
