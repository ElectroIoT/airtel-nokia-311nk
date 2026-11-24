# Nokia FastMile 5G Receiver ODU (Model 5G32-A / AOD311NK)
## Comprehensive Technical Systems & Telecommunications Engineering Analysis

---

### Executive Overview & System Profile
* **Device Target:** Nokia FastMile 5G Receiver ODU (Model: `5G32-A` | Hardware Board: `AOD311NK`)
* **SoC / Modem Platform:** Qualcomm Snapdragon X65 5G Modem-RF System (`sdxlemur`)
* **Core Architecture:** ARMv7l (32-bit Cortex-A7 embedded application core + Hexagon DSP baseband cores)
* **Kernel & OS:** Linux `5.4.289 #1 PREEMPT armv7l` (Nokia OpenWrt-derived hybrid embedded stack)
* **Storage Topology:** 1 GB (8 Gb) Micron/Winbond SLC NAND Flash over MTD/UBI with dm-verity
* **Cellular Modem Subsystem:** Qualcomm IP Accelerator (IPA v4.5+), QCMAP (`QCMAP_ConnectionManager`), SMD/QMI/AT (`/dev/smd11`, `rmnet_ipa`)
* **Stock Carrier Profile:** Bharti Airtel India 5G (Locked to PLMN `40445` / `40410` / `40431`, EoGRE Tunneling to `gre.fwabng.airtelbroadband.in`)
* **Target Carrier Integration:** Reliance Jio Infocomm Ltd (PLMN `405862`, 5G Standalone [SA], Band n28 / n78, Pure IPv6 PDN / 464XLAT)

---

## 1. Hardware & Firmware Architecture

```
+---------------------------------------------------------------------------------------------------+
|                                 Qualcomm Snapdragon X65 (sdxlemur)                                |
|  +-------------------------------------+   +---------------------------------------------------+  |
|  |     Hexagon 6G/5G Vector DSPs       |   |             ARMv7 Application Core                |  |
|  |  (3GPP Rel 16 Baseband Engine, RF)  |   |           Linux Kernel 5.4.289 PREEMPT            |  |
|  +------------------+------------------+   +-------------------------+-------------------------+  |
|                     |                                                |                            |
|             SMD / QMI IPC (/dev/smd11)                    Qualcomm IPA (Hardware Engine)          |
|                     |                                                |                            |
|                     +-----------------------+------------------------+                            |
|                                             |                                                     |
|                               +-------------v-------------+                                       |
|                               | Qualcomm QCMAP Datapath   |                                       |
|                               | (rmnet_ipa / rmnet_data1) |                                       |
|                               +-------------+-------------+                                       |
+---------------------------------------------|-----------------------------------------------------+
                                              |
     +----------------------------------------+----------------------------------------+
     |                                                                                 |
     v                                                                                 v
+-----------------------------------------------+   +-----------------------------------------------+
|         Slot A (Active: R6.0 / R7.0)          |   |          Slot B (Standby: R5.0 Fallback)      |
| - mtd17: a_boot     (Kernel zImage + DTB)     |   | - mtd18: b_boot     (Kernel zImage + DTB)     |
| - mtd21: a_modem    (SDX DSP Firmware & NV)   |   | - mtd22: b_modem    (SDX DSP Firmware & NV)   |
| - mtd33: a_system   (dm-verity + SquashFS)    |   | - mtd34: b_system   (dm-verity + SquashFS)    |
+-----------------------------------------------+   +-----------------------------------------------+
     |                                                                                 |
     +----------------------------------------+----------------------------------------+
                                              |
                                              v
+---------------------------------------------------------------------------------------------------+
|                                Shared Persistent Storage & Data Plane                             |
|  - mtd24: persist   (Factory RF calibration, board MAC addresses, serial numbers)                |
|  - mtd35: configs   (UBIFS /configs: USP db, mobileap_cfg.xml, aic_conf.json, certificates)       |
|  - mtd36: systemrw  (UBIFS /systemrw: writable system state, persistent scripts, override binds)  |
|  - mtd37: data      (UBIFS /data: temporary statistics, crash dumps, event logs)                 |
+---------------------------------------------------------------------------------------------------+
```

