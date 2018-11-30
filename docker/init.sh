#!/bin/sh

gw4=$(ip -4 route show|grep ^default|sed -e 's/.* via \([0-9.]*\)\W.*/\1/')
gw6=$(ip -6 route show|grep ^default|sed -e 's/.* via \([0-9a-f:]*\)\W.*/\1/')
ipmask4=$(ip -4 addr show eth0|grep inet|sed -e 's|.* inet \([0-9.]*\)/\([0-9]*\)\W.*|\1 \2|')
ip4=$(echo $ipmask4|cut -d' ' -f 1)
mask4=$(echo $ipmask4|cut -d' ' -f 2)
ip6=$(ip -6 addr show eth0|grep inet6|grep global|sed -e 's|.* inet6 \([0-9a-f:]*\)/\([0-9]*\)\W.*|\1/\2|')

cat >> /etc/uci-defaults/60_docker-network << EOF
#!/bin/sh

uci set network.lan.proto=static
uci set network.lan.ipaddr=$ip4
uci set network.lan.netmask=$mask4
uci set network.lan.gateway=$gw4
uci set network.lan.ip6addr=$ip6
uci set network.lan.ip6gw=$gw6
uci delete network.lan.type
uci delete network.lan6
uci commit network.lan
exit 0
EOF

cat >> /etc/uci-defaults/50_passwd << EOF
#!/bin/sh

echo -e "openwrtpassword\nopenwrtpassword" | passwd
exit 0
EOF

export container=lxc

exec /sbin/init "$@"
