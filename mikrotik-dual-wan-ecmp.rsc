# MikroTik Dual WAN - ECMP + FastTrack | RouterOS v7.20+
# Features: ECMP Load Balancing, FastTrack, Auto-Failover, Traffic Steering
# Optimized for: hEX S (RB760iGS) and similar MIPS/ARM routers
# ==============================================================================
# This script uses ECMP (Equal-Cost Multi-Path) routing with FastTrack for
# maximum throughput. Unlike PCC, FastTrack is fully compatible with ECMP,
# allowing the router to achieve near wire-speed forwarding (~900Mbps on hEX S).
#
# Failover is handled natively by check-gateway=ping on ECMP routes.
# No scheduler-based failover scripts are needed for route management.
# ==============================================================================

# ==============================================================================
# CONFIGURATION VARIABLES
# ==============================================================================
:local lISP1Name "Vivo"
:local lISP2Name "Claro"
:local lWAN1Interface "ether1"
:local lWAN2Interface "ether2"

:local lLANInterface "bridge-lan"
:local lLANSubnet "192.168.100.0/24"
:local lLANAddress "192.168.100.1/24"
:local lLANGateway "192.168.100.1"
:local lLANPort1 "ether3"
:local lLANPort2 "ether4"
:local lLANPort3 "ether5"

# DNS & Pi-Hole
:local lPiHoleAddress "192.168.100.2"
:local lDNSServers "1.1.1.1,1.0.0.1,8.8.8.8,8.8.4.4"

# DHCP
:local lDHCPPoolRange "192.168.100.100-192.168.100.200"

# Static DHCP Leases (MAC -> IP)
:local lPiHoleMAC "e0:51:d8:67:87:38"
:local lDesktopMAC "94:bb:43:0a:32:36"
:local lDesktopIP "192.168.100.10"
:local lArcherMAC "28:ee:52:95:10:28"
:local lArcherIP "192.168.100.3"
:local lClaroTVMAC "dc:97:e6:b4:b2:2b"
:local lClaroTVIP "192.168.100.20"

# System
:local lTimeZone "America/Sao_Paulo"

# Email Notifications (optional)
:local lEmailEnable false
:local lEmailAddress "your-email@gmail.com"
:local lEmailPassword "your-app-password"

# ==============================================================================
# SYSTEM RESET (DESTRUCTIVE)
# ==============================================================================
:put "WARNING: Starting DESTRUCTIVE configuration reset in 5 seconds..."
:put "WARNING: This will remove ALL firewall rules, routes, and NAT!"
:put "WARNING: Press Ctrl+C NOW to cancel."
:delay 5s

:put "Starting configuration reset..."

# Clear global variables
/system script environment remove [find]

# Remove old scripts and schedulers
:do { /system scheduler remove [/system scheduler find where name~"failover" || name~"memory" || name~"launcher" || name~"isp-monitor" || name~"check-memory" || name~"bootstrap"] } on-error={}
:do { /system script remove [/system script find where name~"failover" || name~"enabler" || name~"config" || name~"dual-wan"] } on-error={}

# Remove firewall rules
:do { /ip firewall nat remove [/ip firewall nat find] } on-error={}
:do { /ip firewall mangle remove [/ip firewall mangle find] } on-error={}
:do { /ip firewall filter remove [/ip firewall filter find] } on-error={}
:do { /ip firewall raw remove [/ip firewall raw find] } on-error={}

# Remove routes and routing config
:do { /ip route remove [/ip route find where !connect] } on-error={}
:do { /routing rule remove [/routing rule find] } on-error={}
:do { /routing table remove [/routing table find where name="ISP1" || name="ISP2" || name="ForceClaro"] } on-error={}

# Remove DHCP clients
:do { /ip dhcp-client remove [/ip dhcp-client find interface=$lWAN1Interface] } on-error={}
:do { /ip dhcp-client remove [/ip dhcp-client find interface=$lWAN2Interface] } on-error={}

