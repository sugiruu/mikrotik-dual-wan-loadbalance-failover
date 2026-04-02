# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

MikroTik RouterOS v7 scripts for dual WAN load balancing (ECMP + FastTrack) with automatic failover. Written for Brazilian ISPs (Vivo + Claro) but adaptable to any DHCP-based ISPs. The user speaks Portuguese.

## Files

- `mikrotik-dual-wan-ecmp.rsc` -- main script, imported on MikroTik via `/import`
- `mikrotik-dual-wan.rsc` -- PCC alternative (original upstream script)
- `scripts/` -- auxiliary scripts, imported separately after the main script:
  - `wireguard-setup.rsc` -- WireGuard VPN setup (DDNS, firewall, tunnel)
  - `wireguard-rollback.rsc` -- removes all WireGuard config
  - `claro-static-restore.rsc` -- workaround: sets static IP when Claro bridge DHCP fails
  - `claro-dhcp-rollback.rsc` -- removes static IP and re-enables DHCP client
  - `vivo-pppoe.rsc` -- switches Vivo from DHCP to PPPoE (bridge mode)
  - `vivo-dhcp-rollback.rsc` -- reverts Vivo back to DHCP
  - `dns-optimization.rsc` -- DNS cache and optimization tweaks
- `local/` -- gitignored, contains credentials and local files (see `local/credentials.md`)

## RouterOS scripting gotchas

These were discovered through hardware testing and cause silent failures:

- **No `\` line continuation in imports.** RouterOS `/import` does not reliably handle `\` at end of line for command continuation. Put everything on one line, or use multiline strings (open quote, newlines, close quote).
- **No `connection-state` in raw table.** The raw table processes packets before connection tracking. Using `connection-state=new` in `/ip firewall raw` causes "expected end of command".
- **`defconf` rules survive script imports.** Factory reset creates firewall rules with "defconf" comments that are NOT removed by `/ip firewall filter remove [find]` if run too early. The cleanup section must aggressively remove all filter rules, the defconf bridge, interface list members, and DNS static entries.
- **DHCP client scripts run on lease events.** The `script=` parameter in `/ip dhcp-client add` executes on bound/renew. Use `\$` and `\"` for escaping inside the script string. Multiline strings work without `\` at line ends.
- **Duplicate DHCP leases fail.** RouterOS rejects two static leases pointing to the same IP address, even with different MACs. Each device needs a unique IP.
- **`add-default-route=yes` with `check-gateway=ping`** is the simplest way to create ECMP routes. RouterOS manages them automatically -- no custom scripts needed for the main routing table.

## Credentials

Never commit real credentials. Placeholders in the script: `your-email@gmail.com`, `your-app-password`. Real values go in `local/credentials.md` (gitignored). No Co-Authored-By lines in commits.

## Testing

There is no automated test suite. Scripts are tested by importing on real hardware (hEX S / RB760iGS). The workflow is:

1. Edit the `.rsc` file
2. Upload to MikroTik (Winbox > Files, or SCP)
3. `/import mikrotik-dual-wan-ecmp.rsc`
4. Verify with `/ip dhcp-client print`, `/ip route print`, `/ip firewall filter print`

SSH access for quick checks: `sshpass -p '<password>' ssh admin@192.168.100.1 '<command>'`

## Known issues

- **Claro bridge mode**: OLT ZTE doesn't recognize new MACs. Workaround: set static IP from old lease, wait for expiry, switch back to DHCP. See README for details.
- **Vivo bridge mode**: Requires PPPoE (not DHCP). Not implemented in the main script yet. Plan saved in memory (`plan_vivo_bridge.md`).
- **Bogon rules block private WAN IPs**: If ISP delivers 192.168.x.x (router mode), the raw bogon rule drops return traffic. Must be disabled manually.
