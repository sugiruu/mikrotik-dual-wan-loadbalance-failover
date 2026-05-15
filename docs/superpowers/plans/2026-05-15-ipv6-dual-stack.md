# IPv6 Dual-Stack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Habilitar IPv6 dual-stack na MikroTik hEX S (RouterOS v7) com NAT66 nas duas WANs (Vivo PPPoE + Claro SFP GPON), espelhando a segurança IPv4 atual, sem mexer no script principal.

**Architecture:** ULA `fd64:1e57:9364:1::/64` na LAN, DHCPv6-PD na Vivo, SLAAC na Claro, NAT66 masquerade em cada WAN. Conntrack mantém conexões pinned na WAN escolhida pelo ECMP → uRPF dos BNGs aprova. Empacotamento: 2 scripts auxiliares (`ipv6-setup.rsc` + `ipv6-rollback.rsc`), script principal não muda.

**Tech Stack:** RouterOS v7 scripting (`.rsc`), `/import` no Mikrotik via SSH, validação via `/print` commands. Sem framework de teste — validação é via comandos do RouterOS + `dig`/`ping`/`curl` no Linux desktop. Hardware: hEX S (RB760iGS).

**Pré-requisitos confirmados (não fazer parte deste plano):**
- ✅ Pi-Hole AAAA habilitado manualmente (verificado via `dig @192.168.100.2 google.com AAAA`)
- ✅ ECMP IPv4 funcionando (Vivo PPPoE + Claro SFP1)
- ✅ Vivo entrega DHCPv6-PD `/64`, Claro entrega SLAAC público (investigação 2026-05-15)
- ✅ SSH access ao MikroTik (`admin@192.168.100.1`, senha em `local/credentials.md`)

**Convenção de comandos no router** (usada em todas as tasks):

A senha admin do MikroTik está em `local/credentials.md` (gitignored, primeira seção `## MikroTik`). Antes de começar, extraia em variável de shell pra reusar:

```bash
export MK_PASS=$(awk '/^## MikroTik/{f=1;next} /^## /{f=0} f && /Admin password:/{print $NF; exit}' local/credentials.md)
# Validar:
echo "MK_PASS tem ${#MK_PASS} chars"  # esperado: 10 chars
sshpass -p "$MK_PASS" ssh -o StrictHostKeyChecking=no admin@192.168.100.1 '/system identity print'
# esperado: "name: <hostname>"
```

Todos os comandos das tasks abaixo usam `"$MK_PASS"` — exporte uma vez no início da sessão.

---

## File Structure

| File | Responsibility | Status |
|------|----------------|--------|
| `scripts/ipv6-setup.rsc` | Idempotente. Habilita stack, configura DHCPv6 Vivo, ULA LAN, RA, NAT66, firewall input/forward/raw, FastTrack v6. Reconecta `pppoe-vivo` pra forçar IPv6CP. | Create |
| `scripts/ipv6-rollback.rsc` | Idempotente. Reverte tudo do setup. Volta `disable-ipv6=yes` + reject forward (estado pós-script-principal). | Create |
| `README.md` | Adicionar 2 linhas na tabela de scripts auxiliares + seção "IPv6 dual-stack" explicando o NAT66 e o gotcha do IPv6CP. | Modify |
| `mikrotik-dual-wan-ecmp.rsc` | **NÃO modifica** — continua `disable-ipv6=yes` | — |
| `scripts/dns-optimization.rsc` | **NÃO modifica** — dstnat IPv4 já intercepta tudo | — |

---

## Task 1: Esqueleto do `scripts/ipv6-setup.rsc`

**Files:**
- Create: `scripts/ipv6-setup.rsc`

- [ ] **Step 1: Criar arquivo com header + variáveis + cleanup inicial**

