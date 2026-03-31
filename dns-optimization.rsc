# dns-optimization.rsc
# Importar DEPOIS do mikrotik-dual-wan-ecmp.rsc
# Forca DNS do Pi-Hole pela Vivo e redireciona DNS da LAN pro Pi-Hole

:local lPiHoleAddress "192.168.100.2"
:local lRouterAddress "192.168.100.1"
:local lLANSubnet "192.168.100.0/24"

# --- Parte 1: DNS do Pi-Hole sempre pela Vivo ---

# Routing table
:do { /routing table remove [find where name="ForceVivo"] } on-error={}
/routing table add name=ForceVivo fib comment="Force DNS via Vivo"

# Rotas (Vivo primary, Claro fallback)
:do { /ip route remove [find where comment~"ForceVivo"] } on-error={}
/ip route add dst-address=0.0.0.0/0 gateway=pppoe-vivo routing-table=ForceVivo distance=1 comment="ForceVivo: Vivo"
:local claroGW [/ip dhcp-client get [find where interface=ether2] gateway]
:if ([:len $claroGW] > 0) do={
    /ip route add dst-address=0.0.0.0/0 gateway=$claroGW routing-table=ForceVivo distance=2 comment="ForceVivo: Claro Fallback"
}

# Mangle: marca DNS do Pi-Hole
:do { /ip firewall mangle remove [find where comment~"DNS: Pi-Hole"] } on-error={}
/ip firewall mangle add chain=prerouting src-address=$lPiHoleAddress protocol=udp dst-port=53 action=mark-routing new-routing-mark=ForceVivo passthrough=no comment="DNS: Pi-Hole via Vivo"
/ip firewall mangle add chain=prerouting src-address=$lPiHoleAddress protocol=tcp dst-port=53 action=mark-routing new-routing-mark=ForceVivo passthrough=no comment="DNS: Pi-Hole via Vivo (TCP)"

# --- Parte 2: Redirecionar DNS da LAN pro Pi-Hole ---

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

:put "DNS optimization applied."
:put ("  Pi-Hole DNS upstream forced via Vivo (PPPoE)")
:put ("  LAN DNS queries redirected to Pi-Hole (" . $lPiHoleAddress . ")")
