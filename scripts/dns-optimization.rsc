# dns-optimization.rsc
# Importar DEPOIS do mikrotik-dual-wan-ecmp.rsc
# Redireciona DNS da LAN pro Pi-Hole

:local lPiHoleAddress "192.168.100.2"
:local lLANSubnet "192.168.100.0/24"

# --- Redirecionar DNS da LAN pro Pi-Hole ---

# Intercepta queries DNS da LAN que NAO vao pro Pi-Hole
# Excecoes:
#   dst=Pi-Hole: ja vai pra la, nao redireciona
#   src=Pi-Hole: query upstream do Pi-Hole, nao redireciona (evita loop)
#   in-interface=bridge-lan: so trafego da LAN (nao WAN, nao router)
:do { /ip firewall nat remove [find where comment~"Force DNS"] } on-error={}
:local lNotPiHole ("!" . $lPiHoleAddress)
/ip firewall nat add chain=dstnat src-address=$lNotPiHole dst-address=$lNotPiHole protocol=udp dst-port=53 in-interface=bridge-lan action=dst-nat to-addresses=$lPiHoleAddress comment="Force DNS to Pi-Hole"
/ip firewall nat add chain=dstnat src-address=$lNotPiHole dst-address=$lNotPiHole protocol=tcp dst-port=53 in-interface=bridge-lan action=dst-nat to-addresses=$lPiHoleAddress comment="Force DNS to Pi-Hole (TCP)"

# SNAT: reescreve source pra MikroTik, senao a resposta do Pi-Hole volta com IP errado e o cliente rejeita
/ip firewall nat add chain=srcnat dst-address=$lPiHoleAddress protocol=udp dst-port=53 src-address=$lLANSubnet action=masquerade comment="Force DNS to Pi-Hole (SNAT)"
/ip firewall nat add chain=srcnat dst-address=$lPiHoleAddress protocol=tcp dst-port=53 src-address=$lLANSubnet action=masquerade comment="Force DNS to Pi-Hole (SNAT TCP)"

# --- Bloquear DNS over TLS (DoT) ---
# Dispositivos com "DNS Privado" (Android) usam DoT na porta 853
# pra bypassar o Pi-Hole. Esta regra forca o fallback pro DNS normal (porta 53)
# que e redirecionado pro Pi-Hole pelas regras acima.
# Regra na RAW pra funcionar antes do FastTrack.
:do { /ip firewall raw remove [find where comment~"DoT"] } on-error={}
/ip firewall raw add chain=prerouting protocol=tcp dst-port=853 src-address=$lLANSubnet action=drop comment="Block DoT (force Pi-Hole)"

:put "DNS optimization applied."
:put ("  LAN DNS queries redirected to Pi-Hole (" . $lPiHoleAddress . ")")