# Remove DHCP server config
:do { /ip dhcp-server lease remove [/ip dhcp-server lease find where comment~"Static:"] } on-error={}
:do { /ip dhcp-server remove [/ip dhcp-server find name="lan-dhcp"] } on-error={}
:do { /ip dhcp-server network remove [/ip dhcp-server network find] } on-error={}
:do { /ip pool remove [/ip pool find name="lan-dhcp-pool"] } on-error={}

# Remove DNS static entries
:do { /ip dns static remove [/ip dns static find where comment~"LAN:"] } on-error={}

# Remove address lists
:do { /ip firewall address-list remove [/ip firewall address-list find where list="LocalTraffic" || list="Management" || list="MonitorIPs" || list="ForceISP2"] } on-error={}

# Remove bridge
:do { /interface bridge remove [/interface bridge find name=$lLANInterface] } on-error={}

:delay 2s

# ==============================================================================
# ROUTING TABLE (Steering Only)
# ==============================================================================
/routing table
add name=ForceClaro fib comment="Steering: Claro TV Box"

# ==============================================================================
# INTERFACE LISTS
# ==============================================================================
/interface list
:do { remove [find name="WAN"] } on-error={}
add name=WAN comment="WAN Interfaces"
:do { remove [find name="LAN"] } on-error={}
add name=LAN comment="LAN Interfaces"

# ==============================================================================
# BRIDGE CONFIGURATION
# ==============================================================================
/interface bridge
add name=$lLANInterface comment="LAN Bridge"

/interface bridge port
:do { remove [find interface=$lWAN1Interface] } on-error={}
:do { remove [find interface=$lWAN2Interface] } on-error={}
:do { remove [find interface=$lLANPort1] } on-error={}
:do { remove [find interface=$lLANPort2] } on-error={}
:do { remove [find interface=$lLANPort3] } on-error={}
add bridge=$lLANInterface interface=$lLANPort1 comment="LAN Port 1"
add bridge=$lLANInterface interface=$lLANPort2 comment="LAN Port 2"
add bridge=$lLANInterface interface=$lLANPort3 comment="LAN Port 3"

# ==============================================================================
# INTERFACE LIST MEMBERS
# ==============================================================================
/interface list member
:do { remove [find interface=$lWAN1Interface] } on-error={}
:do { remove [find interface=$lWAN2Interface] } on-error={}
:do { remove [find interface=$lLANInterface] } on-error={}
add list=WAN interface=$lWAN1Interface comment="WAN1 (Vivo)"
add list=WAN interface=$lWAN2Interface comment="WAN2 (Claro)"
add list=LAN interface=$lLANInterface comment="LAN Bridge"

# ==============================================================================
# ADDRESS LISTS
# ==============================================================================
/ip firewall address-list
add address=$lLANSubnet list=LocalTraffic comment="LAN Subnet"
add address=$lLANSubnet list=Management comment="Management Access (LAN Only)"

# ==============================================================================
# IP ADDRESS (LAN Only - WAN via DHCP Client)
# ==============================================================================
/ip address
:do { remove [find interface=$lWAN1Interface] } on-error={}
:do { remove [find interface=$lWAN2Interface] } on-error={}
:do { remove [find interface=$lLANInterface] } on-error={}
add address=$lLANAddress interface=$lLANInterface comment="LAN"

# ==============================================================================
# DHCP CLIENT (WAN1 + WAN2)
# ==============================================================================
# ISP routers in bridge mode deliver WAN IPs via DHCP.
# Each client script creates ECMP routes with check-gateway=ping for failover,
# plus steering routes in the ForceClaro table for Claro TV Box.

/ip dhcp-client

