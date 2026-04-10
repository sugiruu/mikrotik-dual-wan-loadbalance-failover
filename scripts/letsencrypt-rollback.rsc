# Let's Encrypt Rollback - Remove certificado e scheduler
# ==============================================================================
# Uso: /import letsencrypt-rollback.rsc
# ==============================================================================

:put "Removendo Let's Encrypt..."

# Remove scheduler
:do { /system scheduler remove [find where name="acme-renew"] } on-error={}

# Desabilita www-ssl
/ip service set www-ssl certificate="" disabled=yes

# Remove certificado ACME
:local dnsName [/ip cloud get dns-name]
:if ([:len $dnsName] > 0) do={
    :do { /certificate remove [find where name=$dnsName] } on-error={}
}

# Remove port forward (se existir)
:do { /ip firewall nat remove [find where comment="Port Forward: HTTPS Server"] } on-error={}

:put "Let's Encrypt removido."
:put "  www-ssl desabilitado"
:put "  Scheduler removido"
:put "  Certificado removido"