### 1.1 Dual-Slot A/B Partition Topology & Ping-Pong Mechanics
The Nokia FastMile 5G32-A incorporates a fault-tolerant dual-slot A/B flash partitioning layout designed to guarantee non-blocking Over-The-Air (OTA) updates and autonomous disaster recovery.
* **Boot Control Mechanics:**
  The system boot state is governed by the Qualcomm Secondary Bootloader (SBL) and U-Boot environment variables:
  - `ActivePartitionGroup`: `0` indicates Slot A; `1` indicates Slot B.
  - `partition_sufix`: Kernel cmdline suffix (`_a` or `_b`).
  - `boot_try_count`: Tracks consecutive failed boot attempts. If the hardware watchdog (`/dev/watchdog1`) or kernel panic occurs prior to the user-space watchdog acknowledgement daemon signalling success, `boot_try_count` decrements. Upon reaching zero, the bootloader automatically flips the active partition group to the standby slot.
* **MTD Partition Map Breakdown:**
  The 1 GB NAND flash is divided into 38 hardware MTD blocks:
  - `mtd17 (a_boot)` & `mtd18 (b_boot)`: Hold the raw Linux kernel image (`zImage`) appended with the device tree blob (`dtb`) and initial RAM disk.
  - `mtd21 (a_modem)` & `mtd22 (b_modem)`: House the Qualcomm Hexagon DSP firmware (`NON-HLOS.bin`), RF Front-End (RFFE) drivers, and baseband modem configuration parameters.
  - `mtd33 (a_system)` & `mtd34 (b_system)`: Hold the root filesystem. Each system partition is formatted with an immutable SquashFS volume verified cryptographically by **dm-verity** (`/dev/dm-0`).
  - `mtd35 (configs)`: Writable UBIFS volume mounted at `/configs`. Contains device-specific configuration databases (`usp.db`, `mobileap_cfg.xml`), factory certificates (`/configs/cert/`), and the critical Nokia Auto Installation Controller configuration (`aic_conf.json`).
  - `mtd36 (systemrw)`: Writable UBIFS volume mounted at `/systemrw`. Acts as persistent scratchpad for firmware overlays and operational state.

### 1.2 Qualcomm Baseband SDXlemur Subsystem & Hardware Acceleration
The core telecommunications processing is driven by the Qualcomm Snapdragon X65 5G Modem-RF System (`sdxlemur`):
* **3GPP Capabilities:** 3GPP Release 16 architecture supporting dual-connectivity (EN-DC), NR Standalone (SA), NR Non-Standalone (NSA), sub-6 GHz carrier aggregation (up to 300 MHz bandwidth), and mmWave.
* **Inter-Processor Communication (IPC):**
  Communication between the ARMv7 Linux application subsystem and the Hexagon Baseband DSP takes place across shared memory device (`/dev/smd*`) nodes and Qualcomm MSM Interface (QMI) control ports:
  - `/dev/smd11`: Direct bi-directional AT-command streaming pipe utilized for low-level modem query, RF state manipulation (`AT+CFUN`), and EPS/5GS bearer management.
  - `/dev/qcmap_cm`: High-speed control socket for `QCMAP_ConnectionManager`, binding cellular data bearers to the Linux kernel network stack.
* **Qualcomm IP Accelerator (IPA v4.5+):**
  The SoC incorporates a dedicated hardware data path accelerator—the Qualcomm IPA. The IPA hardware performs checksum computation, deep packet inspection, hardware NAT/NAPT, and direct Direct Memory Access (DMA) transfer between the cellular modem DSP ring-buffers and Ethernet MAC interfaces without CPU intervention.
  - *Driver Binding:* Implemented via `rmnet_ipa` and virtual multiplexed network interfaces `rmnet_data0` through `rmnet_data3`.

