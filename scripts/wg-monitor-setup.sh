#!/bin/bash
set -euo pipefail

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
systemctl status wg-monitor.timer --no-pager
