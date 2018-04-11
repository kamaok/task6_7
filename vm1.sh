#!/bin/bash

DEST_DIR="/etc/ssl/certs"
SSL_DIR="/etc/nginx/ssl"

CUR_PWD=$(dirname $0)
CONFIG_FILE="${CUR_PWD}/vm1.config"

EXT_IF=$(grep EXTERNAL_IF ${CONFIG_FILE} | awk -F= '{print $2}' | sed 's/"//g')
INT_IF=$(grep INTERNAL_IF ${CONFIG_FILE} | awk -F= '{print $2}' | sed 's/"//g')
MNG_IF=$(grep MANAGEMENT_IF ${CONFIG_FILE} | awk -F= '{print $2}' | sed 's/"//g')

EXT_IP=$(grep EXT_IP ${CONFIG_FILE} | awk -F= '{print $2}' | sed 's/"//g')
INT_IP=$(grep INT_IP ${CONFIG_FILE} | awk -F= '{print $2}')
EXT_GTW=$(grep EXT_GW ${CONFIG_FILE} | awk -F= '{print $2}')

EXT_IP_SINGLE=$(echo ${EXT_IP} | awk -F/ '{print $1}')

NGINX_PORT=$(grep NGINX_PORT ${CONFIG_FILE} | awk -F= '{print $2}')

AVIP=$(grep APACHE_VLAN_IP ${CONFIG_FILE} | awk -F= '{print $2}')
VIP=$(grep -w VLAN_IP ${CONFIG_FILE} | awk -F= '{print $2}')
VID=$(grep -w VLAN ${CONFIG_FILE} | awk -F= '{print $2}')

#echo EXT_IF=${EXT_IF}
#echo INT_IF=${INT_IF}
#echo MNG_IF=${MNG_IF}

#echo EXT_IP=${EXT_IP}
#echo INT_IP=${INT_IP}
#echo EXT_GTW=${EXT_GTW}

#echo EXT_IP_SINGLE=${EXT_IP_SINGLE}
#echo NGINX_PORT=${NGINX_PORT}

#echo AVIP=$AVIP
#echo VIP=$VIP
#echo VID=$VID

#CHECK_MOD=$(lsmod | grep 8021q | wc -l)
#if  [ "${CHECK_MOD}" -eq "0" ]; then
#	modprobe 8021q
#fi

### Enable 8021q module whether itisn't already enable
lsmod | grep 8021q > /dev/null || modprobe 8021q

externalipfunction () {
ip link set dev ${EXT_IF} down
ip addr add ${EXT_IP} dev ${EXT_IF}
ip link set dev ${EXT_IF} up

### Set up default route
ip route del default > /dev/null 2>&1 ; ip route add default via ${EXT_GTW}
##ip route change default via ${EXT_GTW}
}

### Configure External interface
if [ "${EXT_IP}" == "DHCP" ]; then true; else externalipfunction; fi

### Configure Internal interface
ip link set dev ${INT_IF} down
ip addr add ${INT_IP} dev ${INT_IF}
ip link set dev ${INT_IF} up

### Configure Managment interface
#ip link set dev ${MNG_IF} down

### Confugire VLAN
ip link add link ${INT_IF} name ${INT_IF}.${VID} type vlan id ${VID}
ip addr add $VIP dev ${INT_IF}.${VID}
ip link set dev ${INT_IF}.${VID} up


apt-get update > /dev/null && apt-get install nginx openssl iptables -y > /dev/null

### Allow private net access to Internet
sysctl -w net.ipv4.ip_forward=1 > /dev/null
iptablesfunction () {
iptables -F
iptables -F -t nat
iptables -F -t mangle
iptables -t nat -A POSTROUTING -s ${INT_IP} -j MASQUERADE
}
iptablesfunction

[ -d /etc/ssl/certs ] || mkdir -p /etc/ssl/certs

