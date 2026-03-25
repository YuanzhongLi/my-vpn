# セキュリティ設計

## 概要

本プロジェクトにおけるセキュリティ対策を、VPN通信・サーバー・クライアント・運用の各レイヤーで整理する。

## 1. VPN暗号化

### WireGuardの暗号スタック

| 機能 | アルゴリズム | 強度 |
|------|------------|------|
| 鍵交換 | Curve25519 (ECDH) | 128-bit security level |
| 暗号化 | ChaCha20-Poly1305 (AEAD) | 256-bit key |
| ハッシュ | BLAKE2s | 256-bit |
| 鍵導出 | HKDF | - |
| ハンドシェイク | Noise IK パターン | 前方秘匿性 (PFS) 対応 |

### 特徴

- **暗号スイートの固定**: ネゴシエーションがないため、ダウングレード攻撃が不可能
- **前方秘匿性**: 各ハンドシェイクで一時的なDH鍵ペアを使用。過去の通信は秘密鍵が漏洩しても解読不可
- **リプレイ攻撃防護**: カウンターベースのリプレイ検出
- **DoS緩和**: 初回ハンドシェイクにCookieメカニズムを使用し、計算資源の消費を防止

## 2. DNSリーク対策

### DNSリークとは

VPN接続中にDNSクエリがVPNトンネル外（ISPのDNSサーバーなど）に送信されてしまう問題。これにより：
- アクセス先のドメイン名がISPに漏洩
- 実際の所在地が特定される可能性

### 対策

#### サーバー側
```ini
# WireGuard クライアント設定でDNSを指定
[Interface]
DNS = 1.1.1.1, 1.0.0.1
```

- **VPN内DNSの強制**: クライアント設定でDNSサーバーを明示的に指定
- **推奨DNSサーバー**:
  - Cloudflare: 1.1.1.1, 1.0.0.1（高速、プライバシー重視）
  - Google: 8.8.8.8, 8.8.4.4（安定性重視）
  - AWS VPC DNS: VPC内のDNSリゾルバ（AWSサービスとの連携時）

#### クライアント側（iPhone）
- WireGuardアプリの設定でDNSを指定すると、VPN接続中は指定されたDNSのみを使用
- `AllowedIPs = 0.0.0.0/0` でフルトンネルモードにすることで、全通信がVPN経由となりDNSリークを防止

### 検証方法

VPN接続後に以下のサイトでリークを確認：
- dnsleaktest.com
- ipleak.net
- browserleaks.com/dns

## 3. Kill Switch

### Kill Switchとは

VPN接続が切断された際に、暗号化されていない通信がインターネットに送信されることを防ぐ仕組み。

### iPhone (WireGuard) での実装

WireGuardアプリのOn-Demand機能で実現：

1. **On-Demand VPN**: WireGuardアプリの設定で「On-Demand」を有効化
   - Wi-Fi: 常にVPN接続
   - Cellular: 常にVPN接続
   - 特定のSSIDを除外可能（自宅Wi-Fiなど）

2. **AllowedIPs設定**: `0.0.0.0/0, ::/0` を設定
   - 全IPv4/IPv6トラフィックをVPNルートに設定
   - VPN切断時はルーティングテーブルにより通信がブロックされる

### 制限事項

- iOS標準のKill Switchは完全ではない（一部のAppleサービス通信は例外）
- WireGuardアプリのOn-Demand機能が最も近い実装

## 4. ネットワークファイアウォール（多層防御）

VPNサーバーは**Public Subnetに配置**する。クライアントがインターネット経由でUDP 51820に直接接続するため、Private Subnetでは成立しない。

Public Subnetに置く以上、多層のファイアウォールで防御する：

```
Internet
  │
  ▼
AWS Shield Basic (L3/L4 DDoS防御・自動・無料)
  │
  ▼
Network ACL (サブネットレベル・ステートレス)
  │
  ▼
Security Group (インスタンスレベル・ステートフル)
  │
  ▼
OS iptables (カーネルレベル)
  │
  ▼
WireGuard (公開鍵認証 - 鍵を持たない通信は無視)
```

### Layer 1: AWS Shield Basic

