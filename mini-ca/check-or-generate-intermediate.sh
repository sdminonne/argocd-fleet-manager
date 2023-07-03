#!/usr/bin/env bash

. ../common.sh

. ./config.sh

[ -d ${INTERMEDIATE} ] || mkdir ${INTERMEDIATE}

[ -d ${INTERMEDIATE}/private ] || mkdir ${INTERMEDIATE}/private
[ "$(stat -L -c "%a" ${INTERMEDIATE}/private)" == "700" ] || chmod 0700 ${INTERMEDIATE}/private

[ -d ${INTERMEDIATE}/issued ] || mkdir ${INTERMEDIATE}/issued

[ -s "${INTERMEDIATE}/index.txt" ] && ( log::warning "${INTERMEDIATE}/index.txt already exists" ) || echo -n >"${INTERMEDIATE}/index.txt"

[ -s "${INTERMEDIATE}/crlnumber.txt" ] && (log::warning "${INTERMEDIATE}/crlnumber.txt already exists" ) || echo 01 > "${INTERMEDIATE}/crlnumber.txt"

log::info "Making intermediate key pair"

[ -s  "${INTERMEDIATE}/private/${INTERMEDIATEPRIVATEKEY}" ] && ( log::warning "${INTERMEDIATE}/private/${INTERMEDIATEPRIVATEKEY} already exists" ) || \
    openssl genpkey \
    -algorithm rsa \
    -out ${INTERMEDIATE}/private/${INTERMEDIATEPRIVATEKEY}

TMPINTERMEDIATECNF=$(mktemp -t intermediate.XXXX.cnf)
cat << EOF > ${TMPINTERMEDIATECNF}
[ca]
default_ca = CA_default

[CA_default]
database                = ${INTERMEDIATE}/index.txt
new_certs_dir           = ${INTERMEDIATE}/issued

certificate             = ${INTERMEDIATE}/${INTERMEDIATECERTPEM}
private_key             = ${INTERMEDIATE}/private/${INTERMEDIATEPRIVATEKEY}

default_days            = 365
default_md              = default
rand_serial             = yes
unique_subject          = no
name_opt                = ca_default
cert_opt                = ca_default

policy                  = policy_server_cert

x509_extensions         = v3_server_cert
copy_extensions         = copy

crl_extensions          = crl_extensions_intermediate_ca
crlnumber               = ${INTERMEDIATE}/crlnumber.txt
default_crl_days        = 30

[req]
prompt                  = no
distinguished_name      = distinguished_name_intermediate_cert

[distinguished_name_intermediate_cert]
countryName             = NA
stateOrProvinceName     = North Argota
localityName            = ArgoBurg
organizationName        = Argo FM
organizationalUnitName	= argo
commonName              = Intermediate CA

[policy_server_cert]
countryName             = match
stateOrProvinceName     = match
localityName            = match
organizationName        = match
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[policy_client_cert]
countryName             = optional
stateOrProvinceName     = optional
localityName            = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = supplied

[v3_server_cert]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always, issuer
basicConstraints = critical, CA:FALSE
nsCertType = server
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
crlDistributionPoints = URI:http://crl.minonne.com/root_crl.der
authorityInfoAccess = OCSP;URI:http://ocsp.minonne.com/

[v3_client_cert]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always, issuer
basicConstraints = critical, CA:FALSE
nsCertType = client, email
keyUsage = critical, nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth, emailProtection
crlDistributionPoints = URI:http://crl.minonne.com/root_crl.der
authorityInfoAccess = OOCSP;URI:http://ocsp.minonne.com/

[v3_ocsp_cert]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always, issuer
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, OCSPSigning
crlDistributionPoints = URI:http://crl.minonne.com/root_crl.der
authorityInfoAccess = OOCSP;URI:http://ocsp.minonne.com/


[crl_extensions_intermediate_ca]
authorityKeyIdentifier = keyid:always, issuer
crlDistributionPoints = URI:http://crl.minonne.com/root_crl.der
authorityInfoAccess = OOCSP;URI:http://ocsp.minonne.com/
EOF


if [ ! -s ${INTERMEDIATE}/intermediate.cnf ]
then
   mv ${TMPINTERMEDIATECNF} ${INTERMEDIATE}/intermediate.cnf
else
    cmp -s ${TMPINTERMEDIATECNF} ${INTERMEDIATE}/intermediate.cnf || \
    { echo "${INTERMEDIATE}/intermediate.cnf already present but different please compare with ${TMPINTERMEDIATECNF}"; exit 1; }
fi
[ -s ${INTERMEDIATE}/intermediate.cnf ] || echo "empty or no intermediate.cnf file"

log::info "Generating the intermediate CA CSR: ${INTERMEDIATE}/intermediate_csr.pem"
[ -s  "${INTERMEDIATE}/intermediate_csr.pem" ] && ( log::warning "${INTERMEDIATE}/intermediate_csr.pem  already exists" ) ||  \
    openssl req \
        -config "${INTERMEDIATE}/intermediate.cnf" \
        -new \
        -key "${INTERMEDIATE}/private/${INTERMEDIATEPRIVATEKEY}" \
        -out "${INTERMEDIATE}/intermediate_csr.pem" \
        -text


log::info "Issuing intermediate CA certificate: ${INTERMEDIATE}/${INTERMEDIATECERTPEM}"
[ -s  "${INTERMEDIATE}/${INTERMEDIATECERTPEM}" ] && ( log::warning "${INTERMEDIATE}/${INTERMEDIATECERTPEM} already exists" ) || openssl ca \
    -config "${ROOT}/root.cnf" \
    -batch \
    -extensions v3_intermediate_cert \
    -in  "${INTERMEDIATE}/intermediate_csr.pem" \
    -out "${INTERMEDIATE}/${INTERMEDIATECERTPEM}"

log::info "Intermediate CA  ${INTERMEDIATE}/${INTERMEDIATECERTPEM} looks OK"