sslfunction () {
### Creating Root-certificate
openssl req -x509 -nodes -days 3650 -newkey rsa:4096 -keyout ${CUR_PWD}/rootCA.key -out ${DEST_DIR}/root-ca.crt -subj '/C=UA/ST=Kievskaya/L=Kiev/O=IT/OU=IT-Department/CN=Root-CA' -sha256

### Check  md5-sum for root certificate and key
#openssl x509 -noout -modulus -in ${DEST_DIR}/root-ca.crt | openssl md5
#openssl rsa -noout -modulus -in  ${CUR_PWD}/rootCA.key | openssl md5

### Create CSR for web-site
cat > ${CUR_PWD}/openssl.cnf << EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
req_extensions = v3_req
distinguished_name = req_distinguished_name

[ req_distinguished_name ]
C=UA
ST=Kharkov
L=Kharkov
O=IT
OU=IT-Department
emailAddress=myname@mydomain.com
CN = vm1

[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = vm1
IP.1 = ${EXT_IP_SINGLE}
EOF

### Create Private key and CSR for one command
#openssl req -new -sha256 -nodes -out ${CUR_PWD}/web.csr -newkey rsa:2048 -keyout ${CUR_PWD}/web.key -config <( cat  ${CUR_PWD}/openssl.cnf )

### Create Private key for web-site
openssl genrsa -out ${CUR_PWD}/web.key 2048

### Create CSR for web-site
openssl req -new -key ${CUR_PWD}/web.key -out ${CUR_PWD}/web.csr -config ${CUR_PWD}/openssl.cnf

### Read CSR
#openssl req -text -noout -in ${CUR_PWD}/web.csr

### Create and sign web-certificate by rootCA
openssl x509 -req -days 730 -in ${CUR_PWD}/web.csr -CA ${DEST_DIR}/root-ca.crt -CAkey ${CUR_PWD}/rootCA.key -CAcreateserial -out ${DEST_DIR}/web.crt -extfile ${CUR_PWD}/openssl.cnf -extensions v3_req

### Check  md5-sum for web certificate, key, csr
#openssl x509 -noout -modulus -in ${DEST_DIR}/web.crt | openssl md5
#openssl rsa -noout -modulus -in ${CUR_PWD}/web.key | openssl md5
#openssl req -noout -modulus -in ${CUR_PWD}/web.csr | openssl md5

}
#sslfunction

### Configure Nginx

[ -d ${SSL_DIR} ] || mkdir ${SSL_DIR}
rm -rf /etc/nginx/sites-enabled/*
#rm -rf /etc/nginx/sites-available/*

cat << EOF > /etc/nginx/ssl.conf
	ssl_session_cache shared:SSL:50m;
	ssl_session_timeout 1d;
	ssl_prefer_server_ciphers       on;
	ssl_protocols  TLSv1.2;
	ssl_ciphers   ECDH+AESGCM:DH+AESGCM:ECDH+AES256:DH+AES256:ECDH+AES128:DH+AES:ECDH+3DES:DH+3DES:RSA+AESGCM:RSA+AES:RSA+3DES:!aNULL:!MD5:!DSS;
	#ssl_ecdh_curve secp521r1;
	ssl_session_tickets off;
	ssl_buffer_size 8k;
EOF

cat << EOF > /etc/nginx/proxy.conf
	proxy_redirect off;
	proxy_set_header Host \$host;
	proxy_set_header X-Real-IP \$remote_addr;
	proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;

	proxy_buffer_size 128k;
	proxy_buffers 256 16k;
	proxy_busy_buffers_size 256k;
	proxy_temp_file_write_size 256k;

	proxy_connect_timeout 90;
	proxy_send_timeout 90;
	proxy_read_timeout 90;
EOF

cat << EOF >  /etc/nginx/sites-available/default

server {
    listen      ${EXT_IP_SINGLE}:${NGINX_PORT} default_server;
    server_name  vm1 ${EXT_IP_SINGLE};

    ssl on;
    ssl_certificate /etc/nginx/ssl/fullchain.crt;
    ssl_certificate_key /etc/nginx/ssl/web.key;
    include     /etc/nginx/ssl.conf;

    root   /usr/share/nginx/html;
    access_log  /var/log/nginx/vm1-access.log;
    error_log  /var/log/nginx/vm1-error.log;

    location / {
        proxy_pass http://$AVIP:80;
        include /etc/nginx/proxy.conf;
        }
   }
EOF

cat  ${DEST_DIR}/web.crt ${DEST_DIR}/root-ca.crt > ${SSL_DIR}/fullchain.crt
cp ${CUR_PWD}/web.key ${SSL_DIR}/
#cp ${DEST_DIR}/web.crt ${SSL_DIR}/
echo "Test page on vm1" > /usr/share/nginx/html/index.html

(cd /etc/nginx/sites-enabled/ && ln -s ../sites-available/default .)
nginx -t > /dev/null 2>&1 && systemctl restart nginx