| 項目 | 内容 |
|------|------|
| 対象 | L3/L4のDDoS攻撃（SYN flood、UDP reflection等） |
| コスト | **無料**（全AWSリソースに自動適用） |
| 設定 | 不要（自動有効） |

AWS Shield Advancedは月額$3,000のため、本プロジェクトでは不要。

### Layer 2: Network ACL (NACL)

サブネットレベルのステートレスファイアウォール。SGの前段で動作する。

#### Inbound

| ルール# | プロトコル | ポート | ソース | 許可/拒否 | 説明 |
|--------|----------|-------|--------|----------|------|
| 100 | UDP | 51820 | 0.0.0.0/0 | ALLOW | WireGuard |
| 110 | TCP | 22 | 管理者IP/32 | ALLOW | SSH |
| 120 | TCP | 1024-65535 | 0.0.0.0/0 | ALLOW | 戻り通信（エフェメラルポート） |
| 130 | UDP | 1024-65535 | 0.0.0.0/0 | ALLOW | 戻り通信（エフェメラルポート） |
| * | All | All | 0.0.0.0/0 | DENY | デフォルト拒否 |

#### Outbound

| ルール# | プロトコル | ポート | 宛先 | 許可/拒否 | 説明 |
|--------|----------|-------|------|----------|------|
| 100 | All | All | 0.0.0.0/0 | ALLOW | VPNクライアントの通信転送 |
| * | All | All | 0.0.0.0/0 | DENY | デフォルト拒否 |

**NACLはステートレス**のため、戻り通信（エフェメラルポート）の明示的な許可が必要な点がSGと異なる。

### Layer 3: Security Group (SG)

インスタンスレベルのステートフルファイアウォール。戻り通信は自動許可。

```
# Inbound（最小権限の原則）
- UDP 51820: 0.0.0.0/0     (WireGuard - 全世界からの接続を許可)
- TCP 22: <admin_ip>/32      (SSH - 管理者IPのみ)

# Outbound
- All: 0.0.0.0/0            (VPNクライアントの通信転送のため)
```

### Layer 4: OS iptables

EC2内部でのパケットフィルタリングとNAT。

```bash
# WireGuard PostUp で設定
iptables -A FORWARD -i wg0 -j ACCEPT
iptables -A FORWARD -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -t nat -A POSTROUTING -o ens5 -j MASQUERADE

# wg0以外のフォワーディングを拒否
iptables -A FORWARD -j DROP
```

### Layer 5: WireGuard自体の防御

- **公開鍵認証**: 有効な鍵ペアを持たない通信は**完全に無視**（応答しない）
- 未認証パケットにはICMP unreachable等も返さないため、ポートスキャンでWireGuardの存在を検知しにくい（"Cryptokey Routing"）
- **DoS緩和**: Cookieメカニズムにより計算資源の消耗を防止

### VPC Flow Logs（通信の可視化）

ファイアウォールではないが、Public SubnetへのアクセスパターンをVPC Flow Logsで記録・監視する。

| 項目 | 設定 |
|------|------|
| 対象 | VPNサーバーのENI |
| 保存先 | CloudWatch Logs |
| 保存期間 | 30日 |
| 用途 | 不正アクセス試行の検知、トラフィック分析 |

## 5. サーバーセキュリティ

### OS・パッケージ管理

| 対策 | 詳細 |
|------|------|
| OS選択 | Amazon Linux 2023（AWS最適化、セキュリティ更新が迅速） |
| 自動更新 | `dnf-automatic` で セキュリティパッチの自動適用 |
| 不要サービス停止 | WireGuard以外の不要なリスニングサービスを無効化 |
| SELinux | enforcing モードで運用 |

### ファイアウォール

多層防御の詳細は「4. ネットワークファイアウォール（多層防御）」セクションを参照。

### SSH強化

| 対策 | 設定 |
|------|------|
| パスワード認証無効 | `PasswordAuthentication no` |
| rootログイン禁止 | `PermitRootLogin no` |
| 鍵認証のみ | ED25519鍵を使用 |
| ポート変更 | 必要に応じてSSHポートを変更（セキュリティグループで制御） |
| 代替案 | AWS Systems Manager Session Manager でSSH不要の管理も可能 |

### EC2 IAMロール