add interface=$lWAN1Interface add-default-route=no use-peer-dns=no use-peer-ntp=no \
    comment="DHCP: Vivo (WAN1)" disabled=no \
    script=":global WAN1Gateway; \
        :local newGW \$\"lease-gateway\"; \
        :if ([:len \$newGW] > 0) do={ \
            :set WAN1Gateway \$newGW; \
            :log info (\"[DHCP] Vivo gateway: \" . \$newGW); \
            :do { /ip route remove [find where comment=\"ECMP: Vivo\"] } on-error={}; \
            /ip route add dst-address=0.0.0.0/0 gateway=\$newGW distance=1 \
                check-gateway=ping comment=\"ECMP: Vivo\"; \
            :do { /ip route remove [find where comment=\"Steer: Vivo Fallback\"] } on-error={}; \
            /ip route add dst-address=0.0.0.0/0 gateway=\$newGW routing-table=ForceClaro \
                distance=2 comment=\"Steer: Vivo Fallback\"; \
        }"

add interface=$lWAN2Interface add-default-route=no use-peer-dns=no use-peer-ntp=no \
    comment="DHCP: Claro (WAN2)" disabled=no \
    script=":global WAN2Gateway; \
        :local newGW \$\"lease-gateway\"; \
        :if ([:len \$newGW] > 0) do={ \
            :set WAN2Gateway \$newGW; \
            :log info (\"[DHCP] Claro gateway: \" . \$newGW); \
            :do { /ip route remove [find where comment=\"ECMP: Claro\"] } on-error={}; \
            /ip route add dst-address=0.0.0.0/0 gateway=\$newGW distance=1 \
                check-gateway=ping comment=\"ECMP: Claro\"; \
            :do { /ip route remove [find where comment=\"Steer: Claro Primary\"] } on-error={}; \
            /ip route add dst-address=0.0.0.0/0 gateway=\$newGW routing-table=ForceClaro \
                distance=1 comment=\"Steer: Claro Primary\"; \
        }"

# ==============================================================================
# DHCP SERVER
# ==============================================================================
/ip pool
:do { remove [find name="lan-dhcp-pool"] } on-error={}
add name=lan-dhcp-pool ranges=$lDHCPPoolRange comment="LAN DHCP Pool"

/ip dhcp-server
:do { remove [find name="lan-dhcp"] } on-error={}
add name=lan-dhcp interface=$lLANInterface address-pool=lan-dhcp-pool disabled=no comment="LAN DHCP Server"

/ip dhcp-server network
:do { remove [find address=$lLANSubnet] } on-error={}
add address=$lLANSubnet gateway=$lLANGateway dns-server=($lPiHoleAddress . ",1.1.1.1") domain="lan" comment="LAN Network (DNS: Pi-Hole + Cloudflare)"

# ==============================================================================
# STATIC DHCP LEASES
# ==============================================================================
/ip dhcp-server lease
:do { remove [find where comment~"Static:"] } on-error={}
add address=$lPiHoleAddress mac-address=$lPiHoleMAC server=lan-dhcp comment="Static: Pi-Hole"
add address=$lDesktopIP mac-address=$lDesktopMAC server=lan-dhcp comment="Static: Desktop"
add address=$lArcherIP mac-address=$lArcherMAC server=lan-dhcp comment="Static: ArcherAX10"
add address=$lClaroTVIP mac-address=$lClaroTVMAC server=lan-dhcp comment="Static: Claro TV Box"

# ==============================================================================
# DNS CONFIGURATION
# ==============================================================================
# Router uses external DNS (independent of Pi-Hole).
# Clients receive Pi-Hole via DHCP (configured above).
/ip dns
set servers=$lDNSServers allow-remote-requests=yes cache-size=32768KiB cache-max-ttl=1d

# Static hostnames for LAN devices (.lan domain)
/ip dns static
:do { remove [find where comment~"LAN:"] } on-error={}
add name="raspberrypi.lan" address=$lPiHoleAddress comment="LAN: Pi-Hole"
add name="desktopnix.lan" address=$lDesktopIP comment="LAN: Desktop"
add name="archerap.lan" address=$lArcherIP comment="LAN: ArcherAX10"
add name="clarotvbox.lan" address=$lClaroTVIP comment="LAN: Claro TV Box"

