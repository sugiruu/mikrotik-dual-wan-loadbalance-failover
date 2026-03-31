# Claro DHCP Rollback - Remove static IP workaround and re-enable DHCP
# ==============================================================================
# Run this when the Claro static IP stops working (lease expired on OLT)
# or after calling Claro (10621) to request an OLT port reset.
#
# Usage: /import claro-dhcp-rollback.rsc
#
# WARNING: Claro internet will drop momentarily. Vivo will keep working.
# ==============================================================================

:put "Removing Claro static IP workaround..."

# Remove static IP
:do { /ip address remove [find where comment="Claro Static (temp)"] } on-error={ :put "No static IP found (already removed?)" }

# Remove static route
:do { /ip route remove [find where comment="ECMP: Claro (temp)"] } on-error={ :put "No static route found (already removed?)" }

# Enable DHCP client
:do { /ip dhcp-client enable [find where comment~"Claro"] } on-error={ :put "ERROR: Could not enable DHCP client" }

:put "DHCP client enabled. Waiting for lease..."
:delay 15s

:local status [/ip dhcp-client get [find where comment~"Claro"] status]
:put ("DHCP status: " . $status)

:if ($status = "bound") do={
    :local addr [/ip dhcp-client get [find where comment~"Claro"] address]
    :put ("SUCCESS: Claro got IP " . $addr)
    :put "DHCP is working. No further action needed."
} else={
    :put ""
    :put "DHCP did not get a lease yet."
    :put "Options:"
    :put "  1. Wait a few minutes and check: /ip dhcp-client print"
    :put "  2. Call Claro (10621) and request OLT port reset"
    :put "  3. To restore static IP, run: /import claro-static-restore.rsc"
}
