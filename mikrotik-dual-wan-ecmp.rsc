# MikroTik Dual WAN - ECMP + FastTrack | RouterOS v7.20+
# ==============================================================================
# Load balancing com ECMP + FastTrack e failover automatico via check-gateway.
# Testado em hEX S (RB760iGS). Funciona em qualquer MikroTik com RouterOS v7.
#
# COMO USAR:
#   1. Edite as variaveis abaixo com seus dados
#   2. Remova as secoes que nao precisa (marcadas com [OPCIONAL])
#   3. Suba o arquivo no router: Winbox > Files > arrastar arquivo
#   4. No terminal: /import mikrotik-dual-wan-ecmp.rsc
#
# ATENCAO: Este script RESETA toda a configuracao do router.
# ==============================================================================

# ==============================================================================
# VARIAVEIS - edite aqui
# ==============================================================================

# --- WANs (suas conexoes de internet) ---
:local lISP1Name "Vivo"
:local lISP2Name "Claro"
:local lWAN1Interface "ether1"
:local lWAN2Interface "ether2"

# --- LAN ---
:local lLANInterface "bridge-lan"
:local lLANSubnet "192.168.100.0/24"
:local lLANAddress "192.168.100.1/24"
:local lLANGateway "192.168.100.1"
:local lLANPort1 "ether3"
:local lLANPort2 "ether4"
:local lLANPort3 "ether5"

# --- DNS ---
# Se voce usa Pi-Hole ou AdGuard, coloque o IP aqui.
# Clientes vao receber esse DNS + 1.1.1.1 como fallback via DHCP.
# Se nao usa, troque lPiHoleAddress pelo IP do router (ex: "192.168.100.1")
:local lPiHoleAddress "192.168.100.2"
:local lDNSServers "1.1.1.1,1.0.0.1,8.8.8.8,8.8.4.4"

# --- DHCP ---
:local lDHCPPoolRange "192.168.100.100-192.168.100.200"

# --- [OPCIONAL] DHCP Leases Estaticos ---
# Remove esta secao inteira se nao precisa de IPs fixos.
# Preencha com MAC e IP de cada dispositivo.
:local lPiHoleMAC "e0:51:d8:67:87:38"
:local lDesktopMAC "94:bb:43:0a:32:36"
:local lDesktopIP "192.168.100.10"
:local lArcherMAC "28:ee:52:95:10:28"
:local lArcherIP "192.168.100.3"
:local lClaroTVMAC "dc:97:e6:b4:b2:2b"
:local lClaroTVIP "192.168.100.20"

# --- Sistema ---
:local lTimeZone "America/Sao_Paulo"

# --- [OPCIONAL] Email ---
# Notificacoes por email quando um ISP cai ou volta.
# Usa Gmail SMTP. Crie uma App Password em: https://myaccount.google.com/apppasswords
# Para desabilitar, deixe lEmailEnable como false.
:local lEmailEnable false
:local lEmailAddress "your-email@gmail.com"
:local lEmailPassword "your-app-password"

# ==============================================================================
# RESET (limpa toda a config anterior)
# ==============================================================================
:put "WARNING: Starting DESTRUCTIVE configuration reset in 5 seconds..."
:put "WARNING: This will remove ALL firewall rules, routes, and NAT!"
:put "WARNING: Press Ctrl+C NOW to cancel."
:delay 5s

:put "Starting configuration reset..."

/system script environment remove [find]

:do { /system scheduler remove [/system scheduler find where name~"failover" || name~"memory" || name~"launcher" || name~"isp-monitor" || name~"check-memory" || name~"bootstrap" || name~"steering"] } on-error={}
:do { /system script remove [/system script find where name~"failover" || name~"enabler" || name~"config" || name~"dual-wan"] } on-error={}

:do { /ip firewall nat remove [/ip firewall nat find] } on-error={}
:do { /ip firewall mangle remove [/ip firewall mangle find] } on-error={}
:do { /ip firewall filter remove [/ip firewall filter find] } on-error={}
:do { /ip firewall raw remove [/ip firewall raw find] } on-error={}

:do { /ip route remove [/ip route find where !connect] } on-error={}
:do { /routing rule remove [/routing rule find] } on-error={}
:do { /routing table remove [/routing table find where name="ISP1" || name="ISP2" || name="ForceClaro"] } on-error={}

:do { /ip dhcp-client remove [/ip dhcp-client find interface=$lWAN1Interface] } on-error={}
:do { /ip dhcp-client remove [/ip dhcp-client find interface=$lWAN2Interface] } on-error={}

