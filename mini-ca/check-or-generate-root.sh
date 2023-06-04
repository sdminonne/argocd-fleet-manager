#!/usr/bin/env bash

. ../common.sh

. ./config.sh


log::info "Ensuring ${ROOT} folder exists"
[ -d ${ROOT} ] || mkdir ${ROOT}
#TOOO checks ${ROOT} is writable

[ -d ${ROOT}/issued ] ||  mkdir -p ${ROOT}/issued

[ -d ${ROOT}/index.txt ] || echo -n >${ROOT}/index.txt

log::info "Init ${ROOT}/crlnumber.txt"
[ -d ${ROOT}/crlnumber.txt ] || echo 01 >${ROOT}/crlnumber.txt

log::info "Ensuring ${PRIVATE} folder exists"
[ -d ${PRIVATE} ] || mkdir -p ${PRIVATE}

#with right permission
[ "$(stat -L -c "%a" ${PRIVATE})" == "700" ] || chmod 0700 ${PRIVATE}

#make root keypair
log::info "Making root key pair: ${PRIVATE}/root_keypair.pem"
[ -s  "${PRIVATE}/root_keypair.pem" ] && ( log::warning "${PRIVATE}/root_keypair.pem already exists" ) ||  openssl genpkey \
                                         -algorithm ED448 \
                                         -out "${PRIVATE}/root_keypair.pem"
[ -s  ${PRIVATE}/root_keypair.pem ] || { log::error "ERROR: empty or no private key"; exit; }
log::info "${PRIVATE}/root_keypair.pem looks OK"

TMPROOTCNF=$(mktemp -t root.XXXXX.cnf)
cat << EOF > "${TMPROOTCNF}"
[ca]
default_ca = CA_default

[CA_default]
database                = ${ROOT}/index.txt
new_certs_dir           = ${ROOT}/issued

certificate             = ${ROOT}/root_cert.pem
private_key             = ${PRIVATE}/root_keypair.pem

default_days            = 3650
default_md              = default
rand_serial             = yes
unique_subject          = no
name_opt                = ca_default
cert_opt                = ca_default

policy                  = policy_intermediate_cert

x509_extensions         = v3_intermediate_cert
copy_extensions         = copy

crl_extensions          = crl_extensions_root_ca
crlnumber               = ${ROOT}/crlnumber.txt
default_crl_days        = 30

[req]
prompt                  = no
distinguished_name      = distinguished_name_root_cert

[distinguished_name_root_cert]
countryName             = FR
stateOrProvinceName     = Tourrettes sur Loup
localityName            = Tourrettes sur Loup
organizationName        = Minonne Family
commonName              = Root CA

[policy_intermediate_cert]
countryName             = match
stateOrProvinceName     = match
localityName            = match
organizationName        = match
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[v3_root_cert]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always, issuer
basicConstraints = critical, CA:TRUE
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
crlDistributionPoints = URI:http://crl.minonne.com/root_crl.der

[v3_intermediate_cert]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always, issuer
basicConstraints = critical, CA:TRUE, pathlen:0
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
crlDistributionPoints = URI:http://crl.minonne.com/root_crl.der

[crl_extensions_root_ca]
authorityKeyIdentifier = keyid:always, issuer
crlDistributionPoints = URI:http://crl.minonne.com/root_crl.der
EOF

if [ ! -s "${ROOT}/root.cnf" ]
then
   mv "${TMPROOTCNF}" "${ROOT}/root.cnf"
else
    cmp -s "${TMPROOTCNF}" "${ROOT}/root.cnf" || { echo " ${ROOT}/root.cnf already present but different please compare with ${TMPROOTCNF}"; exit 1; }
fi
[ -s  "${ROOT}/root.cnf" ] || { log::error "empty or no ${ROOT}/root.cnf file"; exit 1; }

log::info "${ROOT}/root.cnf looks OK"

log::info "Making root CSR ${ROOT}/root_csr.pem "
[ -s  ${ROOT}/root_csr.pem ] && ( log::warning "${ROOT}/root_csr.pem  already exists" ) ||  \
    openssl req \
    -config ${ROOT}/root.cnf \
    -new \
    -key "${PRIVATE}/root_keypair.pem" \
    -out "${ROOT}/root_csr.pem" \
    -text

[ -s  ${ROOT}/root_csr.pem ] ||  { log::error "empty or no root CSR"; exit 1; }

log::info "Making root CERT ${ROOT}/root_cert.pem"
[ -s  "${ROOT}/root_cert.pem" ] && ( log::warning "${ROOT}/root_cert.pem already exists" ) || openssl ca \
                                         -config "${ROOT}/root.cnf" \
                                         -extensions v3_root_cert \
                                         -selfsign \
                                         -batch \
                                         -in "${ROOT}/root_csr.pem" \
                                         -out "${ROOT}/root_cert.pem"

[ -s  ${ROOT}/root_cert.pem ] || { log::error "ERROR: empty or no root CSR"; exit 1; }

log::info "Root CA ${ROOT}/root_cert.pem looks OK"