# ==============================================================================
# TRAFFIC STEERING (Routing Rule)
# ==============================================================================
# Claro TV Box traffic is sent to ForceClaro routing table.
# ForceClaro has: Claro gateway (distance=1) + Vivo gateway (distance=2 fallback).
# No mangle needed - routing rules operate at FIB level.
/routing rule
:do { remove [find where comment~"Steer:"] } on-error={}
add src-address=($lClaroTVIP . "/32") action=lookup-only-in-table table=ForceClaro \
    comment="Steer: Claro TV Box -> Claro"

# ==============================================================================
# MANGLE (MSS Clamping Only)
# ==============================================================================
/ip firewall mangle
add chain=forward protocol=tcp tcp-flags=syn action=change-mss new-mss=1400 \
    passthrough=yes comment="Clamp MSS to 1400 (Safe for PPPoE/LTE/VPN)"

# ==============================================================================
# NAT
# ==============================================================================
/ip firewall nat
add chain=srcnat out-interface-list=WAN action=masquerade comment="NAT: Masquerade"

# ==============================================================================
# FIREWALL FILTER (with FastTrack)
# ==============================================================================
/ip firewall filter

# --- INPUT CHAIN ---
add chain=input connection-state=invalid action=drop comment="Drop: Invalid Input"
add chain=input connection-state=established,related action=accept comment="Accept: Established Input"

# Management access (LAN only)
add chain=input protocol=tcp dst-port=8291 src-address-list=Management action=accept comment="Accept: WinBox (LAN)"
add chain=input protocol=tcp dst-port=80 src-address-list=Management action=accept comment="Accept: HTTP (LAN)"
add chain=input protocol=tcp dst-port=8728 src-address-list=Management action=accept comment="Accept: API (LAN)"

# ICMP rate limiting
add chain=input protocol=icmp limit=10,5:packet action=accept comment="Limit: ICMP"
add chain=input protocol=icmp action=drop comment="Drop: Excess ICMP"

# LAN full access
add chain=input in-interface=$lLANInterface action=accept comment="Accept: LAN Input"

# Drop all WAN input
add chain=input in-interface-list=WAN action=drop comment="Drop: WAN Input"

# --- FORWARD CHAIN ---
add chain=forward connection-state=invalid action=drop comment="Drop: Invalid Forward"

# FastTrack: Accelerate established connections (bypasses mangle/filter for speed)
add chain=forward connection-state=established,related action=fasttrack-connection \
    comment="FastTrack: Established/Related"
add chain=forward connection-state=established,related action=accept \
    comment="Accept: Established Forward"

# LAN -> WAN (new connections)
add chain=forward in-interface=$lLANInterface connection-state=new action=accept \
    comment="Accept: LAN New Forward"

# WAN -> LAN (return traffic only)
add chain=forward in-interface-list=WAN out-interface=$lLANInterface \
    connection-state=established,related action=accept comment="Accept: WAN Return"

# Default deny
add chain=forward action=drop comment="Drop: All Other Forward"

# ==============================================================================
# FIREWALL RAW (Anti-Scan)
# ==============================================================================
/ip firewall raw
add chain=prerouting protocol=tcp dst-port=8291 src-address-list=!Management action=drop comment="Drop: WinBox from Internet"
add chain=prerouting protocol=tcp dst-port=22 src-address-list=!Management action=drop comment="Drop: SSH from Internet"

# SYN flood protection
add chain=prerouting in-interface-list=WAN protocol=tcp tcp-flags=syn connection-state=new \
    limit=200,5:packet action=accept comment="SYN: Rate Limit"
add chain=prerouting in-interface-list=WAN protocol=tcp tcp-flags=syn connection-state=new \
    action=drop comment="SYN: Drop Excess"