```rsc
# ipv6-setup.rsc
# Importar DEPOIS do mikrotik-dual-wan-ecmp.rsc e vivo-pppoe.rsc
# Habilita IPv6 dual-stack com NAT66 nas duas WANs (ECMP via conntrack pinning).
#
# Topologia:
#   - Vivo (pppoe-vivo): DHCPv6-PD recebe /64 da Vivo + SLAAC WAN address
#   - Claro (sfp1): SLAAC publico /64 (sem PD)
#   - LAN (bridge-lan): ULA fd64:1e57:9364:1::/64, RA pra clientes
#   - NAT66 masquerade nas duas WANs (resolve uRPF do BNG)
#
# Gotcha: IPv6CP no PPPoE so negocia se IPv6 stack estiver ON na hora do connect.
# Por isso este script reconecta pppoe-vivo (Vivo cai ~10s).
#
# Rollback: /import scripts/ipv6-rollback.rsc

:local lVivoIf "pppoe-vivo"
:local lClaroIf "sfp1"
:local lLanIf "bridge-lan"
:local lLanULA "fd64:1e57:9364:1::1/64"
:local lLanULAPrefix "fd64:1e57:9364:1::/64"

:put "Configurando IPv6 dual-stack..."

# --- 1. Limpa regra do script principal que rejeita IPv6 forward ---
:do { /ipv6 firewall filter remove [find where comment~"Reject: All IPv6 forward"] } on-error={}
```

- [ ] **Step 2: Validar conteúdo do arquivo**

Run: `head -25 scripts/ipv6-setup.rsc`

Expected: header completo, 5 variáveis definidas, primeira regra de cleanup.

- [ ] **Step 3: Commit**

```bash
git add scripts/ipv6-setup.rsc
git commit -m "wip: ipv6-setup.rsc skeleton with vars and cleanup"
```

---

## Task 2: Bloco "Stack IPv6"

**Files:**
- Modify: `scripts/ipv6-setup.rsc` (append)

- [ ] **Step 1: Adicionar bloco stack ao final do arquivo**

Append exatamente isso:

```rsc

# --- 2. Stack IPv6 ---
# accept-RA whitelist nas WANs (nao LAN — evita rogue RA injection).
# forward=yes pra router rotear IPv6 entre interfaces.
/ipv6 settings set disable-ipv6=no forward=yes disable-link-local-address=no accept-router-advertisements=yes accept-router-advertisements-on=($lClaroIf . "," . $lVivoIf)
```

- [ ] **Step 2: Validar**

Run: `grep -n "ipv6 settings" scripts/ipv6-setup.rsc`

Expected: 1 linha com `disable-ipv6=no forward=yes ... accept-router-advertisements-on=`

- [ ] **Step 3: Commit**

```bash
git add scripts/ipv6-setup.rsc
git commit -m "wip: ipv6-setup.rsc stack settings"
```

---

## Task 3: Bloco "DHCPv6 Vivo + reconnect"

**Files:**
- Modify: `scripts/ipv6-setup.rsc` (append)

- [ ] **Step 1: Adicionar bloco DHCPv6 + reconnect**

```rsc

# --- 3. Reconnect pppoe-vivo pra forcar IPv6CP ---
# Pula se pppoe-vivo nao existir (script principal puro, sem vivo-pppoe.rsc).
# Sem IPv6CP, DHCPv6 nunca completa.
:if ([:len [/interface pppoe-client find where name=$lVivoIf]] > 0) do={
    :put "Reconectando $lVivoIf (Vivo cai ~10s)..."
    /interface pppoe-client disable [find name=$lVivoIf]
    :delay 3s
    /interface pppoe-client enable [find name=$lVivoIf]
    :delay 12s
}

# --- 4. DHCPv6 client Vivo (request=prefix) ---
:do { /ipv6 dhcp-client remove [find where comment~"DHCPv6: Vivo"] } on-error={}
/ipv6 dhcp-client add interface=$lVivoIf request=prefix add-default-route=yes default-route-distance=1 use-peer-dns=no pool-name=vivo-pd6 pool-prefix-length=64 comment="DHCPv6: Vivo PD"

# Claro: SLAAC e default route automaticos via accept-RA whitelist (acima), nada a configurar.
```

- [ ] **Step 2: Validar**

Run: `grep -nE "pppoe-client disable|dhcp-client add interface" scripts/ipv6-setup.rsc`

Expected: 1 linha disable, 1 linha enable, 1 linha dhcp-client add.

- [ ] **Step 3: Commit**

```bash
git add scripts/ipv6-setup.rsc
git commit -m "wip: ipv6-setup.rsc dhcpv6 vivo + pppoe reconnect"
```

---

## Task 4: Bloco "LAN ULA + RA"

**Files:**
- Modify: `scripts/ipv6-setup.rsc` (append)

- [ ] **Step 1: Adicionar bloco LAN**

