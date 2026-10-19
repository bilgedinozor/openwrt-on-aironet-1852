#!/bin/sh
# TEMPLATE — dumb-AP config. Edit the LAN IP/gateway/DNS and SSID/key for your
# network before running. Delivered to the board over HTTP and run with sh.
# Persistent safe config for unit 3 (dumb-AP style, no rogue DHCP, reachable, 2.4G AP).
# Delivered via HTTP so serial drops cannot corrupt it.
set -u
echo "CONFIG_SCRIPT_V1_BEGIN"

# --- network: static, reachable, no DHCP server (do not disturb home LAN) ---
uci set network.lan.proto='static'
uci set network.lan.ipaddr='10.0.5.201'
uci set network.lan.netmask='255.255.255.0'
uci set network.lan.gateway='10.0.5.1'
uci -q delete network.lan.ip6assign
uci set network.lan.dns='10.0.5.1'
uci commit network

# --- stop serving DHCP on LAN (this unit is an AP; the real router serves leases) ---
uci set dhcp.lan.ignore='1'
uci set dhcp.lan.dhcpv6='disabled'
uci set dhcp.lan.ra='disabled'
uci commit dhcp
/etc/init.d/odhcpd disable 2>/dev/null
/etc/init.d/dnsmasq disable 2>/dev/null

# --- wireless: 2.4G AP, TR regdomain, sane power ---
uci set wireless.radio0.disabled='0'
uci set wireless.radio0.country='TR'
uci set wireless.radio0.channel='1'
uci set wireless.radio0.htmode='HT20'
uci set wireless.radio0.txpower='17'
uci set wireless.radio0.cell_density='0'
uci set wireless.default_radio0.mode='ap'
uci set wireless.default_radio0.ssid='AP1852-24G'
uci set wireless.default_radio0.encryption='psk2'
uci set wireless.default_radio0.key='ap1852test'
uci set wireless.default_radio0.network='lan'
# keep the 2nd radio (5G hw, 2.4G-only w/o 5G board data) disabled for now
uci set wireless.radio1.disabled='1'
uci commit wireless

# --- hostname ---
uci set system.@system[0].hostname='ap1852-u3'
uci commit system

echo "CONFIG_RESULT=PASS"
