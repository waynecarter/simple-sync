#!/bin/bash

# Set the company name, domain, country, state, city into
COMPANY_NAME="The Company"
DOMAIN="*.thecompany.com"
COUNTRY="US"
STATE="Florida"
CITY="Miami"

# Generate a private key for the CA
openssl genrsa -out ca_key.pem 4096

# Create a self-signed root CA certificate
openssl req -x509 -new -nodes -key ca_key.pem -sha256 -days 3650 -out ca_cert.pem \
  -subj "/C=${COUNTRY}/ST=${STATE}/L=${CITY}/O=${COMPANY_NAME}/CN=${DOMAIN} Root CA"
openssl x509 -in ca_cert.pem -outform der -out ca_cert.der

# Create P12 for the CA
openssl pkcs12 -export -nodes -out ca_identity.p12 -inkey ca_key.pem \
    -in ca_cert.pem -passout pass:

# Generate a private key for the client
openssl genrsa -out client_key.pem 4096

# Create a certificate signing request (CSR) for the client
openssl req -new -key client_key.pem -out client.csr \
  -subj "/C=${COUNTRY}/ST=${STATE}/L=${CITY}/O=${COMPANY_NAME}/CN=${DOMAIN} Client" \
  -config client_config.cnf

# Sign the client certificate with the CA
openssl x509 -req -in client.csr -CA ca_cert.pem -CAkey ca_key.pem -CAcreateserial \
  -out client_cert.pem -days 365 -sha256 \
  -extfile client_config.cnf -extensions v3_req
openssl x509 -in client_cert.pem -outform der -out client_cert.der

# Create P12 for the client
openssl pkcs12 -export -nodes -out client_identity.p12 -inkey client_key.pem \
    -in client_cert.pem -passout pass:
  
# Clean up the PEM and CSR files
rm ca_key.pem
rm ca_cert.pem
rm client_key.pem
rm client_cert.pem
rm client.csr