:do { /ip dhcp-server lease remove [/ip dhcp-server lease find where comment~"Static:"] } on-error={}
:do { /ip dhcp-server remove [/ip dhcp-server find name="lan-dhcp"] } on-error={}
:do { /ip dhcp-server network remove [/ip dhcp-server network find] } on-error={}
:do { /ip pool remove [/ip pool find name="lan-dhcp-pool"] } on-error={}

:do { /ip dns static remove [/ip dns static find] } on-error={}
:do { /ip firewall address-list remove [/ip firewall address-list find] } on-error={}

# Remove bridges (nosso + defconf do factory reset)
:do { /interface bridge remove [/interface bridge find name=$lLANInterface] } on-error={}
:do { /interface bridge remove [/interface bridge find name="bridge"] } on-error={}

:do { /interface list member remove [/interface list member find] } on-error={}

:delay 2s

# ==============================================================================
# [OPCIONAL] ROUTING TABLE - Traffic Steering
# ==============================================================================
# Forca dispositivos especificos a usar um ISP (ex: TV Box pela Claro).
# Se nao precisa de steering, remova esta secao, a secao "TRAFFIC STEERING"
# mais abaixo, e os scripts dos DHCP clients (linhas com "Steer:").
/routing table
add name=ForceClaro fib comment="Steering: Claro TV Box"

# ==============================================================================
# INTERFACES
# ==============================================================================
/interface list
:do { remove [find name="WAN"] } on-error={}
add name=WAN comment="WAN Interfaces"
:do { remove [find name="LAN"] } on-error={}
add name=LAN comment="LAN Interfaces"

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

/interface list member
:do { remove [find interface=$lWAN1Interface] } on-error={}
:do { remove [find interface=$lWAN2Interface] } on-error={}
:do { remove [find interface=$lLANInterface] } on-error={}
add list=WAN interface=$lWAN1Interface comment="WAN1"
add list=WAN interface=$lWAN2Interface comment="WAN2"
add list=LAN interface=$lLANInterface comment="LAN Bridge"

# ==============================================================================
# ADDRESS LISTS
# ==============================================================================
/ip firewall address-list
add address=$lLANSubnet list=LocalTraffic comment="LAN Subnet"
add address=$lLANSubnet list=Management comment="Management Access (LAN Only)"

# ==============================================================================
# IP / DHCP CLIENT
# ==============================================================================
# WAN recebe IP via DHCP dos roteadores/modems ISP.
# add-default-route=yes cria rotas ECMP automaticamente (mesma distancia = load balance).
# check-gateway=ping detecta ISP fora do ar em ~10s e redireciona trafego.
#
# Os scripts dentro de cada DHCP client criam rotas para o traffic steering.
# Se voce removeu a secao de steering, remova o parametro script= tambem.

/ip address
:do { remove [find interface=$lWAN1Interface] } on-error={}
:do { remove [find interface=$lWAN2Interface] } on-error={}
:do { remove [find interface=$lLANInterface] } on-error={}
add address=$lLANAddress interface=$lLANInterface comment="LAN"

/ip dhcp-client

