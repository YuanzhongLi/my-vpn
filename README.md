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

## コスト

このシステムのコストは「起動時間に応じてかかる固定的なコスト」と「通信量（データ転送量）に応じてかかるコスト」の2種類に分かれる。単価はAWS東京リージョン（ap-northeast-1）の2026年7月時点のオンデマンド価格。

### 固定コスト（起動時間に応じたコスト）

`make start-vpn`〜`make stop-vpn`の間だけ発生する。`make stop-vpn`を実行するとEC2停止・EIP解放されるため、使っていない時間はほぼ無料。

| リソース | 単価 | 課金される条件 |
|---------|------|----------------|
| EC2 t3.nano | $0.0068 / 時間 | インスタンスが`running`の間のみ |
| Elastic IP (Public IPv4) | $0.005 / 時間 | `make start-vpn`でEIPを割り当てている間のみ（`make stop-vpn`で解放すれば課金なし） |
| EBS gp3 8GB | $0.096 / GB・月 ≒ $0.77 / 月 | 停止中も常時課金（ボリュームを保持し続けるため） |
| Route53ホストゾーン | $0.50 / 月 | 常時課金（サブドメイン用ゾーンを保持している間） |

> NAT Gatewayは使用していない（EC2に直接パブリックIPを付与する構成のため）ので、NAT Gateway特有の時間課金・データ処理課金は発生しない。

### 通信量によるコスト（データ転送）

VPN経由の通信は「クライアント→EC2」のインバウンドは無料、「EC2→インターネット」のアウトバウンドのみ課金対象になる。

| データ転送量（月間、全AWS利用の合計） | 単価 |
|---|---|
| 最初の100GBまで | 無料（AWS全リージョン・全サービス共通の無料枠） |
| 100GB〜10TB | $0.114 / GB |
| 10TB〜50TB | $0.089 / GB |
| 50TB〜150TB | $0.086 / GB |
| 150TB超 | $0.084 / GB |

通常のブラウジング・動画視聴程度であれば月100GB以内に収まることが多く、その場合データ転送コストは実質無料。動画のヘビーな視聴やファイルダウンロードを行う場合は、100GBを超えた分に$0.114/GBが加算される。

### 利用パターン別の月額見積もり例

| 利用パターン | EC2起動時間 | 固定コスト | 通信量 | データ転送コスト | 月額合計（概算） |
|---|---|---|---|---|---|
| 軽め（1日2時間） | 60時間/月 | $0.41(EC2) + $0.30(EIP) + $0.77(EBS) + $0.50(Route53) ≒ **$2.0** | 〜30GB | $0（無料枠内） | **約$2** |
| 中程度（1日8時間） | 240時間/月 | $1.63(EC2) + $1.20(EIP) + $0.77(EBS) + $0.50(Route53) ≒ **$4.1** | 〜100GB | $0（無料枠内） | **約$4** |
| 常時起動 | 730時間/月 | $4.96(EC2) + $3.65(EIP) + $0.77(EBS) + $0.50(Route53) ≒ **$9.9** | 150GB | 〜$5.7 | **約$16** |

いずれのパターンでも、`make stop-vpn`を都度実行してEC2を止める運用であればEC2・EIP課金はほぼゼロになり、月額はEBS + Route53の固定分（$1.3程度）＋データ転送分に収まる。詳細な運用コストの考え方は[運用ガイド](docs/plan/07-operations.md)も参照。

## ライセンス

Private