### 1.3 dm-verity Integrity & The 5RDP / BATIDecrypt Flashing Engine
To meet telecom carrier security compliance, the root filesystem in `a_system` and `b_system` is protected by the Linux kernel device-mapper verity (`dm-verity`) target:
* **dm-verity Enforcement:** The kernel verifies every 4096-byte block of the SquashFS rootfs against a Merkle hash tree stored at the end of the partition. Any offline modification to binaries, libraries, or system startup scripts in `/rom` or `/bin` trips cryptographic verification, triggering an immediate kernel panic during boot.
* **The 5RDP Container Format:** Nokia firmware updates (`.bin` files such as `AOD311NK_R6.0.bin`) are packaged in proprietary **5RDP** (5G Receiver Distribution Package) multi-partition encrypted archives.
* **Flashing Pipeline (`/usr/bin/BATIDecrypt` & `/bin/burn`):**
  1. The flashing binary `/bin/burn` reads the target slot argument (`burn a` or `burn b`).
  2. The input stream is piped through `/usr/bin/BATIDecrypt`, which parses the 5RDP header, validates the hardware model signature (`AOD311NK` / `5G32-A`), and performs AES-128-CBC payload decryption using an on-chip key.
  3. The decrypted raw partition blocks are written directly into the respective target MTD partitions (`b_boot`, `b_modem`, `b_system` or `a_boot`, `a_modem`, `a_system`).
  4. Memory-efficient flashing is accomplished over a local HTTP stream without writing the multi-hundred megabyte firmware image to flash:
     ```sh
     wget -O- http://192.168.0.150:8088/AOD311NK_R6.0.bin | /bin/burn a
     ```

---

## 2. Carrier Interoperability & Network Challenges

```
+---------------------------------------------------------------------------------------------------+
|                                  Qualcomm MobileAP (QCMAP) Stack                                  |
|                                                                                                   |
|               Stock Airtel Configuration                        Custom Carrier Unblocked          |
|         +-------------------------------------+           +-------------------------------------+ |
|         | <EoGREProfile1>1</EoGREProfile1>    |           | <EoGREProfile1>0</EoGREProfile1>    | |
|         | <EoGRETunneledTraffic>3</EoGRETunnel|           | <EoGRETunneledTraffic>0</EoGRETunnel| |
|         | <EoGRENonTunneledTraffic>0</EoGRENon|           | <EoGRENonTunneledTraffic>1</EoGRENon| |
|         | APN: airtelfwamdu.com               |           | APN: jionet (AutoConnect=1)         | |
|         +------------------+------------------+           +------------------+------------------+ |
|                            |                                                 |                    |
+----------------------------|-------------------------------------------------|--------------------+
                             |                                                 |
                             v                                                 v
              +-------------------------------+                 +-------------------------------+
              |   Encapsulated GRE Tunnel     |                 |  Direct Linux Kernel Network  |
              |   Destination: Airtel BNG     |                 |  Stack Routing (rmnet_data1)  |
              | (gre.fwabng.airtelbroadband)  |                 +---------------+---------------+
              +---------------+---------------+                                 |
                              |                                                 v
                              v                                 +-------------------------------+
              +-------------------------------+                 |   iptables NAT Masquerading   |
              |  Reliance Jio 5G SA: NO GRE   |                 |   Direct Egress via 5G Baseband|
              |  Endpoint -> 100% Packet Drop |                 |   0% Packet Drop / Live WWW   |
              +-------------------------------+                 +-------------------------------+
```

### 2.1 Overcoming Airtel Stock Firmware Restrictions
Airtel's stock firmware enforces strict network segmentation to bind the hardware exclusively to Airtel Fixed Wireless Access (FWA) infrastructure:
1. **The EoGRE (Ethernet-over-GRE) Datapath Hijack:**
   - Under standard stock operation, Qualcomm's `QCMAP_ConnectionManager` reads its configuration from `/etc/data/mobileap_cfg.xml` and persistent overrides in `/systemrw/data/mobileap_cfg_b2c_494_1.xml`.
   - The stock profile hardwires Profile 1 into an Ethernet-over-GRE tunnel:
     ```xml
     <EoGREProfile1>1</EoGREProfile1>
     <EoGREProfile1TunnelCount>1</EoGREProfile1TunnelCount>
     <EoGREConfiguredForPDN>1</EoGREConfiguredForPDN>
     <EoGRETunneledTraffic>3</EoGRETunneledTraffic>
     <EoGRENonTunneledTraffic>0</EoGRENonTunneledTraffic>
     ```
   - *Technical Mechanism:* The parameter `<EoGRENonTunneledTraffic>0</EoGRENonTunneledTraffic>` instructs the Qualcomm IPA packet processor to drop all egress packets that do not enter the `gretap2` / `br_gre` tunnel interface.
   - When a Reliance Jio SIM is inserted, the radio connects to Jio 5G NR (PLMN `405862`), but the GRE tunnel destination (`gre.fwabng.airtelbroadband.in`) is completely unreachable across Jio's routing domain.
   - Because the tunnel cannot negotiate, the Qualcomm kernel driver `rmnet_ipa` emits `ipa3_check_eogre: Invalid eogre info` and drops 100% of packets passing through `rmnet_data0` / `rmnet_data1`.
   - *Remediation:* The XML profiles must be explicitly re-engineered to disarm EoGRE (`<EoGREProfile1>0</EoGREProfile1>`, `<EoGRETunneledTraffic>0</EoGRETunneledTraffic>`, `<EoGRENonTunneledTraffic>1</EoGRENonTunneledTraffic>`) and shift the backhaul priority to `<FirstPreferredBackhaul>wwan</FirstPreferredBackhaul>`.

