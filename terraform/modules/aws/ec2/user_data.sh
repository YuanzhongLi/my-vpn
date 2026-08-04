#!/bin/bash
set -euo pipefail

# 1. パッケージ更新 + WireGuardインストール
dnf update -y
dnf install -y wireguard-tools iptables-nft

# 2. IPフォワーディング有効化
echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/99-wireguard.conf
sysctl -p /etc/sysctl.d/99-wireguard.conf

# 3. WireGuardサーバー鍵生成
cd /etc/wireguard
umask 077
wg genkey | tee server_private.key | wg pubkey > server_public.key

# 4. WireGuard設定ファイル生成
cat > /etc/wireguard/wg0.conf << 'WGEOF'
[Interface]
Address = 10.0.0.1/24
ListenPort = 51820
PrivateKey = PLACEHOLDER

PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -A POSTROUTING -o ens5 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -D POSTROUTING -o ens5 -j MASQUERADE
WGEOF

# 5. 秘密鍵をconf内に埋め込み
sed -i "s|PLACEHOLDER|$(cat server_private.key)|" /etc/wireguard/wg0.conf

# 6. WireGuard起動 + 自動起動有効化
systemctl enable --now wg-quick@wg0

# 7. 接続状況モニタリング(10秒ごとにwg show wg0 dumpを記録、7日でlogrotate)
cat > /usr/local/bin/wg-monitor.sh << 'SCRIPT_EOF'
#!/bin/bash
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
{
  echo "=== $TS ==="
  wg show wg0 dump
} >> /var/log/wg-monitor.log
SCRIPT_EOF
chmod +x /usr/local/bin/wg-monitor.sh

cat > /etc/systemd/system/wg-monitor.service << 'UNIT_EOF'
[Unit]
Description=Log WireGuard peer status snapshot

[Service]
Type=oneshot
ExecStart=/usr/local/bin/wg-monitor.sh
UNIT_EOF

cat > /etc/systemd/system/wg-monitor.timer << 'TIMER_EOF'
[Unit]
Description=Run wg-monitor every 10 seconds

[Timer]
OnBootSec=10s
OnUnitActiveSec=10s
AccuracySec=1s

[Install]
WantedBy=timers.target
TIMER_EOF

cat > /etc/logrotate.d/wg-monitor << 'LOGROTATE_EOF'
/var/log/wg-monitor.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    copytruncate
}
LOGROTATE_EOF

touch /var/log/wg-monitor.log
systemctl daemon-reload
systemctl enable --now wg-monitor.timer
