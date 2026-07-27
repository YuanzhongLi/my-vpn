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

### 2回目以降の利用（`make stop-vpn`済みの状態から）

`make stop-vpn`はEC2の停止とEIPの解放のみで、EC2のディスク（WireGuardの鍵・設定）やTerraformで構築したインフラはそのまま残ります。iPhone側に登録済みのトンネル設定も端末に保存されたままなので、再度使うときは以下の2ステップだけで元に戻ります。

```bash
make start-vpn    # EC2起動 + EIP再割当 + DNS更新
make status-vpn   # 状態確認（任意）
```

初期設定・インフラ構築・DNS委譲（1〜4）やクライアント登録（6）を再度行う必要はありません（例外は下記の注記を参照）。EC2側の準備ができたら、iPhone側で以下を行ってください。

1. WireGuardアプリを開き、以前作成したトンネル（例:「Japan VPN」）のスイッチをON
2. トンネル名の下に「Handshake: X秒前」のような表示が出ることを確認（表示されない/更新されない場合は接続失敗）

接続できたら、以下で動作確認してください。

| 確認内容 | 方法 | 期待結果 |
|---------|------|---------|
| サーバーIP | Safariで `ifconfig.me` を開く | `make status-vpn`のEIPと一致 |
| 接続先地域 | `whatismyipaddress.com` を開く | Tokyo, Japan と表示される |
| DNSリーク | `dnsleaktest.com` でStandard testを実行 | Cloudflare DNSのみ表示される |
| サーバー側の状態 | `make list-clients` を実行 | 対象クライアントの行に直近のhandshakeが記録されている（`wg show wg0`出力） |

うまく繋がらない場合は、DNSが浸透するまで待つ（`make start-vpn`はTTL 60秒でAレコードを更新）か、`make status-vpn`でEC2・EIP・DNSの状態を確認してください。

> **例外**: `make tf-apply` を実行してインフラ構成を変更した場合は再登録が必要です。EC2のAMIはSSMパラメータ経由で常に最新のAmazon Linuxを参照する設計のため、`tf-apply`のたびにAMIドリフトでEC2が再作成され、WireGuardサーバー鍵も再生成されます。この場合はiPhone側の古いトンネルはサーバーの鍵不一致でHandshakeが確立しなくなるため、クライアント（6）を再登録し、iPhone側でも新しい設定（QRコード）で再度トンネルを作成してください。

### クライアント（iPhone等）の管理・クリーンアップ

デバイスを追加するたびに `make add-client NAME=<name> IP=10.0.0.x` を実行すると、サーバー上にピアが増えていきます。登録済みクライアントの一覧確認・削除は以下のコマンドで行えます。

```bash
make list-clients              # 登録済みクライアント一覧 + 接続状況(wg show)を表示
make remove-client NAME=<name> # 指定したクライアントのピアを削除
```

- `IP`は`10.0.0.2`, `10.0.0.3`, ... のように未使用のアドレスを割り当ててください（`make list-clients`の`wg show`出力の`allowed ips`で使用済みIPを確認できます）
- 使わなくなった端末や、誤って外部に漏れた設定・鍵がある場合は `make remove-client` で必ず削除してください
- `make add-client` は同じ`NAME`を指定すると鍵ペアを再生成して古いピアを新しい鍵で上書きします（鍵の再発行に利用できます）

## ライセンス

Private