# Drop spoofed/bogon source IPs from WAN (not blocking 100.64/10 - CGNAT used by some ISPs)
add chain=prerouting in-interface-list=WAN src-address=0.0.0.0/8 action=drop comment="Drop: Bogon 0.0.0.0/8"
add chain=prerouting in-interface-list=WAN src-address=10.0.0.0/8 action=drop comment="Drop: Bogon RFC1918 10/8"
add chain=prerouting in-interface-list=WAN src-address=172.16.0.0/12 action=drop comment="Drop: Bogon RFC1918 172.16/12"
add chain=prerouting in-interface-list=WAN src-address=192.168.0.0/16 action=drop comment="Drop: Bogon RFC1918 192.168/16"
add chain=prerouting in-interface-list=WAN src-address=127.0.0.0/8 action=drop comment="Drop: Bogon Loopback"
add chain=prerouting in-interface-list=WAN src-address=224.0.0.0/4 action=drop comment="Drop: Bogon Multicast"

# ==============================================================================
# SERVICE HARDENING
# ==============================================================================
/ip service
set telnet disabled=yes
set ftp disabled=yes
set www address=$lLANSubnet disabled=no
set www-ssl disabled=yes
set ssh disabled=yes
set api disabled=yes
set api-ssl disabled=yes
set winbox address=$lLANSubnet disabled=no

# MAC Server restricted to LAN
:do { /tool mac-server set allowed-interface-list=LAN } on-error={}
:do { /tool mac-server mac-winbox set allowed-interface-list=LAN } on-error={}

# Disable unnecessary services
:do { /tool bandwidth-server set enabled=no } on-error={}
:do { /ip proxy set enabled=no } on-error={}
:do { /ip socks set enabled=no } on-error={}
:do { /ip upnp set enabled=no } on-error={}
:do { /tool romon set enabled=no } on-error={}

# Neighbor discovery restricted to LAN only
/ip neighbor discovery-settings set discover-interface-list=LAN

# ==============================================================================
# SYSTEM CONFIGURATION
# ==============================================================================
# Email (optional)
:if ($lEmailEnable) do={
    :do { /tool e-mail set server="smtp.gmail.com" port=587 tls=starttls from="DualWAN-Router" user=$lEmailAddress password=$lEmailPassword } on-error={ :put "WARNING: Email config failed" }
}

/system clock set time-zone-name=$lTimeZone
/system identity set name="DualWAN-Router"

# Disable IPv6 (prevent firewall bypass - this config is IPv4 only)
:do { /ipv6 settings set disable-ipv6=yes forward=no accept-redirects=no } on-error={}

# Allow asymmetric routing for Dual-WAN
/ip settings set rp-filter=loose

# Connection tracking: reduce timeouts to free stale entries faster
/ip firewall connection tracking
set tcp-established-timeout=1h tcp-close-wait-timeout=10s udp-timeout=30s generic-timeout=5m

# NTP
/system ntp client set enabled=yes
/system ntp client servers
:do { remove [/system ntp client servers find] } on-error={}
add address=time.cloudflare.com
add address=time.google.com
add address=time.nist.gov

# ==============================================================================
# ISP MONITOR (Simplified - Notifications Only)
# ==============================================================================
# Route failover is handled automatically by check-gateway=ping on ECMP routes.
# This monitor only tracks state changes for logging and optional email alerts.

:global WAN1Status "up"
:global WAN2Status "up"