```rsc

# --- 5. LAN: ULA + ND/RA ---
# advertise=yes faz hosts LAN derivarem endereco SLAAC do prefixo /64.
:do { /ipv6 address remove [find where comment~"IPv6: LAN ULA"] } on-error={}
/ipv6 address add address=$lLanULA interface=$lLanIf advertise=yes comment="IPv6: LAN ULA"

# SLAAC puro: managed=no other=no (sem DHCPv6 server na LAN).
:do { /ipv6 nd remove [find where interface=$lLanIf and !default] } on-error={}
/ipv6 nd add interface=$lLanIf advertise-mac-address=yes managed-address-configuration=no other-configuration=no comment="IPv6: LAN RA"
```

- [ ] **Step 2: Validar**

Run: `grep -nE "ipv6 address add|ipv6 nd add" scripts/ipv6-setup.rsc`

Expected: 1 address add, 1 nd add.

- [ ] **Step 3: Commit**

```bash
git add scripts/ipv6-setup.rsc
git commit -m "wip: ipv6-setup.rsc lan ula + slaac ra"
```

---

## Task 5: Bloco "Address-list LocalTraffic6"

**Files:**
- Modify: `scripts/ipv6-setup.rsc` (append)

- [ ] **Step 1: Adicionar bloco address-list**

```rsc

# --- 6. Address-list LocalTraffic6 (espelho IPv4 LocalTraffic) ---
:do { /ipv6 firewall address-list remove [find where list="LocalTraffic6"] } on-error={}
/ipv6 firewall address-list add list=LocalTraffic6 address=$lLanULAPrefix comment="LAN ULA"
```

- [ ] **Step 2: Validar**

Run: `grep -n "address-list add" scripts/ipv6-setup.rsc`

Expected: 1 linha (LocalTraffic6).

- [ ] **Step 3: Commit**

```bash
git add scripts/ipv6-setup.rsc
git commit -m "wip: ipv6-setup.rsc address-list LocalTraffic6"
```

---

## Task 6: Bloco "NAT66 masquerade"

**Files:**
- Modify: `scripts/ipv6-setup.rsc` (append)

- [ ] **Step 1: Adicionar bloco NAT66**

```rsc

# --- 7. NAT66 masquerade nas duas WANs ---
# Conntrack mantem cada conexao pinned na WAN escolhida pelo ECMP hash.
# Resolve uRPF: pacote sai com src=address da WAN de saida, nunca cross-WAN.
:do { /ipv6 firewall nat remove [find where comment~"NAT66"] } on-error={}
/ipv6 firewall nat add chain=srcnat out-interface=$lVivoIf action=masquerade comment="NAT66: Vivo masquerade"
/ipv6 firewall nat add chain=srcnat out-interface=$lClaroIf action=masquerade comment="NAT66: Claro masquerade"
```

- [ ] **Step 2: Validar**

Run: `grep -n "ipv6 firewall nat add" scripts/ipv6-setup.rsc`

Expected: 2 linhas (Vivo + Claro masquerade).

- [ ] **Step 3: Commit**

```bash
git add scripts/ipv6-setup.rsc
git commit -m "wip: ipv6-setup.rsc nat66 masquerade"
```

---

## Task 7: Bloco "Firewall input"

**Files:**
- Modify: `scripts/ipv6-setup.rsc` (append)

- [ ] **Step 1: Adicionar bloco firewall input**

```rsc

# --- 8. Firewall IPv6 input ---
# Espelho do IPv4 com diferencas:
#   - Sem accept management (ssh/www/winbox) IPv6 — fica IPv4-only
#   - ICMPv6 nao pode rate-limitar inteiro (NDP/MLD essenciais); rate-limit so echo-request
#   - Accept link-local source (fe80::/10) necessario pra NDP
#   - Accept DHCPv6 client reply (UDP 546) pra receber PD da Vivo
:do { /ipv6 firewall filter remove [find where chain=input] } on-error={}
/ipv6 firewall filter add chain=input action=drop connection-state=invalid comment="Drop: Invalid Input"
/ipv6 firewall filter add chain=input action=accept connection-state=established,related,untracked comment="Accept: Established Input"
# ICMPv6: rate-limit so echo-request (type 128). NDP/MLD/errors passam sem
# limite — sao essenciais e podem ser muitos pacotes legitimos. Drop excess
# echo-request apos o limit.
/ipv6 firewall filter add chain=input action=accept protocol=icmpv6 icmp-options=128:0 limit=50,5:packet comment="Limit: ICMPv6 echo-request"
/ipv6 firewall filter add chain=input action=drop protocol=icmpv6 icmp-options=128:0 comment="Drop: Excess ICMPv6 echo"
/ipv6 firewall filter add chain=input action=accept protocol=icmpv6 comment="Accept: ICMPv6 (NDP/MLD/PTB/errors)"
/ipv6 firewall filter add chain=input action=accept src-address=fe80::/10 comment="Accept: Link-local Source"
/ipv6 firewall filter add chain=input action=accept in-interface=$lLanIf comment="Accept: LAN Input"
/ipv6 firewall filter add chain=input action=accept protocol=udp dst-port=546 comment="Accept: DHCPv6 client"
/ipv6 firewall filter add chain=input action=drop comment="Drop: WAN Input (default)"
```