2. **TR-069 (CWMP) & TR-369 (USP) Telemetry Suppression:**
   - The device continuously runs two remote configuration daemons:
     - `tr_agent`: CWMP TR-069 engine polling Airtel Auto-Configuration Servers (`acs.airtelbroadband.in`).
     - `nuspd`: Broadband Forum TR-369 User Services Platform (USP) daemon communicating with the Nokia Corteca Cloud controller (`verne-shard4.corteca.airtelbroadband.in`) over TLS ports 8103, 5683, and 8883.
   - *Lockout Mechanism:* If the ODU detects an alien SIM or fails ACS authentication, the ACS controller remotely issues parameter updates setting `CellularMgr_Block=true` and forcing the device into an administrative freeze.
   - *Remediation & Sinkholing:*
     - The USP agent daemon is terminated (`killall -9 nuspd`).
     - TR-069 CWMP and TR-369 USP are permanently disarmed within the internal Nokia configuration database via `cfgcli`:
       ```sh
       cfgcli -s InternetGatewayDevice.ManagementServer.EnableCWMP false
       cfgcli -s InternetGatewayDevice.ManagementServer.X_ALU-COM_TR369Agent_Enable false
       cfgcli -s InternetGatewayDevice.ManagementServer.URL "http://127.0.0.1:8080"
       cfgcli --save-flash-now
       ```
     - All carrier ACS and telemetry domain names are loopback-sinkholed in `/etc/hosts` to `127.0.0.1` and `::1`.
     - Outbound firewall rules explicitly reject TCP ports 8103, 5683, and 8883.

### 2.2 Reliance Jio 5G SA Integration (Pure IPv6 / APN / QCMAP Datapath)
Reliance Jio's True5G operates on 5G Standalone (SA) architecture (Option 2), which introduces unique protocol characteristics compared to conventional LTE/NSA deployments:
1. **Pure IPv6 Single-Stack PDN Architecture:**
   - Jio 5G SA does not allocate an IPv4 address upon initial PDP context establishment. It grants a pure IPv6 global unicast address and a delegated `/64` prefix.
   - IPv4 traversal is achieved through carrier-side **464XLAT** (RFC 6877) architecture comprising a Customer Side Translator (CLAT) on the UE and a carrier NAT64 gateway at prefix `64:ff9b::/96` paired with DNS64.
2. **Qualcomm Dotted-Decimal IPv6 Encoding Phenomenon:**
   - Querying the active PDP address over `/dev/smd11` via `AT+CGPADDR=1` yields a 16-element dotted-decimal sequence:
     ```
     +CGPADDR: 1,"36.9.64.243.32.159.166.170.128.0.0.0.0.0.0.0"
     ```
   - Standard parser logic frequently mistakes this for an invalid IPv4 octet sequence. However, in Qualcomm SDX baseband implementations, IPv6 addresses on raw character interfaces are serialized as 16 decimal octets representing the 128-bit address:
     - `36` $\rightarrow$ `0x24`
     - `9` $\rightarrow$ `0x09`
     - `64` $\rightarrow$ `0x40`
     - `243` $\rightarrow$ `0xF3`
     - Full converted address: `2409:40f3:209f:a6aa:8000::/64` (Jio Mobility IPv6 pool).
3. **QCMAP Datapath Re-routing & NAT Masquerade:**
   - To route packets from the physical LAN bridge (`bridge0`) out through the cellular interface without EoGRE encapsulation, standard Linux Netfilter NAT masquerading and packet forwarding must be enforced:
     ```sh
     echo 1 > /proc/sys/net/ipv4/ip_forward
     echo 1 > /proc/sys/net/ipv6/conf/all/forwarding
     iptables -t nat -A POSTROUTING -o rmnet_data1 -j MASQUERADE
     iptables -A FORWARD -i bridge0 -o rmnet_data1 -j ACCEPT
     iptables -A FORWARD -i rmnet_data1 -o bridge0 -m state --state RELATED,ESTABLISHED -j ACCEPT
     ```

