# アーキテクチャ設計

## 概要

プロトコル比較(02)およびインフラ比較(03)の結果に基づき、以下の構成で設計する。

- **VPNプロトコル**: WireGuard
- **実行環境**: EC2 (t3.nano)
- **リージョン**: 東京 (ap-northeast-1)
- **IaC**: Terraform
- **AWSアカウント**: AWS Organizations で新規作成（VPN専用）
- **EIP運用**: 都度作成/削除（コスト最適化）
- **DNS**: 既存ドメインのサブドメインを委譲して使用

## AWSアーキテクチャ

### AWSアカウント構成

```
AWS Organization
├── 親アカウント (既存・ドメイン管理)
│   └── Route53: example.com
│       └── NS レコード: vpn.example.com → VPNアカウントのNSを指定
│
└── VPNアカウント (本プロジェクト用・新規作成)
    ├── Route53: vpn.example.com (サブドメイン委譲)
    │   └── A レコード: → EIP (起動時に動的更新)
    ├── VPC + EC2 (WireGuard)
    └── Terraform管理
```

### ネットワーク構成図

```
                                Internet
                                   |
                          +--------+--------+
                          | Route53         |
                          | vpn.example.com |
                          | → EIP (動的)    |
                          +--------+--------+
                                   |
                            +------+------+
                            | Internet    |
                            | Gateway     |
                            +------+------+
                                   |
                    +--------------+---------------+
                    |         VPC: 10.1.0.0/16     |
                    |                              |
                    |  +------------------------+  |
                    |  | Public Subnet           |  |
                    |  | 10.1.1.0/24            |  |
                    |  | AZ: ap-northeast-1a    |  |
                    |  |                        |  |
                    |  |  +------------------+  |  |
                    |  |  | EC2 (t3.nano)    |  |  |
                    |  |  | WireGuard Server |  |  |
                    |  |  | EIP: 都度作成    |  |  |
                    |  |  +------------------+  |  |
                    |  |                        |  |
                    |  +------------------------+  |
                    |                              |
                    +------------------------------+

    WireGuard VPN Subnet: 10.0.0.0/24 (仮想)
    - Server: 10.0.0.1
    - Clients: 10.0.0.2 ~ 10.0.0.254
```

### VPC設計

| リソース | CIDR / 値 | 説明 |
|---------|-----------|------|
| VPC | 10.1.0.0/16 | VPN専用VPC |
| Public Subnet | 10.1.1.0/24 | VPNサーバー配置用 |
| Internet Gateway | - | インターネット接続用 |
| Route Table | 0.0.0.0/0 → IGW | デフォルトルート |

### WireGuard仮想ネットワーク

| リソース | 値 | 説明 |
|---------|-----|------|
| WireGuard Subnet | 10.0.0.0/24 | VPNトンネル内のアドレス空間 |
| Server Address | 10.0.0.1/24 | WireGuardサーバーのトンネルIP |
| Client Range | 10.0.0.2 - 10.0.0.254 | クライアントに割り当て（最大253台） |
| Listen Port | 51820/UDP | WireGuard標準ポート |
| DNS | 1.1.1.1, 1.0.0.1 | Cloudflare DNS（高速） |

### セキュリティグループ

#### VPNサーバー用セキュリティグループ

| ルール | プロトコル | ポート | ソース | 説明 |
|-------|----------|-------|--------|------|
| Inbound | UDP | 51820 | 0.0.0.0/0 | WireGuard接続 |
| Inbound | TCP | 22 | 管理者IP/32 | SSH管理アクセス |
| Outbound | All | All | 0.0.0.0/0 | 全アウトバウンド許可 |

**注意**: SSH(22)は管理者のIPアドレスのみに制限する。EC2 Instance Connectの利用も検討。

### EC2インスタンス

| 項目 | 値 |
|------|-----|
| インスタンスタイプ | t3.nano (2 vCPU, 0.5GB RAM) |
| AMI | Amazon Linux 2023 (最新) |
| ストレージ | gp3 8GB |
| Elastic IP | 起動時に都度作成・アタッチ / 停止時に解放 |
| Key Pair | ED25519鍵 |
| User Data | WireGuardインストール・初期設定スクリプト |

### IPフォワーディングとNAT

EC2インスタンス上で以下を設定（VPNクライアントの通信をインターネットに転送するため）：

```bash
# IPフォワーディング有効化
echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
sysctl -p

# NAT (MASQUERADE) 設定 - WireGuardのPostUp/PostDownで管理
iptables -A FORWARD -i wg0 -j ACCEPT
iptables -t nat -A POSTROUTING -o ens5 -j MASQUERADE
```

## Terraform構成

### ディレクトリ構造

```
terraform/
├── main.tf              # プロバイダー設定、バックエンド
├── variables.tf         # 変数定義
├── outputs.tf           # 出力値（インスタンスID、ホストゾーンID等）
├── terraform.tfvars     # 変数値（gitignore対象）
├── vpc.tf               # VPC、サブネット、IGW、ルートテーブル
├── security_group.tf    # セキュリティグループ
├── ec2.tf               # EC2インスタンス
├── route53.tf           # Route53ホストゾーン（サブドメイン）
├── iam.tf               # IAMロール（EC2用、SSM用、EIP/Route53操作用）
└── scripts/
    └── user_data.sh     # EC2初期化スクリプト
```

