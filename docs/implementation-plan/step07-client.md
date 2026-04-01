# Step 7: クライアント設定・接続テスト

## 目的

SSM経由でサーバーに接続し、手動でWireGuardピアを追加。QRコードを生成してiPhoneから接続テストを行う。

## 前提

- VPNサーバーが起動中（`make start-vpn` 済み）
- iPhoneにWireGuard公式アプリがインストール済み

## 手順

### 1. SSMでサーバー接続

```bash
make ssm-vpn
```

### 2. qrencodeインストール

```bash
sudo dnf install -y qrencode
```

### 3. クライアント鍵ペア生成

```bash
cd /etc/wireguard
sudo bash -c 'umask 077; wg genkey | tee client1_private.key | wg pubkey > client1_public.key'
```

### 4. サーバーにピア追加

```bash
sudo wg set wg0 peer $(sudo cat client1_public.key) allowed-ips 10.0.0.2/32
sudo wg-quick save wg0
sudo wg show wg0
```

### 5. クライアント設定ファイル生成

```bash
sudo bash -c 'cat > /etc/wireguard/client1.conf << EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/client1_private.key)
Address = 10.0.0.2/32
DNS = 1.1.1.1, 1.0.0.1

[Peer]
PublicKey = $(cat /etc/wireguard/server_public.key)
Endpoint = vpn.example.com:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF'
```

### 6. QRコード表示

```bash
sudo qrencode -t ansiutf8 < /etc/wireguard/client1.conf
```

### 7. iPhoneで接続

1. WireGuardアプリ → 「+」→「QRコードから作成」
2. QRコードをスキャン
3. トンネル名: 「Japan VPN」
4. スイッチONで接続

### 8. セキュリティ後片付け

```bash
sudo rm /etc/wireguard/client1_private.key /etc/wireguard/client1.conf
```

## 接続テスト

| テスト | 方法 | 期待結果 |
|-------|------|---------|
| IPアドレス確認 | Safariで `ifconfig.me` | サーバーのEIPが表示 |
| 日本IP確認 | `whatismyipaddress.com` | Tokyo, Japan |
| DNSリーク | `dnsleaktest.com` | Cloudflare DNSのみ |
| WireGuard状態 | `sudo wg show wg0` | latest handshakeが表示 |

## 設計判断

| 項目 | 判断 | 理由 |
|------|------|------|
| Endpoint | ドメイン名 | EIP変更時にクライアント設定変更不要 |
| DNS | Cloudflare (1.1.1.1) | DNSリーク防止 |
| AllowedIPs | 0.0.0.0/0, ::/0 | フルトンネル（全通信VPN経由） |
| PersistentKeepalive | 25秒 | NAT越え維持 |
| クライアントIP | 10.0.0.2 | 最初のクライアント |
