# my-vpn

海外からiPhoneで日本のWebサイトにアクセスするための自作VPNシステム。

## 構成

- **VPNプロトコル**: WireGuard
- **インフラ**: AWS EC2 (東京リージョン)
- **IaC**: Terraform
- **クライアント**: iPhone (WireGuard公式アプリ)

## 特徴

- 必要な時だけサーバーを起動し、コストを最適化
- WireGuardによる高速・安全な通信
- Terraformによるインフラのコード管理
- QRコードで簡単にiPhoneを設定

## ドキュメント

| # | ドキュメント | 内容 |
|---|------------|------|
| 01 | [プロジェクト概要](docs/plan/01-overview.md) | 目的、全体アーキテクチャ、用語定義 |
| 02 | [VPNプロトコル比較](docs/plan/02-protocol-comparison.md) | WireGuard vs IKEv2/IPSec の詳細比較 |
| 03 | [インフラ構成比較](docs/plan/03-infrastructure-comparison.md) | EC2 vs ECS (Fargate) の比較 |
| 04 | [アーキテクチャ設計](docs/plan/04-architecture.md) | AWS構成、Terraform設計 |
| 05 | [セキュリティ設計](docs/plan/05-security.md) | 暗号化、DNSリーク対策、鍵管理 |
| 06 | [クライアント設定](docs/plan/06-client-setup.md) | iPhone WireGuardアプリの設定手順 |
| 07 | [運用ガイド](docs/plan/07-operations.md) | 起動/停止、ユーザー管理、コスト |
| 08 | [将来構想](docs/plan/08-future-roadmap.md) | 管理コンソール、認証認可等 |

## クイックスタート

セットアップ・運用に必要な操作はすべて `make` コマンドで実行できます。利用可能なコマンド一覧は `make help` で確認できます。

### 前提条件

- AWS CLIプロファイルが設定済みであること
- [Terraform](https://developer.hashicorp.com/terraform) v1.14系がインストールされていること（`terraform/.terraform-version`で固定）
- `jq` / `dig` コマンドがインストールされていること
- 委譲先となるサブドメインの親ドメインのRoute53ホストゾーンを別途保有していること
- iPhoneに [WireGuard公式アプリ](https://apps.apple.com/app/wireguard/id1441195209) がインストール済みであること

### 1. 初期設定

```bash
make setup-config
```

生成された `terraform/prd/.envrc`（`AWS_PROFILE`）と `terraform/prd/terraform.tfvars`（`subdomain`）を編集してください。

### 2. Terraformバックエンド作成（初回のみ）

```bash
make init-backend
```

### 3. インフラ構築

```bash
make tf-init
make tf-apply
```

VPC・EC2（WireGuard）・セキュリティグループ・Route53ホストゾーンなどが作成されます。

### 4. DNS委譲（初回のみ、手動）

```bash
make dns-ns-show
```

表示された4つのNSレコードを、親ドメイン側のRoute53ホストゾーンにNSレコードとして追加してください（詳細: [Step5](docs/implementation-plan/step05-dns.md)）。

### 5. VPN起動・状態確認

```bash
make start-vpn
make status-vpn
```

### 6. iPhoneクライアント設定・接続テスト

```bash
make ssm-vpn
```

サーバーに接続後のクライアント鍵生成・QRコード表示・iPhone側の設定手順は [Step7](docs/implementation-plan/step07-client.md) を参照してください。

### 7. 停止（コスト最適化）

使い終わったら、EIP解放・EC2停止のために以下を実行してください。

```bash
make stop-vpn
```

## ライセンス

Private