---

## 3. Root-Cause Debugging & System Modifications

```
+---------------------------------------------------------------------------------------------------+
|                                  Hardware Watchdog Neutralization                                 |
|                                                                                                   |
|     Linux Hardware Watchdog           Nokia Process Control Daemon (PCD)      Uptime Tracker      |
|         (/dev/watchdog1)                   (/bin/wd_pcdtest.sh)              (/configs/uptime)    |
|                |                                    |                                |            |
|                v                                    v                                v            |
|     Monitors kernel alive           Checks IMS / VoNR / Airtel ACS           Logs boot interval   |
|   Fires at 300s if unserviced       Fires /bin/postaction.sh (reboot -f)    < 700s = short boot   |
|                |                                    |                                |            |
|                +------------------+-----------------+                                |            |
|                                   |                                                  |            |
|                                   v                                                  v            |
|                   Virtual Stub Bind-Mount Architecture                      Persistent Counter    |
|                   /systemrw/dummy_ok.sh (exit 0)                            Padding (0:700)       |
|                   - Binds over /bin/wd_pcdtest.sh                           - Disarms lockout     |
|                   - Binds over /etc/watchdog.d/wdtest.sh                    - Prevents slot flip  |
|                   - Binds over /bin/postaction.sh                                                 |
+---------------------------------------------------------------------------------------------------+
```

### 3.1 Bypassing Hardware Watchdogs & PCD Deadman Loops
The most critical obstacle to field stability on non-Airtel carriers is the multi-tiered deadman reboot mechanism implemented across the kernel and user space:
1. **The 300-Second Hard Reboot Loop:**
   - The device hardware watchdog `/dev/watchdog1` is managed by Nokia's Process Control Daemon (`pcd`).
   - The user-space health monitor consists of `/bin/wd_pcdtest.sh` and `/etc/watchdog.d/wdtest.sh`.
   - Simultaneously, `CellularWanMgr` and `InitMgr` monitor Airtel IMS/VoNR and ACS registration. When these services fail to negotiate across Reliance Jio, `postaction.sh` is invoked, which issues `reboot -f` at exactly 300 seconds of uptime.
2. **The `/configs/uptime` Lockout Trap:**
   - PCD maintains a history of boot durations in `/configs/uptime`.
   - If the system detects consecutive boots where uptime was below 700 seconds, it interprets the condition as critical filesystem corruption or firmware fault.
   - After three short boot cycles, PCD either marks the current slot as unbootable—triggering an unwanted slot fallback—or permanently disables the cellular radio subsystem.
3. **The Bind-Mount Virtualization Solution:**
   - Because dm-verity prohibits editing `/bin/wd_pcdtest.sh` or `/bin/postaction.sh` on the SquashFS rootfs, we construct a persistent dummy success script on the writable UBIFS partition `/systemrw`:
     ```sh
     cat << 'EOF' > /systemrw/dummy_ok.sh
     #!/bin/sh
     exit 0
     EOF
     chmod 755 /systemrw/dummy_ok.sh
     ```
   - During startup, this neutral stub is bind-mounted directly over the reboot-triggering scripts:
     ```sh
     mount --bind /systemrw/dummy_ok.sh /bin/wd_pcdtest.sh
     mount --bind /systemrw/dummy_ok.sh /etc/watchdog.d/wdtest.sh
     mount --bind /systemrw/dummy_ok.sh /bin/postaction.sh
     ```
   - Watchdog stop tokens are instantiated in RAM (`touch /tmp/stop_watchdog /tmp/pcd_stop`).
   - The short-boot history file is disarmed by writing synthetic stable intervals into flash:
     ```sh
     printf '0:700\n0:700\n0:700\n0:700\n0:700\n' > /configs/uptime
     ```

