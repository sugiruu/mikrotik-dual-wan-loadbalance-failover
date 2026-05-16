# wan-monitor.rsc
# Substitui o isp-monitor de mikrotik-dual-wan-ecmp.rsc:351-440 por monitor
# de notificacao com sub-monitores independentes para IPv4 e IPv6 por WAN.
# Logs sao per-sub-monitor; emails sao agregados por WAN (1 email por WAN
# por ciclo do scheduler).
# ==============================================================================
# Usage: /import scripts/wan-monitor.rsc
#
# Rollback: /import scripts/wan-monitor-rollback.rsc
# ==============================================================================

:put "=== WAN Monitor Setup ==="

# --- Cleanup (idempotencia; tambem remove isp-monitor velho) ---
:do { /system scheduler remove [find name="isp-monitor"] } on-error={}
:do { /system scheduler remove [find name="wan-monitor"] } on-error={}
:do { /system script environment remove [find where name~"^WAN[12](Status|DownCount|UpCount)\$"] } on-error={}
:do { /system script environment remove [find where name~"^WAN[12]Mon(Status|DownCount|UpCount)\$"] } on-error={}
:do { /system script environment remove [find where name~"^WAN[12]NotifyCooldown\$"] } on-error={}
:do { /system script environment remove [find where name~"^WAN[12]v[46]Cooldown\$"] } on-error={}
:do { /system script environment remove [find where name~"^WAN[12]v[46](Status|DownCount|UpCount)\$"] } on-error={}
:put "  Cleanup: ok"

# --- Globals (12 = 3 por sub-monitor x 4 sub-monitores) ---
:global WAN1v4Status "up"
:global WAN1v4DownCount 0
:global WAN1v4UpCount 0
:global WAN1v6Status "up"
:global WAN1v6DownCount 0
:global WAN1v6UpCount 0
:global WAN2v4Status "up"
:global WAN2v4DownCount 0
:global WAN2v4UpCount 0
:global WAN2v6Status "up"
:global WAN2v6DownCount 0
:global WAN2v6UpCount 0

