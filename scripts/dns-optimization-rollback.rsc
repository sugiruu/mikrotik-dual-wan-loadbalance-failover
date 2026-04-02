# DNS Optimization Rollback - Remove all DNS optimization rules
# ==============================================================================
# Reverts dns-optimization.rsc changes. DNS goes back to ECMP (no forcing).
#
# Usage: /import scripts/dns-optimization-rollback.rsc
# ==============================================================================

:put "Removing DNS optimization..."

# Remove mangle rules
:do { /ip firewall mangle remove [find where comment~"DNS: Pi-Hole"] } on-error={}
:do { /ip firewall mangle remove [find where comment="Mark: Pi-Hole DNS"] } on-error={}

# Remove NAT redirect
:do { /ip firewall nat remove [find where comment~"Force DNS"] } on-error={}

# Restore original FastTrack (without connection-mark exclusion)
:do { /ip firewall filter remove [find where comment~"FastTrack"] } on-error={}
/ip firewall filter add chain=forward connection-state=established,related action=fasttrack-connection comment="FastTrack: Established/Related" place-before=[find where comment="Accept: Established Forward"]

# Remove routing table and routes
:do { /ip route remove [find where comment~"ForceVivo"] } on-error={}
:do { /routing table remove [find where name="ForceVivo"] } on-error={}

:put "DNS optimization removed."
:put "  DNS now uses ECMP (both WANs)"
:put "  FastTrack restored to default"
:put "  Pi-Hole NAT redirect removed"
