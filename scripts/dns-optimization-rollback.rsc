# DNS Optimization Rollback - Remove DNS redirect to Pi-Hole
# ==============================================================================
# Usage: /import scripts/dns-optimization-rollback.rsc
# ==============================================================================

:put "Removing DNS optimization..."

# Remove NAT redirect
:do { /ip firewall nat remove [find where comment~"Force DNS"] } on-error={}

# Remove DoT block
:do { /ip firewall raw remove [find where comment~"DoT"] } on-error={}

# Remove DHCP lease DNS registration
/ip dhcp-server set lan-dhcp lease-script=""
:do { /system script remove [find where name="dhcp-dns-lease"] } on-error={}

# Remove dynamic DNS entries created by lease script
:do { /ip dns static remove [find where comment~"DHCP-"] } on-error={}

:put "DNS optimization removed."
:put "  Pi-Hole NAT redirect removed"
:put "  DHCP lease DNS registration disabled"
:put "  Devices will use whatever DNS they have configured"