# --- Scheduler ---
/system scheduler add name=wan-monitor interval=1m start-time=startup on-event={
    :global WAN1v4Status
    :global WAN1v4DownCount
    :global WAN1v4UpCount
    :global WAN1v6Status
    :global WAN1v6DownCount
    :global WAN1v6UpCount
    :global WAN2v4Status
    :global WAN2v4DownCount
    :global WAN2v4UpCount
    :global WAN2v6Status
    :global WAN2v6DownCount
    :global WAN2v6UpCount

    :local debounce 3

    # Buffers de eventos por WAN — agregados no fim do ciclo
    :local vivoEvents ""
    :local claroEvents ""

    :local emailTo [/tool e-mail get user]
    :local emailOk ([:len $emailTo] > 0 && $emailTo != "")

    # Resolve interfaces dinamicamente (compartilhadas entre v4 e v6)
    :local vivoIface ""
    :do { :set vivoIface [/interface pppoe-client get [find where name="pppoe-vivo"] name] } on-error={}

    :local claroIface ""
    :do { :set claroIface [/ip dhcp-client get [find where comment~"Claro"] interface] } on-error={}

    # --- Vivo IPv4 ---
    :if ([:len $vivoIface] = 0) do={
        :log warning "[MONITOR] Vivo IPv4: interface nao resolvida, pulando ciclo"
    } else={
        :local pingA ([/ping 1.0.0.1 interface=$vivoIface count=2] > 0)
        :local pingB ([/ping 8.8.4.4 interface=$vivoIface count=2] > 0)
        :local ok ($pingA || $pingB)

        :if ($ok) do={
            :set WAN1v4UpCount ($WAN1v4UpCount + 1)
            :set WAN1v4DownCount 0
            :if ($WAN1v4UpCount >= $debounce && $WAN1v4Status = "down") do={
                :set WAN1v4Status "up"
                :log info "[MONITOR] Vivo IPv4 RECOVERED"
                :set vivoEvents ($vivoEvents . "IPv4 RECOVERED. ")
            }
        } else={
            :set WAN1v4DownCount ($WAN1v4DownCount + 1)
            :set WAN1v4UpCount 0
            :if ($WAN1v4DownCount >= $debounce && $WAN1v4Status = "up") do={
                :set WAN1v4Status "down"
                :log error "[MONITOR] Vivo IPv4 DOWN"
                :set vivoEvents ($vivoEvents . "IPv4 DOWN. ")
            }
        }
    }

    # --- Vivo IPv6 ---
    :if ([:len $vivoIface] = 0) do={
        :log warning "[MONITOR] Vivo IPv6: interface nao resolvida, pulando ciclo"
    } else={
        :local pingA ([/ping 2606:4700:4700::1001 interface=$vivoIface count=2] > 0)
        :local pingB ([/ping 2001:4860:4860::8844 interface=$vivoIface count=2] > 0)
        :local ok ($pingA || $pingB)

        :if ($ok) do={
            :set WAN1v6UpCount ($WAN1v6UpCount + 1)
            :set WAN1v6DownCount 0
            :if ($WAN1v6UpCount >= $debounce && $WAN1v6Status = "down") do={
                :set WAN1v6Status "up"
                :log info "[MONITOR] Vivo IPv6 RECOVERED"
                :set vivoEvents ($vivoEvents . "IPv6 RECOVERED. ")
            }
        } else={
            :set WAN1v6DownCount ($WAN1v6DownCount + 1)
            :set WAN1v6UpCount 0
            :if ($WAN1v6DownCount >= $debounce && $WAN1v6Status = "up") do={
                :set WAN1v6Status "down"
                :log error "[MONITOR] Vivo IPv6 DOWN"
                :set vivoEvents ($vivoEvents . "IPv6 DOWN. ")
            }
        }
    }

    # --- Claro IPv4 ---
    :if ([:len $claroIface] = 0) do={
        :log warning "[MONITOR] Claro IPv4: interface nao resolvida, pulando ciclo"
    } else={
        :local pingA ([/ping 1.1.1.1 interface=$claroIface count=2] > 0)
        :local pingB ([/ping 8.8.8.8 interface=$claroIface count=2] > 0)
        :local ok ($pingA || $pingB)

        :if ($ok) do={
            :set WAN2v4UpCount ($WAN2v4UpCount + 1)
            :set WAN2v4DownCount 0
            :if ($WAN2v4UpCount >= $debounce && $WAN2v4Status = "down") do={
                :set WAN2v4Status "up"
                :log info "[MONITOR] Claro IPv4 RECOVERED"
                :set claroEvents ($claroEvents . "IPv4 RECOVERED. ")
            }
        } else={
            :set WAN2v4DownCount ($WAN2v4DownCount + 1)
            :set WAN2v4UpCount 0
            :if ($WAN2v4DownCount >= $debounce && $WAN2v4Status = "up") do={
                :set WAN2v4Status "down"
                :log error "[MONITOR] Claro IPv4 DOWN"
                :set claroEvents ($claroEvents . "IPv4 DOWN. ")
            }
        }
    }

    # --- Claro IPv6 ---
    :if ([:len $claroIface] = 0) do={
        :log warning "[MONITOR] Claro IPv6: interface nao resolvida, pulando ciclo"
    } else={
        :local pingA ([/ping 2606:4700:4700::1111 interface=$claroIface count=2] > 0)
        :local pingB ([/ping 2001:4860:4860::8888 interface=$claroIface count=2] > 0)
        :local ok ($pingA || $pingB)

        :if ($ok) do={
            :set WAN2v6UpCount ($WAN2v6UpCount + 1)
            :set WAN2v6DownCount 0
            :if ($WAN2v6UpCount >= $debounce && $WAN2v6Status = "down") do={
                :set WAN2v6Status "up"
                :log info "[MONITOR] Claro IPv6 RECOVERED"
                :set claroEvents ($claroEvents . "IPv6 RECOVERED. ")
            }
        } else={
            :set WAN2v6DownCount ($WAN2v6DownCount + 1)
            :set WAN2v6UpCount 0
            :if ($WAN2v6DownCount >= $debounce && $WAN2v6Status = "up") do={
                :set WAN2v6Status "down"
                :log error "[MONITOR] Claro IPv6 DOWN"
                :set claroEvents ($claroEvents . "IPv6 DOWN. ")
            }
        }
    }

    # --- Agregacao de email por WAN ---
    :if ($emailOk && [:len $vivoEvents] > 0) do={
        :do { /tool e-mail send to=$emailTo subject="[DualWAN] Vivo update" body=$vivoEvents } on-error={}
    }
    :if ($emailOk && [:len $claroEvents] > 0) do={
        :do { /tool e-mail send to=$emailTo subject="[DualWAN] Claro update" body=$claroEvents } on-error={}
    }
}

:put "  Scheduler wan-monitor: ok"
:put ""
:put "=== WAN Monitor ativo ==="
:put "  Intervalo: 1min | Debounce: 3 ciclos"
:put "  4 sub-monitores: Vivo IPv4, Vivo IPv6, Claro IPv4, Claro IPv6"
:put "  Email agregado por WAN (1 email/WAN/ciclo se houver transicao)"
:put ""
:put "Verificacao:"
:put "  /system scheduler print where name=wan-monitor"
:put "  /log print follow where message~\"\\[MONITOR\\]\""
:put ""
:put "Rollback: /import scripts/wan-monitor-rollback.rsc"
