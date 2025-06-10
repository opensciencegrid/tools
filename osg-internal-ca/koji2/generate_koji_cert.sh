#!/bin/bash
#
# generate_cert.sh
#
# This generates a host cert and signs it with the Koji CA cert.

dir=$(dirname "$0")
CA_key=$dir/private/kojiCA.key
CA_crt=$dir/certs/kojiCA.crt
CA_config=$dir/koji-ssl.cnf
key_size=4096
days=3650


Prog=${0##*/}
fail () {
    set +exu
    ret=${1}
    shift
    echo "$Prog:" "$@" >&2
    exit "$ret"
}

require_program () {
    command -v "$1" &>/dev/null ||
        fail 127 "Required program '$1' not found in PATH"
}

require_program openssl
require_program dos2unix

set -o nounset

cd "$dir"

user=${1?Need user}
user=${user//\//_}  # replace all '/' with '_'

user_key=$dir/private/${user}.key
user_csr=$dir/private/${user}.csr
user_crt=$dir/certs/${user}.crt
user_pem=$dir/private/${user}.pem

if [[ ! -e index.txt ]]; then
    echo "index.txt not found -- signing is going to fail. Bailing."
    exit 1
fi

set -e

# Make a new private key for the user
(
umask 077
openssl genrsa -out "$user_key" "$key_size"
)

# Generate a Certificate Signing Request (CSR)
req_args=(-config "$CA_config"
          -new
          -nodes
          -key "$user_key"
          -out "$user_csr")
(
umask 077
openssl req "${req_args[@]}"
)

# Sign the CSR using the CA cert and key to make the user cert
ca_args=(-config "$CA_config"
         -in "$user_csr"
         -keyfile "$CA_key"
         -cert "$CA_crt"
         -out "$user_crt"
         -days "$days")
openssl ca "${ca_args[@]}"

# Combine cert and key to make the .pem file that Koji uses
# Cert sometimes doesn't end with a newline so add one
( umask 077; (cat "$user_crt"; echo; cat "$user_key") > "$user_pem" )
dos2unix "$user_pem"

printf "%s written to $dir/%s\n" \
           "CSR" "$user_csr" \
           "certificate" "$user_crt" \
           "private key" "$user_key" \
           "combined cert/key" "$user_pem"

