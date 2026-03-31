# Claro Static IP Restore - Re-apply static IP if DHCP rollback failed
# ==============================================================================
# Run this if claro-dhcp-rollback.rsc didn't work and you need internet back.
#
# Usage: /import claro-static-restore.rsc
# ==============================================================================

:put "Restoring Claro static IP..."

# Disable DHCP client
:do { /ip dhcp-client disable [find where comment~"Claro"] } on-error={}

# Add static IP (skip if already exists)
:if ([:len [/ip address find where comment="Claro Static (temp)"]] = 0) do={
    /ip address add address=YOUR.CLARO.IP/MASK interface=ether2 comment="Claro Static (temp)"
} else={
    :put "Static IP already exists"
}

# Add static route (skip if already exists)
:if ([:len [/ip route find where comment="ECMP: Claro (temp)"]] = 0) do={
    /ip route add dst-address=0.0.0.0/0 gateway=YOUR.CLARO.GATEWAY distance=1 check-gateway=ping comment="ECMP: Claro (temp)"
} else={
    :put "Static route already exists"
}

:delay 3s
:put "Testing connectivity..."
:local result [/tool ping address=1.1.1.1 interface=ether2 count=3]
:if ($result > 0) do={
    :put ("SUCCESS: Claro static IP working (" . $result . "/3 pings)")
} else={
    :put "FAILED: No connectivity. The lease may have expired on the OLT."
    :put "Call Claro (10621) and request OLT port reset."
}