### 3.2 Resolving `Something went wrong` Web GUI WAN Configuration Errors
Users accessing the Nokia FastMile web administrative interface (`https://192.168.0.1`) frequently encounter a fatal modal exception stating `Something went wrong` when viewing WAN status or applying cellular settings.
* **Root-Cause Telemetry & Data Model Inconsistency:**
  - The Web UI backend (`/webs/cgi-bin/login_web_app.cgi` and `ubus`) expects the WAN configuration state to strictly adhere to Nokia's internal schema.
  - When non-Airtel APNs or IPv6-only profiles are written directly to Qualcomm's `mobileap_cfg.xml` without updating Nokia's configuration daemon data store (`/configs/usp.db` and `/configs/backup_cfg.json`), the CGI JSON serializer fails schema validation.
  - Specifically, `wan_mode` in `/etc/config/network` and `Device.Cellular.Interface.1.USIM.Status` encounter null-pointer dereferences in the Web UI JavaScript frontend due to missing Airtel-specific XML keys (`<EoGREProfile1>`, `<EoGREHostName>`).
* **Resolution:**
  - Standardize `mobileap_cfg.xml` with consistent Profile 1 entries matching both QCMAP and Nokia internal formats.
  - Purge cached USP database states (`/configs/usp.db`) and synchronize UCI network settings to recognize `rmnet_data1` as the default cellular WAN interface.