- [ ] **Step 2: Validar**

Run: `grep -c "chain=input" scripts/ipv6-setup.rsc`

Expected: `9` add + `1` remove.

- [ ] **Step 3: Commit**

```bash
git add scripts/ipv6-setup.rsc
git commit -m "wip: ipv6-setup.rsc firewall input chain"
```

---

## Task 8: Bloco "Firewall forward + FastTrack"

**Files:**
- Modify: `scripts/ipv6-setup.rsc` (append)

- [ ] **Step 1: Adicionar bloco firewall forward**

```rsc

# --- 9. Firewall IPv6 forward + FastTrack ---
# FastTrack ANTES de qualquer outra regra (matched conns bypassam conntrack/firewall).
# Drop invalid logo depois pra rejeitar conns malformadas que escaparam FastTrack.
:do { /ipv6 firewall filter remove [find where chain=forward] } on-error={}
/ipv6 firewall filter add chain=forward action=fasttrack-connection connection-state=established,related comment="FastTrack: Established/Related"
/ipv6 firewall filter add chain=forward action=drop connection-state=invalid comment="Drop: Invalid Forward"
/ipv6 firewall filter add chain=forward action=accept connection-state=established,related,untracked comment="Accept: Established Forward"
/ipv6 firewall filter add chain=forward action=accept src-address-list=LocalTraffic6 comment="Accept: LAN New Forward"
/ipv6 firewall filter add chain=forward action=accept protocol=icmpv6 hop-limit=equal:1 comment="Accept: ICMPv6 link-local hops"
/ipv6 firewall filter add chain=forward action=drop comment="Drop: All Other Forward"
```

- [ ] **Step 2: Validar**

Run: `grep -c "chain=forward" scripts/ipv6-setup.rsc`

Expected: `7` (6 add + 1 remove).

- [ ] **Step 3: Commit**

```bash
git add scripts/ipv6-setup.rsc
git commit -m "wip: ipv6-setup.rsc firewall forward + fasttrack"
```

---

## Task 9: Bloco "Firewall raw (bogons)"

**Files:**
- Modify: `scripts/ipv6-setup.rsc` (append)

- [ ] **Step 1: Adicionar bloco raw**

```rsc

# --- 10. Firewall IPv6 raw (bogons + DoT block) ---
# Espelho do raw IPv4: bogons na WAN (early-drop pre-conntrack) + block DoT da LAN.
# fc00::/7 cobre todo ULA externo (LAN ULA vem por bridge-lan, nao por WAN).
:do { /ipv6 firewall raw remove [find where comment~"IPv6 bogon" or comment~"IPv6: Block DoT"] } on-error={}
/ipv6 firewall raw add chain=prerouting action=drop src-address=::/128 in-interface-list=WAN comment="IPv6 bogon: unspecified src from WAN"
/ipv6 firewall raw add chain=prerouting action=drop src-address=fc00::/7 in-interface-list=WAN comment="IPv6 bogon: ULA from WAN"
/ipv6 firewall raw add chain=prerouting action=drop src-address=::1/128 in-interface-list=WAN comment="IPv6 bogon: loopback from WAN"
/ipv6 firewall raw add chain=prerouting action=drop src-address=ff00::/8 in-interface-list=WAN comment="IPv6 bogon: multicast as src from WAN"
/ipv6 firewall raw add chain=prerouting action=drop src-address=2001:db8::/32 in-interface-list=WAN comment="IPv6 bogon: documentation range from WAN"
/ipv6 firewall raw add chain=prerouting action=drop src-address=::ffff:0:0/96 in-interface-list=WAN comment="IPv6 bogon: IPv4-mapped from WAN"
/ipv6 firewall raw add chain=prerouting action=drop protocol=tcp dst-port=853 src-address-list=LocalTraffic6 comment="IPv6: Block DoT (force Pi-Hole)"
```

