# Claro SFP Swap Rollback - volta pro modem Claro em ether2
# ==============================================================================
# Uso: /import scripts/claro-sfp-swap-rollback.rsc
#
# AVISO: execute ANTES de reconectar fisicamente o modem Claro.
#        Depois do rollback, desconecta fibra do stick e reconecta copper
#        do modem na ether2.
#
# NOTA: temp access pra UI do stick (IP 192.168.1.10/24 + NAT) NAO eh removido
# pelo rollback. Se quiser limpar, remove manualmente:
#   /ip firewall nat remove [find where comment="NAT to GPON stick (temp)"]
#   /ip address remove [find where comment="Access GPON stick (temp)"]
# ==============================================================================

:put "=== Claro SFP Swap Rollback ==="

# --- Release lease atual e desabilita client ---
# DHCPRELEASE desassocia o MAC do sfp1 no OLT. Se sobrar binding, o proximo
# DISCOVER via ether2 (MAC factory diferente) seria bloqueado.
:do { /ip dhcp-client release [find where name=client2] } on-error={}
/ip dhcp-client disable [find where name=client2]
:put "  DHCP client2: released + disabled"
:delay 5s

# --- Reset MACs pro factory (idempotente) ---
/interface ethernet reset-mac-address sfp1
/interface ethernet reset-mac-address ether2
:put "  MACs reset to factory (sfp1, ether2)"

# --- Remove ether2 do bridge-lan (volta a ser WAN) ---
:do { /interface bridge port remove [find where interface=ether2 and bridge=bridge-lan] } on-error={}
/interface enable ether2
:put "  ether2 removido do bridge-lan + enabled"

# --- Move DHCP client de volta pra ether2 ---
/ip dhcp-client set [find where name=client2] interface=ether2
:put "  DHCP client interface: sfp1 -> ether2"

# --- WAN interface-list: remove sfp1, adiciona ether2 ---
:do { /interface list member remove [find where interface=sfp1 and list=WAN] } on-error={}
:if ([:len [/interface list member find where interface=ether2 and list=WAN]] = 0) do={
    /interface list member add list=WAN interface=ether2 comment="WAN2 (Claro)"
}
:put "  WAN list: ether2 restaurado"

# --- Remove raw exception (nao eh mais necessaria fora da WAN list) ---
:do { /ip firewall raw remove [find where comment="Allow GPON stick admin (pre-bogon)"] } on-error={}
:put "  Raw exception removed"

# --- Re-enable DHCP client (novo DISCOVER via ether2 com MAC factory) ---
/ip dhcp-client enable [find where name=client2]
:put "  DHCP client2: enabled"

:put ""
:put "=== Proximos passos FISICOS ==="
:put "  1. Desconecta fibra do SFP stick (sfp1)"
:put "  2. Reconecta fibra no modem Claro (ONT)"
:put "  3. Reconecta cabo copper do modem Claro -> ether2"
:put "  4. Espera 30-60s pro DHCP renovar"
:put ""
:put "=== Verificacao ==="
:put "  /ip dhcp-client print where name=client2"
:put "  /tool ping 1.1.1.1 interface=ether2 count=3"