### 3.3 Implementing Persistent Startup Overrides
Because rootfs modifications do not persist across reboots due to dm-verity, initialization overrides must hook into persistent writable storage:
* **The AIC (Auto Installation Controller) Hook Engine:**
  - During boot, the system executes Nokia's installation framework, which parses `/configs/aic_conf.json` residing on the writable UBIFS partition.
  - By injecting a custom background daemon hook into `/configs/aic_conf.json`, our master initialization script ([r7p_master.sh](file:///home/dc/Documents/airtel-nokia-311nk/r7p_master.sh) / `/configs/r7p.sh`) executes with root privileges (`uid=0`) on every boot:
    ```json
    {
      "detector": {
        "command": "/bin/sh /configs/r7p.sh"
      }
    }
    ```
* **Persistent Actions Orchestrated on Boot:**
  1. Virtualize hardware watchdog and reboot scripts via `mount --bind`.
  2. Synthesize disarmed `/configs/uptime` state.
  3. Ensure `/etc/ssh/sshd_config_ext` allows root access and restart OpenSSH (`/usr/sbin/sshd`).
  4. Spawn standalone root Telnet daemon (`busybox telnetd -l /bin/sh`) on port 23.
  5. Suppress `nuspd` and sinkhole Airtel ACS domains in `/etc/hosts`.
  6. Reconfigure LAN bridging so `eth0` is bridged into `bridge0`, enabling untagged access for standard commercial Wi-Fi routers.
  7. Patch QCMAP XML configurations, wake the Qualcomm baseband (`AT+CFUN=1`), and enable IP forwarding and NAT masquerading.
  8. Clear Nokia proprietary traffic blocks via `sysevent` and transition device LEDs to solid Green.

---

## 4. Future Recommendations & Optimization

```
+---------------------------------------------------------------------------------------------------+
|                              Field Deployment Architecture & Roadmap                              |
|                                                                                                   |
|  +-----------------------------+   +-----------------------------+   +--------------------------+ |
|  | Multi-Carrier Auto-APN      |   | TCP MSS & Path MTU Clamping |   | Dual-Slot Rescue Policy  | |
|  | - Sniff PLMN via AT+COPS?   |   | - 5G SA GTP-U + IPv6 Encaps |   | - Slot A: Production R6  | |
|  | - 405862 -> jionet          |   | - Clamp MSS: 1360 - 1400    |   | - Slot B: Verified Golden| |
|  | - 404xx  -> airtelgprs.com  |   | - Eliminates TLS hang/drop  |   | - Auto-rollback if panic | |
|  +-----------------------------+   +-----------------------------+   +--------------------------+ |
+---------------------------------------------------------------------------------------------------+
```

### 4.1 Automated Multi-Carrier APN & Network Profile Switching
To achieve zero-touch field deployment across multiple cellular operators (Reliance Jio, Bharti Airtel, Vodafone-Idea, BSNL 4G/5G), the static APN injection should be upgraded to dynamic PLMN sensing:
* **Dynamic PLMN Sniffing Loop:**
  The startup daemon can query the registered Public Land Mobile Network (PLMN) ID via Qualcomm AT commands on `/dev/smd11`:
  ```sh
  PLMN=$(send_smd11 "AT+COPS?" | grep -o '+COPS: [0-9],[0-9],"[0-9]*"' | cut -d'"' -f2)
  ```
* **Carrier Mapping Table:**
  | Operator | PLMN ID | APN Target | PDP Type | EoGRE Setting |
  | :--- | :--- | :--- | :--- | :--- |
  | **Reliance Jio True5G** | `405862`, `405854` | `jionet` | `IPV6` / `IPV4V6` | Disabled (`EoGREProfile1=0`) |
  | **Bharti Airtel 5G** | `40445`, `40410`, `40431` | `airtelgprs.com` | `IPV4V6` | Disabled (for open internet) |
  | **Vodafone-Idea (Vi)** | `40420`, `40404`, `40446` | `portalnmms` / `vi` | `IPV4V6` | Disabled (`EoGREProfile1=0`) |
  | **BSNL 4G/5G** | `40453`, `40464`, `40438` | `bsnlnet` | `IPV4V6` | Disabled (`EoGREProfile1=0`) |

### 4.2 TCP MSS & Path MTU Optimization for 5G Standalone
In 5G SA architectures, cellular packet encapsulation (GPRS Tunneling Protocol User Plane - GTP-U, IPsec headers, and IPv6 outer wrappers) reduces the effective Path MTU below the standard Ethernet 1500 bytes:
* **The TLS Handshake Stall Problem:**
  When client devices on the LAN transmit packets at standard 1500-byte MTU, large TCP packets (such as TLS ClientHello and ServerHello containing cryptographic certificates) exceed the 5G radio link MTU (typically 1420 bytes on Jio). If Path MTU Discovery (PMTUD) ICMP `Fragmentation Needed` packets are dropped by carrier firewalls, TCP connections hang indefinitely.
* **Recommended iptables MSS Clamping Rule:**
  Add explicit TCP Maximum Segment Size clamping to the firewall forward chain:
  ```sh
  iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
  iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1360
  ip6tables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1340
  ```

### 4.3 Dual-Slot Golden Image Fallback & Safe Upgrade Strategy
To prevent accidental field bricking during firmware experiments:
1. **Maintain Slot B as a Golden Recovery Image:**
   - Keep Slot B flashed with stable stock R5.0/R6.0 firmware.
   - Never flash experimental builds to both slots simultaneously.
2. **Deterministic Slot Switching:**
   - Utilize Qualcomm's partition switching tools to set boot preference safely:
     ```sh
     # To switch active partition group safely:
     /bin/ipq_upgrade test permanent_switch
     ```
3. **Hardware Watchdog Servicing in Production:**
   - In permanent commercial deployments where watchdog supervision is desired, rather than completely neutralizing the watchdog, implement a minimal watchdog ping daemon that writes directly to `/dev/watchdog1` at regular 15-second intervals, ensuring kernel crash protection without being held hostage by Nokia's Airtel-specific ACS connectivity checks.

---

### Verification & Deliverable File Reference Links
* **Interactive Full Analysis Workflow HTML Dashboard:** [nokia_odu_full_analysis_workflow_report.html](file:///home/dc/Documents/airtel-nokia-311nk/nokia_odu_full_analysis_workflow_report.html)
* **Master Automation & Daemon Startup Script:** [r7p_master.sh](file:///home/dc/Documents/airtel-nokia-311nk/r7p_master.sh)
* **Carrier Unblock & Permanent Fix Technical Log:** [NOKIA_ODU_PERMANENT_UNLOCK_REPORT.md](file:///home/dc/Documents/airtel-nokia-311nk/NOKIA_ODU_PERMANENT_UNLOCK_REPORT.md)
* **Reliance Jio 5G SA Network Fix Deep-Dive:** [NOKIA_ODU_JIO_FIX_REPORT.md](file:///home/dc/Documents/airtel-nokia-311nk/NOKIA_ODU_JIO_FIX_REPORT.md)
* **ChatGPT Master Prompt Reference:** [NOKIA_ODU_CHATGPT_MASTER_PROMPT_REPORT.md](file:///home/dc/Documents/airtel-nokia-311nk/NOKIA_ODU_CHATGPT_MASTER_PROMPT_REPORT.md)
* **Firmware Image R6.0:** [AOD311NK_R6.0.bin](file:///home/dc/Documents/airtel-nokia-311nk/New%20Folder/AOD311NK_R6.0.bin)