- [ ] **Step 2: Validar**

Run: `grep -c "ipv6 firewall raw add" scripts/ipv6-setup.rsc`

Expected: `7` (6 bogons + 1 DoT).

- [ ] **Step 3: Adicionar mensagem final ao script**

```rsc

:put ""
:put "IPv6 configurado. Verificacao:"
:put "  /ipv6 address print"
:put "  /ipv6 route print where dst-address=\"::/0\""
:put "  /ipv6 dhcp-client print"
:put "  /tool ping 2606:4700:4700::1111 src-address=$lLanULA count=3"
:put ""
:put "Teste externo (de host LAN):"
:put "  ping -6 ipv6.google.com"
:put "  curl https://test-ipv6.com"
```

- [ ] **Step 4: Validar arquivo completo**

Run: `wc -l scripts/ipv6-setup.rsc && grep -c "^[^#]" scripts/ipv6-setup.rsc`

Expected: arquivo ~90-100 linhas, ~40+ linhas não-comentário.

- [ ] **Step 5: Commit**

```bash
git add scripts/ipv6-setup.rsc
git commit -m "feat: add ipv6-setup.rsc (NAT66 dual-stack + firewall)"
```

---

## Task 10: Criar `scripts/ipv6-rollback.rsc`

**Files:**
- Create: `scripts/ipv6-rollback.rsc`

- [ ] **Step 1: Criar arquivo de rollback completo**

```rsc
# ipv6-rollback.rsc
# Reverte ipv6-setup.rsc - volta IPv6 desabilitado (estado pos-mikrotik-dual-wan-ecmp.rsc).
#
# Uso: /import scripts/ipv6-rollback.rsc

:put "Revertendo IPv6..."

# DHCPv6 client
:do { /ipv6 dhcp-client remove [find where comment~"DHCPv6: Vivo"] } on-error={}

# LAN address + ND
:do { /ipv6 address remove [find where comment~"IPv6: LAN ULA"] } on-error={}
:do { /ipv6 nd remove [find where comment~"IPv6: LAN RA"] } on-error={}

# Address-list
:do { /ipv6 firewall address-list remove [find where list="LocalTraffic6"] } on-error={}

# NAT66
:do { /ipv6 firewall nat remove [find where comment~"NAT66"] } on-error={}

# Firewall input + forward
:do { /ipv6 firewall filter remove [find where chain=input] } on-error={}
:do { /ipv6 firewall filter remove [find where chain=forward] } on-error={}

# Firewall raw (bogons + DoT)
:do { /ipv6 firewall raw remove [find where comment~"IPv6 bogon" or comment~"IPv6: Block DoT"] } on-error={}

# Pool dinamico (removido junto com dhcp-client mas garantia)
:do { /ipv6 pool remove [find where name="vivo-pd6"] } on-error={}

# Recria regra reject all forward (igual mikrotik-dual-wan-ecmp.rsc:338)
:do { /ipv6 firewall filter add chain=forward action=reject reject-with=icmp-no-route comment="Reject: All IPv6 forward (no IPv6 firewall configured)" } on-error={}

# Desabilita stack
/ipv6 settings set disable-ipv6=yes disable-link-local-address=yes forward=no accept-router-advertisements=yes-if-forwarding-disabled accept-router-advertisements-on=all

:put "IPv6 desabilitado. Estado igual apos mikrotik-dual-wan-ecmp.rsc."
:put "Nota: addresses/rotas dinamicas cached podem aparecer como 'I' (invalid) ate TTL expirar - inofensivo."
```

- [ ] **Step 2: Validar arquivo**

Run: `wc -l scripts/ipv6-rollback.rsc && grep -c "^[^#]" scripts/ipv6-rollback.rsc`

Expected: ~30-35 linhas, ~15-18 não-comentário.

- [ ] **Step 3: Verificar simetria com setup (cada componente adicionado é removido)**

Run:
```bash
echo "=== setup adiciona: ==="; grep -oE "(ipv6 [a-z-]+|firewall [a-z]+ add)" scripts/ipv6-setup.rsc | sort -u
echo "=== rollback remove: ==="; grep -oE "(ipv6 [a-z-]+|firewall [a-z]+ remove)" scripts/ipv6-rollback.rsc | sort -u
```

