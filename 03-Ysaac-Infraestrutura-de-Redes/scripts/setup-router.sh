#!/bin/bash
# Monta o roteador/firewall (router-fw) automaticamente.
# Uso: sudo bash setup-router.sh

# ===== AJUSTE AQUI se os nomes das placas forem diferentes (ip -br link) =====
WAN="ens33"
DMZ="ens37"
LAN="ens38"
DB="ens39"
# ==============================================================================

if [ "$EUID" -ne 0 ]; then
  echo "Rode com sudo: sudo bash setup-router.sh"
  exit 1
fi

for IF in $WAN $DMZ $LAN $DB; do
  if ! ip link show "$IF" > /dev/null 2>&1; then
    echo "ERRO: a placa $IF nao existe. Confira com 'ip -br link' e ajuste o topo do script."
    exit 1
  fi
done

echo "[1/5] Configurando IPs (netplan)..."
cat > /etc/netplan/50-cloud-init.yaml <<EOF
network:
  version: 2
  ethernets:
    $WAN:
      dhcp4: true
    $DMZ:
      addresses: [192.168.10.1/24]
    $LAN:
      addresses: [192.168.20.1/24]
    $DB:
      addresses: [192.168.30.1/24]
EOF
chmod 600 /etc/netplan/50-cloud-init.yaml
netplan apply

echo "[2/5] Ativando roteamento..."
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-forward.conf
sysctl --system > /dev/null

echo "[3/5] Instalando dnsmasq..."
apt update
apt install -y dnsmasq

echo "[4/5] Configurando DNS e DHCP..."
cat > /etc/dnsmasq.d/dns.conf <<'EOF'
listen-address=192.168.10.1,192.168.20.1,192.168.30.1
bind-interfaces
no-resolv
server=1.1.1.1
server=8.8.8.8
domain=projeto.local
local=/projeto.local/
address=/router.projeto.local/192.168.20.1
address=/web.projeto.local/192.168.10.10
address=/db.projeto.local/192.168.30.10
address=/files.projeto.local/192.168.20.10
EOF

cat > /etc/dnsmasq.d/dhcp.conf <<'EOF'
dhcp-range=set:lan,192.168.20.100,192.168.20.200,12h
dhcp-option=tag:lan,option:router,192.168.20.1
dhcp-option=tag:lan,option:dns-server,192.168.20.1
EOF

systemctl restart dnsmasq
systemctl enable dnsmasq

echo "[5/5] Configurando firewall (nftables)..."
cat > /etc/nftables.conf <<EOF
#!/usr/sbin/nft -f
flush ruleset

define WAN = "$WAN"
define DMZ = "$DMZ"
define LAN = "$LAN"
define DB  = "$DB"
EOF

cat >> /etc/nftables.conf <<'EOF'

define WEB_SRV  = 192.168.10.10
define FILE_SRV = 192.168.20.10
define DB_SRV   = 192.168.30.10

table inet filter {
  chain input {
    type filter hook input priority 0; policy drop;
    ct state established,related accept
    ct state invalid drop
    iif lo accept
    meta l4proto { icmp, ipv6-icmp } accept
    iifname { $DMZ, $LAN, $DB } udp dport 53 accept
    iifname { $DMZ, $LAN, $DB } tcp dport 53 accept
    iifname $LAN udp dport 67 accept
    iifname $LAN tcp dport 22 accept
    iifname $WAN tcp dport 22 accept
  }

  chain forward {
    type filter hook forward priority 0; policy drop;
    ct state established,related accept
    ct state invalid drop

    iifname $LAN oifname $WAN tcp dport { 80, 443 } accept
    iifname $LAN oifname $DMZ ip daddr $WEB_SRV tcp dport { 80, 443 } accept
    iifname $LAN oifname { $WAN, $DMZ } icmp type echo-request accept

    iifname $DMZ oifname $DB ip saddr $WEB_SRV ip daddr $DB_SRV tcp dport 5432 accept

    iifname $DB oifname $LAN ip saddr $DB_SRV ip daddr $FILE_SRV tcp dport { 139, 445 } accept

    log prefix "FW-DROP: " limit rate 5/minute
  }

  chain output {
    type filter hook output priority 0; policy accept;
  }
}

table ip nat {
  chain postrouting {
    type nat hook postrouting priority 100;
    oifname $WAN masquerade
  }
}
EOF

nft -c -f /etc/nftables.conf && systemctl enable --now nftables
systemctl restart nftables

echo ""
echo "PRONTO! Testes:"
echo "  ping -c 3 8.8.8.8"
echo "  nslookup -type=A web.projeto.local 192.168.20.1"
echo "  sudo nft list ruleset"
