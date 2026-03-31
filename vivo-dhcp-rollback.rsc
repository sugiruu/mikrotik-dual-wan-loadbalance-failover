# Vivo DHCP Rollback - Volta WAN1 de PPPoE para DHCP
# ==============================================================================
# Use se o PPPoE nao funcionou e precisa voltar ao modo DHCP (Vivo em modo roteador).
#
# Uso: /import vivo-dhcp-rollback.rsc
# ==============================================================================

:put "Revertendo Vivo para DHCP..."

# Remove PPPoE client
:do { /interface pppoe-client remove [find where name="pppoe-vivo"] } on-error={}

# Remove VLAN
:do { /interface vlan remove [find where name="vlan600-vivo"] } on-error={}

# Desabilita regra bogon 192.168 (DHCP pode receber IP privado do modem em modo roteador)
:do { /ip firewall raw disable [find where comment~"192.168"] } on-error={}

# Remove entrada PPPoE da WAN list
:do { /interface list member remove [find where comment~"WAN1 PPPoE"] } on-error={}

# Recria DHCP client na ether1 (se nao existir)
:do { /ip dhcp-client remove [find where interface=ether1] } on-error={}
:if ([:len [/ip dhcp-client find where interface=ether1]] = 0) do={
    /ip dhcp-client add interface=ether1 add-default-route=yes default-route-distance=1 check-gateway=ping use-peer-dns=no use-peer-ntp=no comment="DHCP: Vivo (WAN1)" disabled=no
}

# Volta ether1 na WAN list (se nao existir)
:if ([:len [/interface list member find where interface=ether1 and list=WAN]] = 0) do={
    /interface list member add list=WAN interface=ether1 comment="WAN1 (Vivo)"
}

# Restaura monitor para usar ether1 (nao pppoe-vivo)
:do { :local monitorScript [/system scheduler get [find name="isp-monitor"] on-event]; } on-error={}
:put "ATENCAO: Se o monitor de ISP estiver com erro, reimporte o update-monitor.rsc"

:delay 10s

:local status [/ip dhcp-client get [find where interface=ether1] status]
:put ("DHCP status: " . $status)

:if ($status = "bound") do={
    :put "OK: Vivo voltou para DHCP."
} else={
    :put "DHCP ainda conectando. Verifique: /ip dhcp-client print"
}
