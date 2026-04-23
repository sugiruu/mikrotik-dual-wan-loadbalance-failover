# Claro SFP Swap - substitui o modem Claro em ether2 pelo stick SFP em sfp1
# ==============================================================================
# Pre-requisitos:
#   1. SFP GPON stick ja configurado pela UI em http://192.168.1.1 (ver README)
#      Campos minimos clonados do modem Claro: GPON SN, Vendor ID, Product Class,
#      HW Version, Device Serial Number
#   2. Stick fisicamente plugado em sfp1 com fibra conectada
#   3. DHCP client "client2" ativo na ether2 (bound) ou em sfp1 (searching)
#
# Uso:
#   /import scripts/claro-sfp-swap.rsc
#
# Rollback:
#   /import scripts/claro-sfp-swap-rollback.rsc
#
# NOTA sobre MAC:
#   NAO clonamos MAC. OLT ZTE da Claro faz DHCP-snoop: DHCPRELEASE desassocia
#   o MAC antigo, e o proximo DHCPDISCOVER com MAC novo recebe lease normal.
#   Solucao simples e sem risco de clash entre sfp1 e stick.
# ==============================================================================

:put "=== Claro SFP Swap ==="

# --- Garante acesso temp pra UI do stick (preservado pra diagnostico futuro) ---
:if ([:len [/ip address find where comment="Access GPON stick (temp)"]] = 0) do={
    /ip address add address=192.168.1.10/24 interface=sfp1 comment="Access GPON stick (temp)"
}
:if ([:len [/ip firewall nat find where comment="NAT to GPON stick (temp)"]] = 0) do={
    /ip firewall nat add chain=srcnat src-address=192.168.100.0/24 out-interface=sfp1 \
        action=masquerade comment="NAT to GPON stick (temp)"
}
:put "  Temp access pra UI do stick: ok"

# --- Raw exception pra stick admin (quando sfp1 entra na WAN list) ---
# Bogon RFC1918 192.168/16 dropa respostas do stick (src=192.168.1.1) antes de
# conntrack. Esta accept antes do bogon resolve.
:do { /ip firewall raw remove [find where comment="Allow GPON stick admin (pre-bogon)"] } on-error={}
/ip firewall raw add chain=prerouting action=accept in-interface=sfp1 \
    src-address=192.168.1.0/24 \
    place-before=[find where comment~"Bogon RFC1918 192.168"] \
    comment="Allow GPON stick admin (pre-bogon)"
:put "  Raw exception: 192.168.1.0/24 via sfp1 allowed (pre-bogon)"

# --- Release lease atual e desabilita client ---
# OLT recebe DHCPRELEASE e desassocia o MAC antigo do IP. Precisa disable
# depois do release pra cliente nao re-emitir DISCOVER imediatamente com
# o mesmo MAC antigo (que recuperaria o lease).
:do { /ip dhcp-client release [find where name=client2] } on-error={}
/ip dhcp-client disable [find where name=client2]
:put "  DHCP client2: released + disabled"
:delay 5s

# --- Garante sfp1 com MAC factory ---
# reset-mac-address eh idempotente (volta pro orig-mac-address do hardware).
# sfp-ignore-rx-los=yes mantem link Ethernet ativo mesmo com fiber flap.
/interface ethernet reset-mac-address sfp1
/interface ethernet set sfp1 sfp-ignore-rx-los=yes

# --- Move DHCP client pro sfp1 ---
/ip dhcp-client set [find where name=client2] interface=sfp1
:put "  DHCP client interface: ether2 -> sfp1"

# --- WAN interface-list: remove ether2, adiciona sfp1 ---
:do { /interface list member remove [find where interface=ether2 and list=WAN] } on-error={}
:if ([:len [/interface list member find where interface=sfp1 and list=WAN]] = 0) do={
    /interface list member add list=WAN interface=sfp1 comment="WAN2 (Claro SFP)"
}
:put "  WAN list: sfp1 no lugar de ether2"

# --- Move ether2 pra bridge-lan (vira porta LAN extra) ---
/interface enable ether2
:if ([:len [/interface bridge port find where interface=ether2 and bridge=bridge-lan]] = 0) do={
    /interface bridge port add bridge=bridge-lan interface=ether2 comment="LAN (ex-WAN2 Claro)"
}
:put "  ether2 adicionado ao bridge-lan (porta LAN)"

# --- Re-enable DHCP client (novo DISCOVER com MAC factory sfp1) ---
/ip dhcp-client enable [find where name=client2]
:put "  DHCP client2: enabled"

:delay 15s
:local st [/ip dhcp-client get [find where name=client2] status]
:put ("  DHCP status apos 15s: " . $st)

:put ""
:put "=== Verificacao ==="
:put "  /interface ethernet monitor sfp1 once       -> sfp-rx-loss: no, link-ok"
:put "  /ip dhcp-client print where name=client2    -> status=bound"
:put "  /tool ping 1.1.1.1 interface=sfp1 count=3   -> 0% loss"
:put "  /ip route print where dst-address=\"0.0.0.0/0\" -> 2 rotas ECMP (+ flag)"
:put ""
:put "Se DHCP continuar searching depois de 1min:"
:put "  1. Confirma stick O5: curl http://192.168.1.1/status_pon.asp via NAT"
:put "  2. Confirma que ONU MAC field (gpon.asp form inferior) NAO eh igual ao"
:put "     factory MAC da sfp1 - se for, muda pro factory da ONU e commita"