Expected: cada `add` no setup tem `remove` correspondente no rollback (exceto reject forward, que é recriado).

- [ ] **Step 4: Commit**

```bash
git add scripts/ipv6-rollback.rsc
git commit -m "feat: add ipv6-rollback.rsc"
```

---

## Task 11: Upload + Import `ipv6-setup.rsc` no router

**Files:**
- Touch (remote): `pppoe-vivo` será disable/enable (Vivo cai ~10s)

**Pré-condição:** verificar que está conectado de host LAN ou via WireGuard (NÃO de outra rede), e que tem `sshpass` instalado:
```bash
which sshpass || echo "INSTALAR: sudo pacman -S sshpass"
```

- [ ] **Step 1: Upload do script pro router**

Run:
```bash
sshpass -p "$MK_PASS" scp -O scripts/ipv6-setup.rsc admin@192.168.100.1:ipv6-setup.rsc
```

Expected: copia silenciosa, sem erro.

- [ ] **Step 2: Verificar que arquivo subiu**

Run:
```bash
sshpass -p "$MK_PASS" ssh admin@192.168.100.1 '/file print where name=ipv6-setup.rsc'
```

Expected: 1 linha mostrando o arquivo com size > 2KB.

- [ ] **Step 3: Import (Vivo cai 10s durante import)**

Run:
```bash
sshpass -p "$MK_PASS" ssh admin@192.168.100.1 '/import ipv6-setup.rsc'
```

Expected output (excerto):
```
Configurando IPv6 dual-stack...
Reconectando pppoe-vivo (Vivo cai ~10s)...
IPv6 configurado. Verificacao:
  /ipv6 address print
  ...
Script file loaded and executed successfully
```

Se erro: rodar Task 13 (rollback) e investigar.

- [ ] **Step 4: Commit (registra que script foi executado)**

Nenhum commit aqui — só altera estado do router.

---

## Task 12: Validação técnica (router-side)

**Files:** none (só leitura no router)

- [ ] **Step 1: Verificar IPv6 addresses**

Run:
```bash
sshpass -p "$MK_PASS" ssh admin@192.168.100.1 '/ipv6 address print'
```

Expected: ver:
- `fd64:1e57:9364:1::1/64` em `bridge-lan` (ULA, advertise=yes)
- `fe80::*/64` em `bridge-lan`, `sfp1`, `pppoe-vivo`, `ether1` (link-local)
- `2804:14c:5ba0:1000:*/64` em `sfp1` (DG, SLAAC Claro)
- (possivelmente) endereço SLAAC em `pppoe-vivo` (`2804:1b2:*`)

- [ ] **Step 2: Verificar default routes IPv6 (ECMP)**

Run:
```bash
sshpass -p "$MK_PASS" ssh admin@192.168.100.1 '/ipv6 route print where dst-address="::/0"'
```

Expected: 2 rotas `::/0`:
- `DAg+ ::/0  fe80::d6c1:c8ff:fe1c:aae9%sfp1  main  1` (Claro)
- `DAv+ ::/0  pppoe-vivo  main  1` (Vivo)

Ambas com flag `+` (ECMP) e distance=1.

- [ ] **Step 3: Verificar DHCPv6 client Vivo**

Run:
```bash
sshpass -p "$MK_PASS" ssh admin@192.168.100.1 '/ipv6 dhcp-client print detail'
```

Expected: status=`bound`, `prefix=2804:1b2:*::/64, *h*m*s` (lifetime).

- [ ] **Step 4: Verificar NAT66**

Run:
```bash
sshpass -p "$MK_PASS" ssh admin@192.168.100.1 '/ipv6 firewall nat print'
```

Expected: 2 regras srcnat masquerade (Vivo + Claro).

- [ ] **Step 5: Verificar firewall counts**

Run:
```bash
sshpass -p "$MK_PASS" ssh admin@192.168.100.1 ':put ([:len [/ipv6 firewall filter find where chain=input]] . " input rules"); :put ([:len [/ipv6 firewall filter find where chain=forward]] . " forward rules"); :put ([:len [/ipv6 firewall raw find]] . " raw rules")'
```

Expected:
- `9 input rules`
- `6 forward rules`
- `7 raw rules`

---

## Task 13: Validação funcional (router-side + LAN-side)

**Files:** none (testes ao vivo)

- [ ] **Step 1: Ping IPv6 do router via Vivo (source forçado)**

