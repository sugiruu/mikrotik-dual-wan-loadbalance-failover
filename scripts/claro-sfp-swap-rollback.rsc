# Claro SFP Swap Rollback - volta pro modem Claro em ether2
# ==============================================================================
# Uso: /import scripts/claro-sfp-swap-rollback.rsc
#
# AVISO: execute ANTES de reconectar fisicamente o modem Claro.
#        Depois do rollback, desconecta fibra do stick e reconecta copper
#        do modem na ether2.
# ==============================================================================

:put "=== Claro SFP Swap Rollback ==="

# --- Re-habilita ether2 ---
/interface enable ether2

# --- Swap de MACs de volta (sfp1 <-> ether2) ---
# Lendo o estado atual e trocando. Idempotente: rodar 2x se auto-anula.
:local ether2CurMac [/interface ethernet get [find where name=ether2] mac-address]
:local sfp1CurMac [/interface ethernet get [find where name=sfp1] mac-address]
/interface ethernet set sfp1 mac-address=$ether2CurMac
/interface ethernet set ether2 mac-address=$sfp1CurMac
:put ("  MAC swap back: ether2=" . $sfp1CurMac . "  sfp1=" . $ether2CurMac)

# --- Move DHCP client de volta pra ether2 ---
/ip dhcp-client set [find where name=client2] interface=ether2
:put "  DHCP client: sfp1 -> ether2"

# --- WAN interface-list: remove sfp1, adiciona ether2 ---
:do { /interface list member remove [find where interface=sfp1 and list=WAN] } on-error={}
:if ([:len [/interface list member find where interface=ether2 and list=WAN]] = 0) do={
    /interface list member add list=WAN interface=ether2 comment="WAN2 (Claro)"
}
:put "  WAN interface-list: ether2 restaurado"

:put ""
:put "=== Proximos passos FISICOS ==="
:put "  1. Desconecte fibra do SFP stick (sfp1)"
:put "  2. Reconecte fibra no modem Claro (ONT)"
:put "  3. Reconecte cabo copper do modem Claro -> ether2"
:put "  4. Espere 30-60s pro DHCP renovar"
:put ""
:put "=== Verificacao ==="
:put "  /ip dhcp-client print where name=client2"
:put "  /tool ping 1.1.1.1 interface=ether2 count=3"
