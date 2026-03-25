# 運用ガイド

## 概要

VPNサーバーの日常的な運用手順、ユーザー管理、監視、コスト管理について説明する。

## 1. サーバーの起動・停止

### 前提

- AWS CLIがインストール・設定済み
- EC2インスタンスIDが既知（Terraform outputで取得可能）

### 起動

```bash
# インスタンスID取得（初回）
INSTANCE_ID=$(terraform -chdir=terraform output -raw instance_id)

# サーバー起動
aws ec2 start-instances \
  --instance-ids $INSTANCE_ID \
  --region ap-northeast-1

# 起動確認（runningになるまで待機）
aws ec2 wait instance-running \
  --instance-ids $INSTANCE_ID \
  --region ap-northeast-1

echo "VPN server is running"
```

起動後、WireGuardはsystemdにより自動的に開始される。

### 停止

```bash
# サーバー停止
aws ec2 stop-instances \
  --instance-ids $INSTANCE_ID \
  --region ap-northeast-1

# 停止確認
aws ec2 wait instance-stopped \
  --instance-ids $INSTANCE_ID \
  --region ap-northeast-1

echo "VPN server is stopped"
```

### 状態確認

```bash
# インスタンス状態確認
aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --region ap-northeast-1 \
  --query 'Reservations[0].Instances[0].State.Name' \
  --output text
```

## 2. ユーザー（ピア）管理

### ユーザー追加手順

#### 1. 鍵ペア生成

```bash
# 新規ユーザーの鍵ペアを生成
wg genkey | tee /tmp/new_client_private.key | wg pubkey > /tmp/new_client_public.key

# Pre-shared Key生成（オプション）
wg genpsk > /tmp/new_client_psk.key

# 鍵の表示
echo "Private Key: $(cat /tmp/new_client_private.key)"
echo "Public Key:  $(cat /tmp/new_client_public.key)"
```

#### 2. サーバー設定に追加

```bash
# SSH接続してサーバー設定に[Peer]を追加
# 次に利用可能なIPを割り当て（例: 10.0.0.X）

# ライブ追加（再起動不要）
sudo wg set wg0 peer <new_client_public_key> \
  allowed-ips 10.0.0.X/32

# 設定ファイルにも永続化
sudo wg-quick save wg0
```

#### 3. クライアント設定ファイル生成

```ini
# /tmp/new_client.conf
[Interface]
PrivateKey = <new_client_private_key>
Address = 10.0.0.X/32
DNS = 1.1.1.1, 1.0.0.1

[Peer]
PublicKey = <server_public_key>
Endpoint = <server_elastic_ip>:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
```

#### 4. QRコード生成・共有

```bash
qrencode -t ansiutf8 < /tmp/new_client.conf
```

#### 5. 後片付け

```bash
# ローカルの秘密鍵を削除
rm /tmp/new_client_private.key /tmp/new_client_psk.key
```

### ユーザー削除手順

```bash
# ピアの削除（再起動不要）
sudo wg set wg0 peer <client_public_key> remove

# 設定ファイルにも反映
sudo wg-quick save wg0
```

### ユーザー一覧確認

```bash
# 全ピアの状態確認
sudo wg show wg0

# 接続中のピアのみ表示（latest handshakeが2分以内）
sudo wg show wg0 dump | awk '$6 != 0 && (systime() - $6) < 120 {print $1, $4}'
```

### IP割り当て管理

| IP | ユーザー/デバイス | 状態 |
|----|-----------------|------|
| 10.0.0.1 | サーバー | 固定 |
| 10.0.0.2 | Admin - iPhone | 使用中 |
| 10.0.0.3 | Admin - MacBook | 使用中 |
| 10.0.0.4-254 | 未割り当て | 空き |

**注意**: IP割り当ての台帳管理は手動。将来的に管理コンソールで自動化予定。

## 3. サーバーメンテナンス

### OS・パッケージ更新

```bash
# SSH接続後
sudo dnf update -y

# セキュリティパッチのみ
sudo dnf update --security -y

# 再起動が必要な場合
sudo reboot
```

### WireGuard設定のバックアップ

```bash
# 設定ファイルのバックアップ
sudo cp /etc/wireguard/wg0.conf /etc/wireguard/wg0.conf.backup.$(date +%Y%m%d)
```

### ログ確認

```bash
# WireGuardサービスのログ
sudo journalctl -u wg-quick@wg0 --since today

# システムログ
sudo journalctl --since today

# 認証ログ
sudo journalctl -u sshd --since today
```

## 4. 監視

### CloudWatch メトリクス（推奨設定）

| メトリクス | 閾値 | アクション |
|-----------|------|----------|
| CPUUtilization | > 80% (5分) | SNS通知 |
| StatusCheckFailed | > 0 | SNS通知 |
| NetworkIn | 異常増加 | 確認 |
| NetworkOut | 異常増加 | 確認 |

### 手動監視コマンド

```bash
# WireGuard接続状態
sudo wg show

# ネットワーク統計
sudo wg show wg0 transfer

# システムリソース
top -bn1 | head -5
df -h
free -m
```

## 5. コスト見積もり

### 月額コスト試算

#### パターンA: 軽量利用（1日2時間使用）

| リソース | 月額 (USD) |
|---------|-----------|
| EC2 t3.nano (60h/月) | $0.31 |
| EBS gp3 8GB | $0.76 |
| Elastic IP (停止中: 22h × 30日 = 660h) | $3.30 |
| データ転送 30GB | $3.42 |
| **合計** | **~$8/月** |

#### パターンB: 中程度利用（1日8時間使用）

| リソース | 月額 (USD) |
|---------|-----------|
| EC2 t3.nano (240h/月) | $1.25 |
| EBS gp3 8GB | $0.76 |
| Elastic IP (停止中: 16h × 30日 = 480h) | $2.40 |
| データ転送 100GB | $11.40 |
| **合計** | **~$16/月** |

#### パターンC: 常時起動

| リソース | 月額 (USD) |
|---------|-----------|
| EC2 t3.nano (730h/月) | $3.80 |
| EBS gp3 8GB | $0.76 |
| Elastic IP (常時使用中) | $3.65 |
| データ転送 100GB | $11.40 |
| **合計** | **~$20/月** |

### コスト最適化のポイント

1. **使わない時は停止**: EC2停止でコンピューティング費用ゼロ
2. **Elastic IP**: 停止中も課金されるため、長期停止時はEIP解放も検討（ただしIP変更が発生）
3. **データ転送**: 動画ストリーミング等の大量通信に注意
4. **Reserved Instance**: 常時起動の場合、1年RIで30〜40%割引
5. **Savings Plans**: コンピューティング全般で割引を受けられる

## 6. 障害対応

### よくある問題と対処

| 問題 | 原因 | 対処 |
|------|------|------|
| VPN接続不可 | EC2停止中 | `aws ec2 start-instances` |
| VPN接続不可 | WireGuardサービス停止 | `sudo systemctl start wg-quick@wg0` |
| VPN接続不可 | セキュリティグループ変更 | UDP 51820の許可を確認 |
| 接続後に通信不可 | IPフォワーディング無効 | `sudo sysctl -w net.ipv4.ip_forward=1` |
| 接続後に通信不可 | iptables NAT設定消失 | `wg-quick down wg0 && wg-quick up wg0` |
| 速度低下 | t3バーストクレジット枯渇 | CloudWatchでCPUCreditBalance確認 |
| SSH接続不可 | IPアドレス変更 | セキュリティグループのSSH許可IPを更新 |
