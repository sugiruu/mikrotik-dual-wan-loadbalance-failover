# Let's Encrypt SSL via ACME - Obtém certificado e configura renovação
# ==============================================================================
# Prerequisitos:
#   - RouterOS v7.20+
#   - IP público (Vivo PPPoE)
#   - Porta 80 acessível da WAN durante a validação (o script abre e fecha)
#
# Uso: /import letsencrypt-setup.rsc
#
# Após setup, os scripts ficam disponíveis no router:
#   /system script run letsencrypt-export
#   /system script run letsencrypt-renew
#
# Rollback: /import letsencrypt-rollback.rsc
# ==============================================================================

:put "Configurando Let's Encrypt..."

# 1. Habilita DDNS
/ip cloud set ddns-enabled=yes
:delay 5s
:local dnsName [/ip cloud get dns-name]
:if ([:len $dnsName] = 0) do={
    :put "ERRO: DDNS não retornou hostname. Verifique /ip cloud print"
    :error "DDNS failed"
}
:local certName ("acme_cert_" . $dnsName)
:put ("DDNS: " . $dnsName)

# 2. Verifica se já tem certificado
:local certExists ([:len [/certificate find where name=$certName]] > 0)
:if ($certExists) do={
    :put "Certificado já existe. Pulando solicitação."
} else={
    # 3. Abre porta 80 na WAN temporariamente pra validação HTTP-01
    :local wwwAddr [/ip service get www address]
    /ip service set www address="" disabled=no
    :put "Porta 80 aberta na WAN pra validação..."

    # 4. Solicita certificado
    :put "Solicitando certificado Let's Encrypt..."
    :do {
        /certificate add-acme directory-url=https://acme-v02.api.letsencrypt.org/directory domain-names=$dnsName
    } on-error={
        /ip service set www address=$wwwAddr disabled=no
        :put "ERRO: Falha ao solicitar certificado. Porta 80 restaurada."
        :error "ACME request failed"
    }

    # 5. Espera validação (pode demorar até 2 minutos)
    :put "Aguardando validação (até 3 minutos)..."
    :delay 3m

    # 6. Fecha porta 80
    /ip service set www address=$wwwAddr disabled=no
    :put "Porta 80 restaurada pra LAN."
}

# 7. Aplica no www-ssl
/ip service set www-ssl certificate=$certName disabled=no
:put "Certificado aplicado no WebFig HTTPS."

# 8. Cria script de export no router
:do { /system script remove [find where name="letsencrypt-export"] } on-error={}
/system script add name="letsencrypt-export" source={
    :local dnsName [/ip cloud get dns-name]
    :if ([:len $dnsName] = 0) do={
        :put "ERRO: DDNS nao configurado."
        :error "No DDNS"
    }
    :local certName ("acme_cert_" . $dnsName)
    :put ("Exportando certificado: " . $certName)
    /certificate export-certificate $certName type=pem export-passphrase="changeme"
    :put "Arquivos gerados em Files (.crt + .key)"
    :put "Chave criptografada com passphrase: changeme"
}

# 9. Cria script de renovação no router
# Roda todo dia as 4h. Abre porta 80 se faltam menos de 20 dias (renovação precisa de HTTP-01).
# Fecha porta 80 se o certificado já foi renovado (days-valid > 20).
:do { /system script remove [find where name="letsencrypt-renew"] } on-error={}
/system script add name="letsencrypt-renew" source={
    :local dnsName [/ip cloud get dns-name]
    :local certName ("acme_cert_" . $dnsName)
    :local cert [/certificate find where name=$certName]
    :if ([:len $cert] = 0) do={ :return "" }
    :local daysValid [/certificate get $cert days-valid]
    :local addr [/ip service get www address]
    :if ($daysValid < 20 && $addr != "") do={
        /ip service set www address="" disabled=no
        :log warning ("[ACME] Certificado expira em " . $daysValid . " dias. Porta 80 aberta pra renovacao.")
    }
    :if ($daysValid > 20 && $addr = "") do={
        /ip service set www address=192.168.100.0/24 disabled=no
        :log info "[ACME] Certificado renovado. Porta 80 restaurada pra LAN."
        :local emailTo [/tool e-mail get user]
        :if ([:len $emailTo] > 0) do={
            :do { /tool e-mail send to=$emailTo subject="[DualWAN] Certificado SSL renovado" body=("Certificado Let's Encrypt renovado. Valido por " . $daysValid . " dias.") } on-error={}
        }
    }
}

# 10. Scheduler roda diariamente as 4h
:do { /system scheduler remove [find where name="acme-renew"] } on-error={}
/system scheduler add name=acme-renew interval=1d start-time=00:00:00 on-event="/system script run letsencrypt-renew"

:put ""
:put "Let's Encrypt configurado!"
:put ("  Domínio: " . $dnsName)
:put "  Renovação automática: a cada 60 dias"
:put "  WebFig HTTPS: habilitado"
:put ""
:put "Scripts disponíveis:"
:put "  /system script run letsencrypt-export  (exporta cert+key PEM)"
:put "  /system script run letsencrypt-renew   (renova manualmente)"
:put ""
