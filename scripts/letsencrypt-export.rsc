# Let's Encrypt Export - Exporta certificado + chave em PEM
# ==============================================================================
# Gera dois arquivos em Files:
#   - cert_export_<nome>.crt (certificado PEM)
#   - cert_export_<nome>.key (chave privada PEM)
#
# Baixe via Winbox (Files) ou SCP:
#   scp admin@192.168.100.1:/cert_export_*.crt .
#   scp admin@192.168.100.1:/cert_export_*.key .
#
# Uso: /import letsencrypt-export.rsc
#   ou: /system script run letsencrypt-export (se o setup já rodou)
# ==============================================================================

:local dnsName [/ip cloud get dns-name]
:if ([:len $dnsName] = 0) do={
    :put "ERRO: DDNS não configurado."
    :error "No DDNS"
}

:local certName ("acme_cert_" . $dnsName)
:put ("Exportando certificado: " . $certName)
/certificate export-certificate $certName type=pem export-passphrase="changeme"
:put ""
:put "Arquivos gerados em Files:"
:put ("  cert_export_" . $certName . ".crt")
:put ("  cert_export_" . $certName . ".key")
:put ""
:put "Baixe via SCP:"
:put ("  scp admin@192.168.100.1:/cert_export_" . $certName . ".crt .")
:put ("  scp admin@192.168.100.1:/cert_export_" . $certName . ".key .")
:put ""
