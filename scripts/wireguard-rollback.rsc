# WireGuard VPN Rollback - Remove all WireGuard configuration
# ==============================================================================
# Usage: /import scripts/wireguard-rollback.rsc
# ==============================================================================

:put "Removing WireGuard VPN..."

:do { /interface wireguard peers remove [find where interface=wireguard1] } on-error={}
:do { /ip address remove [find where comment="WireGuard Subnet"] } on-error={}
:do { /ip firewall filter remove [find where comment="Accept: WireGuard VPN"] } on-error={}
:do { /ip firewall filter remove [find where comment="Accept: WireGuard to LAN"] } on-error={}
:do { /ip firewall address-list remove [find where comment="WireGuard VPN Subnet"] } on-error={}
:do { /interface wireguard remove [find name=wireguard1] } on-error={}
:do { /ip route remove [find where comment="Cloud: Force Vivo"] } on-error={}

/ip cloud set ddns-enabled=no

:put "WireGuard VPN removed."