Run:
```bash
sshpass -p "$MK_PASS" ssh admin@192.168.100.1 '/ping 2606:4700:4700::1111 src-address=fd64:1e57:9364:1::1 count=3'
```

Expected: 3 echo replies, latência ~5-20ms.

- [ ] **Step 2: Traceroute IPv6 do router**

Run:
```bash
sshpass -p "$MK_PASS" ssh admin@192.168.100.1 '/tool traceroute 2606:4700:4700::1111 src-address=fd64:1e57:9364:1::1 count=1 max-hops=8 timeout=2s'
```

Expected: hops mostrando IPs `2804:14c:*` (Claro) ou `2804:1b2:*` (Vivo) até `2606:4700:4700::1111`.

- [ ] **Step 3: Test from LAN host (Linux/Mac)**

De um host LAN com IPv6 (verificar com `ip -6 addr show | grep "fd64:1e57"`):

Run:
```bash
ping -6 -c 3 ipv6.google.com
```

Expected: 3 echo replies. Se "Cannot assign requested address", host LAN ainda não pegou IPv6 — esperar ~30s (RA periodicidade) ou rodar `sudo dhclient -6` / desligar+ligar wifi.

- [ ] **Step 4: Test dual-stack from LAN host**

Run:
```bash
curl -s https://test-ipv6.com/json/index.json | grep -E "ipv4|ipv6" | head -5
```

Expected: `ipv6_address` populado, `ipv4_address` populado.

- [ ] **Step 5: Sanity check de DNS AAAA fluxo end-to-end**

Run:
```bash
dig @192.168.100.2 ipv6.google.com AAAA +short
```

Expected: 1 ou mais endereços `2607:*` ou similar (não vazio).

---

## Task 14: Teste de rollback

**Files:** none (testa rollback no router)

- [ ] **Step 1: Upload do rollback**

Run:
```bash
sshpass -p "$MK_PASS" scp -O scripts/ipv6-rollback.rsc admin@192.168.100.1:ipv6-rollback.rsc
```

- [ ] **Step 2: Import rollback**

Run:
```bash
sshpass -p "$MK_PASS" ssh admin@192.168.100.1 '/import ipv6-rollback.rsc'
```

Expected:
```
Revertendo IPv6...
IPv6 desabilitado. Estado igual apos mikrotik-dual-wan-ecmp.rsc.
Script file loaded and executed successfully
```

- [ ] **Step 3: Verificar estado pós-rollback**

Run:
```bash
sshpass -p "$MK_PASS" ssh admin@192.168.100.1 '/ipv6 settings print; :put "---"; /ipv6 firewall filter print where chain=forward; :put "---"; /ipv6 firewall nat print; :put "---"; /ipv6 dhcp-client print'
```

Expected:
- `disable-ipv6: yes`
- Forward chain: 1 regra `reject ... icmp-no-route` (a do script principal)
- NAT chain: vazio (sem regras IPv6)
- DHCPv6 client: vazio

- [ ] **Step 4: Re-aplicar setup pra deixar IPv6 ON**

Run:
```bash
sshpass -p "$MK_PASS" ssh admin@192.168.100.1 '/import ipv6-setup.rsc'
```

(Volta a ter IPv6 ativo. Vivo cai ~10s de novo.)

- [ ] **Step 5: Re-validar com Task 12 Step 5**

Run:
```bash
sshpass -p "$MK_PASS" ssh admin@192.168.100.1 ':put ([:len [/ipv6 firewall filter find where chain=input]] . " input rules")'
```

Expected: `9 input rules` (estado IPv6 ON de volta).

---

## Task 15: Atualizar README + commit final

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Adicionar 2 linhas na tabela de scripts auxiliares**

Localizar a linha:
```markdown
| `scripts/dns-optimization.rsc` | Redireciona DNS pro Pi-Hole + bloqueia DoT | Quer forçar todo DNS pelo Pi-Hole |
```

E adicionar abaixo:
```markdown
| `scripts/ipv6-setup.rsc` | Habilita IPv6 dual-stack com NAT66 nas duas WANs | Quer IPv6 na LAN (ver seção IPv6 abaixo) |
| `scripts/ipv6-rollback.rsc` | Reverte tudo de IPv6 (volta `disable-ipv6=yes`) | Quer desfazer o IPv6 |
```

- [ ] **Step 2: Adicionar seção "IPv6 dual-stack" antes de "Regras bogon"**