/system scheduler
:do { remove [find name="isp-monitor"] } on-error={}
add name=isp-monitor interval=1m start-time=startup on-event={
    :global WAN1Status
    :global WAN2Status
    :global EmailEnable
    :global EmailTo

    :local wan1Active ([:len [/ip route find where comment="ECMP: Vivo" and active]] > 0)
    :local wan2Active ([:len [/ip route find where comment="ECMP: Claro" and active]] > 0)

    # ISP1 (Vivo) state change
    :if (!$wan1Active && $WAN1Status = "up") do={
        :set WAN1Status "down"
        :log error "[MONITOR] Vivo DOWN - Route inactive"
        :if ($EmailEnable = true) do={
            :do { /tool e-mail send to=$EmailTo subject="[DualWAN] Vivo DOWN" body="Vivo internet connection is down. Traffic rerouted to Claro." } on-error={}
        }
    }
    :if ($wan1Active && $WAN1Status = "down") do={
        :set WAN1Status "up"
        :log info "[MONITOR] Vivo RECOVERED"
        :if ($EmailEnable = true) do={
            :do { /tool e-mail send to=$EmailTo subject="[DualWAN] Vivo RECOVERED" body="Vivo internet connection has been restored." } on-error={}
        }
    }

    # ISP2 (Claro) state change
    :if (!$wan2Active && $WAN2Status = "up") do={
        :set WAN2Status "down"
        :log error "[MONITOR] Claro DOWN - Route inactive"
        :if ($EmailEnable = true) do={
            :do { /tool e-mail send to=$EmailTo subject="[DualWAN] Claro DOWN" body="Claro internet connection is down. Traffic rerouted to Vivo." } on-error={}
        }
    }
    :if ($wan2Active && $WAN2Status = "down") do={
        :set WAN2Status "up"
        :log info "[MONITOR] Claro RECOVERED"
        :if ($EmailEnable = true) do={
            :do { /tool e-mail send to=$EmailTo subject="[DualWAN] Claro RECOVERED" body="Claro internet connection has been restored." } on-error={}
        }
    }
}

# Export email globals for monitor scheduler
:global EmailEnable $lEmailEnable
:global EmailTo $lEmailAddress

# ==============================================================================
# MEMORY MONITOR
# ==============================================================================
/system scheduler
:do { remove [find name="check-memory"] } on-error={}
add name=check-memory interval=1h start-time=startup on-event={
    :local memFree [/system resource get free-memory]
    :local memTotal [/system resource get total-memory]
    :local memPercent (($memTotal - $memFree) * 100 / $memTotal)
    :if ($memPercent > 90) do={
        :log warning ("High Memory Usage: " . $memPercent . "%")
    }
}

# Flush existing connections to apply new routing immediately
/ip firewall connection remove [/ip firewall connection find]

# ==============================================================================
# COMPLETION SUMMARY
# ==============================================================================
:put ""
:put "========================================================================"
:put " ECMP + FastTrack Configuration Applied"
:put "========================================================================"
:put ""
:put ("ISP1: " . $lISP1Name . " (" . $lWAN1Interface . ") - DHCP Client")
:put ("ISP2: " . $lISP2Name . " (" . $lWAN2Interface . ") - DHCP Client")
:put "Load Balancing: ECMP (Equal-Cost Multi-Path) with FastTrack"
:put "Failover: Automatic via check-gateway=ping (~10s detection)"
:put ""
:put ("DNS for clients: Pi-Hole (" . $lPiHoleAddress . ") + Cloudflare fallback")
:put ("DNS for router: " . $lDNSServers)
:put ""
:put "Static Leases:"
:put ("  Pi-Hole:       " . $lPiHoleAddress . " (raspberrypi.lan)")
:put ("  ArcherAX10:    " . $lArcherIP . " (archerap.lan)")
:put ("  Desktop:       " . $lDesktopIP . " (desktopnix.lan)")
:put ("  Claro TV Box:  " . $lClaroTVIP . " (clarotvbox.lan) -> Forced to Claro")
:put ""
:put "Next Steps:"
:put "1. Connect WAN cables (ether1=Vivo, ether2=Claro)"
:put "2. Check DHCP clients: /ip dhcp-client print detail"
:put "3. Check routes: /ip route print where dst-address=0.0.0.0/0"
:put "4. Check FastTrack: /ip firewall filter print stats where comment~\"FastTrack\""
:put "5. Monitor ISP status: /log print follow where message~\"MONITOR\""
:put "6. Test hostnames: ping raspberrypi.lan"
:put ""
:put ("Security: WinBox restricted to LAN (" . $lLANSubnet . ") only")
:put ""
:put "!! IMPORTANT: Change the default admin password !!"
:put "   /user set admin password=YOUR-STRONG-PASSWORD"
:put ""
