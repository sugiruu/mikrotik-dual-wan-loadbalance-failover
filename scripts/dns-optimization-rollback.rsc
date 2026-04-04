# DNS Optimization Rollback - Remove DNS redirect to Pi-Hole
# ==============================================================================
# Usage: /import scripts/dns-optimization-rollback.rsc
# ==============================================================================

:put "Removing DNS optimization..."

# Remove NAT redirect
:do { /ip firewall nat remove [find where comment~"Force DNS"] } on-error={}

# Remove DoT block
:do { /ip firewall raw remove [find where comment~"DoT"] } on-error={}

:put "DNS optimization removed."
:put "  Pi-Hole NAT redirect removed"
:put "  Devices will use whatever DNS they have configured"