最小権限の原則に基づくIAMポリシー：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameter",
        "ssm:GetParameters"
      ],
      "Resource": "arn:aws:ssm:ap-northeast-1:*:parameter/vpn/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
```

## 5. 鍵管理

### WireGuard鍵の種類

| 鍵 | 用途 | 保管場所 |
|----|------|---------|
| サーバー秘密鍵 | サーバーの暗号化 | AWS Systems Manager Parameter Store (SecureString) |
| サーバー公開鍵 | クライアント設定に含める | 設定ファイル / Parameter Store |
| クライアント秘密鍵 | クライアントの暗号化 | iPhone WireGuardアプリ内 |
| クライアント公開鍵 | サーバー設定の[Peer]に登録 | サーバー設定ファイル |
| Pre-shared Key (任意) | 量子コンピュータ耐性の追加レイヤー | 両端に保管 |

### 鍵生成手順

```bash
# サーバー鍵ペア生成
wg genkey | tee server_private.key | wg pubkey > server_public.key

# クライアント鍵ペア生成
wg genkey | tee client_private.key | wg pubkey > client_public.key

# Pre-shared Key生成（オプション）
wg genpsk > preshared.key
```

### 鍵のセキュアな管理

1. **生成後すぐに秘密鍵をParameter Storeに格納**
2. **ローカルの秘密鍵ファイルは即座に削除**
3. **Gitリポジトリに鍵を絶対にコミットしない**（.gitignoreに追加）
4. **Parameter Storeは KMS暗号化 (SecureString) を使用**

### .gitignore に含めるべきファイル

```
# WireGuard keys
*.key
*.conf

# Terraform
*.tfvars
*.tfstate
*.tfstate.backup
.terraform/

# SSH
*.pem
```

## 6. ログ管理・監視

### ログ設計

| ログ種別 | ソース | 保存先 | 保存期間 |
|---------|--------|--------|---------|
| VPN接続ログ | WireGuard (wg show) | CloudWatch Logs | 30日 |
| システムログ | syslog / journald | CloudWatch Logs | 30日 |
| セキュリティログ | auth.log | CloudWatch Logs | 90日 |
| AWSアクセスログ | CloudTrail | S3 | 90日 |

### WireGuardのログ特性

WireGuardは設計上、最小限のログしか出力しない（プライバシー保護のため）。
接続状態の確認は `wg show` コマンドで行う：

```bash
$ wg show
interface: wg0
  public key: <server_public_key>
  private key: (hidden)
  listening port: 51820

peer: <client_public_key>
  endpoint: <client_ip>:<port>
  allowed ips: 10.0.0.2/32
  latest handshake: 42 seconds ago
  transfer: 1.23 GiB received, 4.56 GiB sent
```

### 監視項目

| 項目 | 方法 | アラート条件 |
|------|------|------------|
| EC2インスタンス状態 | CloudWatch | StatusCheckFailed |
| CPU使用率 | CloudWatch | > 80% が5分継続 |
| ネットワーク使用量 | CloudWatch | 異常なトラフィック増加 |
| ディスク使用率 | CloudWatch Agent | > 80% |

## 7. セキュリティベストプラクティスまとめ

### 必須対策

- [ ] NACLでサブネットレベルのフィルタリング
- [ ] セキュリティグループで最小限のポートのみ開放
- [ ] SSH鍵認証のみ許可、パスワード認証無効
- [ ] WireGuard秘密鍵をParameter Store (SecureString) に保管
- [ ] .gitignoreで機密ファイルを除外
- [ ] IPフォワーディングはwg0インターフェースのみに制限
- [ ] DNSリーク対策（クライアント設定でDNSを明示指定）
- [ ] AllowedIPs = 0.0.0.0/0 でフルトンネルモード

### 推奨対策

- [ ] Pre-shared Keyの追加（量子コンピュータ耐性）
- [ ] OS自動セキュリティ更新の有効化
- [ ] CloudWatch Logsへのログ転送
- [ ] AWS Systems Manager Session ManagerによるSSHレス管理
- [ ] 定期的な鍵ローテーション（6ヶ月〜1年ごと）
- [ ] VPC Flow Logsの有効化（不正アクセス検知）