add interface=$lWAN1Interface add-default-route=yes default-route-distance=1 check-gateway=ping use-peer-dns=no use-peer-ntp=no comment="DHCP: Vivo (WAN1)" disabled=no script=":local newGW \$\"lease-gateway\"
    :if ([:len \$newGW] > 0) do={
        :do { /ip route remove [find where comment=\"Steer: Vivo Fallback\"] } on-error={}
        /ip route add dst-address=0.0.0.0/0 gateway=\$newGW routing-table=ForceClaro distance=2 comment=\"Steer: Vivo Fallback\"
        :log info (\"[DHCP] Vivo gateway: \" . \$newGW)
    }"

add interface=$lWAN2Interface add-default-route=yes default-route-distance=1 check-gateway=ping use-peer-dns=no use-peer-ntp=no comment="DHCP: Claro (WAN2)" disabled=no script=":local newGW \$\"lease-gateway\"
    :if ([:len \$newGW] > 0) do={
        :do { /ip route remove [find where comment=\"Steer: Claro Primary\"] } on-error={}
        /ip route add dst-address=0.0.0.0/0 gateway=\$newGW routing-table=ForceClaro distance=1 comment=\"Steer: Claro Primary\"
        :log info (\"[DHCP] Claro gateway: \" . \$newGW)
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
:local lDHCPDNS ($lPiHoleAddress . ",1.1.1.1")
add address=$lLANSubnet gateway=$lLANGateway dns-server=$lDHCPDNS domain="internal" comment="LAN Network"

# ==============================================================================
# [OPCIONAL] DHCP LEASES ESTATICOS
# ==============================================================================
# IPs fixos por MAC address. Remova esta secao se nao precisa.
# Adicione ou remova linhas conforme seus dispositivos.
/ip dhcp-server lease
:do { remove [find where comment~"Static:"] } on-error={}
add address=$lPiHoleAddress mac-address=$lPiHoleMAC server=lan-dhcp comment="Static: Pi-Hole"
add address=$lDesktopIP mac-address=$lDesktopMAC server=lan-dhcp comment="Static: Desktop"
add address=$lArcherIP mac-address=$lArcherMAC server=lan-dhcp comment="Static: ArcherAX10"
add address=$lClaroTVIP mac-address=$lClaroTVMAC server=lan-dhcp comment="Static: Claro TV Box"

# ==============================================================================
# DNS
# ==============================================================================
# O router usa DNS externo (independente do Pi-Hole).
# Clientes recebem o Pi-Hole via DHCP (configurado acima).
# Se nao usa Pi-Hole, mude o dns-server na secao DHCP SERVER NETWORK.
/ip dns
set servers=$lDNSServers allow-remote-requests=yes cache-size=32768KiB cache-max-ttl=1d

# ==============================================================================
# [OPCIONAL] DNS HOSTNAMES
# ==============================================================================
# Nomes .internal para acessar dispositivos na rede local (ex: ping raspberrypi.internal).
# Remova esta secao se nao precisa.
/ip dns static
:do { remove [find where comment~"LAN:"] } on-error={}
add name="raspberrypi.internal" address=$lPiHoleAddress comment="LAN: Pi-Hole"
add name="desktopnix.internal" address=$lDesktopIP comment="LAN: Desktop"
add name="archerap.internal" address=$lArcherIP comment="LAN: ArcherAX10"
add name="clarotvbox.internal" address=$lClaroTVIP comment="LAN: Claro TV Box"

# ==============================================================================
# [OPCIONAL] TRAFFIC STEERING
# ==============================================================================
# Forca um dispositivo a usar um ISP especifico, com fallback pro outro.
# Neste exemplo, o Claro TV Box sempre sai pela Claro.
# As rotas da table ForceClaro sao criadas pelos scripts dos DHCP clients acima.
#
# Para adicionar mais dispositivos, crie routing rules adicionais.
# Para remover steering, apague esta secao, a routing table ForceClaro,
# e os scripts dos DHCP clients.
/routing rule
:do { remove [find where comment~"Steer:"] } on-error={}
:local lClaroTVCIDR ($lClaroTVIP . "/32")
add src-address=$lClaroTVCIDR action=lookup-only-in-table table=ForceClaro comment="Steer: Claro TV Box -> Claro"

# ==============================================================================
# MANGLE (MSS Clamping)
# ==============================================================================
/ip firewall mangle
add chain=forward protocol=tcp tcp-flags=syn action=change-mss new-mss=1400 passthrough=yes comment="Clamp MSS to 1400 (Safe for PPPoE/LTE/VPN)"

# ==============================================================================
# NAT
# ==============================================================================
/ip firewall nat
add chain=srcnat out-interface-list=WAN action=masquerade comment="NAT: Masquerade"

# ==============================================================================
# FIREWALL
# ==============================================================================
/ip firewall filter

# --- INPUT (trafego destinado ao router) ---
add chain=input connection-state=invalid action=drop comment="Drop: Invalid Input"
add chain=input connection-state=established,related action=accept comment="Accept: Established Input"
add chain=input protocol=tcp dst-port=8291 src-address-list=Management action=accept comment="Accept: WinBox (LAN)"
add chain=input protocol=tcp dst-port=80 src-address-list=Management action=accept comment="Accept: HTTP (LAN)"
add chain=input protocol=tcp dst-port=8728 src-address-list=Management action=accept comment="Accept: API (LAN)"
add chain=input protocol=icmp limit=10,5:packet action=accept comment="Limit: ICMP"
add chain=input protocol=icmp action=drop comment="Drop: Excess ICMP"
add chain=input in-interface=$lLANInterface action=accept comment="Accept: LAN Input"
add chain=input in-interface-list=WAN action=drop comment="Drop: WAN Input"

# --- FORWARD (trafego passando pelo router) ---
add chain=forward connection-state=invalid action=drop comment="Drop: Invalid Forward"
add chain=forward connection-state=established,related action=fasttrack-connection comment="FastTrack: Established/Related"
add chain=forward connection-state=established,related action=accept comment="Accept: Established Forward"
add chain=forward in-interface=$lLANInterface connection-state=new action=accept comment="Accept: LAN New Forward"
add chain=forward in-interface-list=WAN out-interface=$lLANInterface connection-state=established,related action=accept comment="Accept: WAN Return"
add chain=forward action=drop comment="Drop: All Other Forward"

# --- RAW (pre-processamento, antes do connection tracking) ---
/ip firewall raw
add chain=prerouting protocol=tcp dst-port=8291 src-address-list=!Management action=drop comment="Drop: WinBox from Internet"
add chain=prerouting protocol=tcp dst-port=22 src-address-list=!Management action=drop comment="Drop: SSH from Internet"

# Protecao contra SYN flood
add chain=prerouting in-interface-list=WAN protocol=tcp tcp-flags=syn limit=200,5:packet action=accept comment="SYN: Rate Limit"
add chain=prerouting in-interface-list=WAN protocol=tcp tcp-flags=syn action=drop comment="SYN: Drop Excess"

# Bloqueia IPs falsos/reservados vindos da WAN.
# NOTA: Se seu ISP entrega IP privado (ex: 192.168.x.x em modo roteador),
# desabilite a regra correspondente no Winbox ou ela vai bloquear o trafego.
add chain=prerouting in-interface-list=WAN src-address=0.0.0.0/8 action=drop comment="Drop: Bogon 0.0.0.0/8"
add chain=prerouting in-interface-list=WAN src-address=10.0.0.0/8 action=drop comment="Drop: Bogon RFC1918 10/8"
add chain=prerouting in-interface-list=WAN src-address=172.16.0.0/12 action=drop comment="Drop: Bogon RFC1918 172.16/12"
add chain=prerouting in-interface-list=WAN src-address=192.168.0.0/16 action=drop disabled=yes comment="Drop: Bogon RFC1918 192.168/16"
add chain=prerouting in-interface-list=WAN src-address=127.0.0.0/8 action=drop comment="Drop: Bogon Loopback"
add chain=prerouting in-interface-list=WAN src-address=224.0.0.0/4 action=drop comment="Drop: Bogon Multicast"

# ==============================================================================
# SERVICOS
# ==============================================================================
/ip service
set telnet disabled=yes
set ftp disabled=yes
set www address=$lLANSubnet disabled=no
set www-ssl address=$lLANSubnet disabled=no
set ssh address=$lLANSubnet disabled=no
set api disabled=yes
set api-ssl disabled=yes
set winbox address=$lLANSubnet disabled=no

:do { /tool mac-server set allowed-interface-list=LAN } on-error={}
:do { /tool mac-server mac-winbox set allowed-interface-list=LAN } on-error={}
:do { /tool bandwidth-server set enabled=no } on-error={}
:do { /ip proxy set enabled=no } on-error={}
:do { /ip socks set enabled=no } on-error={}
:do { /ip upnp set enabled=no } on-error={}
:do { /tool romon set enabled=no } on-error={}
/ip neighbor discovery-settings set discover-interface-list=LAN

# ==============================================================================
# SISTEMA
# ==============================================================================
:if ($lEmailEnable) do={
    :do { /tool e-mail set server="smtp.gmail.com" port=587 tls=starttls from="DualWAN-Router" user=$lEmailAddress password=$lEmailPassword } on-error={ :put "WARNING: Email config failed" }
}

/system clock set time-zone-name=$lTimeZone
/system identity set name="DualWAN-Router"
:do { /ipv6 settings set disable-ipv6=yes forward=no accept-redirects=no disable-link-local-address=yes } on-error={}
:do { /ipv6 firewall filter add chain=forward action=reject reject-with=icmp-no-route comment="Reject: All IPv6 forward (no IPv6 firewall configured)" } on-error={}
/ip settings set rp-filter=loose

/ip firewall connection tracking
set tcp-established-timeout=1h tcp-close-wait-timeout=10s udp-timeout=30s generic-timeout=5m

/system ntp client set enabled=yes
/system ntp client servers
:do { remove [/system ntp client servers find] } on-error={}
add address=time.cloudflare.com
add address=time.google.com
add address=time.nist.gov

# ==============================================================================
# [OPCIONAL] MONITOR DE ISP
# ==============================================================================
# Loga quando um ISP cai ou volta. Opcionalmente envia email.
# O failover em si e automatico (check-gateway). Isso e so notificacao.
# Remova esta secao se nao quer monitoramento.

:global WAN1Status "up"
:global WAN2Status "up"
:global WAN1DownCount 0
:global WAN2DownCount 0
:global WAN1UpCount 0
:global WAN2UpCount 0

/system scheduler
:do { remove [find name="isp-monitor"] } on-error={}
add name=isp-monitor interval=1m start-time=startup on-event={
    :global WAN1Status
    :global WAN2Status
    :global WAN1DownCount
    :global WAN2DownCount
    :global WAN1UpCount
    :global WAN2UpCount
    # Email: le direto do /tool e-mail (persiste no reboot)
    :local emailTo [/tool e-mail get user]
    :local emailOk ([:len $emailTo] > 0 && $emailTo != "")

    :local debounce 3

    :local wan1RouteActive ([:len [/ip route find where comment~"Vivo" and active]] > 0)
    :local wan2RouteActive ([:len [/ip route find where comment~"Claro" and active]] > 0)

    :local wan1PingOk false
    :if ($wan1RouteActive) do={
        :set wan1PingOk ([/ping 1.1.1.1 interface=ether1 count=2] > 0)
    }
    :local wan2PingOk false
    :if ($wan2RouteActive) do={
        :set wan2PingOk ([/ping 1.1.1.1 interface=ether2 count=2] > 0)
    }

    :local wan1Active ($wan1RouteActive && $wan1PingOk)
    :local wan2Active ($wan2RouteActive && $wan2PingOk)

    # --- WAN1 (Vivo) ---
    :if (!$wan1Active) do={
        :set WAN1DownCount ($WAN1DownCount + 1)
        :set WAN1UpCount 0
        :if ($WAN1DownCount = $debounce && $WAN1Status = "up") do={
            :set WAN1Status "down"
            :log error "[MONITOR] Vivo DOWN"
            :if ($emailOk) do={
                :do { /tool e-mail send to=$emailTo subject="[DualWAN] Vivo DOWN" body="Vivo caiu. Trafego redirecionado para Claro." } on-error={}
            }
        }
    } else={
        :set WAN1UpCount ($WAN1UpCount + 1)
        :set WAN1DownCount 0
        :if ($WAN1UpCount = $debounce && $WAN1Status = "down") do={
            :set WAN1Status "up"
            :log info "[MONITOR] Vivo RECOVERED"
            :if ($emailOk) do={
                :do { /tool e-mail send to=$emailTo subject="[DualWAN] Vivo voltou" body="Vivo voltou ao normal." } on-error={}
            }
        }
    }

    # --- WAN2 (Claro) ---
    :if (!$wan2Active) do={
        :set WAN2DownCount ($WAN2DownCount + 1)
        :set WAN2UpCount 0
        :if ($WAN2DownCount = $debounce && $WAN2Status = "up") do={
            :set WAN2Status "down"
            :log error "[MONITOR] Claro DOWN"
            :if ($emailOk) do={
                :do { /tool e-mail send to=$emailTo subject="[DualWAN] Claro DOWN" body="Claro caiu. Trafego redirecionado para Vivo." } on-error={}
            }
        }
    } else={
        :set WAN2UpCount ($WAN2UpCount + 1)
        :set WAN2DownCount 0
        :if ($WAN2UpCount = $debounce && $WAN2Status = "down") do={
            :set WAN2Status "up"
            :log info "[MONITOR] Claro RECOVERED"
            :if ($emailOk) do={
                :do { /tool e-mail send to=$emailTo subject="[DualWAN] Claro voltou" body="Claro voltou ao normal." } on-error={}
            }
        }
    }
}

# ==============================================================================
# [OPCIONAL] MONITOR DE MEMORIA
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

# Limpa conexoes para aplicar roteamento imediatamente
/ip firewall connection remove [/ip firewall connection find]

# ==============================================================================
# PRONTO
# ==============================================================================
:put ""
:put "========================================================================"
:put " Configuracao aplicada"
:put "========================================================================"
:put ""
:put ("WAN1: " . $lISP1Name . " (" . $lWAN1Interface . ")")
:put ("WAN2: " . $lISP2Name . " (" . $lWAN2Interface . ")")
:put "Load Balancing: ECMP com FastTrack"
:put "Failover: Automatico (~10s)"
:put ""
:put "Verificacao:"
:put "  /ip dhcp-client print"
:put "  /ip route print where dst-address=0.0.0.0/0"
:put "  /ip firewall filter print stats where comment~\"FastTrack\""
:put "  /log print follow where message~\"MONITOR\""
:put ""
:put "!! TROQUE A SENHA ADMIN !!"
:put "   /user set admin password=SUA-SENHA"
:put ""