**注意**: EIP (`aws_eip`, `aws_eip_association`) はTerraform管理外。起動/停止スクリプトで動的に管理する。

### 主要リソース一覧

| Terraformリソース | 用途 |
|-----------------|------|
| `aws_vpc` | VPN専用VPC |
| `aws_subnet` | パブリックサブネット |
| `aws_internet_gateway` | インターネットゲートウェイ |
| `aws_route_table` | ルートテーブル |
| `aws_security_group` | VPNサーバー用SG |
| `aws_instance` | EC2インスタンス |
| `aws_route53_zone` | サブドメイン用ホストゾーン |
| `aws_iam_role` | EC2用IAMロール |
| `aws_iam_instance_profile` | インスタンスプロファイル |

### Terraform管理外のリソース（スクリプトで管理）

| リソース | 管理方法 | 理由 |
|---------|---------|------|
| EIP | 起動/停止スクリプト | 都度作成/削除のためstateと不整合になる |
| Route53 Aレコード | 起動スクリプト | EIPに連動して動的更新 |

### クロスアカウント: サブドメイン委譲設定

親アカウント側で必要な設定（手動 or 別Terraform）：

```hcl
# 親アカウント側: example.com のホストゾーンにNSレコードを追加
resource "aws_route53_record" "vpn_subdomain_delegation" {
  zone_id = data.aws_route53_zone.parent.zone_id
  name    = "vpn.example.com"
  type    = "NS"
  ttl     = 300
  records = [
    # VPNアカウントのホストゾーンのNSレコード値（terraform output で取得）
    "ns-xxx.awsdns-xx.org.",
    "ns-xxx.awsdns-xx.co.uk.",
    "ns-xxx.awsdns-xx.com.",
    "ns-xxx.awsdns-xx.net.",
  ]
}
```

### 主要変数

```hcl
variable "instance_type" {
  description = "EC2 instance type"
  default     = "t3.nano"
}

variable "admin_ssh_cidr" {
  description = "SSH access CIDR (admin IP)"
  type        = string
}

variable "wireguard_port" {
  description = "WireGuard listen port"
  default     = 51820
}

variable "vpn_subnet" {
  description = "WireGuard VPN subnet"
  default     = "10.0.0.0/24"
}

variable "subdomain" {
  description = "VPN subdomain (e.g., vpn.example.com)"
  type        = string
}
```

### Terraformバックエンド

| 方式 | 説明 |
|------|------|
| Local (初期) | terraform.tfstate をローカル管理。gitignoreに追加 |
| S3 + DynamoDB (将来) | チーム運用時にリモートバックエンドに移行 |

## User Data スクリプト概要

EC2起動時に自動実行されるスクリプトの概要：

1. パッケージ更新
2. WireGuardインストール
3. IPフォワーディング有効化
4. WireGuardサーバー鍵ペア生成
5. サーバー設定ファイル生成
6. WireGuardサービス起動・自動起動設定

**注意**: 鍵はUser Dataで生成する方式と、事前に生成してAWS Systems Manager Parameter Storeに格納する方式がある。セキュリティの観点からは後者が望ましい。詳細は [05-security.md](./05-security.md) を参照。

## 起動/停止フロー

### サーバー起動

```bash
# start-vpn.sh の処理フロー
1. aws ec2 start-instances           # EC2起動
2. aws ec2 wait instance-running     # 起動待ち
3. aws ec2 allocate-address          # EIP作成
4. aws ec2 associate-address         # EIPをEC2にアタッチ
5. aws route53 change-resource-record-sets  # Aレコード更新 (vpn.example.com → 新EIP)
6. 起動確認
```

- EC2起動 → EIP作成・アタッチ → DNS更新 → WireGuard自動起動（systemd）
- 起動所要時間: 約1〜2分（DNS伝播含む。TTL短めに設定）

### サーバー停止

```bash
# stop-vpn.sh の処理フロー
1. aws ec2 describe-addresses        # 現在のEIP取得
2. aws ec2 disassociate-address      # EIPをデタッチ
3. aws ec2 release-address           # EIP解放
4. aws ec2 stop-instances            # EC2停止
```

- EIP解放 → EC2停止
- 停止中のコスト: **EBS($0.76/月) のみ**（EIPなし、Route53 HZ $0.50/月）

### 運用スクリプト（将来作成）

```
scripts/
├── start-vpn.sh     # EC2起動 + EIP作成 + DNS更新
├── stop-vpn.sh      # EC2停止 + EIP解放
├── status-vpn.sh    # 接続状態確認
├── add-peer.sh      # ユーザー追加
└── remove-peer.sh   # ユーザー削除
```

### IAMポリシー（起動/停止スクリプト用）

スクリプト実行者（またはEC2自身）に以下の権限が必要：

```json
{
  "Effect": "Allow",
  "Action": [
    "ec2:StartInstances",
    "ec2:StopInstances",
    "ec2:DescribeInstances",
    "ec2:AllocateAddress",
    "ec2:AssociateAddress",
    "ec2:DisassociateAddress",
    "ec2:ReleaseAddress",
    "ec2:DescribeAddresses",
    "route53:ChangeResourceRecordSets",
    "route53:ListResourceRecordSets"
  ],
  "Resource": "*"
}
```
