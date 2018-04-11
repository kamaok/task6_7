#!/bin/bash

CUR_PWD=$(dirname $0)
CONFIG_FILE="${CUR_PWD}/vm2.config"
CONFIG_FILE_VM1="${CUR_PWD}/vm1.config"

INT_IF=$(grep INTERNAL_IF ${CONFIG_FILE} | awk -F= '{print $2}' | sed 's/"//g')
MNG_IF=$(grep MANAGEMENT_IF ${CONFIG_FILE} | awk -F= '{print $2}' | sed 's/"//g')
INT_IP=$(grep INTERNAL_IP ${CONFIG_FILE} | awk -F= '{print $2}')
GW_IP=$(grep GW_IP ${CONFIG_FILE} | awk -F= '{print $2}')

AVIP=$(grep APACHE_VLAN_IP ${CONFIG_FILE} | awk -F= '{print $2}')
AIP=$(echo $AVIP | awk -F/ '{print $1}')
VID=$(grep -w VLAN ${CONFIG_FILE} | awk -F= '{print $2}')


#echo INT_IF=${INT_IF}
#echo MNG_IF=${MNG_IF}
#echo INT_IP=${INT_IP}
#echo GW_IP=${GW_IP}

#echo AVIP=${AVIP}
#echo AIP=${AIP}
#echo VID=${VID}

#CHECK_MOD=$(lsmod | grep 8021q | wc -l)
#if  [ "${CHECK_MOD}" -eq "0" ]; then
#        modprobe 8021q
#fi

lsmod | grep -q 8021q || modprobe 8021q

### Configure internal interface
ip link set dev ${INT_IF} down
ip addr add ${INT_IP} dev ${INT_IF}
ip link set dev ${INT_IF} up

### Confugire VLAN
ip link add link ${INT_IF} name ${INT_IF}.${VID} type vlan id ${VID}
ip addr add $AVIP dev ${INT_IF}.${VID}
ip link set dev ${INT_IF}.${VID} up

### Configure managment interface
#ip link set dev ${MNG_IF} down

### Configure default route
ip route del default > /dev/null; ip route add default via ${GW_IP}


apt-get update > /dev/null && apt-get install apache2 -y > /dev/null

### Apache configuration
#sed -i "s/Listen 80/Listen $AIP:80/" /etc/apache2/ports.conf
rm -rf /etc/apache2/ports.conf
cat << EOF > /etc/apache2/ports.conf
Listen $AIP:80
EOF

rm -rf /etc/apache2/sites-enabled/*
#rm -rf /etc/apache2/sites-available/*
cat <<EOF > /etc/apache2/sites-available/000-default.conf
<VirtualHost $AIP:80>
	ServerName vm2
	ServerAlias $AIP
        DocumentRoot /var/www/html
        ErrorLog /var/log/apache2/error.log
        CustomLog /var/log/apache2/access.log combined
</VirtualHost>
EOF

a2ensite 000-default > /dev/null
apache2ctl configtest > /dev/null  2>&1 && systemctl restart apache2 > /dev/null

echo "Test page vm2" > /var/www/html/index.html
