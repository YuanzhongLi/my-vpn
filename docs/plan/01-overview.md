# プロジェクト概要

## 目的・背景

海外滞在中にiPhoneから日本のWebサイト・サービスにアクセスするための自作VPNシステム。

多くの日本のWebサービスは海外IPアドレスからのアクセスを制限しており、海外からの利用に支障がある。本プロジェクトでは、AWS東京リージョンにVPNサーバーを構築し、日本のIPアドレスを経由してアクセスすることでこの問題を解決する。

### なぜ自作するのか

- 商用VPNサービスの月額費用を削減
- 自分のインフラで通信内容のプライバシーを完全に管理
- 必要な時だけサーバーを起動しコストを最適化
- VPN技術の学習・理解

## 全体アーキテクチャ概要

```
                        +-----------------------+
                        |   AWS Tokyo Region    |
                        |   (ap-northeast-1)    |
                        |                       |
  +----------+          |  +------------------+ |          +------------------+
  |  iPhone   |  VPN    |  |   VPN Server     | |  通常    |  日本のWeb       |
  | (海外)    |-------->|  | (EC2 or ECS)     |--------->|  サービス        |
  |          |  Tunnel  |  |  日本IP付与       | | 通信    |                  |
  +----------+          |  +------------------+ |          +------------------+
                        |                       |
                        +-----------------------+

  iPhoneクライアント:
  - WireGuard公式アプリ (App Store無料)
  - または iOS標準VPN機能 (IKEv2/IPSec)
```

### 通信フロー

1. iPhone上のVPNクライアントがAWS上のVPNサーバーに暗号化トンネルを確立
2. iPhoneの全通信がVPNトンネルを経由
3. VPNサーバーが日本のIPアドレスとして通信を中継
4. 日本のWebサービスには日本からのアクセスとして認識される

## 用語定義

| 用語 | 説明 |
|------|------|
| VPN | Virtual Private Network。暗号化されたトンネルを通じてネットワーク通信を行う技術 |
| WireGuard | 高速・軽量な最新のVPNプロトコル。Linux カーネルに統合済み |
| IKEv2/IPSec | iOSが標準サポートするVPNプロトコル。アプリ不要で設定可能 |
| ピア (Peer) | VPN接続における各端末のこと。サーバーもクライアントもピアと呼ぶ |
| トンネル | VPNの暗号化された通信経路 |
| Elastic IP | AWSで固定のパブリックIPアドレスを割り当てる機能 |
| Terraform | HashiCorp社のInfrastructure as Code (IaC) ツール |

## 前提条件

- AWSアカウントを保有していること
- Terraform CLIがローカルにインストールされていること
- iPhoneを所有していること（iOS 15以降推奨）
- 基本的なLinux/ネットワークの知識があること

## 制約

- **App Store公開はしない**: 年間費用が高いため、iPhoneアプリは自作しない。既存の無料アプリまたはiOS標準機能を利用する
- **常時起動不要**: コスト削減のため、VPNサーバーは必要時のみ起動する
- **ユーザー規模**: 登録ユーザー最大100人、同時接続最大20人

## プロジェクト構成

```
my-vpn/
├── README.md
├── docs/
│   └── plan/
│       ├── 01-overview.md              # 本ドキュメント
│       ├── 02-protocol-comparison.md   # VPNプロトコル比較
│       ├── 03-infrastructure-comparison.md  # インフラ構成比較
│       ├── 04-architecture.md          # アーキテクチャ設計
│       ├── 05-security.md              # セキュリティ設計
│       ├── 06-client-setup.md          # iPhoneクライアント設定ガイド
│       ├── 07-operations.md            # 運用ガイド
│       └── 08-future-roadmap.md        # 将来構想
├── terraform/                          # Terraformコード（将来実装）
└── scripts/                            # 運用スクリプト（将来実装）
```

## 次のステップ

1. [VPNプロトコル比較](./02-protocol-comparison.md) でWireGuard vs IKEv2/IPSecを評価し、採用プロトコルを決定
2. [インフラ構成比較](./03-infrastructure-comparison.md) でEC2 vs ECS等の実行環境を決定
3. 上記の決定に基づき、詳細なアーキテクチャ設計・セキュリティ設計へ進む
