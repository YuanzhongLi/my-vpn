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

> 実装後に追加予定

## ライセンス

Private
