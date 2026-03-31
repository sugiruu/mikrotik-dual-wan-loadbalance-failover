# MikroTik Dual WAN - ECMP + FastTrack

Script para RouterOS v7 que configura duas conexões de internet com load balancing e failover automático.

Testado com **Vivo + Claro** no Brasil, mas funciona com qualquer combinação de ISPs que entregue IP via DHCP (modo roteador ou bridge).

## O que faz

- **Load balancing**: distribui conexões entre as duas WANs usando ECMP (Equal-Cost Multi-Path)
- **FastTrack**: conexões estabelecidas são aceleradas pelo hardware, sem passar pelo firewall (~900Mbps no hEX S)
- **Failover**: se um ISP cair, o tráfego vai automaticamente pro outro em ~10 segundos (via `check-gateway=ping`)
- **Traffic steering**: força dispositivos específicos (ex: TV Box) a usar um ISP, com fallback pro outro
- **Firewall**: bloqueia acesso externo, rate limit de ICMP e SYN, proteção contra IP spoofing
- **DHCP server**: com suporte a leases estáticos e hostnames `.lan`
- **Monitor**: loga mudanças de estado dos ISPs, opcionalmente envia email

## Requisitos

- MikroTik com **RouterOS v7.20+**
- 5 portas ethernet (2 WAN + 3 LAN) ou mais
- Winbox, WebFig ou SSH para acessar o router

Testado em: hEX S (RB760iGS), RB750Gr3

## Como usar

1. Baixe o `mikrotik-dual-wan-ecmp.rsc`
2. Abra o arquivo e edite as variáveis no topo (interfaces, IPs, MACs, timezone)
3. Remova as seções marcadas com `[OPCIONAL]` que não precisa
4. Suba o arquivo no router (Winbox > Files > arrastar) e importe:

```
/import mikrotik-dual-wan-ecmp.rsc
```

> **CUIDADO**: o script reseta toda a configuração do router. Esteja conectado fisicamente (não via VPN/remoto). Faça backup antes: `/export file=backup`

5. Depois de importar, troque a senha admin:

```
/user set admin password=SUA-SENHA-FORTE
```

## Verificação

```
# DHCP pegou IP dos ISPs?
/ip dhcp-client print

# Duas rotas ECMP ativas?
/ip route print where dst-address=0.0.0.0/0

# FastTrack processando tráfego?
/ip firewall filter print stats where comment~"FastTrack"

# Log do monitor
/log print follow where message~"MONITOR"
```

## Testar failover

Puxe o cabo de uma WAN. Em ~10 segundos a rota desativa e o tráfego vai pela outra. Reconecte e a rota volta automaticamente.

## Seções opcionais

O script tem seções marcadas com `[OPCIONAL]` que você pode remover:

| Seção | O que faz | Quando remover |
|-------|-----------|----------------|
| DHCP Leases Estáticos | IPs fixos por MAC | Se não precisa de IP fixo pra nenhum dispositivo |
| DNS Hostnames | Nomes .lan (ex: `ping meupc.lan`) | Se não quer acessar dispositivos por nome |
| Traffic Steering | Força dispositivo a usar um ISP | Se não precisa direcionar tráfego |
| Email | Notificações de queda/retorno | Se não quer receber alertas |
| Monitor de ISP | Log de mudanças de estado | Se não quer monitoramento |
| Monitor de Memória | Alerta de memória alta | Se não quer monitoramento |

## Bridge mode

O script assume que ambos os ISPs entregam IP via DHCP. Isso funciona quando:
- Os modems estão em **modo roteador** (double NAT, funciona normal pra uso residencial)
- A **Claro** está em bridge (entrega DHCP/CGNAT direto)

Se você não precisa de bridge, pode usar os modems em modo roteador sem problemas.

### Claro em bridge

Claro pode não reconhecer o MAC do seu roteador e não entregar o IPv4. Você vai notar que só o IPv6 funciona e o DHCP fica em `requesting` pra sempre.

**Solução 1 -- IP estático temporário (funciona com certeza)**:
1. Antes de ativar bridge, entre no modem e anote: IP público, gateway e máscara (tela Status > WAN)
2. Coloque o modem em bridge
3. Configure a WAN do MikroTik em modo estático com os dados anotados -- a internet vai funcionar
4. Depois de um tempo você vai perder a internet
5. Troque a WAN do MikroTik de volta pra DHCP -- a partir daí o IPv4 volta a funcionar normalmente

Scripts auxiliares para os passos 3 e 5:
- `claro-static-restore.rsc` -- configura o IP estático no MikroTik (passo 3)
- `claro-dhcp-rollback.rsc` -- remove o estático e reativa DHCP (passo 5)

**Solução 2 -- Clonar MAC (pode funcionar)**:
Clone o MAC da WAN do modem da Claro na interface WAN do MikroTik e depois coloque em bridge. Não faça isso se for usar a solução 1.

### Vivo em bridge

A Vivo **não usa DHCP** em bridge. Ela usa **PPPoE**. Quando você ativa bridge no modem da Vivo, ele para de discar e o MikroTik precisa fazer a autenticação PPPoE.

Este script **não inclui PPPoE** -- ele assume DHCP em ambas as WANs. Para usar a Vivo em bridge, você precisa:

1. Criar um PPPoE client na interface da Vivo
2. Credenciais padrão: usuário `cliente@cliente`, senha `cliente` (pode variar por região)
3. Adicionar a interface PPPoE na lista WAN do firewall

O MAC do primeiro dispositivo que conectar no modem Vivo fica "travado". Se trocar de equipamento, reinicie o modem ou clone o MAC.

## Regras bogon (importante)

O firewall bloqueia IPs privados vindos da WAN (proteção contra spoofing). Se seu ISP entrega IP privado (ex: 192.168.x.x em modo roteador), desabilite a regra correspondente:

```
/ip firewall raw disable [find where comment~"192.168"]
```

## Licença

MIT

## Créditos

Fork de [vishnunuk/mikrotik-dual-wan-loadbalance-failover](https://github.com/vishnunuk/mikrotik-dual-wan-loadbalance-failover). Reescrito para usar ECMP + FastTrack.
