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

# --- Registro DNS automatico de DHCP leases ---
# Quando um dispositivo pega ou libera lease, cria/remove registros DNS (A).
# Nao sobrescreve registros manuais (comment comeca com "LAN:").
# O Pi-Hole usa conditional forwarding pro MikroTik resolver esses nomes.

:do { /system script remove [find where name="dhcp-dns-lease"] } on-error={}
/system script add name="dhcp-dns-lease" source={
    :local token ("DHCP-" . $leaseActMAC)
    :if ($leaseBound = 1) do={
        :local hostName $"lease-hostname"
        :if ([:len $hostName] = 0) do={ :set hostName $leaseActMAC }
        :local upper "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        :local lower "abcdefghijklmnopqrstuvwxyz"
        :local clean ""
        :for i from=0 to=([:len $hostName] - 1) do={
            :local c [:pick $hostName $i]
            :local pos [:find $upper $c]
            :if ([:typeof $pos] = "num") do={
                :set clean ($clean . [:pick $lower $pos])
            } else={
                :if ($c ~ "[a-z0-9]") do={ :set clean ($clean . $c) } else={ :set clean ($clean . "-") }
            }
        }
        :set hostName $clean
        :local fqdn ($hostName . ".lan")
        :do { /ip dns static remove [find where comment=$token] } on-error={}
        :if ([:len [/ip dns static find where name=$fqdn and comment~"LAN:"]] = 0) do={
            /ip dns static add name=$fqdn address=$leaseActIP ttl=00:15:00 comment=$token
        }
    } else={
        :do { /ip dns static remove [find where comment=$token] } on-error={}
    }
}

/ip dhcp-server set lan-dhcp lease-script="/system script run dhcp-dns-lease"

:put "DNS optimization applied."
:put ("  LAN DNS queries redirected to Pi-Hole (" . $lPiHoleAddress . ")")
:put "  DHCP lease DNS registration enabled"
