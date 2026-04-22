# Claro SFP Swap - substitui o modem Claro em ether2 pelo stick SFP em sfp1
# ==============================================================================
# Pre-requisitos:
#   1. SFP GPON stick ja configurado (GPON SN, Vendor ID, Product Class, HW,
#      SW, Device Serial Number, MAC e OUI clonados do modem Claro original)
#   2. Stick fisicamente plugado na sfp1 (sem fibra ainda)
#   3. DHCP client "client2" ativo na ether2 (estado normal pre-swap)
#
# Uso:
#   /import scripts/claro-sfp-swap.rsc
#
# Rollback:
#   /import scripts/claro-sfp-swap-rollback.rsc
# ==============================================================================

:put "=== Claro SFP Swap ==="

# --- Remove recursos temporarios da fase de config do stick ---
# IP secundario e NAT que existiam so pra acessar o 192.168.1.1 do stick.
# Apos o swap, o stick vira passthrough GPON e a UI nao eh mais acessivel.
:do { /ip firewall nat remove [find where comment="NAT to GPON stick (temp)"] } on-error={}
:do { /ip address remove [find where comment="Access GPON stick (temp)"] } on-error={}
:put "  Cleanup temp access: ok"

# --- Swap de MACs (ether2 <-> sfp1) ---
# sfp1 fica com o MAC que o OLT Claro ja conhece -> lease DHCP preservado.
# ether2 fica com o MAC antigo do sfp1 pra nao duplicar MAC.
:local ether2CurMac [/interface ethernet get [find where name=ether2] mac-address]
:local sfp1CurMac [/interface ethernet get [find where name=sfp1] mac-address]
/interface ethernet set sfp1 mac-address=$ether2CurMac
/interface ethernet set ether2 mac-address=$sfp1CurMac
:put ("  MAC swap: sfp1=" . $ether2CurMac . "  ether2=" . $sfp1CurMac)

# --- Garante sfp-ignore-rx-los (caso tenha resetado) ---
/interface ethernet set sfp1 sfp-ignore-rx-los=yes

# --- Move DHCP client pro sfp1 ---
/ip dhcp-client set [find where name=client2] interface=sfp1
:put "  DHCP client: ether2 -> sfp1"

# --- WAN interface-list: remove ether2, adiciona sfp1 ---
:do { /interface list member remove [find where interface=ether2 and list=WAN] } on-error={}
:if ([:len [/interface list member find where interface=sfp1 and list=WAN]] = 0) do={
    /interface list member add list=WAN interface=sfp1 comment="WAN2 (Claro SFP)"
}
:put "  WAN interface-list: sfp1 adicionado"

# --- Desabilita ether2 (nao eh mais WAN) ---
/interface disable ether2
:put "  ether2 disabled"

:put ""
:put "=== Proximos passos FISICOS ==="
:put "  1. Desconecte cabo copper do modem Claro -> ether2"
:put "  2. Desconecte fibra do modem Claro (ONT)"
:put "  3. Conecte fibra no SFP GPON stick (sfp1)"
:put "  4. Espere 30-60s pro stick autenticar com o OLT"
:put ""
:put "=== Verificacao ==="
:put "  /interface ethernet monitor sfp1 once"
:put "    -> sfp-rx-loss: no, status: link-ok"
:put "  /ip dhcp-client print where name=client2"
:put "    -> status=bound, com IP publico/CGNAT entregue pela Claro"
:put "  /tool ping 1.1.1.1 interface=sfp1 count=3"
:put "    -> 0% packet loss"
:put "  /ip route print where dst-address=\"0.0.0.0/0\" and active"
:put "    -> duas rotas ECMP (pppoe-vivo + sfp1 gateway)"
:put ""
:put "Se DHCP nao pegar lease em 2 min, rodar rollback e investigar VLAN."
