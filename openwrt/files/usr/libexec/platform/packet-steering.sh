#!/bin/sh
# Platform packet steering hook, called by /etc/init.d/packet_steering
# (at boot and on every interface event) with network.globals.packet_steering
# as $1. OpenWrt uses this file instead of the generic packet-steering.uc.
#
# Cisco AP1852: both GMACs have a single RX queue. Measured on a 1000/50 line
# (nPerf from a LAN client): one core saturates at ~300-450 Mbit/s; with each
# NIC's IRQ on its own core and RX processing (NAT/firewall/forwarding)
# steered to the other core it reaches ~930 Mbit/s.
#   eth0 (LAN, GMAC2): IRQ -> CPU0, RPS -> CPU1
#   eth1 (WAN, GMAC3): IRQ -> CPU1, RPS -> CPU0
# packet_steering=0 removes RPS (IRQs stay split); any other value enables it.

if [ "$(cat /tmp/sysinfo/board_name 2>/dev/null)" != "cisco,ap1852" ]; then
	exec /usr/libexec/network/packet-steering.uc "$@"
fi

set_dev() {
	local dev=$1 aff=$2 rps=$3 irq
	[ -d /sys/class/net/$dev ] || return 0
	irq=$(grep -w "$dev" /proc/interrupts | cut -d: -f1 | tr -d ' ')
	[ -n "$irq" ] && echo $aff > /proc/irq/$irq/smp_affinity
	echo $rps > /sys/class/net/$dev/queues/rx-0/rps_cpus
}

mode=${1:-1}
if [ "$mode" = 0 ]; then
	set_dev eth0 1 0
	set_dev eth1 2 0
else
	set_dev eth0 1 2
	set_dev eth1 2 1
fi
exit 0
