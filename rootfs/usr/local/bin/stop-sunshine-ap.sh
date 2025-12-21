#!/bin/bash

WIFI_IF="wlp11s0f3u2" # Your interface
NET_IF=$(ip route | grep default | awk '{print $5}' | head -n1)

echo "Stopping Moonlight AP..."

# 1. Kill DHCP
killall dnsmasq 2>/dev/null || true

# 2. Remove NAT Rules (Clean up firewall)
if [ -n "$NET_IF" ]; then
    iptables -t nat -D POSTROUTING -o $NET_IF -j MASQUERADE 2>/dev/null || true
    iptables -D FORWARD -i $NET_IF -o $WIFI_IF -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i $WIFI_IF -o $NET_IF -j ACCEPT 2>/dev/null || true
fi

# 3. Bring down interface
ip link set $WIFI_IF down
ip addr flush dev $WIFI_IF

echo "Cleanup complete."
