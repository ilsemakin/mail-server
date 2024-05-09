#!/bin/bash

# sudo openssl req -new -x509 -days 365 -key $HOME_DIR/certificate/out/ca.key -out $HOME_DIR/certificate/out/ca.crt -subj "/C=${C}/ST=${ST}/L=${L}/O=${O}/CN=${CN}/emailAddress=${email}"
function genetate_root_cert {
  sudo openssl genrsa -out $HOME_DIR/certificate/out/ca.key 2048
  sudo openssl req -new -x509 -days 365 -key $HOME_DIR/certificate/out/ca.key -config $HOME_DIR/certificate/conf/root.conf -extensions v3_ca -out $HOME_DIR/certificate/out/ca.crt
}

# keyUsage = nonRepudiation, digitalSignature, keyEncipherment
function genetate_mail_cert {
  sudo sed -i "s|^DNS.*|DNS.1 = $FQDN|" $HOME_DIR/certificate/conf/mail.conf

  sudo openssl genrsa -out $HOME_DIR/certificate/out/mail.key 2048
  sudo openssl req -new -key $HOME_DIR/certificate/out/mail.key -config $HOME_DIR/certificate/conf/mail.conf -out $HOME_DIR/certificate/csr/mail.csr
  sudo openssl x509 -req -sha256 -days 365 -CA $HOME_DIR/certificate/out/ca.crt -CAkey $HOME_DIR/certificate/out/ca.key -CAcreateserial -extfile $HOME_DIR/certificate/conf/mail.conf -extensions req_ext -in $HOME_DIR/certificate/csr/mail.csr -out $HOME_DIR/certificate/out/mail.crt

  sudo mv out/ca.srl $HOME_DIR/certificate/tmp/ca_mail.srl &> /dev/null

  sudo mkdir -p $CRT_DIR &> /dev/null
  sudo cp $HOME_DIR/certificate/out/mail.key $CRT_DIR
  sudo cp $HOME_DIR/certificate/out/mail.crt $CRT_DIR
}
