#!/usr/bin/env bash
set -e
cwd=$(pwd)
script_dir=$(dirname "$(realpath "$0")")
function cleanup() {
    cd "${cwd}"
}

trap cleanup EXIT

cd "$script_dir"
if [[ "$#" -lt 3 ]]; then
    echo "Usage: $0 <prefix> <domain> <ip>"
    exit 1
fi

PREFIX=${1}
DOMAIN=${2}
IP=${3}
if [[ -f "$PREFIX.crt" ]]; then
    echo "$PREFIX.crt already exists"
    exit 0
fi


# using keytool to generate key pair,  IP shall be specified in SAN's DNS
echo "======1. Generating keystore $PREFIX.jks"
keytool -genkeypair -keystore "${PREFIX}.jks" -storepass changeit -alias "$DOMAIN"  -keyalg RSA -keysize 2048 -validity 5000 -keypass changeit  -dname "CN=*.$DOMAIN, OU=rd, O=neo, L=Unspecified, ST=Unspecified, C=CN"  -ext "SAN=IP:$IP"

# export the certificate in PEM format
echo "======2. Exporting certificate $PREFIX.crt"
keytool -exportcert -keystore "${PREFIX}.jks" -alias neo.com -rfc > "$PREFIX.crt"

# convert to PKCS12 format
echo "======3. Converting to PKCS12 format $PREFIX.p12"
keytool -importkeystore -srckeystore "${PREFIX}.jks" -destkeystore "${PREFIX}.p12" -deststoretype PKCS12

# (optional) using openssl to export the certificate in PEM format
echo "======4. Exporting certificate in PEM format $PREFIX.pem"
openssl pkcs12 -nokeys -in "${PREFIX}.p12" -out "${PREFIX}.pem"

# (optional) using openssl to export the private key in PEM format 
echo "======5. Exporting private key in PEM format $PREFIX.key"
openssl pkcs12 -nocerts -nodes -in "${PREFIX}.p12" -out "${PREFIX}.key"

# (optional) using keytool to list the certificate in p12 file
echo "======6. Listing the certificate in p12 file"
keytool -list -keystore "${PREFIX}.p12" -storetype PKCS12