Localizar `## Regras bogon` e inserir antes:

```markdown
## IPv6 dual-stack (Vivo + Claro)

Habilita IPv6 nas duas WANs com NAT66 (masquerade IPv6 → endereço global da WAN de saída). LAN recebe ULA `fd64:1e57:9364:1::/64` via SLAAC.

```
/import scripts/ipv6-setup.rsc
```

**O que cada ISP entrega:**
- **Vivo**: DHCPv6-PD `/64` + SLAAC WAN address (negociado via PPP/IPv6CP)
- **Claro**: só SLAAC público `/64` (sem PD; bloco `2804:14c:5ba0:1000::/64`)

**Por que NAT66 em vez de ECMP IPv6 puro:** os BNGs das duas ISPs fazem uRPF strict. Em ECMP puro, o MikroTik pode escolher mandar tráfego com source da WAN A pela WAN B, e o BNG da WAN B dropa. NAT66 masquerade resolve: o tráfego sempre sai com o endereço da WAN de saída.

**Failover:** funciona igual IPv4 — `check-gateway=ping` na default route, monitor de ISP. Conexões já estabelecidas pinned na WAN morta caem; novas conexões usam a WAN viva.

**Gotcha do IPv6CP:** o PPPoE com a Vivo só negocia IPv6 se a stack IPv6 do MikroTik estiver ON na hora do `connect`. O script já reconecta o `pppoe-vivo` (10s offline) pra forçar isso.

**Pré-requisito Pi-Hole:** desabilitar `filter-AAAA` em Pi-hole admin → Settings → All settings → DNS → "Additional dnsmasq lines". Senão hosts LAN não resolvem AAAA e IPv6 não é usado pra hostname.

Pra reverter: `/import scripts/ipv6-rollback.rsc`

```

- [ ] **Step 3: Validar README**

Run: `grep -c "ipv6-setup.rsc" README.md && grep -c "## IPv6 dual-stack" README.md`

Expected: `2` e `1` (2 ocorrências do script: tabela + seção; 1 título de seção).

- [ ] **Step 4: Commit final**

```bash
git add README.md
git commit -m "docs: add IPv6 dual-stack section to README"
```

---

## Critério de sucesso final (cobre todos os pontos do spec)

Após executar tasks 1-15:

| # | Critério do spec | Como validar | Task |
|---|------------------|--------------|------|
| 1 | `/ipv6 address print` mostra ULA, SLAAC sfp1, link-local pppoe-vivo, PD vivo-pd6 | `sshpass... /ipv6 address print` | 12.1 |
| 2 | 2 default routes IPv6 ECMP | `... /ipv6 route print where dst-address="::/0"` | 12.2 |
| 3 | Ping 2606:4700:4700::1111 com src ULA retorna echo reply | `... /ping ... src-address=fd64:...` | 13.1 |
| 4 | De host LAN, `ping6 ipv6.google.com` funciona | `ping -6 ipv6.google.com` | 13.3 |
| 5 | `curl test-ipv6.com` reporta dual-stack | `curl ... /json/index.json` | 13.4 |
| 6 | Failover IPv6 funciona (deferido — não inclui pull-cable test no plano) | Manual, fora do plano (opcional) | — |
| 7 | Rollback volta ao estado pré | Task 14.3 | 14 |

Item 6 (failover) é deferido — implica desconectar fisicamente uma WAN, o que requer presença física e disruption real. Pode ser feito como teste manual posterior pelo user.

---

## Rollback de emergência

Se durante qualquer task algo der errado e a internet IPv4 também cair (improvável, mas):

1. Acessar router via console/winbox em IP de fábrica (192.168.88.1) se houver — *não aplica aqui, sem console*
2. Pull cable de uma WAN, conectar laptop direto em ether2 ou ether3, acessar 192.168.100.1
3. Importar rollback:
   ```bash
   sshpass -p "$MK_PASS" ssh admin@192.168.100.1 '/import ipv6-rollback.rsc'
   ```
4. Se rollback falhar: `/ipv6 settings set disable-ipv6=yes` manualmente e remover regras criadas via Winbox.

IPv4 NUNCA é afetado por esse plano (script só toca `/ipv6 ...` paths). O único impacto IPv4 é o 5-10s de PPPoE Vivo reconnect — coberto pelo ECMP IPv4 (tráfego vai pra Claro temporariamente).
