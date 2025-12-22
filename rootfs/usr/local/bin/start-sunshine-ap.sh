#!/bin/bash

# Defaults
WIFI_IF=""
IP_ADDR="192.168.10.1"
USE_6GHZ=0
USE_160MHZ=0
USE_DFS=0

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -6|--6ghz)
            USE_6GHZ=1
            shift
            ;;
        -w|--160mhz)
            USE_160MHZ=1
            shift
            ;;
        -d|--dfs)
            USE_DFS=1
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [-6|--6ghz] [-w|--160mhz] [-d|--dfs] [interface]"
            echo "  -6, --6ghz    Use 6GHz band instead of 5GHz"
            echo "  -w, --160mhz  Use 160MHz channel width (default: 80MHz)"
            echo "  -d, --dfs     Use DFS channel 100 for 5GHz (default: channel 36)"
            echo "  interface     WiFi interface (auto-detected if not specified)"
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            exit 1
            ;;
        *)
            WIFI_IF="$1"
            shift
            ;;
    esac
done

# Auto-detect WiFi interface if not specified
if [ -z "$WIFI_IF" ]; then
    WIFI_IF=$(iw dev 2>/dev/null | awk '/Interface/{print $2}' | head -n1)
    if [ -z "$WIFI_IF" ]; then
        echo "Error: No WiFi interface found. Please specify one manually."
        exit 1
    fi
    echo "Auto-detected WiFi interface: $WIFI_IF"
fi

NET_IF=$(ip route | grep default | awk '{print $5}' | head -n1)

if [ "$USE_6GHZ" -eq 1 ]; then
    echo "Starting Moonlight AP on $WIFI_IF (6GHz)..."
else
    echo "Starting Moonlight AP on $WIFI_IF (5GHz)..."
fi

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
killall dnsmasq 2>/dev/null || true

DNSMASQ_CONF=$(mktemp)
HOSTAPD_CONF=$(mktemp)
trap "rm -f $DNSMASQ_CONF $HOSTAPD_CONF" EXIT

cat > "$DNSMASQ_CONF" <<EOF
# Only listen on the WiFi adapter
interface=$WIFI_IF
# Assign IPs from .10 to .30
dhcp-range=192.168.10.10,192.168.10.30,12h
# Set the gateway (your PC)
dhcp-option=3,192.168.10.1
# DNS
dhcp-option=6,1.1.1.1
bind-interfaces
dhcp-leasefile=/tmp/dnsmasq.leases
EOF

dnsmasq -C "$DNSMASQ_CONF"

# 5. Start Hostapd
# We do NOT use '&' here. We want systemd to track this process.
echo "Starting Hostapd..."

if [ "$USE_6GHZ" -eq 1 ]; then
    # Set channel width parameters based on 160MHz flag
    # Using UNII-5 band available in Italy
    if [ "$USE_160MHZ" -eq 1 ]; then
        OP_CLASS=134
        HE_CHWIDTH=2
        CHANNEL=65
        HE_CENTER_IDX=79  # Center of 160MHz block (channels 65-93)
        WIDTH_INFO="160MHz"
    else
        OP_CLASS=133
        HE_CHWIDTH=1
        CHANNEL=69
        HE_CENTER_IDX=71  # Center of 80MHz block (channels 65-77)
        WIDTH_INFO="80MHz"
    fi
    echo "Channel width: $WIDTH_INFO"

    # 6GHz configuration (WiFi 6E)
    cat > "$HOSTAPD_CONF" <<EOF
interface=$WIFI_IF
driver=nl80211
ssid=Moonlight_Stream_6G
country_code=IT

# --- BASE 6GHz SETTINGS ---
hw_mode=a
channel=$CHANNEL
# 6GHz band requires op_class (133=80MHz, 134=160MHz)
op_class=$OP_CLASS

# --- WI-FI 6E (AX) SETTINGS ---
ieee80211ax=1
he_oper_chwidth=$HE_CHWIDTH
he_oper_centr_freq_seg0_idx=$HE_CENTER_IDX

# 6GHz requires SAE (WPA3) only
ieee80211w=2
wpa=2
wpa_key_mgmt=SAE
wpa_passphrase=Voglio10\$nasi
rsn_pairwise=CCMP
sae_require_mfp=1

# --- TUNING ---
wmm_enabled=1
EOF
else
    # 5GHz configuration
    if [ "$USE_DFS" -eq 1 ]; then
        CHANNEL_5G=100
        CENTER_FREQ_IDX=106  # Center of 100-116 block
        echo "Using DFS channel 100"
    else
        CHANNEL_5G=36
        CENTER_FREQ_IDX=42   # Center of 36-48 block
    fi

    cat > "$HOSTAPD_CONF" <<EOF
interface=$WIFI_IF
driver=nl80211
ssid=Moonlight_Stream_5G
country_code=IT

# --- BASE 5GHz SETTINGS ---
hw_mode=a
channel=$CHANNEL_5G

# --- WI-FI 6 (AX) SETTINGS ---
ieee80211ax=1
# 1 = 80MHz Width
he_oper_chwidth=1
he_oper_centr_freq_seg0_idx=$CENTER_FREQ_IDX

# --- WI-FI 5 (AC) SETTINGS (CRITICAL FIX) ---
# You MUST enable AC and set VHT parameters identical to HE parameters
ieee80211ac=1
vht_oper_chwidth=1
vht_oper_centr_freq_seg0_idx=$CENTER_FREQ_IDX
# Set HT40+ capability (Use 40MHz+ width for N devices)
ht_capab=[HT40+][SHORT-GI-40][SHORT-GI-20]

# --- SECURITY ---
wpa=2
wpa_key_mgmt=WPA-PSK SAE
wpa_passphrase=Voglio10\$nasi
rsn_pairwise=CCMP
ieee80211w=1

# --- TUNING ---
wmm_enabled=1
preamble=1
EOF
fi

exec hostapd "$HOSTAPD_CONF"
