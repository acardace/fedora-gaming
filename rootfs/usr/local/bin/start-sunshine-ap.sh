#!/bin/bash

# Configuration
WIFI_IF="wlp11s0f3u2" # Your specific USB Interface from the logs
IP_ADDR="192.168.10.1"
NET_IF=$(ip route | grep default | awk '{print $5}' | head -n1)

echo "Starting Moonlight AP on $WIFI_IF..."

# 1. Unlock Italy 6GHz channels
iw reg set IT

# 2. Setup Interface
ip link set $WIFI_IF up
ip addr flush dev $WIFI_IF
ip addr add $IP_ADDR/24 dev $WIFI_IF

# 3. Enable NAT (Internet Sharing)
if [ -n "$NET_IF" ]; then
    echo "Enabling NAT from $NET_IF..."
    sysctl -w net.ipv4.ip_forward=1 > /dev/null
    # Clear old rules just in case to avoid duplicates
    iptables -t nat -D POSTROUTING -o $NET_IF -j MASQUERADE 2>/dev/null || true
    iptables -D FORWARD -i $NET_IF -o $WIFI_IF -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i $WIFI_IF -o $NET_IF -j ACCEPT 2>/dev/null || true
    
    # Add new rules
    iptables -t nat -A POSTROUTING -o $NET_IF -j MASQUERADE
    iptables -A FORWARD -i $NET_IF -o $WIFI_IF -m state --state RELATED,ESTABLISHED -j ACCEPT
    iptables -A FORWARD -i $WIFI_IF -o $NET_IF -j ACCEPT
fi

# 4. Start DHCP
# We use 'exec' here? No, we run it in background because hostapd needs to be the main process
killall dnsmasq 2>/dev/null || true
dnsmasq -C /etc/dnsmasq-moonlight.conf

# 5. Start Hostapd
# We do NOT use '&' here. We want systemd to track this process.
echo "Starting Hostapd..."
exec hostapd /etc/hostapd/moonlight-6g.conf
