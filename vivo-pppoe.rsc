# Vivo PPPoE Bridge Mode - Troca WAN1 de DHCP para PPPoE
# ==============================================================================
# Importe DEPOIS do script principal (mikrotik-dual-wan-ecmp.rsc).
# Coloque o modem da Vivo em bridge antes de importar.
#
# Uso: /import vivo-pppoe.rsc
#
# Para voltar ao modo DHCP: /import vivo-dhcp-rollback.rsc
# ==============================================================================

# --- Edite aqui ---
:local vivoUser "cliente@cliente"
:local vivoPass "cliente"
:local vivoVLAN 600
:local wanInterface "ether1"

:put "Configurando Vivo PPPoE (VLAN $vivoVLAN)..."

# Remove DHCP client da Vivo
:do { /ip dhcp-client remove [find where comment~"Vivo"] } on-error={}

# Cria VLAN na ether1
:do { /interface vlan remove [find where name="vlan600-vivo"] } on-error={}
/interface vlan add interface=$wanInterface vlan-id=$vivoVLAN name=vlan600-vivo comment="Vivo WAN VLAN"

# Cria PPPoE client na VLAN
:do { /interface pppoe-client remove [find where name="pppoe-vivo"] } on-error={}
/interface pppoe-client add interface=vlan600-vivo name=pppoe-vivo user=$vivoUser password=$vivoPass add-default-route=yes default-route-distance=1 use-peer-dns=no disabled=no comment="PPPoE: Vivo"

# Troca interface na WAN list
:do { /interface list member remove [find where comment~"WAN1"] } on-error={}
/interface list member add list=WAN interface=pppoe-vivo comment="WAN1 PPPoE (Vivo)"

# Atualiza o monitor para pingar pela interface PPPoE
/system scheduler set [find name="isp-monitor"] on-event={
    :global WAN1Status
    :global WAN2Status
    :global WAN1DownCount
    :global WAN2DownCount
    :global WAN1UpCount
    :global WAN2UpCount
    :global EmailEnable
    :global EmailTo

    :local debounce 3

    :local wan1PingOk ([/ping 1.1.1.1 interface=pppoe-vivo count=2] > 0)
    :local wan2RouteActive ([:len [/ip route find where comment~"Claro" and active]] > 0)
    :local wan2PingOk false
    :if ($wan2RouteActive) do={
        :set wan2PingOk ([/ping 1.1.1.1 interface=ether2 count=2] > 0)
    }

    :local wan1Active $wan1PingOk
    :local wan2Active ($wan2RouteActive && $wan2PingOk)

    :if (!$wan1Active) do={
        :set WAN1DownCount ($WAN1DownCount + 1)
        :set WAN1UpCount 0
        :if ($WAN1DownCount = $debounce && $WAN1Status = "up") do={
            :set WAN1Status "down"
            :log error "[MONITOR] Vivo DOWN"
            :if ($EmailEnable = true) do={
                :do { /tool e-mail send to=$EmailTo subject="[DualWAN] Vivo DOWN" body="Vivo caiu. Trafego redirecionado para Claro." } on-error={}
            }
        }
    } else={
        :set WAN1UpCount ($WAN1UpCount + 1)
        :set WAN1DownCount 0
        :if ($WAN1UpCount = $debounce && $WAN1Status = "down") do={
            :set WAN1Status "up"
            :log info "[MONITOR] Vivo RECOVERED"
            :if ($EmailEnable = true) do={
                :do { /tool e-mail send to=$EmailTo subject="[DualWAN] Vivo voltou" body="Vivo voltou ao normal." } on-error={}
            }
        }
    }

    :if (!$wan2Active) do={
        :set WAN2DownCount ($WAN2DownCount + 1)
        :set WAN2UpCount 0
        :if ($WAN2DownCount = $debounce && $WAN2Status = "up") do={
            :set WAN2Status "down"
            :log error "[MONITOR] Claro DOWN"
            :if ($EmailEnable = true) do={
                :do { /tool e-mail send to=$EmailTo subject="[DualWAN] Claro DOWN" body="Claro caiu. Trafego redirecionado para Vivo." } on-error={}
            }
        }
    } else={
        :set WAN2UpCount ($WAN2UpCount + 1)
        :set WAN2DownCount 0
        :if ($WAN2UpCount = $debounce && $WAN2Status = "down") do={
            :set WAN2Status "up"
            :log info "[MONITOR] Claro RECOVERED"
            :if ($EmailEnable = true) do={
                :do { /tool e-mail send to=$EmailTo subject="[DualWAN] Claro voltou" body="Claro voltou ao normal." } on-error={}
            }
        }
    }
}

:put ""
:put "Vivo PPPoE configurado."
:put "Verificacao:"
:put "  /interface pppoe-client print"
:put "  /ip route print where dst-address=0.0.0.0/0"
:put "  /tool ping 1.1.1.1 interface=pppoe-vivo count=3"
:put ""
