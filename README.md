# MikroTik Dual WAN Load Balancing + Failover | RouterOS v7

[![MikroTik](https://img.shields.io/badge/MikroTik-RouterOS%20v7-blue)](https://mikrotik.com)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

MikroTik RouterOS v7 configurations for dual WAN load balancing with automatic failover. Two approaches are included -- pick the one that fits your setup:

| Script | Method | FastTrack | Throughput (hEX S) | Use when... |
|--------|--------|-----------|-------------------|-------------|
| [`mikrotik-dual-wan-ecmp.rsc`](#ecmp--fasttrack) | ECMP + FastTrack | Yes | ~900 Mbps | You want max speed and simplicity |
| [`mikrotik-dual-wan.rsc`](#pcc-load-balancing) | PCC + Mangle | No | ~300-400 Mbps | You need custom load balance ratios |

**Requires**: RouterOS v7.20+, 2 WAN ports + 3 LAN ports minimum, Winbox or SSH access.

Tested on: RB760iGS (hEX S), RB750Gr3, E50UG

---

## ECMP + FastTrack

Uses Equal-Cost Multi-Path routing with FastTrack. Failover is native via `check-gateway=ping` -- no scheduler scripts needed. This is the simpler and faster option.

**What it does:**
- Two default routes (same distance) -- the kernel distributes flows across both ISPs
- FastTrack accelerates established connections, bypassing firewall for near wire-speed
- `check-gateway=ping` detects a dead ISP in ~10s and shifts all traffic automatically
- Supports DHCP on WAN interfaces (for ISP routers in bridge mode)
- Traffic steering: force specific devices to a specific ISP (with fallback)
- Pi-Hole DNS support, static DHCP leases, `.lan` hostnames
- ISP state monitoring with optional email alerts
- Firewall hardening, service lockdown, IPv6 disabled

### Quick Start

**1. Download and edit variables:**

```bash
wget https://raw.githubusercontent.com/sugiruu/mikrotik-dual-wan-loadbalance-failover/main/mikrotik-dual-wan-ecmp.rsc
```

Open the file and set your interfaces, IPs, MAC addresses, and timezone at the top.

**2. Upload and import:**

> [!WARNING]
> This script **resets your router config**. Be physically connected -- don't run this over VPN or remote tunnel.

```routeros
/import mikrotik-dual-wan-ecmp.rsc
```

**3. Verify:**

```routeros
/ip dhcp-client print detail                           # WAN IPs from ISPs
/ip route print where dst-address=0.0.0.0/0            # Two ECMP routes, both active
/ip firewall filter print stats where comment~"FastTrack"  # FastTrack processing traffic
/log print follow where message~"MONITOR"              # ISP state changes
```

### How it works

```
Client -> MikroTik -> ECMP hash (src + dst + port)
                      |-- Flow A -> ISP1
                      |-- Flow B -> ISP2
                      (FastTrack kicks in after connection is established)
```

Each flow (unique src+dst+port combo) sticks to one ISP. If an ISP goes down, `check-gateway=ping` deactivates that route and all traffic goes through the surviving one.

### Traffic steering

You can force specific devices to always use one ISP. The ECMP script includes an example: Claro TV Box is forced to Claro with automatic fallback to Vivo.

This works via a routing rule + a dedicated routing table -- no mangle rules needed:

```routeros
/routing rule
add src-address=192.168.100.20/32 action=lookup-only-in-table table=ForceClaro
```

The `ForceClaro` table has Claro at distance 1 and Vivo at distance 2. If Claro goes down, the device automatically fails over.

---

## PCC Load Balancing

Uses Per Connection Classifier with mangle rules. More control, more complexity, and no FastTrack (every packet hits the CPU).

> **Throughput note**: PCC disables FastTrack. On a hEX S, expect ~300-400 Mbps. For 500+ Mbps, consider RB5009 or RB4011.

**What it does:**
- PCC distributes connections across WANs with configurable ratio (1:1, 2:1, 3:1, etc.)
- Dual-IP failover monitoring -- pings two IPs per ISP, only triggers if both fail
- Connection cleanup on failover (kills stuck connections for faster recovery)
- Cross-ISP failover with failsafe routes
- Tiered email alerts (1h, 6h, daily reminders, recovery)
- Self-healing startup logic for v7 stability

### Quick Start

**1. Download and edit variables:**

```bash
wget https://raw.githubusercontent.com/sugiruu/mikrotik-dual-wan-loadbalance-failover/main/mikrotik-dual-wan.rsc
```

Set your WAN/LAN IPs, interfaces, gateways, monitor IPs, and email config.

**2. Upload and import:**

> [!WARNING]
> This script **resets your router config**. Be physically connected -- don't run this over VPN or remote tunnel.

```routeros
/import mikrotik-dual-wan.rsc
/system reboot
```

**3. Verify:**

```routeros
/ip route print detail where dst-address=0.0.0.0/0     # Routes active
/system scheduler print detail where name=dual-ip-failover  # Scheduler running
/log print follow where message~"FAILOVER"              # Failover events
/ip firewall connection print where connection-mark~"ISP"   # PCC distribution
```

### How it works

```
Client -> MikroTik -> PCC Classifier (both-addresses-and-ports hash)
                      |-- Hash 0..N -> ISP1
                      |-- Hash N+1..M -> ISP2
```

Each new connection gets classified once and sticks to that ISP for its lifetime. A scheduler runs every 10 seconds, pinging monitor IPs through each WAN. If both monitors fail for an ISP, it disables routes and PCC rules, killing stuck connections.

### Customization (PCC)

**Load balance ratio** -- favor the faster ISP:
```routeros
:local lLBRatio1 3  # ISP1 gets 75%
:local lLBRatio2 1  # ISP2 gets 25%
```

**Failover sensitivity**:
```routeros
:local lFailureThreshold 2  # Consecutive failures before DOWN (default: 2 = 20s)
```

**Preferred ISP**:
```routeros
:local lPreferredISP "ISP1"  # or "ISP2"
```

**Email alerts** (uses Gmail SMTP by default):
```routeros
:local lEmailEnable true
:local lEmailAddress "your-email@gmail.com"
:local lEmailPassword "your-app-password"
```

---

## Performance

Both scripts will show combined bandwidth on multi-connection speed tests:

| ISP1 | ISP2 | Combined |
|------|------|----------|
| 500 Mbps | 100 Mbps | ~600 Mbps |
| 300 Mbps | 300 Mbps | ~600 Mbps |

Single-connection tests (like a single download) will only use one ISP -- that's expected.

**Failover timing:**
- ECMP: ~10 seconds (check-gateway native)
- PCC: ~20 seconds (scheduler-based)

**Works well with**: browsing, streaming, downloads, gaming.
**Brief interruption on failover**: VoIP calls, live streams, long SSH sessions.

---

## Security

Both scripts include:
- Firewall blocks all WAN-to-router traffic
- WinBox and WebFig restricted to LAN subnet only
- ICMP rate limiting
- Invalid connection dropping
- Telnet, FTP, SSH disabled by default
- MAC WinBox limited to LAN bridge
- IPv6 disabled (no IPv6 firewall rules, so it's safer to turn it off)

**You should also**: change the default admin password and schedule regular backups.

---

## Troubleshooting

**Routes inactive**: Check WAN cables and that ISP routers are delivering IPs. For ECMP, check `/ip dhcp-client print`. For PCC, check gateway reachability with `/tool ping`.

**No load balancing**: For PCC, check `/ip firewall connection print where connection-mark~"ISP"` -- you should see a mix of ISP1 and ISP2 marks. For ECMP, check that both routes show as active.

**Failover not working**: For ECMP, verify `check-gateway=ping` is set on both routes. For PCC, check `/log print where message~"FAILOVER"` and verify monitor IPs are reachable.

**Speed only shows one ISP**: Normal for single-connection tests. Use multi-threaded tests (Speedtest.net, OpenSpeedTest).

---

## Contributing

1. Fork the repo
2. Create a feature branch
3. Test on actual hardware
4. Submit a PR with a clear description

When reporting issues, include: RouterOS version, router model, your config variables, and relevant logs from `/log print`.

---

## License

MIT -- do whatever you want with it.

---

## Credits

Based on [vishnunuk/mikrotik-dual-wan-loadbalance-failover](https://github.com/vishnunuk/mikrotik-dual-wan-loadbalance-failover). ECMP script and additional features by [@sugiruu](https://github.com/sugiruu).
